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

    private var symbol: String? {
        if isPro || quota?.isPro == true { return "sparkles" }
        if quota?.remaining == 0 { return "clock" }
        return nil
    }

    private var symbolTint: Color {
        if quota?.remaining == 0 && !(isPro || quota?.isPro == true) { return Palette.warning }
        return Palette.textSecondary
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(symbolTint)
                }
                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.s)
            .frame(height: 32)
            .background(Palette.fillControl, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(onTap == nil ? "" : (isPro || quota?.isPro == true
            ? String(localized: "查看 Pro 权益和恢复购买")
            : String(localized: "quota.badge.openPro", defaultValue: "打开 \(Brand.proName)")))
    }
}
