import SwiftUI

/// About tab within Settings — version, links, copyright.
/// Uses native Form layout for HIG compliance.
struct AboutView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section(String(localized: "settings.about.version")) {
                LabeledContent(String(localized: "settings.about.appVersion")) {
                    Text("v\(appState.appVersion)")
                }

                Link(String(localized: "settings.about.seeWhatsNew"), destination: URL(string: "https://desktop.openwebui.com")!)
                    .font(.callout)
            }

            Section(String(localized: "settings.about.community")) {
                Link(destination: URL(string: "https://discord.gg/5rJgQTnV4s")!) {
                    Label(String(localized: "settings.about.discord"), systemImage: "bubble.left.and.bubble.right")
                }
                Link(destination: URL(string: "https://x.com/spapinwar")!) {
                    Label(String(localized: "settings.about.twitter"), systemImage: "at")
                }
                Link(destination: URL(string: "https://github.com/anomalyco/oval")!) {
                    Label(String(localized: "settings.about.github"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section {
                Text(String(localized: "settings.about.twemojiCredit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: String(localized: "settings.about.copyright"), currentYear))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(localized: "settings.about.allRightsReserved"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var currentYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }
}
