import AVFoundation
import Foundation
import os

/// Orchestrates the voice conversation pipeline:
///   Mic capture -> STT -> Open WebUI Server LLM -> TTS -> Speaker
///
/// Uses on-device STT and TTS while routing the LLM call through the
/// user's Open WebUI server (same models as text chat).
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

    /// Fixed silence threshold — uses a proven value that works for most mics.
    /// The adaptive calibration was too aggressive and prevented speech detection.
    private var silenceThreshold: Float = 0.02
    /// How long to wait after silence before processing (seconds)
    private let silenceDuration: TimeInterval = 1.5
    /// Minimum audio buffer size to process (~0.5s at 16kHz Int16 mono = 16000 bytes)
    private let minAudioSize = 16_000
    /// Maximum listening time before auto-processing (seconds).
    private let maxListenDuration: TimeInterval = 30.0
    /// Peak RMS seen during this listening turn
    private var peakRMS: Float = 0.0
    /// Frame counter for periodic debug logging
    private var frameCount: Int = 0

    private var lastSpeechTime: Date?
    private var isSpeechActive = false
    private weak var appState: AppState?

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
        peakRMS = 0.0
        frameCount = 0
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

        // STT requires 16kHz mono Int16 PCM
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

        // Reset state for each listening turn
        peakRMS = 0.0
        frameCount = 0
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

    /// Simple energy-based VAD with fixed threshold.
    /// Speech detection: level > threshold starts speech.
    /// End-of-speech: silence for 1.5s after speech was detected.
    /// Hallucination filtering happens post-STT, not here.
    private func checkSpeechState(level: Float) {
        guard sessionState == .listening, !isStopped else { return }

        // Track peak RMS
        if level > peakRMS { peakRMS = level }

        // Log levels periodically so we can debug mic issues
        frameCount += 1
        if frameCount % 50 == 0 {
            logger.debug("Audio level: \(level) (peak: \(self.peakRMS), threshold: \(self.silenceThreshold), speech: \(self.isSpeechActive), buffer: \(self.audioBuffer.count))")
        }

        if level > silenceThreshold {
            if !isSpeechActive {
                isSpeechActive = true
                logger.info("Speech started (level=\(level), threshold=\(self.silenceThreshold))")
            }
            lastSpeechTime = Date()
            silenceTimer?.cancel()
            silenceTimer = nil
        } else if isSpeechActive {
            // Speech was active, now silence — start end-of-speech timer
            if silenceTimer == nil {
                silenceTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(self?.silenceDuration ?? 1.5))
                    guard !Task.isCancelled else { return }
                    await self?.onSilenceDetected()
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

    // MARK: - Hallucination Filter

    /// Known Whisper hallucination outputs that should be discarded.
    /// These appear when Whisper processes audio with no clear speech
    /// (ambient noise, silence, or very faint audio).
    private static let hallucinationPatterns: Set<String> = [
        "silence", "(silence)", "[silence]",
        "music", "(music)", "[music]",
        "blank audio", "[blank_audio]", "(blank_audio)",
        "thank you", "thanks", "you",
        "bye", "goodbye",
        "♪", "...", "…",
        "the end", "subtitle",
        "thanks for watching",
        "thank you for watching",
        "please subscribe",
        "like and subscribe",
    ]

    /// Returns true if the transcript is likely a Whisper hallucination.
    private func isHallucination(_ text: String) -> Bool {
        let cleaned = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Exact match against known hallucinations
        if Self.hallucinationPatterns.contains(cleaned) { return true }

        // Very short output (1-2 chars) is almost always hallucination
        if cleaned.count <= 2 { return true }

        // Single repeated character
        if Set(cleaned).count == 1 { return true }

        return false
    }

    // MARK: - Pipeline: STT -> LLM -> TTS

    private func processCurrentAudio() async {
        let audio = audioBuffer
        audioBuffer = Data()

        guard !audio.isEmpty, !isStopped else { return }

        logger.info("Processing audio: \(audio.count) bytes, peakRMS=\(self.peakRMS)")

        // STT unavailable — no on-device STT backend
        stopCapture()
        sessionState = .error("On-device STT is not available")
        errorMessage = "On-device STT is not available in this build."
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
