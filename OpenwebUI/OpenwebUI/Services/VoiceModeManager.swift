import AVFoundation
import Foundation
import RunAnywhere
import os

/// Orchestrates the voice conversation pipeline:
///   Mic capture -> RunAnywhere STT -> Open WebUI Server LLM -> RunAnywhere TTS -> Speaker
///
/// This does NOT use RunAnywhere's built-in voice agent (which couples a local LLM).
/// Instead, it uses RunAnywhere only for on-device STT and TTS, while routing the
/// LLM call through the user's Open WebUI server (same models as text chat).
@MainActor
@Observable
final class VoiceModeManager {

    // MARK: - State

    enum SessionState: Equatable {
        case idle
        case listening
        case transcribing
        case thinking       // Waiting for server LLM response
        case speaking
        case error(String)
    }

    var sessionState: SessionState = .idle
    var audioLevel: Float = 0.0
    var currentTranscript = ""
    var assistantResponse = ""
    var conversationHistory: [(role: String, content: String)] = []
    var errorMessage: String?

    var isActive: Bool {
        switch sessionState {
        case .idle, .error: return false
        default: return true
        }
    }

    // MARK: - Private

    private let logger = Logger(subsystem: "com.oval.app", category: "VoiceMode")
    private var audioBuffer = Data()
    private var silenceTimer: Task<Void, Never>?
    private var isCapturing = false

    /// Set to true when stopSession() is called. Checked by processCurrentAudio()
    /// before each async step to bail out early instead of continuing the pipeline.
    private var isStopped = true

    /// The in-flight processing task (STT -> LLM -> TTS pipeline).
    /// Cancelled on stopSession() so we don't restart listening after stop.
    private var processingTask: Task<Void, Never>?

    /// Base silence threshold (RMS level below which we consider silence).
    /// Adaptive: calibrated from ambient noise during the first ~0.5s.
    private var silenceThreshold: Float = 0.008
    /// How long to wait after silence before processing (seconds)
    private let silenceDuration: TimeInterval = 1.5
    /// Minimum audio buffer size to process (~0.5s at 16kHz Int16 = 16000 bytes)
    private let minAudioSize = 16000
    /// Maximum listening time before auto-processing (seconds).
    /// Prevents listening forever if VAD never triggers end-of-speech.
    private let maxListenDuration: TimeInterval = 30.0

    private var lastSpeechTime: Date?
    private var isSpeechActive = false
    private weak var appState: AppState?

    // Adaptive noise floor calibration
    private var noiseFloorSamples: [Float] = []
    private var noiseFloor: Float = 0.0
    private var isCalibrated = false
    private var listenStartTime: Date?
    private var maxListenTimer: Task<Void, Never>?

    // Persistent audio engine + converter (reuse across turns to avoid reinstall issues)
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    // MARK: - Setup

    func setup(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Session Control

    /// Start a voice conversation session.
    func startSession() async {
        guard !isActive else { return }
        guard RunAnywhereService.shared.isVoiceReady else {
            sessionState = .error("Voice models not loaded")
            errorMessage = "Download and load STT/TTS models first"
            return
        }

        isStopped = false
        errorMessage = nil
        currentTranscript = ""
        assistantResponse = ""
        conversationHistory = []

        await startListening()
    }

    /// Stop the voice conversation session completely.
    func stopSession() {
        logger.info("stopSession() called")
        isStopped = true

        // Cancel the in-flight pipeline task (STT/LLM/TTS)
        processingTask?.cancel()
        processingTask = nil

        stopCapture()
        teardownAudioEngine()
        silenceTimer?.cancel()
        silenceTimer = nil
        maxListenTimer?.cancel()
        maxListenTimer = nil
        audioBuffer = Data()
        isSpeechActive = false
        lastSpeechTime = nil
        noiseFloorSamples = []
        isCalibrated = false
        sessionState = .idle
        audioLevel = 0.0
    }

    // MARK: - Audio Engine Lifecycle

    /// Create the audio engine, converter, and install the tap once.
    /// Reused across conversation turns — only the engine is started/stopped.
    private func setupAudioEngine() -> Bool {
        if audioEngine != nil { return true }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            sessionState = .error("Microphone not available")
            errorMessage = "No microphone detected"
            return false
        }

        // RunAnywhere STT requires 16kHz mono Int16 PCM
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                          sampleRate: 16000,
                                          channels: 1,
                                          interleaved: true) else {
            sessionState = .error("Failed to create audio format")
            return false
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: format) else {
            sessionState = .error("Failed to create audio converter")
            return false
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.audioConverter, let format = self.targetFormat else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / hwFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                                          frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error else { return }

            let frameLength = Int(convertedBuffer.frameLength)
            guard let rawBuffer = convertedBuffer.int16ChannelData else { return }
            let int16Ptr = rawBuffer[0]

            // Calculate RMS from Int16 samples
            var sumSquares: Float = 0
            for i in 0..<frameLength {
                let sample = Float(int16Ptr[i]) / 32768.0
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(max(frameLength, 1)))

            // Pack Int16 samples as raw PCM Data
            let data = Data(bytes: int16Ptr, count: frameLength * MemoryLayout<Int16>.size)

            Task { @MainActor in
                guard !self.isStopped, self.isCapturing else { return }
                self.audioLevel = min(rms * 5, 1.0)
                self.audioBuffer.append(data)
                self.checkSpeechState(level: rms)
            }
        }

