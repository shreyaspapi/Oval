import Speech

/// Manages on-device speech recognition using Apple's SFSpeechRecognizer.
///
/// Usage:
///   1. Call `startListening()` — requests permissions if needed, then begins transcribing.
///   2. Observe `transcript` for the live text and `isListening` for state.
///   3. Call `stopListening()` to end — the final transcript remains in `transcript`.
@MainActor
@Observable
final class SpeechManager {

    // MARK: - Public State

    /// The live transcript text (updates as the user speaks).
    var transcript: String = ""

    /// Whether the recognizer is actively listening.
    var isListening: Bool = false

    /// A user-facing error message if something goes wrong.
    var error: String?

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    // MARK: - Public API

    func startListening() {
        guard !isListening else { return }

        // Check speech recognizer availability
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognition is not available on this device."
            return
        }

        // Request permissions
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginRecognition()
                case .denied:
                    self.error = "Speech recognition permission denied. Enable it in System Settings > Privacy."
                case .restricted:
                    self.error = "Speech recognition is restricted on this device."
                case .notDetermined:
                    self.error = "Speech recognition permission not determined."
                @unknown default:
                    self.error = "Unknown speech recognition authorization status."
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    /// Toggle listening on/off.
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    // MARK: - Private

    nonisolated private func beginRecognition() {
        Task { @MainActor in
            await _beginRecognition()
        }
    }

    private func _beginRecognition() async {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let speechRecognizer else { return }

        // Create request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device recognition for privacy and speed
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request
        error = nil
        transcript = ""

        // Install audio tap (no AVAudioSession on macOS — audio engine works directly)
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            self.error = "Microphone not available."
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            return
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    // Ignore cancellation errors
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // User cancelled — not a real error
                        return
                    }
                    if nsError.code == 1110 { // No speech detected
                        return
                    }
                    self.error = error.localizedDescription
                    self.stopListening()
                }

                if result?.isFinal == true {
                    self.stopListening()
                }
            }
        }
    }
}
