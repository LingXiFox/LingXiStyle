import SwiftUI
import LingXiKit

/// A quiet, photographic paywall: one lifetime purchase, the real localized App Store price,
/// and no countdowns, fake discounts or subscription language.
struct ProPurchaseView: View {
    @ObservedObject var purchases: PurchaseManager
    var onEntitlementChanged: () -> Void
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var purchaseTitle: String {
        if purchases.isPro { return String(localized: "pro.owner.title", defaultValue: "\(Brand.proName) 已解锁") }
        if let product = purchases.product {
            return String(localized: "pro.purchase.price", defaultValue: "永久解锁 · \(product.displayPrice)")
        }
        return purchases.isLoadingProduct
            ? String(localized: "正在读取 App Store 价格…")
            : String(localized: "永久解锁")
    }

    private var canPurchase: Bool {
        guard !purchases.isPro, purchases.product != nil else { return false }
        switch purchases.purchaseState {
        case .purchasing, .awaitingApproval: return false
        default: return true
        }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ambientLight

            ScrollView {
                VStack(spacing: 0) {
                    topBar

                    hero
                        .padding(.top, Spacing.s)

                    benefits
                        .padding(.top, Spacing.l)

                    priceCard
                        .padding(.top, Spacing.l)

                    purchaseArea
                        .padding(.top, Spacing.m)

                    restoreArea
                        .padding(.top, Spacing.m)

                    legal
                        .padding(.top, Spacing.l)
                        .padding(.bottom, Spacing.l)
                }
                .padding(.horizontal, Spacing.margin(for: 390))
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task {
            await purchases.start()
            if purchases.product == nil {
                await purchases.loadProduct()
            }
        }
        .onChange(of: purchases.isPro) { _, isPro in
            if isPro { onEntitlementChanged() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "pro.page.accessibility", defaultValue: "\(Brand.proName) 购买页"))
    }

    private var topBar: some View {
        HStack {
            Text(Brand.name.uppercased())
                .font(.system(.caption2, design: .default, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(Palette.accentText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                    .background(Palette.surface.opacity(0.8), in: Circle())
            }
            .accessibilityLabel("关闭 Pro 页面")
        }
        .padding(.top, Spacing.s)
    }

    private var hero: some View {
        VStack(spacing: Spacing.s) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.accent.opacity(0.24), Palette.accentSecondary.opacity(0.08), .clear],
                                         center: .center, startRadius: 2, endRadius: 64))
                    .frame(width: 120, height: 120)
                Circle()
                    .strokeBorder(LinearGradient(colors: [Palette.accent.opacity(0.7), Palette.accentSecondary.opacity(0.5)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
                    .frame(width: 68, height: 68)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(Palette.accent)
            }
            .accessibilityHidden(true)

            Text(Brand.proName)
                .font(.system(.title, design: .default, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("一次购买，永久解锁无限照片转换。")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            benefit(String(localized: "无限张数"),
                    detail: String(localized: "pro.benefit.unlimited.detail", defaultValue: "不再受每天 \(QuotaConfiguration.freeDailyLimit) 张免费额度限制"),
                    symbol: "infinity")
            Divider().overlay(Palette.hairline)
            benefit(String(localized: "一次购买，永久使用"),
                    detail: String(localized: "非订阅，不会按月扣费"),
                    symbol: "checkmark.seal")
            Divider().overlay(Palette.hairline)
            benefit(String(localized: "本职不变"),
                    detail: String(localized: "只补第三代纹理与颗粒，原图始终保留"),
                    symbol: "photo.badge.checkmark")
            Divider().overlay(Palette.hairline)
            benefit(String(localized: "免费仍可用"),
                    detail: String(localized: "pro.benefit.free.detail", defaultValue: "不购买也可以每天转换 \(QuotaConfiguration.freeDailyLimit) 张照片"),
                    symbol: "gift")
        }
        .padding(.horizontal, Spacing.m)
        .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var priceCard: some View {
        VStack(spacing: Spacing.xs) {
            if purchases.isLoadingProduct {
                ProgressView()
                    .tint(Palette.accent)
                Text("正在读取当前地区价格…")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else if let product = purchases.product {
                Text(product.displayPrice)
                    .font(Typography.numeric)
                    .foregroundStyle(Palette.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("一次性购买 · 永久使用")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Text("价格由 App Store 按当前商店地区显示")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary.opacity(0.8))
            } else {
                InlineErrorNotice(
                    message: purchases.productLoadError ?? String(localized: "暂时无法加载商品信息，请稍后重试。"),
                    actionTitle: String(localized: "重新加载")
                ) {
                    Task { await purchases.loadProduct() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.m)
        .background(Palette.surfaceElevated.opacity(0.62), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Palette.accent.opacity(0.34), Palette.hairline],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    private var purchaseArea: some View {
        VStack(spacing: Spacing.s) {
            if purchases.isPro {
                statusCard(String(localized: "pro.owner.card", defaultValue: "已解锁 \(Brand.proName)"),
                       detail: String(localized: "pro.owner.detail", defaultValue: "无限转换已生效。感谢支持独立开发。"),
                       symbol: "checkmark.seal.fill",
                       tint: Palette.success)
            } else {
                PrimaryActionButton(
                    title: purchaseTitle,
                    systemImage: "sparkles",
                    isEnabled: canPurchase,
                    isWorking: purchases.purchaseState == .purchasing
                ) {
                    Task { await purchases.purchase() }
                }

                switch purchases.purchaseState {
                case .awaitingApproval:
                    statusCard(String(localized: "等待批准"),
                       detail: String(localized: "购买正在等待 App Store 批准。批准后会自动解锁，不需要重复购买。"),
                       symbol: "hourglass",
                       tint: Palette.warning)
                case .cancelled:
                    statusCard(String(localized: "购买已取消"),
                       detail: String(localized: "没有产生扣款，你可以随时回来再购买。"),
                       symbol: "xmark.circle",
                       tint: Palette.textSecondary)
                case .failed(let message):
                    InlineErrorNotice(message: message)
                case .success:
                    statusCard(String(localized: "购买完成"),
                       detail: String(localized: "已验证交易，Pro 权益已生效。"),
                       symbol: "checkmark.circle.fill",
                       tint: Palette.success)
                case .idle, .purchasing:
                    EmptyView()
                }
            }
        }
    }

    private var restoreArea: some View {
        VStack(spacing: Spacing.xs) {
            SecondaryActionButton(title: purchases.isRestoring
                                  ? String(localized: "正在恢复…")
                                  : String(localized: "恢复购买"),
                                  systemImage: "arrow.clockwise") {
                Task { await purchases.restore() }
            }
            .disabled(purchases.isRestoring)

            if let message = purchases.restoreMessage {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var legal: some View {
        VStack(spacing: Spacing.xs) {
            Text("一次性非消耗型内购，不是订阅。购买后会向 App Store 验证交易，只有验证通过的权益才会解锁。")
            Text(String(localized: "pro.legal.freeLimit", defaultValue: "免费用户每天仍可转换 \(QuotaConfiguration.freeDailyLimit) 张照片，额度按本地自然日重置。"))
        }
        .font(Typography.micro)
        .foregroundStyle(Palette.textSecondary.opacity(0.8))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statusCard(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
            .strokeBorder(tint.opacity(0.26), lineWidth: 1))
    }

    private var ambientLight: some View {
        ZStack {
            RadialGradient(colors: [Palette.accent.opacity(colorScheme == .dark ? 0.17 : 0.10), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 360)
                .offset(x: -100, y: -130)
            RadialGradient(colors: [Palette.accentSecondary.opacity(colorScheme == .dark ? 0.12 : 0.07), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 320)
                .offset(x: 120, y: 140)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}