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
            Section(String(localized: "settings.section.server")) {
                LabeledContent(String(localized: "settings.server.url")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.serverReachable ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(appState.serverURL.isEmpty ? String(localized: "settings.server.notConnected") : appState.serverURL)
                            .textSelection(.enabled)
                    }
                }

                if let version = appState.serverVersion {
                    LabeledContent(String(localized: "settings.server.version")) {
                        Text("v\(version)")
                    }
                }

                LabeledContent(String(localized: "settings.server.status")) {
                    Text(appState.serverReachable ? String(localized: "settings.server.online") : String(localized: "settings.server.unreachable"))
                        .foregroundStyle(appState.serverReachable ? .green : .orange)
                }
            }

            // Section: Behavior
            Section(String(localized: "settings.section.behavior")) {
                Toggle(String(localized: "settings.behavior.launchAtLogin"), isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.launchAtLogin = $0 }
                ))

                Toggle(String(localized: "settings.behavior.alwaysOnTop"), isOn: Binding(
                    get: { appState.alwaysOnTop },
                    set: { appState.alwaysOnTop = $0 }
                ))
            }

            // Section: Keyboard Shortcuts
            Section(String(localized: "settings.section.shortcuts")) {
                LabeledContent(String(localized: "settings.shortcut.quickChat")) {
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
                LabeledContent(String(localized: "settings.shortcut.toggleWindow")) {
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
                LabeledContent(String(localized: "settings.shortcut.pasteToChat")) {
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
                LabeledContent(String(localized: "settings.shortcut.copyResponse")) {
                    Text(String(localized: "settings.shortcut.copyResponse.value"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Section: Cache
            Section(String(localized: "settings.section.cache")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.cache.clearTitle"))
                            .font(.callout)
                        Text(String(localized: "settings.cache.clearDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(cacheCleared ? String(localized: "settings.cache.cleared") : String(localized: "settings.cache.clear")) {
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
            Section(String(localized: "settings.section.connection")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.connection.openInBrowser"))
                            .font(.callout)
                        Text(String(localized: "settings.connection.openInBrowserDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.connection.open")) {
                        appState.openInBrowser()
                    }
                    .disabled(!appState.serverReachable)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.connection.disconnect"))
                            .font(.callout)
                        Text(String(localized: "settings.connection.disconnectDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.connection.disconnect"), role: .destructive) {
                        showDisconnectConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "settings.connection.disconnect"),
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.connection.disconnect"), role: .destructive) {
                appState.disconnect()
            }
            Button(String(localized: "settings.connection.disconnectCancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.connection.disconnectConfirm"))
        }
    }
}
