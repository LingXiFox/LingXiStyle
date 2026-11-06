import SwiftUI

/// The photo is always shown untouched and uncropped. Only the border layer carries motion,
/// which keeps the "your pixels never moved" promise visible.
struct PhotoHeroCard: View {
    let image: UIImage?
    var isWorking: Bool = false
    var isScanning: Bool = false
    var badge: CompatibilityBadge.Kind?
    /// Changes when the user picks another photo; used only for the 0.98 → 1 selection pop.
    var selectionID: UUID?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    @State private var scanProgress: CGFloat = 0
    @State private var breathe = false
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
                        .accessibilityLabel("所选照片预览")
                } else {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "photo")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Palette.textSecondary)
                        Text("正在准备预览")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card - 4, style: .continuous))
            .padding(6)

            if isWorking && !reduceMotion {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(breathe ? 0.55 : 0.15), lineWidth: 2)
                    .shadow(color: Palette.accent.opacity(breathe ? 0.35 : 0), radius: 12)
            }

            if isScanning && !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, Palette.accent.opacity(0.9), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 2)
                        .offset(y: scanProgress * max(proxy.size.height - 2, 0))
                        .shadow(color: Palette.accent.opacity(0.8), radius: 6)
                }
                .mask(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(lineWidth: 2))
                .allowsHitTesting(false)
            }

            if let badge {
                VStack {
                    HStack {
                        CompatibilityBadge(kind: badge)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
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
        .onAppear { startAnimationIfNeeded() }
        .onChange(of: isWorking) { _, _ in startAnimationIfNeeded() }
        .onChange(of: isScanning) { _, _ in startAnimationIfNeeded() }
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

    private func startAnimationIfNeeded() {
        guard !reduceMotion else {
            scanProgress = 0
            breathe = false
            return
        }
        if isWorking {
            withAnimation(Motion.breathe) { breathe = true }
        } else {
            breathe = false
        }
        if isScanning {
            scanProgress = 0
            withAnimation(Motion.scan) { scanProgress = 1 }
        }
    }
}
