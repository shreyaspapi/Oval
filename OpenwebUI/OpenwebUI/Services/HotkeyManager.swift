import AppKit
import Carbon.HIToolbox

private enum HotkeyAction: UInt32, CaseIterable {
    case quickChat = 1
    case toggleWindow = 2
    case pasteToChat = 3
}

/// Manages global keyboard shortcuts using Carbon event hotkeys.
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

    // MARK: - Carbon Registration

    private var handlerRef: EventHandlerRef?
    private var registrations: [HotkeyAction: EventHotKeyRef] = [:]

    // MARK: - Shared State (nonisolated for C callback access)

    /// These closures are set from the main actor and invoked by the Carbon event handler.
    nonisolated(unsafe) static var miniWindowCallback: (() -> Void)?
    nonisolated(unsafe) static var mainWindowCallback: (() -> Void)?
    nonisolated(unsafe) static var pasteCallback: (() -> Void)?

    func start() {
        HotkeyManager.miniWindowCallback = { [weak self] in
            Task { @MainActor in self?.onToggleMiniWindow?() }
        }
        HotkeyManager.mainWindowCallback = { [weak self] in
            Task { @MainActor in self?.onToggleMainWindow?() }
        }
        HotkeyManager.pasteCallback = { [weak self] in
            Task { @MainActor in self?.onPasteToMiniChat?() }
        }

        installEventHandlerIfNeeded()
        registerHotkeys()
    }

    func stop() {
        unregisterHotkeys()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        HotkeyManager.miniWindowCallback = nil
        HotkeyManager.mainWindowCallback = nil
        HotkeyManager.pasteCallback = nil
    }

    /// Stop and re-start with the current `bindings`. Call after the user changes a shortcut.
    func restart() {
        stop()
        start()
    }

    // MARK: - Registration

    private func installEventHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventSpec,
            nil,
            &handlerRef
        )

        if status != noErr {
            NSLog("HotkeyManager: failed to install hotkey handler (\(status))")
        }
    }

    private func registerHotkeys() {
        unregisterHotkeys()

        register(binding: bindings.quickChat, action: .quickChat)
        register(binding: bindings.toggleWindow, action: .toggleWindow)
        register(binding: bindings.pasteToChat, action: .pasteToChat)
    }

    private func register(binding: HotkeyBinding, action: HotkeyAction) {
        guard binding.isSupportedGlobalShortcut else {
            NSLog("HotkeyManager: skipped unsupported shortcut for action \(action.rawValue)")
            return
        }

        let hotkeySignature: OSType = 0x4F56414C // "OVAL"
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = hotkeySignature
        hotKeyID.id = action.rawValue

        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            NSLog("HotkeyManager: failed to register shortcut for action \(action.rawValue) (\(status))")
            return
        }

        registrations[action] = hotKeyRef
    }

    private func unregisterHotkeys() {
        for hotKeyRef in registrations.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        registrations.removeAll()
    }

    nonisolated fileprivate static func handleHotkeyEvent(id: EventHotKeyID) {
        guard id.signature == OSType(0x4F56414C) else { return } // "OVAL"

        switch HotkeyAction(rawValue: id.id) {
        case .quickChat:
            miniWindowCallback?()
        case .toggleWindow:
            mainWindowCallback?()
        case .pasteToChat:
            pasteCallback?()
        case .none:
            break
        }
    }
}

// MARK: - Carbon Event Handler

nonisolated private func carbonHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else {
        return status
    }

    HotkeyManager.handleHotkeyEvent(id: hotKeyID)
    return noErr
}
