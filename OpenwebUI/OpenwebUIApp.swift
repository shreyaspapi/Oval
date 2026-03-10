import SwiftUI

/// App delegate to handle lifecycle events.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Restore all non-panel windows (main window, settings, etc.)
            for window in sender.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        // Always ensure the app is fully activated with its menu bar
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure window frame autosave (HIG Rule 2.5)
        for window in NSApp.windows {
            window.setFrameAutosaveName("MainWindow")
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure the app has a visible main window when activated.
        // This prevents the "no menu bar" state when all windows were hidden.
        let hasVisibleNonPanel = NSApp.windows.contains { window in
            !(window is NSPanel) && window.isVisible && !window.isMiniaturized
        }
        if !hasVisibleNonPanel {
            for window in NSApp.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
                break  // Only restore one main window
            }
        }
    }
}

@main
struct OpenwebUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {

        // MARK: - Main Window

        WindowGroup(String(localized: "app.name")) {
            ContentView(appState: appState)
                .frame(minWidth: 700, minHeight: 450)
        }
        .defaultSize(width: 1000, height: 650)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // MARK: File Menu
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.newChat")) {
                    appState.newConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.currentScreen != .chat)

                Divider()

                Button("\(String(localized: "menu.quickChat"))  \(appState.hotkeyPreferences.quickChat.displayString)") {
                    appState.miniChatWindowManager.toggle()
                }

                Divider()

                Button(appState.isRealtimeTranscriptionActive ? String(localized: "menu.stopTranscription") : String(localized: "menu.liveTranscription")) {
                    appState.setRealtimeTranscriptionActive(!appState.isRealtimeTranscriptionActive)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            // MARK: Edit Menu
            CommandGroup(after: .textEditing) {
                Button(String(localized: "menu.find")) {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(appState.currentScreen != .chat)

                Divider()

                Button(String(localized: "menu.copyLastResponse")) {
                    appState.copyLastAssistantMessage()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            // MARK: View Menu
            CommandGroup(after: .sidebar) {
                Button(appState.isSidebarVisible ? String(localized: "menu.hideSidebar") : String(localized: "menu.showSidebar")) {
                    withAnimation { appState.isSidebarVisible.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(appState.currentScreen != .chat)

                Divider()

                Toggle(String(localized: "menu.alwaysOnTop"), isOn: Binding(
                    get: { appState.alwaysOnTop },
                    set: { appState.alwaysOnTop = $0 }
                ))
                .keyboardShortcut("t", modifiers: [.command, .option])
            }

            // MARK: Custom App Commands
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updateManager: updateManager)

                Divider()

                Button(String(localized: "menu.openServerInBrowser")) {
                    appState.openInBrowser()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(!appState.serverReachable)
            }

            // MARK: Help Menu
            CommandGroup(replacing: .help) {
                Link(String(localized: "menu.ovalDocumentation"),
                     destination: URL(string: "https://docs.openwebui.com")!)
                Link(String(localized: "menu.githubRepository"),
                     destination: URL(string: "https://github.com/open-webui/open-webui")!)
                Divider()
                Link(String(localized: "menu.reportIssue"),
                     destination: URL(string: "https://github.com/open-webui/open-webui/issues")!)
            }
        }

        // MARK: - Settings Scene (Cmd+,)

        Settings {
            SettingsView(appState: appState)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openServerInBrowser = Notification.Name("openServerInBrowser")
    static let focusSearch = Notification.Name("focusSearch")
}
