import SwiftUI

/// Settings tab for on-device voice models.
/// Currently shows a placeholder since on-device STT/TTS has been removed.
struct VoiceModelSettingsView: View {

    var body: some View {
        Form {
            Section(String(localized: "voice.section.engine")) {
                LabeledContent(String(localized: "voice.engine.label")) {
                    Text(String(localized: "voice.engine.name"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(String(localized: "voice.engine.status")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "voice.engine.unavailable"))
                    }
                }
            }

            Section(String(localized: "voice.section.about")) {
                Text("voice.engine.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
