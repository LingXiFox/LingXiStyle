import AppKit
import SwiftUI
import LingXiKit

struct MacPurchaseView: View {
    @ObservedObject var model: MacModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: ProPlan = .lifetime

    private var purchases: PurchaseManager { model.purchases }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MacSpacing.l) {
                    header
                    if purchases.access.isActive {
                        accessCard
                    } else {
                        planList
                        trialCard
                    }
                    legal
                }
                .padding(MacSpacing.xl)
            }
            Divider()
            footer
        }
        .background(MacPalette.background)
        .task { await purchases.loadPlans() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MacSpacing.xs) {
            Text(Brand.proName)
                .font(MacType.display)
            Text(String(localized: "mac.pro.subtitle",
                        defaultValue: "不限张数、保留保险箱与任务历史，处理方式与免费版完全一致。"))
                .font(MacType.body)
                .foregroundStyle(MacPalette.textSecondary)
        }
    }

    private var planList: some View {
        VStack(spacing: MacSpacing.s) {
            ForEach(ProPlan.allCases) { plan in
                planRow(plan)
            }
        }
    }

    private func planRow(_ plan: ProPlan) -> some View {
        let isSelected = selectedPlan == plan
        let product = purchases.planProducts[plan]
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: MacSpacing.s) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? MacPalette.accent : MacPalette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: MacSpacing.xs) {
                        Text(plan.displayName)
                            .font(MacType.bodyEmphasized)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(MacType.micro)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(MacPalette.accentSoft))
                                .foregroundStyle(MacPalette.accentText)
                        }
                    }
                    Text(plan.periodDescription)
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.textSecondary)
                }
                Spacer()
                Text(product?.displayPrice ?? "—")
                    .font(MacType.numeric)
            }
            .padding(.horizontal, MacSpacing.m)
            .padding(.vertical, MacSpacing.s)
            .background(RoundedRectangle(cornerRadius: MacRadius.group, style: .continuous)
                .fill(isSelected ? MacPalette.accentSoft : MacPalette.surfaceElevated))
            .overlay(RoundedRectangle(cornerRadius: MacRadius.group, style: .continuous)
                .strokeBorder(isSelected ? MacPalette.accent : MacPalette.hairline.opacity(0.6),
                              lineWidth: isSelected ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.group, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(product == nil)
    }

    private var trialCard: some View {
        MacCard {
            VStack(alignment: .leading, spacing: MacSpacing.xs) {
                Text(String(localized: "先试 24 小时", defaultValue: "先试 24 小时"))
                    .font(MacType.section)
                Text(String(localized: "mac.pro.trialBody",
                            defaultValue: "每台设备可以领取一次 24 小时体验：不订阅、不扣费，从确认领取开始计时，到期后回到免费额度。"))
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.textSecondary)
                switch purchases.trialState {
                case .eligible:
                    Button(String(localized: "领取 24 小时体验", defaultValue: "领取 24 小时体验")) {
                        Task { await model.claimTrial() }
                    }
                    .buttonStyle(MacQuietButtonStyle())
                case .active(let trial):
                    Text(String(localized: "体验剩余 %@", defaultValue: "体验剩余 \(MacModel.lifetimeText(max(0, trial.expiresAt.timeIntervalSinceNow)))"))
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.success)
                case .expired:
                    Text(String(localized: "这台设备已经领取过了。", defaultValue: "这台设备已经领取过了。"))
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.textSecondary)
                }
            }
        }
    }

    private var accessCard: some View {
        MacCard {
            VStack(alignment: .leading, spacing: MacSpacing.xs) {
                Text(String(localized: "已拥有 %@", defaultValue: "已拥有 \(Brand.proName)"))
                    .font(MacType.section)
                if let expiresAt = purchases.access.expiresAt {
                    Text(String(localized: "有效期至 %@", defaultValue: "有效期至 \(expiresAt.formatted(date: .abbreviated, time: .shortened))"))
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.textSecondary)
                } else {
                    Text(String(localized: "永久生效。", defaultValue: "永久生效。"))
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.textSecondary)
                }
                if purchases.access.source == .subscription {
                    Button(String(localized: "管理订阅", defaultValue: "管理订阅")) {
                        NSWorkspace.shared.open(PurchaseManager.manageSubscriptionsURL)
                    }
                    .buttonStyle(MacQuietButtonStyle())
                }
            }
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: MacSpacing.xxs) {
            Text(String(localized: "mac.pro.legal",
                        defaultValue: "周订阅与月订阅会自动续期，可随时在“管理订阅”中取消；日卡与永久版为一次性购买。价格由 App Store 按地区展示。"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
            Text(String(localized: "已在 iPhone 或 iPad 购买的权益可以用“恢复购买”找回。",
                        defaultValue: "已在 iPhone 或 iPad 购买的权益可以用“恢复购买”找回。"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
        }
    }

    private var footer: some View {
        HStack(spacing: MacSpacing.s) {
            Button(String(localized: "恢复购买", defaultValue: "恢复购买")) {
                Task { await model.restore() }
            }
            .buttonStyle(.link)
            .disabled(purchases.isRestoring)
            if let error = purchases.productLoadError {
                Text(error)
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.error)
            }
            Spacer()
            Button(String(localized: "关闭", defaultValue: "关闭")) { dismiss() }
                .buttonStyle(MacQuietButtonStyle())
            if !purchases.access.isActive {
                Button(purchaseTitle) {
                    Task { await model.purchase(selectedPlan) }
                }
                .buttonStyle(MacPrimaryButtonStyle())
                .disabled(purchases.planProducts[selectedPlan] == nil || purchases.purchaseState == .purchasing)
            }
        }
        .padding(MacSpacing.l)
        .background(MacPalette.surfaceElevated)
    }

    private var purchaseTitle: String {
        let price = purchases.planProducts[selectedPlan]?.displayPrice ?? ""
        return String(localized: "购买 %@", defaultValue: "购买 \(selectedPlan.displayName) \(price)")
    }
}