        self.audioEngine = engine
        self.audioConverter = converter
        self.targetFormat = format
        return true
    }

    private func teardownAudioEngine() {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        audioConverter = nil
        targetFormat = nil
    }

    // MARK: - Audio Capture (start/pause without reinstalling tap)

    private func startListening() async {
        guard !isStopped else {
            logger.info("startListening() aborted — session stopped")
            return
        }

        // Setup engine once (installs tap)
        guard setupAudioEngine(), let engine = audioEngine else { return }

        sessionState = .listening
        audioBuffer = Data()
        isSpeechActive = false
        lastSpeechTime = nil

        // Reset noise calibration for each listening turn
        noiseFloorSamples = []
        isCalibrated = false
        listenStartTime = Date()

        // Safety net: if we're still listening after maxListenDuration, process whatever we have.
        // Prevents infinite listening when VAD doesn't trigger for some voices.
        maxListenTimer?.cancel()
        maxListenTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxListenDuration ?? 30.0))
            guard !Task.isCancelled else { return }
            await self?.onMaxListenReached()
        }

        // Reset the converter state for a fresh conversion pass
        audioConverter?.reset()

        do {
            engine.prepare()
            try engine.start()
            isCapturing = true
            logger.info("Audio capture started")
        } catch {
            sessionState = .error("Mic error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Called when max listen time is reached without VAD triggering end-of-speech.
    private func onMaxListenReached() async {
        guard sessionState == .listening, !isStopped else { return }
        logger.info("Max listen duration reached, processing audio")
        isSpeechActive = false
        silenceTimer?.cancel()
        silenceTimer = nil

        guard audioBuffer.count > minAudioSize else {
            audioBuffer = Data()
            await startListening()
            return
        }

        processingTask = Task { [weak self] in
            await self?.processCurrentAudio()
        }
    }

    /// Pause capturing (stop engine) without removing the tap.
    /// This allows quick restart for the next conversation turn.
    private func pauseCapture() {
        guard isCapturing, let engine = audioEngine else { return }
        engine.pause()
        isCapturing = false
        logger.info("Audio capture paused")
    }

    /// Full stop — removes tap. Used only by stopSession().
    private func stopCapture() {
        guard isCapturing else { return }
        audioEngine?.stop()
        isCapturing = false
        logger.info("Audio capture stopped")
    }

    // MARK: - Voice Activity Detection (adaptive energy-based)

    /// Adaptive VAD: Calibrates noise floor from the first ~20 frames (~0.5s),
    /// then uses a dynamic threshold above the noise floor.
    /// Also uses a secondary "any-audio" path: if speech was never formally
    /// detected but we have substantial audio, we still process it after
    /// a longer silence gap.
    private func checkSpeechState(level: Float) {
        guard sessionState == .listening, !isStopped else { return }

        // Phase 1: Calibrate noise floor from the first ~20 audio frames
        if !isCalibrated {
            noiseFloorSamples.append(level)
            if noiseFloorSamples.count >= 20 {
                noiseFloor = noiseFloorSamples.reduce(0, +) / Float(noiseFloorSamples.count)
                // Threshold = noise floor + adaptive margin (at least 0.005)
                // For quiet rooms: noiseFloor~0.002, threshold~0.007
                // For noisy rooms: noiseFloor~0.01, threshold~0.02
                silenceThreshold = max(noiseFloor * 2.5, noiseFloor + 0.005)
                // Clamp to reasonable range
                silenceThreshold = min(max(silenceThreshold, 0.005), 0.05)
                isCalibrated = true
                logger.info("VAD calibrated: noiseFloor=\(self.noiseFloor), threshold=\(self.silenceThreshold)")
            }
            // During calibration, don't trigger VAD but still accumulate audio
            return
        }

        if level > silenceThreshold {
            if !isSpeechActive {
                isSpeechActive = true
                logger.debug("Speech started (level=\(level), threshold=\(self.silenceThreshold))")
            }
            lastSpeechTime = Date()
            silenceTimer?.cancel()
            silenceTimer = nil
        } else if isSpeechActive {
            // Speech was active, now silence — start timer
            if silenceTimer == nil {
                silenceTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(self?.silenceDuration ?? 1.5))
                    guard !Task.isCancelled else { return }
                    await self?.onSilenceDetected()
                }
            }
        } else {
            // Speech was never formally detected, but we have audio accumulating.
            // If we have a decent amount of audio and haven't heard anything "loud"
            // for a while, try processing anyway — handles very quiet speakers.
            if audioBuffer.count > minAudioSize * 4 {
                // ~2+ seconds of audio accumulated without formal speech detection
                if silenceTimer == nil {
                    silenceTimer = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2.5))
                        guard !Task.isCancelled else { return }
                        // Double-check: if still no speech detected but buffer is large,
                        // force process it
                        guard let self else { return }
                        if !self.isSpeechActive, self.audioBuffer.count > self.minAudioSize * 2 {
                            self.logger.info("Quiet-speaker fallback: processing accumulated audio (\(self.audioBuffer.count) bytes)")
                            await self.onSilenceDetected()
                        }
                    }
                }
            }
        }
    }

    private func onSilenceDetected() async {
        guard sessionState == .listening, !isStopped else { return }
        isSpeechActive = false
        silenceTimer = nil

        // Only process if we have enough audio
        guard audioBuffer.count > minAudioSize else {
            audioBuffer = Data()
            return
        }

        // Run the pipeline in a cancellable task
        processingTask = Task { [weak self] in
            await self?.processCurrentAudio()
        }
    }

    // MARK: - Pipeline: STT -> LLM -> TTS

    private func processCurrentAudio() async {
        let audio = audioBuffer
        audioBuffer = Data()

        guard !audio.isEmpty, !isStopped else { return }

        // Pause capturing during processing (don't tear down the tap)
        pauseCapture()

        // Step 1: STT — transcribe audio on-device
        sessionState = .transcribing
        do {
            let sttOutput = try await RunAnywhere.transcribe(audio)

            guard !isStopped, !Task.isCancelled else { return }

            let transcript = sttOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                logger.info("Empty transcription, resuming listening")
                guard !isStopped else { return }
                await startListening()
                return
            }

            currentTranscript = transcript
            conversationHistory.append((role: "user", content: transcript))
            logger.info("Transcribed: \(transcript)")
        } catch {
            guard !isStopped, !Task.isCancelled else { return }
            logger.error("STT failed: \(error)")
            sessionState = .error("Transcription failed")
            errorMessage = error.localizedDescription
            return
        }

        // Step 2: LLM — send to Open WebUI server
        guard !isStopped, !Task.isCancelled else { return }
        sessionState = .thinking
        do {
            let response = try await sendToServer(userMessage: currentTranscript)

            guard !isStopped, !Task.isCancelled else { return }

            assistantResponse = response
            conversationHistory.append((role: "assistant", content: response))
            logger.info("LLM response: \(response.prefix(100))")
        } catch {
            guard !isStopped, !Task.isCancelled else { return }
            logger.error("LLM failed: \(error)")
            sessionState = .error("Server error")
            errorMessage = error.localizedDescription
            return
        }

        // Step 3: TTS — synthesize and speak on-device
        guard !isStopped, !Task.isCancelled else { return }
        sessionState = .speaking
        do {
            _ = try await RunAnywhere.speak(assistantResponse)
            logger.info("TTS playback complete")
        } catch {
            guard !isStopped, !Task.isCancelled else { return }
            logger.error("TTS failed: \(error)")
            // Non-fatal — we still have the text response
        }

        // Clear display for next turn
        guard !isStopped, !Task.isCancelled else { return }
        currentTranscript = ""
        assistantResponse = ""

        // Resume listening for next turn
        await startListening()
    }

    // MARK: - Server LLM Call

    /// Send the user's message to the Open WebUI server and collect the full response.
    private func sendToServer(userMessage: String) async throws -> String {
        guard let appState, let model = appState.selectedModel else {
            throw VoiceModeError.noModel
        }
        guard let client = appState.currentClient else {
            throw VoiceModeError.notConnected
        }

        // Build messages array with conversation history
        var messages: [CompletionMessage] = []

        // System prompt for voice mode
        messages.append(CompletionMessage(
            role: "system",
            content: .text("You are a helpful voice assistant. Keep your responses concise and conversational — ideally 1-3 sentences. Avoid markdown formatting, code blocks, or bullet points since your response will be spoken aloud.")
        ))

        // Add conversation history
        for turn in conversationHistory {
            messages.append(CompletionMessage(role: turn.role, content: .text(turn.content)))
        }

        // Stream the response and collect it
        var fullResponse = ""
        let stream = await client.streamChat(
            model: model.id,
            messages: messages
        )

        for try await delta in stream {
            guard !isStopped, !Task.isCancelled else { break }

            switch delta {
            case .content(let text):
                fullResponse += text
                assistantResponse = fullResponse
            case .done:
                break
            case .toolCall:
                break
            }
        }

        guard !fullResponse.isEmpty else {
            throw VoiceModeError.emptyResponse
        }

        return fullResponse
    }
}

// MARK: - Errors

enum VoiceModeError: LocalizedError {
    case noModel
    case notConnected
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noModel: return "No model selected"
        case .notConnected: return "Not connected to server"
        case .emptyResponse: return "Empty response from server"
        }
    }
}
