import SwiftUI
import LingXiKit

/// Quiet lifetime unlock sheet. The only price shown is Product.displayPrice; if the product
/// cannot be loaded there is an honest retry state, never a made-up amount.
struct ProPurchaseView: View {
    @ObservedObject var purchases: PurchaseManager
    var onEntitlementChanged: () -> Void
    var onClose: () -> Void
    @Environment(\.displayCornerInset) private var displayCornerInset
    var controlInset: CGFloat = 0

    private var purchaseTitle: String {
        if purchases.isPro { return String(localized: "pro.owner.title", defaultValue: "\(Brand.proName) 已解锁") }
        if let product = purchases.product {
            return String(localized: "pro.purchase.price", defaultValue: "一次性购买 · \(product.displayPrice)")
        }
        return purchases.isLoadingProduct
            ? String(localized: "正在读取 App Store 价格…")
            : String(localized: "一次性购买")
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
            AmbientBackdrop(intensity: .quiet)

            ScrollView {
                VStack(spacing: 0) {
                    topBar

                    BrandMark(size: 72)
                        .padding(.top, Spacing.s)

                    Text(Brand.proName)
                        .font(Typography.sheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.top, Spacing.m)
                        .accessibilityAddTraits(.isHeader)

                    Text("一次购买，永久不限张数。")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.xxs)

                    benefits
                        .padding(.top, Spacing.l)

                    purchaseArea
                        .padding(.top, Spacing.l)

                    restoreArea
                        .padding(.top, Spacing.s)

                    legal
                        .padding(.top, Spacing.l)
                        .padding(.bottom, Spacing.l)
                }
                .padding(.horizontal, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .duoFormWidth()
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
            Spacer(minLength: 0)
            Button(action: onClose) {
                ZStack {
                    Circle()
                        .fill(Palette.fillControl)
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "pro.close", defaultValue: "关闭 Pro 页面"))
            .accessibilityIdentifier("pro.close")
        }
        .padding(.trailing, controlInset)
        .padding(.top, displayCornerInset > 0 ? Spacing.s : 0)
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            benefit(String(localized: "无限张数"),
                    detail: String(localized: "pro.benefit.unlimited.detail", defaultValue: "不再受每天 \(QuotaConfiguration.freeDailyLimit) 张免费额度限制"),
                    symbol: "infinity",
                    tint: Palette.accentText)
            divider
            benefit(String(localized: "处理方式不变"),
                    detail: String(localized: "同样只追加纹理与颗粒，原图始终保留"),
                    symbol: "square.3.layers.3d")
            divider
            benefit(String(localized: "免费版继续可用"),
                    detail: String(localized: "pro.benefit.free.detail", defaultValue: "不购买也可以每天处理 \(QuotaConfiguration.freeDailyLimit) 张，质量与校验完全一致"),
                    symbol: "moon")
        }
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func benefit(_ title: String, detail: String, symbol: String, tint: Color = Palette.textSecondary) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
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
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder
    private var purchaseArea: some View {
        VStack(spacing: Spacing.s) {
            if purchases.isPro {
                statusCard(String(localized: "pro.owner.card", defaultValue: "已解锁 \(Brand.proName)"),
                           detail: String(localized: "pro.owner.detail", defaultValue: "无限转换已生效。感谢支持独立开发。"),
                           symbol: "checkmark.seal",
                           tint: Palette.success)
            } else {
                PrimaryActionButton(
                    title: purchaseTitle,
                    isEnabled: canPurchase,
                    isWorking: purchases.purchaseState == .purchasing
                ) {
                    Task { await purchases.purchase() }
                }

                if purchases.product == nil, !purchases.isLoadingProduct {
                    InlineErrorNotice(
                        message: purchases.productLoadError ?? String(localized: "暂时无法加载商品信息，请稍后重试。"),
                        actionTitle: String(localized: "重新加载")
                    ) {
                        Task { await purchases.loadProduct() }
                    }
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
                               symbol: "checkmark.circle",
                               tint: Palette.success)
                case .idle, .purchasing:
                    EmptyView()
                }
            }
        }
    }

    private var restoreArea: some View {
        VStack(spacing: Spacing.xxs) {
            Button {
                Task { await purchases.restore() }
            } label: {
                Text(purchases.isRestoring
                     ? String(localized: "正在恢复…")
                     : String(localized: "恢复购买"))
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(Palette.accentText)
                    .frame(minHeight: Layout.minimumTouchTarget)
            }
            .buttonStyle(.plain)
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
        Text("非消耗型内购，不是订阅。价格由 App Store 按当前地区显示，交易验证通过后才生效。")
            .font(Typography.micro)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusCard(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 17, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }
}
