import AVFoundation
import Accelerate
import Foundation
import os

// MARK: - Transcription Segment

/// A completed segment of transcription with optional speaker label.
struct TranscriptionSegment: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let speaker: String?       // e.g. "Speaker 1" — nil when diarization is off
    let timestamp: Date
    let startTime: TimeInterval // Relative to session start
    let endTime: TimeInterval
}

// MARK: - Realtime Transcription Manager

/// Manages continuous realtime speech-to-text transcription using WhisperKit
/// on Apple Neural Engine. Uses a sliding window approach:
///
///   1. Continuously captures mic audio at 16kHz Int16 mono
///   2. Every ~1s, transcribes the last N seconds of audio (sliding window)
///   3. Diffs new transcription against previous to determine stable vs tentative text
///   4. Emits stable segments + tentative (in-progress) text for the UI
///
/// This is separate from VoiceModeManager (which does batch STT after silence
/// for the conversational voice pipeline). This is for live-captions-style
/// continuous transcription.
@MainActor
@Observable
final class RealtimeTranscriptionManager {

    // MARK: - Public State

    /// All finalized transcription segments (stable text that won't change).
    var segments: [TranscriptionSegment] = []

    /// The tentative/in-progress text currently being recognized.
    /// This may change as more audio comes in.
    var tentativeText: String = ""

    /// Current audio input level (0.0 - 1.0) for visualization.
    var audioLevel: Float = 0.0

    /// Whether the transcription session is active.
    var isActive: Bool = false

    /// Whether the model is loaded and ready.
    var isModelReady: Bool = false

    /// Error message if something goes wrong.
    var errorMessage: String?

    /// Full transcript as a single string (all segments + tentative).
    var fullTranscript: String {
        let stable = segments.map(\.text).joined(separator: " ")
        if tentativeText.isEmpty {
            return stable
        }
        return stable.isEmpty ? tentativeText : stable + " " + tentativeText
    }

    // MARK: - Configuration

    /// How often to run transcription (seconds). Lower = more responsive, higher CPU.
    private let transcriptionInterval: TimeInterval = 1.0

    /// Size of the audio window to transcribe each tick (seconds).
    /// Larger window = more context = better accuracy, but slower inference.
    private let windowDuration: TimeInterval = 5.0

    /// Minimum audio energy (RMS) to consider as speech. Below this, skip transcription.
    private let speechThreshold: Float = 0.01

    /// After this many seconds of silence, finalize any tentative text as a segment.
    private let silenceTimeout: TimeInterval = 2.0

    /// Number of consecutive matching transcriptions before text is considered "stable".
    private let stabilityCount = 2

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.oval.app", category: "RealtimeTranscription")

    // Audio capture
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    /// Ring buffer of Int16 PCM samples at 16kHz mono.
    /// We keep `windowDuration` seconds of audio (e.g. 5s = 160,000 bytes).
    private var ringBuffer = Data()
    private let maxRingBufferBytes: Int  // windowDuration * 16000 * 2 (Int16)

    /// Timer-driven transcription loop.
    private var transcriptionTask: Task<Void, Never>?

    /// Tracks when we last detected speech (for silence timeout).
    private var lastSpeechTime: Date?

    /// Previous transcription result for diffing.
    private var previousTranscription = ""

    /// How many times the current tentative text has been confirmed by consecutive runs.
    private var tentativeConfirmCount = 0

    /// Session start time for relative timestamps.
    private var sessionStartTime: Date?

    /// Reference to the speaker diarization manager (set externally).
    private weak var diarizationManager: SpeakerDiarizationManager?

    /// Current speaker label from diarization (nil when diarization is off).
    private var currentSpeakerLabel: String?

    // MARK: - Init

    init() {
        self.maxRingBufferBytes = Int(windowDuration * 16000) * MemoryLayout<Int16>.size
    }

    /// Set the diarization manager reference.
    func setDiarizationManager(_ manager: SpeakerDiarizationManager) {
        self.diarizationManager = manager
    }

    // MARK: - Model Loading

    /// Load model for realtime transcription.
    /// RunAnywhere SDK removed — realtime transcription is unavailable.
    func loadModel() async {
        isModelReady = false
        errorMessage = "Realtime transcription is unavailable (voice SDK removed)."
    }

    // MARK: - Session Control

