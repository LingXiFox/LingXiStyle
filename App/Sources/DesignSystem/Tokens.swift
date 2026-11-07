import SwiftUI
import UIKit

/// 1.5 design tokens. Structure uses iOS semantic colors; fox orange is the only interaction
/// accent. The handoff's #C24A14 was overridden by the owner with #E8A13A, so the foreground on
/// the accent fill is brand ink (#1A1410, 8.33:1) instead of white (2.19:1).
enum Palette {
    // Structure: iOS semantic colors, so light/dark and Increase Contrast stay native.
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    // The handoff's tertiarySystemGroupedBackground collapses into systemGroupedBackground
    // in light mode, which would erase elevated cards on the page background. Keep the
    // intended contrast in both appearances: white in light, #2C2C2E in dark.
    static let surfaceElevated = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    static let hairline = Color(uiColor: .separator)
    static let fillControl = Color(uiColor: .tertiarySystemFill)
    static let shadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.10, darkAlpha: 0.30)

    // Interaction brand: fox orange. accentText is the darker variant used for text and icons.
    static let accent = Color(light: 0xE8A13A, dark: 0xE8A13A)
    static let accentText = Color(light: 0xB3430F, dark: 0xE8A13A)
    static let accentSoft = Color(light: 0xE8A13A, dark: 0xE8A13A, lightAlpha: 0.10, darkAlpha: 0.22)
    static let onAccent = Color(light: 0x1A1410, dark: 0x1A1410)

    // Atmosphere: only the backdrop and small running indicators.
    static let running = Color(light: 0x0E8A85, dark: 0x3CC9BD)
    static let thinking = Color(light: 0x4A4FC0, dark: 0x9EA2F5)

    // Semantic status: icons only; labels stay textPrimary.
    static let success = Color(light: 0x248A3D, dark: 0x30DB5B)
    static let warning = Color(light: 0xB25000, dark: 0xFFD426)
    static let error = Color(light: 0xD70015, dark: 0xFF6961)
    static let info = Color(light: 0x0040DD, dark: 0x409CFF)

    // Brand ink: icon mark only, never a page background.
    static let brandInk = Color(light: 0x1A1410, dark: 0x1A1410)
    static let brandMilk = Color(light: 0xF6F1E8, dark: 0xF6F1E8)
}

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32

    /// 20pt on regular width, 16pt on narrow phones.
    static func margin(for width: CGFloat) -> CGFloat { width < 390 ? 16 : 20 }
}

enum Radius {
    static let card: CGFloat = 20
    static let group: CGFloat = 14
    static let button: CGFloat = 14
    static let thumbnail: CGFloat = 14
    static let chip: CGFloat = 12
    static let stat: CGFloat = 12
}

/// Text styles keep Dynamic Type working; explicit point sizes would freeze it.
enum Typography {
    static let brand = Font.system(.title, design: .default, weight: .semibold)
    static let hero = Font.system(.largeTitle, design: .default, weight: .bold)
    static let sheetTitle = Font.system(.title, design: .default, weight: .bold)
    static let section = Font.system(.title2, design: .default, weight: .semibold)
    static let status = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default)
    static let bodyEmphasized = Font.system(.body, design: .default, weight: .medium)
    static let caption = Font.system(.footnote, design: .default)
    static let captionEmphasized = Font.system(.footnote, design: .default, weight: .semibold)
    static let micro = Font.system(.caption2, design: .default, weight: .medium)
    static let numeric = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()
    static let statNumber = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let monospaced = Font.system(.footnote, design: .monospaced)
}

enum Layout {
    static let minimumTouchTarget: CGFloat = 44
    static let heroAspect: CGFloat = 4.0 / 5.0
    static let thumbnailSide: CGFloat = 68
    static let primaryButtonHeight: CGFloat = 52
    static let secondaryButtonHeight: CGFloat = 48
}

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
