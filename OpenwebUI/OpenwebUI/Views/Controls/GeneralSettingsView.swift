import SwiftUI

/// General tab within Settings — server info, status, disconnect, preferences.
/// Uses native Form for HIG-compliant settings layout.
struct GeneralSettingsView: View {
    @Bindable var appState: AppState

    @State private var showDisconnectConfirm = false
    @State private var cacheCleared = false

    var body: some View {
        Form {
            // Section: Server
            Section("Server") {
                LabeledContent("URL") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.serverReachable ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(appState.serverURL.isEmpty ? "Not connected" : appState.serverURL)
                            .textSelection(.enabled)
                    }
                }

                if let version = appState.serverVersion {
                    LabeledContent("Version") {
                        Text("v\(version)")
                    }
                }

                LabeledContent("Status") {
                    Text(appState.serverReachable ? "Online" : "Unreachable")
                        .foregroundStyle(appState.serverReachable ? .green : .orange)
                }
            }

            // Section: Behavior
            Section("Behavior") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.launchAtLogin = $0 }
                ))

                Toggle("Always on Top", isOn: Binding(
                    get: { appState.alwaysOnTop },
                    set: { appState.alwaysOnTop = $0 }
                ))
            }

            // Section: Keyboard Shortcuts
            Section("Keyboard Shortcuts") {
                LabeledContent("Quick Chat") {
                    HStack(spacing: 8) {
                        ShortcutRecorderView(
                            binding: Binding(
                                get: { appState.hotkeyPreferences.quickChat },
                                set: { appState.hotkeyPreferences.quickChat = $0 }
                            ),
                            onChanged: { appState.applyHotkeyChanges() }
                        )
                        Button {
                            appState.hotkeyPreferences.quickChat = HotkeyPreferences.defaults.quickChat
                            appState.applyHotkeyChanges()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reset to default")
                    }
                }
                LabeledContent("Toggle Window") {
                    HStack(spacing: 8) {
                        ShortcutRecorderView(
                            binding: Binding(
                                get: { appState.hotkeyPreferences.toggleWindow },
                                set: { appState.hotkeyPreferences.toggleWindow = $0 }
                            ),
                            onChanged: { appState.applyHotkeyChanges() }
                        )
                        Button {
                            appState.hotkeyPreferences.toggleWindow = HotkeyPreferences.defaults.toggleWindow
                            appState.applyHotkeyChanges()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reset to default")
                    }
                }
                LabeledContent("Paste to Chat") {
                    HStack(spacing: 8) {
                        ShortcutRecorderView(
                            binding: Binding(
                                get: { appState.hotkeyPreferences.pasteToChat },
                                set: { appState.hotkeyPreferences.pasteToChat = $0 }
                            ),
                            onChanged: { appState.applyHotkeyChanges() }
                        )
                        Button {
                            appState.hotkeyPreferences.pasteToChat = HotkeyPreferences.defaults.pasteToChat
                            appState.applyHotkeyChanges()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reset to default")
                    }
                }
                LabeledContent("Copy Response") {
                    Text("Cmd + Shift + C")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Section: Cache
            Section("Cache") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Clear Message Cache")
                            .font(.callout)
                        Text("Force reload all conversations from server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(cacheCleared ? "Cleared" : "Clear") {
                        appState.clearMessageCache()
                        cacheCleared = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            cacheCleared = false
                        }
                    }
                    .disabled(cacheCleared)
                }
            }

            // Section: Connection Actions
            Section("Connection") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Open in Browser")
                            .font(.callout)
                        Text("Open the server web interface")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") {
                        appState.openInBrowser()
                    }
                    .disabled(!appState.serverReachable)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Disconnect")
                            .font(.callout)
                        Text("Return to the connection screen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        showDisconnectConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Disconnect",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                appState.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to disconnect from this server?")
        }
    }
}
