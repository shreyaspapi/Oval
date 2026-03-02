import SwiftUI
import AppKit

/// Color palette matching Open WebUI's Tailwind theme.
/// Light values sourced from the actual Open WebUI web app (Tailwind v4, `darkMode: 'class'`).
/// Dark values are the real hex values from `open-webui/tailwind.css`.
///
/// Adaptive colors use `NSColor(name:dynamicProvider:)` to resolve
/// the correct value based on the current system appearance.
enum AppColors {

    // MARK: - Gray Scale (Open WebUI tailwind.css custom grays — pure neutral, chroma 0)
    //
    // These are *static* palette entries. Use the semantic colors below for UI.

    static let gray50  = Color(hex: "#f8f8f8")
    static let gray100 = Color(hex: "#ebebeb")
    static let gray200 = Color(hex: "#e4e4e4")
    static let gray300 = Color(hex: "#cecece")
    static let gray400 = Color(hex: "#b4b4b4")
    static let gray500 = Color(hex: "#9b9b9b")
    static let gray600 = Color(hex: "#666666")
    static let gray700 = Color(hex: "#4d4d4d")
    static let gray800 = Color(hex: "#333333")
    static let gray850 = Color(hex: "#262626")
    static let gray900 = Color(hex: "#161616")
    static let gray950 = Color(hex: "#0d0d0d")

    // MARK: - Greens

    static let green400   = Color(hex: "#4ade80")
    static let green500   = Color(hex: "#22c55e")
    static let emerald600 = Color(hex: "#059669")

    // MARK: - Blues

    static let blue500 = Color(hex: "#3b82f6")
    static let blue600 = Color(hex: "#2563eb")

    // MARK: - Reds

    static let red400 = Color(hex: "#f87171")
    static let red500 = Color(hex: "#ef4444")

    // MARK: - Semantic Surfaces (Adaptive: light ↔ dark)
    //
    // Light values from Open WebUI web app:
    //   sidebar: bg-gray-50     chat: bg-white      input: bg-gray-50
    //   hover: bg-gray-100      selected: bg-gray-100
    //   border: gray-200        user bubble: bg-gray-50
    //
    // Dark values:
    //   sidebar: bg-gray-950    chat: bg-gray-900    input: #2f2f2f
    //   hover: #2a2a2a          selected: #343434
    //   border: #2e2e2e         user bubble: bg-gray-850

    /// Sidebar background: bg-gray-50 (light) / bg-gray-950 (dark)
    static let sidebarBg = adaptive(light: "#f8f8f8", dark: "#0d0d0d")

    /// Main chat area: bg-white (light) / bg-gray-900 (dark)
    static let chatBg = adaptive(light: "#ffffff", dark: "#161616")

    /// Input field background: bg-gray-50 (light) / #2f2f2f (dark)
    static let inputBg = adaptive(light: "#f8f8f8", dark: "#2f2f2f")

    /// Hover state (sidebar items): bg-gray-100 (light) / #2a2a2a (dark)
    static let hoverBg = adaptive(light: "#ebebeb", dark: "#2a2a2a")

    /// Selected item: bg-gray-100 (light) / #343434 (dark)
    static let selectedBg = adaptive(light: "#ebebeb", dark: "#343434")

    /// Subtle borders: gray-200 (light) / #2e2e2e (dark)
    static let borderColor = adaptive(light: "#e4e4e4", dark: "#2e2e2e")

    /// User message bubble: bg-gray-50 (light) / bg-gray-850 (dark)
    static let userBubble = adaptive(light: "#f8f8f8", dark: "#262626")

    /// Accent blue
    static let accentBlue = blue500

    // MARK: - Code Block Colors

    /// Inline code text color: text-gray-800 (light) / #eb5757 (dark)
    static let inlineCodeText = adaptive(light: "#333333", dark: "#eb5757")

    /// Inline code background: bg-gray-100 (light) / bg-gray-850 (dark)
    static let inlineCodeBg = adaptive(light: "#ebebeb", dark: "#262626")

    /// Code block background: bg-white (light) / bg-gray-800 (dark)
    static let codeBlockBg = adaptive(light: "#ffffff", dark: "#333333")

    /// Code block header: bg-white (light) / #1e1e1e (dark)
    static let codeBlockHeader = adaptive(light: "#ffffff", dark: "#1e1e1e")

    /// Code block text: text-gray-800 (light) / gray-200 (dark)
    static let codeBlockText = adaptive(light: "#333333", dark: "#e4e4e4")

    /// Code block border: gray-100/30 (light) / transparent (dark)
    static let codeBlockBorder = adaptive(light: "#ebebeb", dark: "#333333")

    // MARK: - Text Colors (Adaptive)

    /// Primary text: text-gray-700 (light) / text-gray-100 (dark)
    static let textPrimary = adaptive(light: "#4d4d4d", dark: "#ebebeb")

    /// Secondary text: text-gray-600 (light) / text-gray-400 (dark)
    static let textSecondary = adaptive(light: "#666666", dark: "#b4b4b4")

