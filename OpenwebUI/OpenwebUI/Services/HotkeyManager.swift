import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts using CGEvent taps.
/// Works even when the app is not focused (requires Accessibility permissions).
@MainActor
final class HotkeyManager {

    // MARK: - Hotkey Actions

    var onToggleMiniWindow: (() -> Void)?
    var onToggleMainWindow: (() -> Void)?
    var onPasteToMiniChat: (() -> Void)?

    // MARK: - Event Tap

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Shared Callbacks (nonisolated for C callback access)

    /// These closures are set from the main actor but invoked from the CGEvent callback.
    /// Using nonisolated(unsafe) because the CGEvent callback runs on the main run loop.
    nonisolated(unsafe) static var miniWindowCallback: (() -> Void)?
    nonisolated(unsafe) static var mainWindowCallback: (() -> Void)?
    nonisolated(unsafe) static var pasteCallback: (() -> Void)?
    nonisolated(unsafe) static var tapPort: CFMachPort?

    func start() {
        // Set up the static callbacks to forward to our instance closures
        HotkeyManager.miniWindowCallback = { [weak self] in
            Task { @MainActor in self?.onToggleMiniWindow?() }
        }
        HotkeyManager.mainWindowCallback = { [weak self] in
            Task { @MainActor in self?.onToggleMainWindow?() }
        }
        HotkeyManager.pasteCallback = { [weak self] in
            Task { @MainActor in self?.onPasteToMiniChat?() }
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyCallback,
            userInfo: nil
        ) else {
            // Accessibility permission not granted — fall back to NSEvent monitors
            setupLocalMonitor()
            return
        }

        eventTap = tap
        HotkeyManager.tapPort = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        HotkeyManager.tapPort = nil
        HotkeyManager.miniWindowCallback = nil
        HotkeyManager.mainWindowCallback = nil
        HotkeyManager.pasteCallback = nil
        localMonitor.flatMap { NSEvent.removeMonitor($0) }
        localMonitor = nil
        globalMonitor.flatMap { NSEvent.removeMonitor($0) }
        globalMonitor = nil
    }

    // MARK: - Fallback: NSEvent Monitors

    private var localMonitor: Any?
    private var globalMonitor: Any?

    private func setupLocalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            Self.handleNSEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.handleNSEvent(event) {
                return nil // consume
            }
            return event
        }
    }

    @discardableResult
    private static func handleNSEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // Ctrl+Space → toggle mini window
        if keyCode == UInt16(kVK_Space) && flags == .control {
            miniWindowCallback?()
            return true
        }

        // Ctrl+Option+Space → toggle full window
        if keyCode == UInt16(kVK_Space) && flags == [.control, .option] {
            mainWindowCallback?()
            return true
        }

        // Ctrl+Shift+V → paste clipboard to mini chat
        if keyCode == UInt16(kVK_ANSI_V) && flags == [.control, .shift] {
            pasteCallback?()
            return true
        }

        return false
    }
}

// MARK: - CGEvent Callback (C function pointer — must be a free function)

nonisolated private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Re-enable if system disabled the tap
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = HotkeyManager.tapPort {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let ctrl = flags.contains(.maskControl)
    let alt = flags.contains(.maskAlternate)
    let shift = flags.contains(.maskShift)
    let cmd = flags.contains(.maskCommand)

    // Ctrl+Space → toggle mini window
    if keyCode == UInt16(kVK_Space) && ctrl && !alt && !shift && !cmd {
        HotkeyManager.miniWindowCallback?()
        return nil // consume
    }

    // Ctrl+Option+Space → toggle full window
    if keyCode == UInt16(kVK_Space) && ctrl && alt && !shift && !cmd {
        HotkeyManager.mainWindowCallback?()
        return nil
    }

    // Ctrl+Shift+V → paste clipboard to mini chat
    if keyCode == UInt16(kVK_ANSI_V) && ctrl && shift && !alt && !cmd {
        HotkeyManager.pasteCallback?()
        return nil
    }

    return Unmanaged.passRetained(event)
}
