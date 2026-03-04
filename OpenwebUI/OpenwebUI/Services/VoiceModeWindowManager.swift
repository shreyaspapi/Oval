import AppKit
import SwiftUI

/// Manages the floating voice mode panel (NSPanel) — a small rounded window
/// similar to ChatGPT's voice mode bubble that floats above other windows.
@MainActor
final class VoiceModeWindowManager {

    private var panel: VoiceModePanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var appState: AppState?

    private let windowWidth: CGFloat = 340
    private let windowHeight: CGFloat = 480

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func setup(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Show / Hide

    func show() {
        guard let appState else { return }

        if panel == nil {
            createPanel(appState: appState)
        }

        guard let panel else { return }

        // Position: bottom-right of the screen, above the dock
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - windowWidth - 24
            let y = screenFrame.origin.y + 24
            panel.setFrame(
                NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
                display: true
            )
        }

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        // Stop the voice session before hiding
        appState?.voiceModeManager.stopSession()
        panel?.orderOut(nil)
    }

    // MARK: - Panel Creation

    private func createPanel(appState: AppState) {
        let voiceView = VoiceModeView(appState: appState)
        let wrappedView = AnyView(voiceView)
        let hosting = NSHostingView(rootView: wrappedView)
        hosting.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        let panel = VoiceModePanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hosting
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // Hide traffic lights
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Rounded corners
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 20
        panel.contentView?.layer?.masksToBounds = true

        // Size limits
        panel.minSize = NSSize(width: 280, height: 380)
        panel.maxSize = NSSize(width: 500, height: 700)

        // Esc to dismiss
        panel.dismissCallback = { [weak self] in
            self?.hide()
            self?.appState?.setVoiceModeActive(false)
        }

        self.panel = panel
        self.hostingView = hosting
    }

    func teardown() {
        appState?.voiceModeManager.stopSession()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

// MARK: - Custom NSPanel

final class VoiceModePanel: NSPanel {
    var dismissCallback: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        dismissCallback?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            dismissCallback?()
            return
        }
        super.keyDown(with: event)
    }
}
