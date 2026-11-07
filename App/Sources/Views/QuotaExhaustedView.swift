import SwiftUI
import LingXiKit

/// Shown when today's free allowance is gone. No countdown and no forced purchase:
/// the user can always come back tomorrow, or choose a lifetime unlock.
struct QuotaExhaustedView: View {
    let limit: Int
    var onUpgrade: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ambientLight

            VStack(spacing: 0) {
                HStack {
                    Text(Brand.name.uppercased())
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(Palette.accentText)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                            .background(Palette.surface.opacity(0.8), in: Circle())
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(.top, Spacing.s)

                Spacer(minLength: Spacing.xl)

                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.warning.opacity(0.22), .clear],
                                             center: .center, startRadius: 2, endRadius: 90))
                        .frame(width: 170, height: 170)
                    Circle()
                        .strokeBorder(Palette.warning.opacity(0.35), lineWidth: 1)
                        .frame(width: 86, height: 86)
                    Image(systemName: "moon.stars")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Palette.warning)
                }
                .accessibilityHidden(true)

                Text("今日免费额度已用完")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.m)
                    .accessibilityAddTraits(.isHeader)

                Text(String(localized: "quota.resetNote", defaultValue: "每天 00:00 按本地时间重置，明天会恢复 \(limit) 张免费额度。"))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.s)

                VStack(spacing: Spacing.s) {
                    PrimaryActionButton(title: String(localized: "永久解锁无限转换"), systemImage: "sparkles") {
                        onUpgrade()
                    }
                    SecondaryActionButton(title: String(localized: "明天继续免费使用"), systemImage: "sunrise") {
                        onDismiss()
                    }
                }
                .padding(.top, Spacing.xl)

                Text("不购买也可以继续使用免费额度。转换质量与完整性校验完全一致。")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.m)

                Spacer(minLength: Spacing.xl)
            }
            .padding(.horizontal, Spacing.margin(for: 390))
            .padding(.bottom, Spacing.l)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日免费额度已用完")
    }

    private var ambientLight: some View {
        ZStack {
            RadialGradient(colors: [Palette.warning.opacity(0.08), .clear],
                           center: .top, startRadius: 0, endRadius: 320)
                .offset(y: -80)
            RadialGradient(colors: [Palette.accent.opacity(0.10), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 300)
                .offset(x: -100, y: 120)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}