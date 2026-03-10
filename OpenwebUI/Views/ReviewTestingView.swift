import SwiftUI

/// Hidden testing view for App Store review.
/// Accessible by tapping the "Oval" title 10 times on the login screen.
///
/// Provides:
/// - **Demo Mode** — Full offline demo with mock data and simulated streaming
/// - Quick-connect with a demo server URL + API key
/// - App diagnostics (version, build, OS)
/// - Feature checklist for reviewers
struct ReviewTestingView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var demoURL = ""
    @State private var demoAPIKey = ""
    @State private var isConnecting = false
    @State private var connectionResult: String?
    @State private var connectionSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "review.title"))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(String(localized: "review.close")) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: - Demo Mode (prominent)
                    GroupBox {
                        VStack(spacing: 16) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)

                            Text(String(localized: "review.demoTitle"))
                                .font(.system(size: 18, weight: .semibold))

                            Text(String(localized: "review.demoDescription"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                appState.enterDemoMode()
                                dismiss()
                            } label: {
                                Text(String(localized: "review.launchDemo"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.blue)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Text(String(localized: "review.demoNote"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    // MARK: - App Info
                    GroupBox(String(localized: "review.appInfo")) {
                        VStack(alignment: .leading, spacing: 8) {
                            infoRow(String(localized: "review.appName"), value: String(localized: "review.appNameValue"))
                            infoRow(String(localized: "review.version"), value: appState.appVersion)
                            infoRow(String(localized: "review.macos"), value: ProcessInfo.processInfo.operatingSystemVersionString)
                            infoRow(String(localized: "review.architecture"), value: cpuArchitecture)
                            infoRow(String(localized: "review.sandbox"), value: isSandboxed ? String(localized: "review.sandboxYes") : String(localized: "review.sandboxNo"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // MARK: - Quick Connect (for real server testing)
                    GroupBox(String(localized: "review.quickConnect")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "review.quickConnectDescription"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField(String(localized: "review.serverURL"), text: $demoURL, prompt: Text("https://your-server.example.com"))
                                .textFieldStyle(.roundedBorder)

                            SecureField(String(localized: "review.apiKey"), text: $demoAPIKey, prompt: Text("sk-..."))
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Button {
                                    Task { await quickConnect() }
                                } label: {
                                    HStack(spacing: 6) {
                                        if isConnecting {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                         Text(isConnecting ? String(localized: "review.connecting") : String(localized: "review.connect"))
                                    }
                                }
                                .disabled(demoURL.isEmpty || demoAPIKey.isEmpty || isConnecting)

                                Spacer()

                                if let result = connectionResult {
                                    HStack(spacing: 4) {
                                        Image(systemName: connectionSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(connectionSuccess ? .green : .red)
                                        Text(result)
                                            .font(.caption)
                                            .foregroundStyle(connectionSuccess ? .green : .red)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // MARK: - Feature Checklist
                    GroupBox(String(localized: "review.featureChecklist")) {
                        VStack(alignment: .leading, spacing: 6) {
                            featureItem("Multi-server support (Discord-style rail)")
                            featureItem("Model selector (toolbar)")
                            featureItem("Chat streaming with markdown")
                            featureItem("Image & file attachments (drag/drop, paste, picker)")
                            featureItem("Web search toggle")
                            featureItem("Speech-to-text (native SFSpeechRecognizer)")
                            featureItem("Auto-generated chat titles")
                            featureItem("Conversation caching & prefetch")
                            featureItem("Light & dark mode (adaptive colors)")
                            featureItem("Quick Chat window (Ctrl+Space)")
                            featureItem("System tray menu bar icon")
                            featureItem("macOS Settings window (Cmd+,)")
                            featureItem("Keyboard shortcuts (Cmd+N, Cmd+F, etc.)")
                            featureItem("Launch at Login")
                            featureItem("Always on Top")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // MARK: - Permissions
                    GroupBox(String(localized: "review.permissions")) {
                        VStack(alignment: .leading, spacing: 6) {
                            permissionRow("Network (outgoing)", description: "Connect to Open WebUI servers")
                            permissionRow("Microphone", description: "Speech-to-text input")
                            permissionRow("Speech Recognition", description: "On-device transcription")
                            permissionRow("User-selected files (read)", description: "File attachment picker")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 650)
    }

    // MARK: - Quick Connect

    private func quickConnect() async {
        let url = demoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = demoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !key.isEmpty else { return }

        isConnecting = true
        connectionResult = nil

        // Try to validate the connection by fetching models
        let client = OpenWebUIClient(baseURL: url, apiKey: key)
        do {
            let models = try await client.listModels()
            if models.isEmpty {
                connectionResult = String(localized: "review.connectedNoModels")
                connectionSuccess = true
            } else {
                connectionResult = String(format: String(localized: "review.connected"), models.count)
                connectionSuccess = true
            }

            // Actually connect the app
            let server = ServerConfig(
                name: "Review Test Server",
                url: url,
                apiKey: key,
                authMethod: .apiKey,
                email: nil
            )
            await appState.addServer(server)
            dismiss()
        } catch {
            connectionResult = error.localizedDescription
            connectionSuccess = false
        }

        isConnecting = false
    }

    // MARK: - Helpers

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func featureItem(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Text(text)
                .font(.callout)
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, description: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.callout)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cpuArchitecture: String {
        #if arch(arm64)
        return String(localized: "review.archSilicon")
        #elseif arch(x86_64)
        return String(localized: "review.archIntel")
        #else
        return String(localized: "review.archUnknown")
        #endif
    }

    private var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
