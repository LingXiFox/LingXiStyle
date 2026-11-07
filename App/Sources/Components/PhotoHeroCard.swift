import SwiftUI

/// The photo is always shown untouched and uncropped. 1.5 removes the breathing border and
/// scan line: the only motion is the one-shot selection pop, and status lives in badges.
struct PhotoHeroCard: View {
    let image: UIImage?
    var badge: CompatibilityBadge.Kind?
    var isPreparing: Bool = false
    /// Changes when the user picks another photo; used only for the 0.98 → 1 selection pop.
    var selectionID: UUID?
    var infoLeading: String?
    var infoTrailing: String?
    var statusText: String?
    var showsRunningDot: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    @State private var cardScale: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(String(localized: "所选照片预览"))
                } else {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "photo")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Palette.textTertiary)
                        Text("正在准备预览")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            if isPreparing {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Palette.running)
                    .padding(Spacing.s)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Spacing.m)
            }

            if let badge {
                CompatibilityBadge(kind: badge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Spacing.m)
            }

            if let infoLeading {
                HStack(spacing: Spacing.xs) {
                    Text(infoLeading)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.xs)
                    if let infoTrailing {
                        Text(infoTrailing)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .background(.ultraThinMaterial)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if let statusText {
                HStack(spacing: 6) {
                    if showsRunningDot {
                        Circle()
                            .fill(Palette.running)
                            .frame(width: 6, height: 6)
                    }
                    Text(statusText)
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                }
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(Spacing.m)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: Palette.shadow, radius: 18, y: 8)
        .scaleEffect(cardScale)
        .onChange(of: selectionID) { _, newValue in
            guard newValue != nil else { return }
            guard !reduceMotion else {
                cardScale = 1
                return
            }
            cardScale = 0.98
            withAnimation(Motion.selection) { cardScale = 1 }
        }
    }
}
