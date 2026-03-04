import FluidAudio
import Foundation
import os

// MARK: - Speaker Diarization Result

/// A diarization segment with speaker ID and time range.
struct DiarizationSegment {
    let speakerLabel: String     // e.g. "Speaker 1"
    let startTime: TimeInterval
    let endTime: TimeInterval
}

// MARK: - Speaker Diarization Manager

/// Manages on-device speaker diarization using FluidAudio's Pyannote pipeline.
/// Runs concurrently with the transcription manager — receives audio chunks and produces
/// speaker labels that get merged into transcription segments.
///
/// Pipeline: Pyannote segmentation (CoreML/ANE) + WeSpeaker embeddings + clustering
@MainActor
@Observable
final class SpeakerDiarizationManager {

    // MARK: - Public State

    /// Whether diarization is enabled by the user.
    var isEnabled: Bool = false

    /// Whether models are downloaded and ready.
    var isModelReady: Bool = false

    /// Whether currently processing.
    var isActive: Bool = false

    /// Current speaker label for the active audio (updated in realtime).
    var currentSpeaker: String = ""

    /// Number of unique speakers detected so far.
    var speakerCount: Int = 0

    /// Error message if something goes wrong.
    var errorMessage: String?

    /// Whether models are currently being downloaded/prepared.
    var isPreparing: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.oval.app", category: "Diarization")

    /// FluidAudio's diarizer manager (maintains speaker tracking across calls).
    private var diarizer: DiarizerManager?

    /// Map from FluidAudio speaker IDs (strings like "speaker_0") to human-readable labels.
    private var speakerLabelMap: [String: String] = [:]
    private var nextSpeakerNumber = 1

    /// Session start time for relative timestamps.
    private var sessionStartTime: Date?

    // MARK: - Model Preparation

    /// Download and prepare diarization models (Pyannote segmentation + WeSpeaker).
    /// Models are cached after first download (~100MB total).
    func prepareModels() async {
        guard !isModelReady, !isPreparing else { return }

        isPreparing = true
        errorMessage = nil

        do {
            logger.info("Downloading diarization models...")
            let downloadedModels = try await DiarizerModels.downloadIfNeeded()

            let config = DiarizerConfig(
                clusteringThreshold: 0.7,
                minSpeechDuration: 0.5,
                chunkDuration: 5.0,
                chunkOverlap: 1.0
            )
            let manager = DiarizerManager(config: config)
            manager.initialize(models: downloadedModels)
            self.diarizer = manager

            isModelReady = true
            isPreparing = false
            logger.info("Diarization models ready")
        } catch {
            isPreparing = false
            errorMessage = "Failed to prepare diarization models: \(error.localizedDescription)"
            logger.error("Diarization model preparation failed: \(error)")
        }
    }

    // MARK: - Session Control

    /// Start a diarization session.
    func startSession() {
        guard isModelReady else {
            errorMessage = "Diarization models not ready"
            return
        }

        speakerLabelMap = [:]
        nextSpeakerNumber = 1
        currentSpeaker = ""
        speakerCount = 0
        sessionStartTime = Date()
        isActive = true

        // Remove all previous speakers for a fresh session
        if let diarizer {
            for speakerId in diarizer.speakerManager.getAllSpeakers().keys {
                diarizer.speakerManager.removeSpeaker(speakerId, keepIfPermanent: false)
            }
        }

        logger.info("Diarization session started")
    }

    /// Stop the diarization session.
    func stopSession() {
        isActive = false
        currentSpeaker = ""
        logger.info("Diarization session stopped. Detected \(self.speakerCount) speakers.")
    }

    // MARK: - Audio Processing

    /// Process a chunk of audio for speaker diarization.
    /// Call this with the same audio data being sent to STT.
    ///
    /// - Parameter audioData: Int16 PCM audio at 16kHz mono
    /// - Returns: The speaker label for this audio chunk, or nil if not yet determined
    func processAudioChunk(_ audioData: Data) async -> String? {
        guard isActive, isModelReady, let diarizer else { return nil }

        // Convert Int16 PCM Data to [Float] samples (FluidAudio expects Float)
        let samples: [Float] = audioData.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            return int16Buffer.map { Float($0) / 32768.0 }
        }

        // Need minimum ~3s of audio for reliable diarization (48000 samples at 16kHz)
        guard samples.count >= 48000 else { return currentSpeaker.isEmpty ? nil : currentSpeaker }

        do {
            // Run diarization on the audio window
            // performCompleteDiarization maintains speaker tracking across calls
            // via the internal SpeakerManager
            let result = try diarizer.performCompleteDiarization(samples)

            // Process the diarization segments
            for segment in result.segments {
                let label = humanLabel(for: segment.speakerId)

                // Update current speaker from the most recent/longest segment
                if !label.isEmpty {
                    currentSpeaker = label
                }
            }

            speakerCount = speakerLabelMap.count
            return currentSpeaker.isEmpty ? nil : currentSpeaker

        } catch {
            logger.error("Diarization chunk processing failed: \(error)")
        }

        return currentSpeaker.isEmpty ? nil : currentSpeaker
    }

    // MARK: - Private Helpers

    /// Map a FluidAudio speaker ID string to a human-readable label.
    private func humanLabel(for speakerId: String) -> String {
        if let existing = speakerLabelMap[speakerId] {
            return existing
        }
        let label = "Speaker \(nextSpeakerNumber)"
        speakerLabelMap[speakerId] = label
        nextSpeakerNumber += 1
        return label
    }
}