    /// Start continuous realtime transcription.
    func start() async {
        guard !isActive else { return }

        if !isModelReady {
            await loadModel()
        }
        guard isModelReady else {
            errorMessage = "STT model not ready"
            return
        }

        logger.info("Starting realtime transcription")

        // Reset state
        segments = []
        tentativeText = ""
        previousTranscription = ""
        tentativeConfirmCount = 0
        ringBuffer = Data()
        errorMessage = nil
        sessionStartTime = Date()
        lastSpeechTime = nil

        // Setup and start audio capture
        guard setupAudioEngine() else { return }

        guard let engine = audioEngine else { return }
        do {
            engine.prepare()
            try engine.start()
            isActive = true
            logger.info("Audio capture started for realtime transcription")
        } catch {
            errorMessage = "Failed to start microphone: \(error.localizedDescription)"
            logger.error("Audio engine start failed: \(error)")
            return
        }

        // Start the transcription loop
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.transcriptionInterval))
                guard !Task.isCancelled else { break }
                await self.transcribeCurrentWindow()
            }
        }
    }

    /// Stop transcription and finalize any pending text.
    func stop() {
        guard isActive else { return }

        logger.info("Stopping realtime transcription")

        // Finalize tentative text
        if !tentativeText.isEmpty {
            finalizeSegment(text: tentativeText)
            tentativeText = ""
        }

        // Stop transcription loop
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Stop audio
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        audioConverter = nil
        targetFormat = nil

        isActive = false
        audioLevel = 0.0
    }

    /// Clear all transcription history.
    func clearTranscript() {
        segments = []
        tentativeText = ""
        previousTranscription = ""
        tentativeConfirmCount = 0
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() -> Bool {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            errorMessage = "No microphone detected"
            return false
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            errorMessage = "Failed to create audio format"
            return false
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: format) else {
            errorMessage = "Failed to create audio converter"
            return false
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.audioConverter, let format = self.targetFormat else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / hwFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(
                      pcmFormat: format, frameCapacity: frameCount
                  ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error else { return }

            let frameLength = Int(convertedBuffer.frameLength)
            guard let rawBuffer = convertedBuffer.int16ChannelData else { return }
            let int16Ptr = rawBuffer[0]

            // Calculate RMS
            var sumSquares: Float = 0
            for i in 0..<frameLength {
                let sample = Float(int16Ptr[i]) / 32768.0
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(max(frameLength, 1)))

            let data = Data(bytes: int16Ptr, count: frameLength * MemoryLayout<Int16>.size)

            Task { @MainActor in
                self.audioLevel = min(rms * 5, 1.0)
                self.appendToRingBuffer(data)

                if rms > self.speechThreshold {
                    self.lastSpeechTime = Date()
                }
            }
        }

        self.audioEngine = engine
        self.audioConverter = converter
        self.targetFormat = format
        return true
    }

    // MARK: - Ring Buffer

    private func appendToRingBuffer(_ data: Data) {
        ringBuffer.append(data)
        // Trim to max size (keep most recent audio)
        if ringBuffer.count > maxRingBufferBytes {
            let excess = ringBuffer.count - maxRingBufferBytes
            ringBuffer.removeFirst(excess)
        }
    }

    // MARK: - Transcription Loop

    private func transcribeCurrentWindow() async {
        guard isActive else { return }

        // Check if there's been recent speech
        let now = Date()
        let timeSinceLastSpeech = lastSpeechTime.map { now.timeIntervalSince($0) } ?? .infinity

        // If prolonged silence, finalize tentative text and skip transcription
        if timeSinceLastSpeech > silenceTimeout && !tentativeText.isEmpty {
            finalizeSegment(text: tentativeText)
            tentativeText = ""
            previousTranscription = ""
            tentativeConfirmCount = 0
            return
        }

        // Skip if no recent speech activity
        if timeSinceLastSpeech > silenceTimeout {
            return
        }

        // Need minimum audio to transcribe (~0.5s)
        let minBytes = 16000 * MemoryLayout<Int16>.size  // 0.5s
        guard ringBuffer.count >= minBytes else { return }

        // Copy the current window for transcription
        let audioData = Data(ringBuffer)

        // Feed audio to diarization concurrently (if enabled)
        let diarizationTask: Task<String?, Never>? = if let dm = diarizationManager,
            dm.isEnabled, dm.isActive {
            Task { await dm.processAudioChunk(audioData) }
        } else {
            nil
        }

        // Transcribe — RunAnywhere/WhisperKit SDK removed, transcription unavailable
        do {
            let text: String = ""  // No STT backend available

            guard !Task.isCancelled, isActive else { return }

            // Get speaker label from diarization (if running)
            if let dTask = diarizationTask {
                let speaker = await dTask.value
                currentSpeakerLabel = speaker
            }

            // Skip empty / noise-only results
            let cleaned = cleanTranscription(text)
            guard !cleaned.isEmpty else { return }

            // Diff against previous to find stable vs tentative text
            processTranscriptionResult(cleaned)

        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Transcription tick failed: \(error)")
        }
    }

    // MARK: - Text Diffing & Stability

    /// Compare new transcription against previous. Text that has been consistent
    /// across multiple ticks is "stable" and gets finalized as a segment.
    private func processTranscriptionResult(_ newText: String) {
        let prevWords = previousTranscription.split(separator: " ").map(String.init)
        let newWords = newText.split(separator: " ").map(String.init)

        // Find the longest common prefix between previous and new transcription
        var commonPrefixLen = 0
        for i in 0..<min(prevWords.count, newWords.count) {
            if prevWords[i].lowercased() == newWords[i].lowercased() {
                commonPrefixLen = i + 1
            } else {
                break
            }
        }

        if commonPrefixLen > 0 && commonPrefixLen == prevWords.count && newWords.count >= prevWords.count {
            // Previous text is fully confirmed + new words appended
            tentativeConfirmCount += 1
        } else if newText.lowercased() == previousTranscription.lowercased() {
            // Exact match — increase confidence
            tentativeConfirmCount += 1
        } else {
            // Text changed — reset stability counter
            tentativeConfirmCount = 0
        }

        // If text has been stable for N consecutive ticks, finalize the stable prefix
        if tentativeConfirmCount >= stabilityCount && commonPrefixLen > 0 {
            let stableText = newWords[0..<commonPrefixLen].joined(separator: " ")
            let remaining = newWords.count > commonPrefixLen
                ? newWords[commonPrefixLen...].joined(separator: " ")
                : ""

            if !stableText.isEmpty {
                finalizeSegment(text: stableText)
                // Reset ring buffer to avoid re-transcribing finalized audio
                // Keep only the most recent 2 seconds of audio for context
                let keepBytes = Int(2.0 * 16000) * MemoryLayout<Int16>.size
                if ringBuffer.count > keepBytes {
                    ringBuffer.removeFirst(ringBuffer.count - keepBytes)
                }
            }

            tentativeText = remaining
            previousTranscription = remaining
            tentativeConfirmCount = 0
        } else {
            // Not yet stable — update tentative display
            tentativeText = newText
            previousTranscription = newText
        }
    }

    /// Clean up common Whisper artifacts.
    private func cleanTranscription(_ text: String) -> String {
        var cleaned = text

        // Remove common Whisper hallucination patterns
        let hallucinations = [
            "Thank you.",
            "Thanks for watching.",
            "Subscribe to my channel.",
            "Please subscribe.",
            "Thank you for watching.",
            "[BLANK_AUDIO]",
            "(silence)",
            "...",
            "you",
            "You",
        ]
        for pattern in hallucinations {
            if cleaned.trimmingCharacters(in: .whitespacesAndNewlines) == pattern {
                return ""
            }
        }

        // Remove leading/trailing whitespace and punctuation artifacts
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip very short single-character results (noise)
        if cleaned.count <= 1 {
            return ""
        }

        return cleaned
    }

    // MARK: - Segment Management

    private func finalizeSegment(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        let startTime = sessionStartTime.map { now.timeIntervalSince($0) } ?? 0

        let segment = TranscriptionSegment(
            text: trimmed,
            speaker: currentSpeakerLabel,
            timestamp: now,
            startTime: max(0, startTime - windowDuration),
            endTime: startTime
        )
        segments.append(segment)

        let speakerInfo = currentSpeakerLabel.map { " [\($0)]" } ?? ""
        logger.info("Finalized segment\(speakerInfo): '\(trimmed.prefix(80))'")
    }
}
