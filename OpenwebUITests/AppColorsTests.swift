import Testing
import SwiftUI
import AppKit
@testable import Oval

@Suite("AppColors & Theme")
struct AppColorsTests {

    // MARK: - Color(hex:) Tests

    @Test("Color hex initializer parses valid hex")
    func colorHexValid() {
        // Should not crash
        let _ = Color(hex: "#ff0000")
        let _ = Color(hex: "00ff00")
        let _ = Color(hex: "#0000ff")
    }

    @Test("Color hex initializer handles no hash prefix")
    func colorHexNoHash() {
        let _ = Color(hex: "ff0000")
    }

    // MARK: - NSColor(hex:) Tests

    @Test("NSColor hex initializer parses correctly")
    func nsColorHex() {
        let red = NSColor(hex: "#ff0000")
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        red.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.99)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test("NSColor hex initializer for white")
    func nsColorHexWhite() {
        let white = NSColor(hex: "#ffffff")
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        white.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.99)
        #expect(g > 0.99)
        #expect(b > 0.99)
    }

    @Test("NSColor hex initializer for black")
    func nsColorHexBlack() {
        let black = NSColor(hex: "#000000")
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        black.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    // MARK: - NSAppearance.isDark Tests

    @Test("NSAppearance.isDark returns correct value for aqua")
    func isDarkAqua() {
        let aqua = NSAppearance(named: .aqua)!
        #expect(aqua.isDark == false)
    }

    @Test("NSAppearance.isDark returns correct value for darkAqua")
    func isDarkDarkAqua() {
        let darkAqua = NSAppearance(named: .darkAqua)!
        #expect(darkAqua.isDark == true)
    }

    // MARK: - Static Color Properties Existence

    @Test("static gray scale colors exist")
    func grayScaleColors() {
        // Just verify they don't crash when accessed
        let _ = AppColors.gray50
        let _ = AppColors.gray100
        let _ = AppColors.gray200
        let _ = AppColors.gray300
        let _ = AppColors.gray400
        let _ = AppColors.gray500
        let _ = AppColors.gray600
        let _ = AppColors.gray700
        let _ = AppColors.gray800
        let _ = AppColors.gray850
        let _ = AppColors.gray900
        let _ = AppColors.gray950
    }

    @Test("semantic surface colors exist")
    func semanticColors() {
        let _ = AppColors.sidebarBg
        let _ = AppColors.chatBg
        let _ = AppColors.inputBg
        let _ = AppColors.hoverBg
        let _ = AppColors.selectedBg
        let _ = AppColors.borderColor
        let _ = AppColors.userBubble
        let _ = AppColors.accentBlue
    }

    @Test("text colors exist")
    func textColors() {
        let _ = AppColors.textPrimary
        let _ = AppColors.textSecondary
        let _ = AppColors.textTertiary
        let _ = AppColors.textPlaceholder
        let _ = AppColors.textHeading
        let _ = AppColors.textBold
    }

    @Test("code block colors exist")
    func codeBlockColors() {
        let _ = AppColors.inlineCodeText
        let _ = AppColors.inlineCodeBg
        let _ = AppColors.codeBlockBg
        let _ = AppColors.codeBlockHeader
        let _ = AppColors.codeBlockText
    }

    @Test("component colors exist")
    func componentColors() {
        let _ = AppColors.sendButtonBg
        let _ = AppColors.sendButtonIcon
        let _ = AppColors.sendButtonDisabled
        let _ = AppColors.avatarBg
        let _ = AppColors.fileAttachmentBg
        let _ = AppColors.searchFieldBg
    }

    // MARK: - AppFont Tests

    @Test("AppFont body returns system font")
    func appFontBody() {
        let _ = AppFont.body()
        let _ = AppFont.body(size: 16)
    }

    @Test("AppFont variants exist")
    func appFontVariants() {
        let _ = AppFont.semibold()
        let _ = AppFont.bold()
        let _ = AppFont.mono()
        let _ = AppFont.caption()
        let _ = AppFont.h1
        let _ = AppFont.h2
        let _ = AppFont.h3
    }
}
