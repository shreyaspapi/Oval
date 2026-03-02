import SwiftUI

/// About tab within Settings — version, links, copyright.
/// Uses native Form layout for HIG compliance.
struct AboutView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Version") {
                LabeledContent("App Version") {
                    Text("v\(appState.appVersion)")
                }

                Link("See what's new", destination: URL(string: "https://desktop.openwebui.com")!)
                    .font(.callout)
            }

            Section("Community") {
                Link(destination: URL(string: "https://discord.gg/5rJgQTnV4s")!) {
                    Label("Discord", systemImage: "bubble.left.and.bubble.right")
                }
                Link(destination: URL(string: "https://x.com/OpenWebUI")!) {
                    Label("Twitter / X", systemImage: "at")
                }
                Link(destination: URL(string: "https://github.com/open-webui/open-webui")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section {
                Text("Twemoji graphics made by Twitter/X, licensed under CC-BY 4.0.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Copyright (c) \(currentYear) Oval")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("All rights reserved.")
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
