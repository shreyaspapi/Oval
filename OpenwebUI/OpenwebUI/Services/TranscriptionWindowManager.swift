import AppKit
import SwiftUI

/// Manages the floating transcription panel — a wide, short window at the bottom
/// of the screen showing live captions as they're spoken, similar to macOS Live Captions.
@MainActor
final class TranscriptionWindowManager {

    private var panel: TranscriptionPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var appState: AppState?

    private let windowWidth: CGFloat = 600
    private let windowHeight: CGFloat = 200

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

        // Position: bottom-center of the screen, above the dock
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.origin.y + 24
            panel.setFrame(
                NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
                display: true
            )
        }

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        appState?.realtimeTranscriptionManager.stop()
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Panel Creation

    private func createPanel(appState: AppState) {
        let transcriptionView = RealtimeTranscriptionView(appState: appState)
        let wrappedView = AnyView(transcriptionView)
        let hosting = NSHostingView(rootView: wrappedView)
        hosting.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        let panel = TranscriptionPanel(
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
        panel.contentView?.layer?.cornerRadius = 16
        panel.contentView?.layer?.masksToBounds = true

        // Size limits
        panel.minSize = NSSize(width: 400, height: 140)
        panel.maxSize = NSSize(width: 900, height: 500)

        // Esc to dismiss
        panel.dismissCallback = { [weak self] in
            self?.hide()
        }

        self.panel = panel
        self.hostingView = hosting
    }

    func teardown() {
        appState?.realtimeTranscriptionManager.stop()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

// MARK: - Custom NSPanel

final class TranscriptionPanel: NSPanel {
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
