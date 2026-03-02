import AppKit

/// Manages the macOS menu bar status item (system tray icon).
@MainActor
final class TrayManager {
    private var statusItem: NSStatusItem?
    private weak var appState: AppState?

    func setup(appState: AppState) {
        self.appState = appState

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "oval.inset.filled", accessibilityDescription: "Oval")
            button.image?.size = NSSize(width: 18, height: 18)
            button.toolTip = "Oval"
        }

        self.statusItem = statusItem
        updateMenu()
    }

    /// Rebuild the context menu to reflect current state.
    func updateMenu() {
        guard let appState else { return }

        let menu = NSMenu()

        // Show Window
        let showItem = NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        // Quick Chat
        let quickChatItem = NSMenuItem(title: "Quick Chat", action: #selector(toggleMiniChat), keyEquivalent: "")
        quickChatItem.target = self
        menu.addItem(quickChatItem)

        menu.addItem(.separator())

        // Status line
        let statusLabel: String
        let statusEnabled: Bool

        switch appState.currentScreen {
        case .loading:
            statusLabel = "Oval: Loading..."
            statusEnabled = false
        case .connect:
            statusLabel = "Oval: Not Connected"
            statusEnabled = false
        case .chat, .controls:
            if appState.serverReachable {
                statusLabel = "Connected: \(appState.serverURL)"
                statusEnabled = true
            } else {
                statusLabel = "Oval: Unreachable"
                statusEnabled = false
            }
        }

        let statusMenuItem = NSMenuItem(title: statusLabel, action: statusEnabled ? #selector(openInBrowser) : nil, keyEquivalent: "")
        statusMenuItem.target = self
        statusMenuItem.isEnabled = statusEnabled
        menu.addItem(statusMenuItem)

        // Copy URL (only when connected)
        if appState.serverReachable && !appState.serverURL.isEmpty {
            let copyItem = NSMenuItem(title: "Copy Server URL", action: #selector(copyServerURL), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }

        menu.addItem(.separator())

        // Shortcuts reference
        let shortcutsHeader = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        shortcutsHeader.isEnabled = false
        menu.addItem(shortcutsHeader)

        let s1 = NSMenuItem(title: "  Quick Chat: Ctrl+Space", action: nil, keyEquivalent: "")
        s1.isEnabled = false
        menu.addItem(s1)

        let s2 = NSMenuItem(title: "  Toggle Window: Ctrl+Opt+Space", action: nil, keyEquivalent: "")
        s2.isEnabled = false
        menu.addItem(s2)

        let s3 = NSMenuItem(title: "  Paste to Chat: Ctrl+Shift+V", action: nil, keyEquivalent: "")
        s3.isEnabled = false
        menu.addItem(s3)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Oval", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
    }

    func teardown() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Actions

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.title.contains("Oval") || window.identifier?.rawValue == "main" {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func toggleMiniChat() {
        appState?.miniChatWindowManager.toggle()
    }

    @objc private func openInBrowser() {
        appState?.openInBrowser()
    }

    @objc private func copyServerURL() {
        appState?.copyURL()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
