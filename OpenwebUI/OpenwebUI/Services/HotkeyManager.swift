import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts using CGEvent taps.
/// Works even when the app is not focused (requires Accessibility permissions).
/// Hotkey bindings are configurable at runtime via `bindings`.
@MainActor
final class HotkeyManager {

    // MARK: - Hotkey Actions

    var onToggleMiniWindow: (() -> Void)?
    var onToggleMainWindow: (() -> Void)?
    var onPasteToMiniChat: (() -> Void)?

    // MARK: - Configurable Bindings

    /// Current hotkey preferences. Call `restart()` after changing to apply.
    var bindings: HotkeyPreferences = .defaults

    // MARK: - Event Tap

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Shared State (nonisolated for C callback access)

    /// These closures are set from the main actor but invoked from the CGEvent callback.
    /// Using nonisolated(unsafe) because the CGEvent callback runs on the main run loop.
    nonisolated(unsafe) static var miniWindowCallback: (() -> Void)?
    nonisolated(unsafe) static var mainWindowCallback: (() -> Void)?
    nonisolated(unsafe) static var pasteCallback: (() -> Void)?
    nonisolated(unsafe) static var tapPort: CFMachPort?

    /// Current bindings exposed to the C callback (value type, safe to copy).
    /// Initialized with the same defaults as HotkeyPreferences.defaults but using
    /// raw initializers to avoid actor-isolation warnings in nonisolated context.
    nonisolated(unsafe) static var activeBindings = HotkeyPreferences(
        quickChat:    HotkeyBinding(rawKeyCode: UInt16(kVK_Space),  rawModifiers: CGEventFlags.maskControl.rawValue),
        toggleWindow: HotkeyBinding(rawKeyCode: UInt16(kVK_Space),  rawModifiers: CGEventFlags([.maskControl, .maskAlternate]).rawValue),
        pasteToChat:  HotkeyBinding(rawKeyCode: UInt16(kVK_ANSI_V), rawModifiers: CGEventFlags([.maskControl, .maskShift]).rawValue)
    )

    func start() {
        // Publish current bindings to the static context used by the C callback
        HotkeyManager.activeBindings = bindings

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

    /// Stop and re-start with the current `bindings`. Call after the user changes a shortcut.
    func restart() {
        stop()
        start()
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
        let b = activeBindings

        if matchesNSEvent(keyCode: keyCode, flags: flags, binding: b.quickChat) {
            miniWindowCallback?()
            return true
        }
        if matchesNSEvent(keyCode: keyCode, flags: flags, binding: b.toggleWindow) {
            mainWindowCallback?()
            return true
        }
        if matchesNSEvent(keyCode: keyCode, flags: flags, binding: b.pasteToChat) {
            pasteCallback?()
            return true
        }

        return false
    }

    /// Check whether an NSEvent matches a HotkeyBinding.
    private static func matchesNSEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags, binding: HotkeyBinding) -> Bool {
        keyCode == binding.keyCode && flags == binding.nsModifierFlags
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
    let b = HotkeyManager.activeBindings

    if matchesCGEvent(keyCode: keyCode, flags: flags, binding: b.quickChat) {
        HotkeyManager.miniWindowCallback?()
        return nil // consume
    }

    if matchesCGEvent(keyCode: keyCode, flags: flags, binding: b.toggleWindow) {
        HotkeyManager.mainWindowCallback?()
        return nil
    }

    if matchesCGEvent(keyCode: keyCode, flags: flags, binding: b.pasteToChat) {
        HotkeyManager.pasteCallback?()
        return nil
    }

    return Unmanaged.passRetained(event)
}

/// Check whether a CGEvent matches a HotkeyBinding by comparing key code and exact modifier state.
/// Uses raw modifiers field directly to avoid accessing main-actor-isolated computed properties.
nonisolated private func matchesCGEvent(keyCode: UInt16, flags: CGEventFlags, binding: HotkeyBinding) -> Bool {
    guard keyCode == binding.keyCode else { return false }
    let expected = CGEventFlags(rawValue: binding.modifiers)
    let ctrl  = flags.contains(.maskControl)
    let alt   = flags.contains(.maskAlternate)
    let shift = flags.contains(.maskShift)
    let cmd   = flags.contains(.maskCommand)
    return ctrl == expected.contains(.maskControl)
        && alt == expected.contains(.maskAlternate)
        && shift == expected.contains(.maskShift)
        && cmd == expected.contains(.maskCommand)
}
