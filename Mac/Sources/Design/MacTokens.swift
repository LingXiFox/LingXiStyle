import AppKit
import SwiftUI
import LingXiKit

/// macOS counterpart of `App/Sources/DesignSystem/Tokens.swift`. The brand values are the same;
/// the structure colors come from AppKit semantic colors so light/dark, Increase Contrast and the
/// system accent-independent palette stay native.
enum MacPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color.adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let hairline = Color(nsColor: .separatorColor)
    static let fillControl = Color(nsColor: .quaternaryLabelColor).opacity(0.18)

    /// Fox orange is the only interaction accent, exactly as on iPhone.
    static let accent = Color(hex: 0xE8A13A)
    static let accentText = Color.adaptive(light: 0xB97A18, dark: 0xF2B75C)
    static let accentSoft = Color.adaptive(light: 0xE8A13A, dark: 0xE8A13A, lightAlpha: 0.14, darkAlpha: 0.22)
    static let onAccent = Color(hex: 0x1A1410)

    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
    static let info = Color(nsColor: .systemBlue)

    static let selection = Color(nsColor: .selectedContentBackgroundColor)
    static let shadowColor = Color.black.opacity(0.12)
}

enum MacSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

enum MacRadius {
    static let card: CGFloat = 16
    static let group: CGFloat = 12
    static let button: CGFloat = 10
    static let thumbnail: CGFloat = 10
}

enum MacType {
    static let display = Font.system(size: 30, weight: .bold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasized = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11)
    static let micro = Font.system(size: 10, weight: .medium)
    static let numeric = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    static let statNumber = Font.system(size: 20, weight: .bold, design: .rounded).monospacedDigit()
    static let brand = Font.system(size: 15, weight: .semibold)
}

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// Same trick as the iOS tokens: one color that follows the system appearance.
    static func adaptive(light: Int, dark: Int, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: CGFloat(alpha))
    }
}

/// Hosting a shared brand card without duplicating the iOS "elevated surface" recipe.
struct MacCard<Content: View>: View {
    var padding: CGFloat = MacSpacing.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MacRadius.card, style: .continuous)
                .fill(MacPalette.surfaceElevated))
            .overlay(RoundedRectangle(cornerRadius: MacRadius.card, style: .continuous)
                .strokeBorder(MacPalette.hairline.opacity(0.6), lineWidth: 0.5))
    }
}

/// Brand primary button: fox orange fill with brand ink label (8.33:1), never white-on-orange.
struct MacPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacType.bodyEmphasized)
            .foregroundStyle(MacPalette.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: MacRadius.button, style: .continuous)
                .fill(MacPalette.accent.opacity(configuration.isPressed ? 0.82 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.button, style: .continuous))
    }
}

struct MacQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacType.body)
            .foregroundStyle(MacPalette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: MacRadius.button, style: .continuous)
                .fill(MacPalette.fillControl)
                .opacity(configuration.isPressed ? 0.7 : 1))
    }
}

extension VaultRecord {
    /// "剩 6 天 3 小时" style countdown for the lists and the preview.
    func remainingText(at date: Date = Date()) -> String {
        guard let remaining = remainingLifetime(at: date) else {
            return String(localized: "永久保留", defaultValue: "永久保留")
        }
        return String(localized: "剩 %@", defaultValue: "剩 \(MacModel.lifetimeText(remaining))")
    }
}

