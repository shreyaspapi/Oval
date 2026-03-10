import AppKit
import SwiftUI

/// Manages the floating mini chat panel (NSPanel) that appears via global hotkey.
/// Two modes:
///   - Compact: Just the input bar (when no messages)
///   - Expanded: Messages + input (after first send)
/// Styled to match ChatGPT's quick chat — dark rounded rect, no title bar chrome.
@MainActor
final class MiniChatWindowManager {

    private var panel: MiniChatPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var appState: AppState?

    private let compactWidth: CGFloat = 680
    private let compactHeight: CGFloat = 82
    private let expandedWidth: CGFloat = 680
    private let expandedHeight: CGFloat = 540

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func setup(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Show / Hide / Toggle

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let appState else { return }

        if panel == nil {
            createPanel(appState: appState)
        }

        guard let panel else { return }

        // Determine size based on state
        let hasMessages = !appState.miniChatMessages.isEmpty
        let targetWidth = hasMessages ? expandedWidth : compactWidth
        let targetHeight = hasMessages ? expandedHeight : compactHeight

        // Transparent in compact mode, opaque dark in expanded mode
        panel.backgroundColor = hasMessages ? NSColor(hex: "#1a1a1a") : .clear
        panel.contentView?.layer?.cornerRadius = hasMessages ? 18 : 0

        // Center on the screen with the cursor
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - targetWidth) / 2
            let y: CGFloat
            if hasMessages {
                y = screenFrame.origin.y + (screenFrame.height - targetHeight) / 2 + 40
            } else {
                // Position higher up for compact mode (like Spotlight)
                y = screenFrame.origin.y + screenFrame.height * 0.65 - targetHeight / 2
            }
            panel.setFrame(NSRect(x: x, y: y, width: targetWidth, height: targetHeight), display: true)
        }

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // Focus the text input after a small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            panel.makeFirstResponder(panel.contentView)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func showWithClipboard() {
        guard let appState else { return }

        // Start a new mini conversation
        appState.miniChatMessages = []
        appState.miniMessageInput = ""
        appState.miniStreamingContent = ""

        // Paste clipboard content
        if let clipboardText = NSPasteboard.general.string(forType: .string), !clipboardText.isEmpty {
            appState.miniMessageInput = clipboardText
        }

        show()
    }

    /// Animate from compact to expanded size when first message is sent.
    func expandToFullSize() {
        guard let panel else { return }
        // Switch to opaque background and rounded corners for expanded (messages) mode
        panel.backgroundColor = NSColor(hex: "#1a1a1a")
        panel.contentView?.layer?.cornerRadius = 18
        let currentFrame = panel.frame
        let newHeight = expandedHeight
        let newWidth = expandedWidth
        // Keep centered horizontally, grow downward from current top
        let newY = currentFrame.origin.y + currentFrame.height - newHeight
        let newX = currentFrame.origin.x + (currentFrame.width - newWidth) / 2
        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
        panel.animator().setFrame(newFrame, display: true)
    }

    // MARK: - Panel Creation

    private func createPanel(appState: AppState) {
        let miniView = MiniChatView(appState: appState)

        let wrappedView = AnyView(miniView)
        let hosting = NSHostingView(rootView: wrappedView)
        hosting.frame = NSRect(x: 0, y: 0, width: compactWidth, height: compactHeight)

        let panel = MiniChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: compactWidth, height: compactHeight),
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hosting
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // Hide the traffic-light (close/minimize/zoom) buttons entirely
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        // Start transparent — the input card provides its own background
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Rounded corners — start with none for compact (transparent) mode;
        // corners are applied when expanding to show messages.
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 0
        panel.contentView?.layer?.masksToBounds = true

        // Size limits
        panel.minSize = NSSize(width: 400, height: compactHeight)
        panel.maxSize = NSSize(width: 900, height: 700)

        // Esc to dismiss
        panel.dismissCallback = { [weak self] in
            self?.hide()
        }

        self.panel = panel
        self.hostingView = hosting
    }

    func teardown() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

// MARK: - Custom NSPanel Subclass

/// Custom NSPanel that handles Esc to dismiss and keeps floating behavior.
final class MiniChatPanel: NSPanel {
    var dismissCallback: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        dismissCallback?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            dismissCallback?()
            return
        }
        super.keyDown(with: event)
    }
}
