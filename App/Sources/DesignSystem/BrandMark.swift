import SwiftUI

/// Temporary app mark drawn in code, per the 1.5 handoff. It is a 3×3 milk grid on brand ink
/// with the center cell in fox orange.
struct BrandMark: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    private let opacity: [[Double]] = [
        [1, 0.55, 1],
        [0.55, 1, 0.30],
        [1, 0.30, 0.55]
    ]

    var body: some View {
        let corner = size * 0.234
        let inset = size * 0.2
        let gap = size * 0.0625
        let cell = (size - inset * 2 - gap * 2) / 3

        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Palette.brandInk)
            .overlay {
                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { column in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(column == 1 && row == 1 ? Palette.accent : Palette.brandMilk)
                                    .opacity(column == 1 && row == 1 ? 1 : opacity[row][column])
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .overlay {
                if scheme == .dark {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .shadow(color: scheme == .dark ? .clear : Palette.shadow, radius: size * 0.12, y: size * 0.04)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
