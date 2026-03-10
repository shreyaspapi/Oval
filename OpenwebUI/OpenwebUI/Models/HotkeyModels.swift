import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey Binding

/// A single customizable keyboard shortcut: key code + modifier flags.
/// Codable so it can be persisted to config.json.
/// Sendable so it can be safely read from the nonisolated CGEvent callback.
struct HotkeyBinding: Codable, Equatable, Sendable {
    /// Virtual key code (`kVK_*` constants from Carbon).
    var keyCode: UInt16
    /// Raw value of `CGEventFlags` for CGEvent path / `NSEvent.ModifierFlags` for NSEvent path.
    var modifiers: UInt64

    // MARK: - Modifier helpers

    var control: Bool { CGEventFlags(rawValue: modifiers).contains(.maskControl) }
    var option: Bool  { CGEventFlags(rawValue: modifiers).contains(.maskAlternate) }
    var shift: Bool   { CGEventFlags(rawValue: modifiers).contains(.maskShift) }
    var command: Bool  { CGEventFlags(rawValue: modifiers).contains(.maskCommand) }

    /// Create from an NSEvent (used by the shortcut recorder and NSEvent monitor).
    init(keyCode: UInt16, nsFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        // Store only device-independent flags and convert to CGEventFlags raw value
        let clean = nsFlags.intersection(.deviceIndependentFlagsMask)
        var cg = CGEventFlags()
        if clean.contains(.control)  { cg.insert(.maskControl) }
        if clean.contains(.option)   { cg.insert(.maskAlternate) }
        if clean.contains(.shift)    { cg.insert(.maskShift) }
        if clean.contains(.command)  { cg.insert(.maskCommand) }
        self.modifiers = cg.rawValue
    }

    /// Create directly from raw values (for defaults).
    init(keyCode: UInt16, cgFlags: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = cgFlags.rawValue
    }

    /// Create from raw numeric values (nonisolated-safe, avoids actor isolation on custom inits).
    nonisolated init(rawKeyCode: UInt16, rawModifiers: UInt64) {
        self.keyCode = rawKeyCode
        self.modifiers = rawModifiers
    }

    /// NSEvent.ModifierFlags equivalent (for the NSEvent fallback path).
    var nsModifierFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if control  { flags.insert(.control) }
        if option   { flags.insert(.option) }
        if shift    { flags.insert(.shift) }
        if command  { flags.insert(.command) }
        return flags
    }

    /// Human-readable label (e.g. "Ctrl + Opt + Space").
    var displayString: String {
        var parts: [String] = []
        if control  { parts.append("Ctrl") }
        if option   { parts.append("Opt") }
        if shift    { parts.append("Shift") }
        if command  { parts.append("Cmd") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    // MARK: - Key name lookup

    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space:            return "Space"
        case kVK_Return:           return "Return"
        case kVK_Tab:              return "Tab"
        case kVK_Delete:           return "Delete"
        case kVK_ForwardDelete:    return "Fwd Del"
        case kVK_Escape:           return "Esc"
        case kVK_UpArrow:          return "Up"
        case kVK_DownArrow:        return "Down"
        case kVK_LeftArrow:        return "Left"
        case kVK_RightArrow:       return "Right"
        case kVK_Home:             return "Home"
        case kVK_End:              return "End"
        case kVK_PageUp:           return "Page Up"
        case kVK_PageDown:         return "Page Down"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Slash:        return "/"
        case kVK_ANSI_Grave:        return "`"
        default:                    return "Key(\(keyCode))"
        }
    }
}

// MARK: - Hotkey Preferences

/// All customizable global hotkey bindings.
struct HotkeyPreferences: Codable, Equatable, Sendable {
    var quickChat: HotkeyBinding
    var toggleWindow: HotkeyBinding
    var pasteToChat: HotkeyBinding

    /// Nonisolated memberwise init (allows use from nonisolated static contexts).
    nonisolated init(quickChat: HotkeyBinding, toggleWindow: HotkeyBinding, pasteToChat: HotkeyBinding) {
        self.quickChat = quickChat
        self.toggleWindow = toggleWindow
        self.pasteToChat = pasteToChat
    }

    /// Factory defaults matching the original hard-coded hotkeys.
    static let defaults = HotkeyPreferences(
        quickChat:    HotkeyBinding(keyCode: UInt16(kVK_Space),  cgFlags: .maskControl),
        toggleWindow: HotkeyBinding(keyCode: UInt16(kVK_Space),  cgFlags: [.maskControl, .maskAlternate]),
        pasteToChat:  HotkeyBinding(keyCode: UInt16(kVK_ANSI_V), cgFlags: [.maskControl, .maskShift])
    )
}
