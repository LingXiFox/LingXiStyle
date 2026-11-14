import SwiftUI
import StoreKit
import LingXiKit

/// Pro sheet: day pass, weekly, monthly and lifetime unlocks plus the one-time 24-hour trial.
/// Every price comes from Product.displayPrice; nothing is hard-coded per storefront.
struct ProPurchaseView: View {
    @ObservedObject var purchases: PurchaseManager
    var onEntitlementChanged: () -> Void
    var onClose: () -> Void
    @Environment(\.displayCornerInset) private var displayCornerInset
    var controlInset: CGFloat = 0

    @State private var selectedPlan: ProPlan = .lifetime
    @State private var isClaimingTrial = false

    private var isBusy: Bool {
        switch purchases.purchaseState {
        case .purchasing, .awaitingApproval:
            return true
        default:
            return false
        }
    }

    private var canPurchase: Bool {
        guard purchases.planProducts[selectedPlan] != nil, !isBusy else { return false }
        switch selectedPlan {
        case .lifetime:
            return !purchases.access.isLifetime
        case .dayPass, .weekly, .monthly:
            return true
        }
    }
    /// Keeps the call to action usable when the plan the sheet opens on is not for sale, for
    /// example a lifetime product that is still unpublished while the subscriptions are live.
    private func selectAvailablePlanIfNeeded() {
        guard purchases.planProducts[selectedPlan] == nil else { return }
        guard let fallback = ProPlan.allCases.first(where: { purchases.planProducts[$0] != nil }) else { return }
        selectedPlan = fallback
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            AmbientBackdrop(intensity: .quiet)

            ScrollView {
                VStack(spacing: 0) {
                    topBar

                    BrandMark(size: 64)
                        .padding(.top, Spacing.xs)

                    Text(Brand.proName)
                        .font(Typography.sheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.top, Spacing.m)
                        .accessibilityAddTraits(.isHeader)

                    Text(String(localized: "pro.subtitle", defaultValue: "按需选择时长，所有权益完全一致。"))
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.xxs)

                    benefits
                        .padding(.top, Spacing.m)

                    accessCard
                        .padding(.top, Spacing.m)

                    if !purchases.access.isLifetime, purchases.access.source != .subscription {
                        plans
                            .padding(.top, Spacing.m)

                        purchaseArea
                            .padding(.top, Spacing.m)
                    }

                    if !purchases.access.isActive {
                        trialArea
                            .padding(.top, Spacing.m)
                    }

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
            await purchases.loadPlansIfNeeded()
            selectAvailablePlanIfNeeded()
        }
        .onChange(of: purchases.isPro) { _, isPro in
            if isPro { onEntitlementChanged() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "pro.page.accessibility", defaultValue: "\(Brand.proName) 购买页"))
    }

    // MARK: - Top bar

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

    // MARK: - Benefits

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
            benefit(String(localized: "成果保险箱与任务历史"),
                    detail: String(localized: "pro.benefit.vault.detail", defaultValue: "转换结果可重新保存、导出，记录随时可查"),
                    symbol: "shippingbox")
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

    // MARK: - Current access

