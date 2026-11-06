import SwiftUI
import UIKit

/// The brief's token table, expressed as real dynamic colors so light and dark are both
/// first-class instead of a dark palette with an inverted afterthought.
enum Palette {
    static let background = Color(light: 0xF6F8FB, dark: 0x0B101A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x161E2B)
    static let surfaceElevated = Color(light: 0xEAF0F7, dark: 0x202A39)
    static let textPrimary = Color(light: 0x182233, dark: 0xF7F9FC)
    static let textSecondary = Color(light: 0x526175, dark: 0xAAB6C8)
    static let accent = Color(light: 0x087DB5, dark: 0x82D7FF)
    /// Accent as text on background. The brief's accent is a fill color; at 4.28:1 it misses
    /// the 4.5:1 body-text bar in light mode, so text uses this slightly deeper variant.
    static let accentText = Color(light: 0x06688F, dark: 0x82D7FF)
    static let accentSecondary = Color(light: 0x7954C5, dark: 0xBBA7F4)
    static let success = Color(light: 0x148059, dark: 0x80DDB8)
    static let warning = Color(light: 0x956009, dark: 0xF3CD8A)
    static let error = Color(light: 0xBB3940, dark: 0xFF9F9F)
    static let hairline = Color(light: 0x182233, dark: 0xF7F9FC).opacity(0.10)
    static let shadow = Color(light: 0x182233, dark: 0x000000).opacity(0.12)
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
    static let card: CGFloat = 26
    static let button: CGFloat = 18
    static let thumbnail: CGFloat = 14
    static let chip: CGFloat = 12
}

/// Text styles keep Dynamic Type working; explicit point sizes would freeze it.
enum Typography {
    static let brand = Font.system(.title, design: .default, weight: .semibold)
    static let section = Font.system(.title2, design: .default, weight: .semibold)
    static let status = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default)
    static let bodyEmphasized = Font.system(.body, design: .default, weight: .medium)
    static let caption = Font.system(.footnote, design: .default)
    static let captionEmphasized = Font.system(.footnote, design: .default, weight: .semibold)
    static let micro = Font.system(.caption2, design: .default, weight: .medium)
    static let numeric = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()
}

enum Layout {
    static let minimumTouchTarget: CGFloat = 44
    static let heroAspect: CGFloat = 4.0 / 5.0
    static let thumbnailSide: CGFloat = 68
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
