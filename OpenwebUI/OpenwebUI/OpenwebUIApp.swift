import SwiftUI

/// App delegate to handle lifecycle events.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
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
}

@main
struct OpenwebUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {

        // MARK: - Main Window

        WindowGroup("Oval") {
            ContentView(appState: appState)
                .frame(minWidth: 700, minHeight: 450)
        }
        .defaultSize(width: 1000, height: 650)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // MARK: File Menu
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    appState.newConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.currentScreen != .chat)

                Divider()

                Button("Quick Chat") {
                    appState.miniChatWindowManager.toggle()
                }
                .keyboardShortcut(" ", modifiers: .control)
            }

            // MARK: Edit Menu
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(appState.currentScreen != .chat)

                Divider()

                Button("Copy Last Response") {
                    appState.copyLastAssistantMessage()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            // MARK: View Menu
            CommandGroup(after: .sidebar) {
                Button(appState.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation { appState.isSidebarVisible.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(appState.currentScreen != .chat)

                Divider()

                Toggle("Always on Top", isOn: Binding(
                    get: { appState.alwaysOnTop },
                    set: { appState.alwaysOnTop = $0 }
                ))
                .keyboardShortcut("t", modifiers: [.command, .option])
            }

            // MARK: Custom App Commands
            CommandGroup(after: .appInfo) {
                Button("Open Server in Browser") {
                    appState.openInBrowser()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(!appState.serverReachable)
            }

            // MARK: Help Menu
            CommandGroup(replacing: .help) {
                Link("Oval Documentation",
                     destination: URL(string: "https://docs.openwebui.com")!)
                Link("GitHub Repository",
                     destination: URL(string: "https://github.com/open-webui/open-webui")!)
                Divider()
                Link("Report an Issue",
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