    @ViewBuilder
    private var accessCard: some View {
        if purchases.access.isActive {
            statusCard(accessTitle,
                       detail: accessDetail,
                       symbol: purchases.access.isLifetime ? "checkmark.seal" : "clock.badge.checkmark",
                       tint: Palette.success)
            if purchases.access.source == .subscription {
                Button {
                    openManageSubscriptions()
                } label: {
                    Text(String(localized: "pro.manage", defaultValue: "管理订阅"))
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.accentText)
                        .frame(minHeight: Layout.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pro.manage")
            }
        }
    }

    private var accessTitle: String {
        switch purchases.access.source {
        case .lifetime:
            return String(localized: "pro.owner.card", defaultValue: "已解锁 \(Brand.proName)")
        case .subscription:
            return String(localized: "pro.access.subscription", defaultValue: "订阅生效中")
        case .dayPass:
            return String(localized: "pro.access.dayPass", defaultValue: "日卡生效中")
        case .trial:
            return String(localized: "pro.access.trial", defaultValue: "免费体验进行中")
        case .none:
            return ""
        }
    }

    private var accessDetail: String {
        if purchases.access.expiresAt != nil, let remaining = purchases.access.remainingLifetime(at: Date()) {
            let text = AppModel.lifetimeText(remaining)
            return String(localized: "pro.access.expires", defaultValue: "剩余 \(text)，到期后回到免费额度。")
        }
        return String(localized: "pro.owner.detail", defaultValue: "无限转换已生效。感谢支持独立开发。")
    }

    // MARK: - Plans

    private var plans: some View {
        VStack(spacing: Spacing.xs) {
            if let message = purchases.productLoadError, !purchases.isLoadingProduct {
                InlineErrorNotice(
                    message: message,
                    actionTitle: String(localized: "重新加载")
                ) {
                    Task { await purchases.loadPlans() }
                }
                .padding(.bottom, Spacing.xs)
            }


            ForEach(ProPlan.allCases) { plan in
                planRow(plan)
            }
        }
    }
    /// A dash would hide which plan the App Store refused to return, so a finished load that is
    /// still missing a product says so instead of showing a placeholder price.
    private var missingPriceText: String {
        purchases.isLoadingProduct
            ? "—"
            : String(localized: "pro.plan.unavailable", defaultValue: "暂不可用")
    }

    private func planRow(_ plan: ProPlan) -> some View {
        let product = purchases.planProducts[plan]
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? Palette.accentText : Palette.textTertiary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan.displayName)
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(Palette.textPrimary)
                        if plan == .lifetime {
                            Text(String(localized: "pro.plan.badge.lifetime", defaultValue: "买断"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.accentText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    Text(plan.periodDescription)
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 0)

                Text(product?.displayPrice ?? missingPriceText)
                    .font(Typography.numeric)
                    .foregroundStyle(product == nil ? Palette.textTertiary : Palette.textPrimary)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(minHeight: Layout.minimumTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
                    .fill(isSelected ? Palette.accentSoft : Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
                    .stroke(isSelected ? Palette.accent : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pro.plan.\(plan.rawValue)")
    }

    // MARK: - Purchase

    @ViewBuilder
    private var purchaseArea: some View {
        VStack(spacing: Spacing.s) {
            if purchases.access.isLifetime {
                EmptyView()
            } else {
                PrimaryActionButton(
                    title: purchaseTitle,
                    isEnabled: canPurchase,
                    isWorking: purchases.purchaseState == .purchasing
                ) {
                    Task {
                        await purchases.purchase(plan: selectedPlan)
                        if purchases.isPro { onEntitlementChanged() }
                    }
                }
                .accessibilityIdentifier("pro.purchase")

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

    private var purchaseTitle: String {
        guard let product = purchases.planProducts[selectedPlan] else {
            return purchases.isLoadingProduct
                ? String(localized: "正在读取 App Store 价格…")
                : String(localized: "暂时无法购买")
        }
        switch selectedPlan {
        case .lifetime:
            return String(localized: "pro.cta.lifetime", defaultValue: "\(product.displayPrice) · 永久解锁")
        case .dayPass, .weekly, .monthly:
            return String(localized: "pro.cta.subscribe", defaultValue: "\(product.displayPrice) · \(selectedPlan.displayName)")
        }
    }

    // MARK: - Trial

    @ViewBuilder
    private var trialArea: some View {
        if !purchases.access.isLifetime {
            switch purchases.trialState {
            case .eligible:
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "gift")
                            .foregroundStyle(Palette.accentText)
                        Text(String(localized: "pro.trial.title", defaultValue: "免费体验 24 小时"))
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    Text(String(localized: "pro.trial.detail",
                                defaultValue: "每位新用户可领取一次，从确认领取开始计时，不订阅、不扣费。到期后回到免费额度。"))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        guard !isClaimingTrial else { return }
                        isClaimingTrial = true
                        Task {
                            let granted = await purchases.claimTrial()
                            isClaimingTrial = false
                            if granted { onEntitlementChanged() }
                        }
                    } label: {
                        if isClaimingTrial {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "pro.trial.claim", defaultValue: "领取免费体验"))
                                .font(Typography.captionEmphasized)
                                .foregroundStyle(Palette.accentText)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isClaimingTrial)
                    .frame(minHeight: Layout.minimumTouchTarget)
                    .accessibilityIdentifier("pro.trial.claim")
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
            case .active:
                EmptyView()
            case .expired:
                Text(String(localized: "pro.trial.used", defaultValue: "免费体验已使用过。"))
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textTertiary)
            }

            if let trialError = purchases.trialError {
                Text(trialError)
                    .font(Typography.micro)
                    .foregroundStyle(Palette.error)
            }
            if let dayPassError = purchases.dayPassError {
                Text(dayPassError)
                    .font(Typography.micro)
                    .foregroundStyle(Palette.error)
            }
        }
    }

    // MARK: - Restore & legal

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
            .accessibilityIdentifier("pro.restore")

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
        VStack(spacing: Spacing.xxs) {
            Text(String(localized: "pro.legal.purchase",
                        defaultValue: "价格由 App Store 按当前地区显示，交易验证通过后才生效。日卡与永久解锁为一次性购买；周订阅与月订阅会自动续期，可随时在系统「订阅」中取消，取消后当前周期结束前仍然有效。"))
            Text(String(localized: "pro.legal.privacy",
                        defaultValue: "照片始终只在本机处理，购买与试用记录不上传照片。"))
        }
        .font(Typography.micro)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

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

    private func openManageSubscriptions() {
        UIApplication.shared.open(PurchaseManager.manageSubscriptionsURL)
    }
}
