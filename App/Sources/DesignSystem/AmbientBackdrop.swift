import SwiftUI

/// A static, very low-contrast atmosphere. Light centers sit outside the screen so no glow ball
/// or seam is visible; Reduce Transparency hides it and Increase Contrast halves it.
enum AmbientIntensity {
    case empty, standard, quiet

    var scale: Double {
        switch self {
        case .empty: return 1.5
        case .standard: return 1.0
        case .quiet: return 0.4
        }
    }
}

struct AmbientBackdrop: View {
    var intensity: AmbientIntensity = .standard
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let long = max(proxy.size.width, proxy.size.height)
            let k = intensity.scale * (contrast == .increased ? 0.5 : 1)
            let dark = scheme == .dark
            ZStack {
                glow(dark ? Color(red: 107 / 255, green: 111 / 255, blue: 235 / 255)
                          : Color(red: 91 / 255, green: 95 / 255, blue: 214 / 255),
                     alpha: (dark ? 0.13 : 0.06) * k,
                     center: UnitPoint(x: -0.22, y: -0.16),
                     radius: long * 0.62)
                glow(dark ? Color(red: 46 / 255, green: 196 / 255, blue: 184 / 255)
                          : Color(red: 22 / 255, green: 163 / 255, blue: 156 / 255),
                     alpha: (dark ? 0.09 : 0.045) * k,
                     center: UnitPoint(x: 1.22, y: 1.12),
                     radius: long * 0.58)
                glow(Color(red: 232 / 255, green: 161 / 255, blue: 58 / 255),
                     alpha: (dark ? 0.035 : 0.015) * k,
                     center: UnitPoint(x: -0.18, y: 1.18),
                     radius: long * 0.45)
            }
        }
        .opacity(reduceTransparency ? 0 : 1)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, alpha: Double, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(alpha), color.opacity(0)],
                       center: center, startRadius: 0, endRadius: radius)
    }
}
