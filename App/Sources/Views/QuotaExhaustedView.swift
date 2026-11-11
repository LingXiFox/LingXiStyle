import SwiftUI
import LingXiKit

/// Quiet end-of-allowance sheet. No countdown, no fake urgency, no automatic paywall.
struct QuotaExhaustedView: View {
    let limit: Int
    var onUpgrade: () -> Void
    var onDismiss: () -> Void
    var controlInset: CGFloat = 0
    @Environment(\.displayCornerInset) private var displayCornerInset

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            AmbientBackdrop(intensity: .quiet)

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                        }
                        .accessibilityLabel("关闭")
                    }
                    .padding(.trailing, controlInset)
                    .padding(.top, displayCornerInset > 0 ? Spacing.s : 0)

                    ZStack {
                        Circle()
                            .fill(Palette.fillControl)
                            .frame(width: 52, height: 52)
                        Image(systemName: "moon")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Palette.thinking)
                    }
                    .accessibilityHidden(true)

                    Text("今日免费额度已用完")
                        .font(Typography.sheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.m)
                        .accessibilityAddTraits(.isHeader)

                    Text(String(localized: "quota.exhaustedBody", defaultValue: "每天 00:00 按本地时间重置，明天会恢复 \(limit) 张。没有处理的照片不会消耗额度。"))
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Spacing.xs)

                    VStack(spacing: Spacing.xs) {
                        PrimaryActionButton(title: String(localized: "了解\(Brand.name) Pro")) {
                            onUpgrade()
                        }
                        SecondaryActionButton(title: String(localized: "明天再来")) {
                            onDismiss()
                        }
                    }
                    .padding(.top, Spacing.l)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .duoSheetWidth()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日免费额度已用完")
    }
}
