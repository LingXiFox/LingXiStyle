import SwiftUI
import LingXiKit

/// Compact allowance chip shown on the home screen and above the selection CTA.
/// It never invents a price or a count: the numbers come from QuotaStatus, which is
/// backed by the same StoreKit-aware quota ledger as the conversion service.
struct QuotaBadge: View {
    let quota: QuotaStatus?
    let isPro: Bool
    var compact = false
    var onTap: (() -> Void)?

    private var title: String {
        if isPro || quota?.isPro == true {
            return String(localized: "quota.badge.pro", defaultValue: "\(Brand.proName) · 无限转换")
        }
        guard let quota else { return String(localized: "正在读取今日额度") }
        guard quota.isAvailable else { return String(localized: "今日额度暂不可用") }
        if quota.remaining <= 0 { return String(localized: "今日免费额度已用完") }
        return String(localized: "quota.badge.remaining", defaultValue: "今日剩余 \(quota.remaining) / \(quota.limit) 张")
    }

    private var symbol: String {
        if isPro || quota?.isPro == true { return "sparkles" }
        if quota?.remaining == 0 { return "clock.badge.exclamationmark" }
        return "bolt.fill"
    }

    private var tint: Color {
        if isPro || quota?.isPro == true { return Palette.accentSecondary }
        if quota?.remaining == 0 { return Palette.warning }
        return Palette.accent
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(compact ? Typography.micro : Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary.opacity(0.55))
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, compact ? 5 : 7)
            .background(Palette.surface.opacity(0.82), in: Capsule())
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [tint.opacity(0.42), Palette.hairline],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                lineWidth: 1
            ))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(onTap == nil ? "" : (isPro
            ? String(localized: "查看 Pro 权益和恢复购买")
            : String(localized: "quota.badge.openPro", defaultValue: "打开 \(Brand.proName)")))
    }
}
