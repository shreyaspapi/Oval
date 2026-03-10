import SwiftUI

/// About tab within Settings — version, links, copyright.
/// Uses native Form layout for HIG compliance.
struct AboutView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section(String(localized: "about.section.version")) {
                LabeledContent(String(localized: "about.appVersion")) {
                    Text("v\(appState.appVersion)")
                }

                Link(String(localized: "about.seeWhatsNew"), destination: URL(string: "https://desktop.openwebui.com")!)
                    .font(.callout)
            }

            Section(String(localized: "about.section.community")) {
                Link(destination: URL(string: "https://discord.gg/5rJgQTnV4s")!) {
                    Label(String(localized: "about.discord"), systemImage: "bubble.left.and.bubble.right")
                }
                Link(destination: URL(string: "https://x.com/spapinwar")!) {
                    Label(String(localized: "about.twitter"), systemImage: "at")
                }
                Link(destination: URL(string: "https://github.com/anomalyco/oval")!) {
                    Label(String(localized: "about.github"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section {
                Text("about.twemojiCredit")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: String(localized: "about.copyright"), currentYear))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("about.allRightsReserved")
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