    /// Tertiary text: text-gray-500 in both modes
    static let textTertiary = adaptive(light: "#9b9b9b", dark: "#9b9b9b")

    /// Placeholder text: gray-400 in both modes
    static let textPlaceholder = adaptive(light: "#b4b4b4", dark: "#b4b4b4")

    /// Heading text: near-black (light) / near-white (dark)
    static let textHeading = adaptive(light: "#161616", dark: "#f8f8f8")

    /// Bold/emphasis text: text-gray-900 (light) / gray-50 (dark)
    static let textBold = adaptive(light: "#161616", dark: "#f8f8f8")

    /// Bullet/number list marker: text-gray-500 (light) / gray-400 (dark)
    static let textListMarker = adaptive(light: "#9b9b9b", dark: "#b4b4b4")

    /// Italic text: text-gray-600 (light) / gray-200 (dark)
    static let textItalic = adaptive(light: "#666666", dark: "#e4e4e4")

    // MARK: - Component-specific Colors

    /// Assistant avatar circle: bg-gray-100 (light) / bg-gray-800 (dark)
    static let avatarBg = adaptive(light: "#ebebeb", dark: "#333333")

    /// Avatar text: text-gray-600 (light) / gray-200 (dark)
    static let avatarText = adaptive(light: "#666666", dark: "#e4e4e4")

    /// File attachment background: bg-gray-100 (light) / bg-gray-800 (dark)
    static let fileAttachmentBg = adaptive(light: "#ebebeb", dark: "#333333")

    /// Search field background: bg-gray-100 (light) / bg-gray-850 (dark)
    static let searchFieldBg = adaptive(light: "#ebebeb", dark: "#262626")

    /// Action button hover: hover:bg-black/5 (light) / hover:bg-white/5 (dark)
    static let actionHover = adaptive(light: "#f2f2f2", dark: "#2a2a2a")

    /// Send button fill: bg-gray-900 (light) / white (dark)
    static let sendButtonBg = adaptive(light: "#161616", dark: "#ffffff")

    /// Send button icon: text-white (light) / text-gray-900 (dark)
    static let sendButtonIcon = adaptive(light: "#ffffff", dark: "#161616")

    /// Send button disabled: gray-300 (light) / gray-600 (dark)
    static let sendButtonDisabled = adaptive(light: "#cecece", dark: "#666666")

    /// Glass tint for user bubble: light tint in light, dark tint in dark
    static let userBubbleGlass = adaptive(light: "#e4e4e4", dark: "#262626")

    /// Glass tint for input field
    static let inputGlass = adaptive(light: "#e4e4e4", dark: "#2f2f2f")

    /// Glass tint for code blocks
    static let codeBlockGlass = adaptive(light: "#f8f8f8", dark: "#333333")

    /// Glass tint for toasts
    static let toastGlass = adaptive(light: "#f8f8f8", dark: "#262626")

    /// Welcome text: text-gray-600 (light) / gray-200 (dark)
    static let welcomeText = adaptive(light: "#666666", dark: "#e4e4e4")

    /// Server rail active icon bg
    static let serverIconBg = adaptive(light: "#ebebeb", dark: "#333333")

    /// Web search button active bg
    static let webSearchActiveBg = adaptive(light: "#3b82f6", dark: "#3b82f6")

    /// Input bottom bar bg (attach/send buttons area): subtle bg
    static let inputActionBg = adaptive(light: "#ebebeb", dark: "#333333")

    // MARK: - NSTextView Colors (for PasteInterceptingTextView)

    /// NSColor for text in NSTextView
    static var nsTextColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: "#ebebeb") : NSColor(hex: "#4d4d4d")
        }
    }

    /// NSColor for insertion point in NSTextView
    static var nsInsertionPointColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? .white : NSColor(hex: "#161616")
        }
    }

    // MARK: - Adaptive Color Helper

    /// Creates an adaptive SwiftUI Color that resolves differently in light vs dark mode.
    private static func adaptive(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

// MARK: - NSAppearance Helper

extension NSAppearance {
    /// Returns true if this appearance is a dark variant.
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - NSColor(hex:) Initializer

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Open WebUI Font

/// The base font stack from Open WebUI: Inter with system fallbacks.
enum AppFont {

    /// Body text font
    static func body(size: CGFloat = 14) -> Font {
        .system(size: size)
    }

    /// Semibold variant
    static func semibold(size: CGFloat = 14) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Bold variant
    static func bold(size: CGFloat = 14) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Monospaced for code
    static func mono(size: CGFloat = 13) -> Font {
        .system(size: size, design: .monospaced)
    }

    /// Heading sizes
    static let h1: Font = .system(size: 24, weight: .bold)
    static let h2: Font = .system(size: 20, weight: .bold)
    static let h3: Font = .system(size: 16, weight: .semibold)

    /// Caption / small text
    static func caption(size: CGFloat = 12) -> Font {
        .system(size: size)
    }
}

// MARK: - Color(hex:) Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
