import SwiftUI

/// Supported app languages with their native display names.
private enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case en, de, fr, it, es, nl, ru
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ko

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "settings.language.system")
        case .en:     return "English"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        case .it:     return "Italiano"
        case .es:     return "Español"
        case .nl:     return "Nederlands"
        case .ru:     return "Русский"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ko:     return "한국어"
        }
    }

    /// Read the current override from UserDefaults.
    static var current: AppLanguage {
        if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = langs.first,
           let match = AppLanguage.allCases.first(where: { $0.rawValue == first }) {
            return match
        }
        return .system
    }

    /// Apply the override. Requires app restart to take effect.
    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// General tab within Settings — server info, status, disconnect, preferences.
/// Uses native Form for HIG-compliant settings layout.
struct GeneralSettingsView: View {
    @Bindable var appState: AppState

    @State private var showDisconnectConfirm = false
    @State private var cacheCleared = false
    @State private var selectedLanguage: AppLanguage = AppLanguage.current
    @State private var showRestartAlert = false

    var body: some View {
        Form {
            // Section: Language
            Section(String(localized: "settings.section.language")) {
                Picker(String(localized: "settings.language.label"), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    newValue.apply()
                    showRestartAlert = true
                }
            }

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
                LabeledContent(String(localized: "settings.shortcuts.quickChat")) {
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
                        .help(String(localized: "settings.shortcuts.resetHelp"))
                    }
                }
                LabeledContent(String(localized: "settings.shortcuts.toggleWindow")) {
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
                        .help(String(localized: "settings.shortcuts.resetHelp"))
                    }
                }
                LabeledContent(String(localized: "settings.shortcuts.pasteToChat")) {
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
                        .help(String(localized: "settings.shortcuts.resetHelp"))
                    }
                }
                LabeledContent(String(localized: "settings.shortcuts.copyResponse")) {
                    Text(String(localized: "settings.shortcuts.copyResponseValue"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Section: Cache
            Section(String(localized: "settings.section.cache")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("settings.cache.clearTitle")
                            .font(.callout)
                        Text("settings.cache.clearSubtitle")
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

            // Section: Support
            Section(String(localized: "settings.section.support")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("settings.support.buyMeCoffeeTitle")
                            .font(.callout)
                        Text("settings.support.buyMeCoffeeSubtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.support.donateButton")) {
                        if let url = URL(string: "https://buymeacoffee.com/shreyaspapi") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("settings.support.githubSponsorsTitle")
                            .font(.callout)
                        Text("settings.support.githubSponsorsSubtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.support.sponsorButton")) {
                        if let url = URL(string: "https://github.com/sponsors/shreyaspapi") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("settings.support.starGithubTitle")
                            .font(.callout)
                        Text("settings.support.starGithubSubtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.support.starButton")) {
                        if let url = URL(string: "https://github.com/shreyaspapi/Oval") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            // Section: Connection Actions
            Section(String(localized: "settings.section.connection")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("settings.connection.openInBrowserTitle")
                            .font(.callout)
                        Text("settings.connection.openInBrowserSubtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.connection.openButton")) {
                        appState.openInBrowser()
                    }
                    .disabled(!appState.serverReachable)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("settings.connection.disconnectTitle")
                            .font(.callout)
                        Text("settings.connection.disconnectSubtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.connection.disconnectButton"), role: .destructive) {
                        showDisconnectConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "settings.connection.disconnectTitle"),
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.connection.disconnectButton"), role: .destructive) {
                appState.disconnect()
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text("settings.connection.disconnectConfirm")
        }
        .alert(String(localized: "settings.language.restartTitle"), isPresented: $showRestartAlert) {
            Button(String(localized: "settings.language.restartNow")) {
                // Relaunch the app
                let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
                let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = [path]
                task.launch()
                NSApplication.shared.terminate(nil)
            }
            Button(String(localized: "settings.language.restartLater"), role: .cancel) {}
        } message: {
            Text("settings.language.restartMessage")
        }
    }
}
