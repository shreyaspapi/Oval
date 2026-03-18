import Testing
import AppKit
import Carbon.HIToolbox
@testable import Oval

@Suite("HotkeyBinding")
struct HotkeyBindingTests {

    @Test("Carbon modifiers mirror stored modifier flags")
    func carbonModifierMapping() {
        let binding = HotkeyBinding(
            keyCode: UInt16(kVK_Space),
            cgFlags: [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        )

        let expected = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        #expect(binding.carbonModifiers == expected)
    }

    @Test("Supported global shortcuts include Control or Command")
    func supportedGlobalShortcutValidation() {
        let optionShift = HotkeyBinding(
            keyCode: UInt16(kVK_Space),
            cgFlags: [.maskAlternate, .maskShift]
        )
        let controlShift = HotkeyBinding(
            keyCode: UInt16(kVK_Space),
            cgFlags: [.maskControl, .maskShift]
        )
        let commandOnly = HotkeyBinding(
            keyCode: UInt16(kVK_Space),
            cgFlags: [.maskCommand]
        )

        #expect(optionShift.isSupportedGlobalShortcut == false)
        #expect(controlShift.isSupportedGlobalShortcut)
        #expect(commandOnly.isSupportedGlobalShortcut)
    }

    @Test("Default quick chat shortcut avoids Control-Space")
    func defaultsUseNonConflictingQuickChatShortcut() {
        #expect(HotkeyPreferences.defaults.quickChat.displayString == "Ctrl + Shift + Space")
    }
}
