import SwiftUI

/// Hidden testing view for App Store review.
/// Accessible by tapping the "Oval" title 10 times on the login screen.
///
/// Provides:
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
                Text("Review Testing")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: - App Info
                    GroupBox("App Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            infoRow("App Name", value: "Oval")
                            infoRow("Version", value: appState.appVersion)
                            infoRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                            infoRow("Architecture", value: cpuArchitecture)
                            infoRow("Sandbox", value: isSandboxed ? "Yes" : "No")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // MARK: - Quick Connect
                    GroupBox("Quick Connect") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Enter a demo server URL and API key to test the app without signing in through the main login flow.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Server URL", text: $demoURL, prompt: Text("https://demo.openwebui.com"))
                                .textFieldStyle(.roundedBorder)

                            SecureField("API Key", text: $demoAPIKey, prompt: Text("sk-..."))
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
                                        Text(isConnecting ? "Connecting..." : "Connect")
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
                    GroupBox("Feature Checklist") {
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
                            featureItem("System tray menu bar icon")
                            featureItem("macOS Settings window (Cmd+,)")
                            featureItem("Keyboard shortcuts (Cmd+N, Cmd+F, etc.)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // MARK: - Permissions
                    GroupBox("Required Permissions") {
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
        .frame(width: 500, height: 600)
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
                connectionResult = "Connected but no models found"
                connectionSuccess = true
            } else {
                connectionResult = "Connected (\(models.count) models)"
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
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
