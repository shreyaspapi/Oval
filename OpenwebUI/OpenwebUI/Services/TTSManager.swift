import AppKit
import AVFoundation

/// Manages text-to-speech playback using macOS native AVSpeechSynthesizer.
@MainActor
@Observable
final class TTSManager: NSObject {

    /// Whether TTS is currently speaking.
    var isSpeaking: Bool = false

    /// The message ID currently being spoken (for UI state).
    var speakingMessageId: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var delegateHandler: TTSDelegateHandler?

    override init() {
        super.init()
        let handler = TTSDelegateHandler { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
                self?.speakingMessageId = nil
            }
        }
        self.delegateHandler = handler
        synthesizer.delegate = handler
    }

    /// Speak the given text. Stops any current speech first.
    func speak(_ text: String, messageId: String? = nil) {
        stop()

        let cleaned = text
            .replacingOccurrences(of: "```[\\s\\S]*?```", with: " code block ", options: .regularExpression)
            .replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[#*_~>]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\n{2,}", with: ". ", options: .regularExpression)
            .replacingOccurrences(of: "\\n", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Use a good default voice for the user's locale
        if let voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US") {
            utterance.voice = voice
        }

        isSpeaking = true
        speakingMessageId = messageId
        synthesizer.speak(utterance)
    }

    /// Stop any current speech.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        speakingMessageId = nil
    }
}

/// Non-isolated delegate handler for AVSpeechSynthesizer callbacks.
private final class TTSDelegateHandler: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
