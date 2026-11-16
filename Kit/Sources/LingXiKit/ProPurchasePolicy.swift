import Foundation

/// What the paywall may offer for one plan, given the access the customer already holds.
public enum ProPlanAvailability: String, Sendable, Equatable {
    /// The App Store may sell this plan to this customer right now.
    case available
    /// The customer is already on this exact plan.
    case currentPlan
    /// A purchase the customer already owns covers this plan.
    case included
    /// The plan cannot add anything on top of the current access, so it must not be sold.
    case redundant

    public var isPurchasable: Bool { self == .available }
}

/// Purchase and upgrade rules shared by the iOS paywall, the macOS paywall and `PurchaseManager`.
///
/// The paywall used to hide every plan as soon as a subscription was active, which also hid the
/// plan switch and the lifetime buyout. These rules keep the whole ladder reachable while they
/// refuse the purchases Apple would reject anyway: a second day pass while one is running, the
/// same subscription twice, or a lifetime purchase for someone who already owns it.
public enum ProPurchasePolicy {
    /// Resolves the access the rules work with. The Keychain day pass mirror can be newer than the
    /// entitlement snapshot right after a purchase, and a stub provider may not report it at all.
    public static func resolved(_ access: ProAccessSnapshot,
                                dayPassExpiry: Date?,
                                now: Date) -> ProAccessSnapshot {
        guard access.source == .none || access.isTrial else { return access }
        guard let dayPassExpiry, dayPassExpiry > now else { return access }
        return ProAccessSnapshot(source: .dayPass, plan: .dayPass, expiresAt: dayPassExpiry)
    }

    public static func availability(of plan: ProPlan,
                                    access: ProAccessSnapshot,
                                    dayPassExpiry: Date? = nil,
                                    now: Date = Date()) -> ProPlanAvailability {
        let access = resolved(access, dayPassExpiry: dayPassExpiry, now: now)
        switch access.source {
        case .lifetime:
            return .included
        case .subscription:
            if plan == access.plan { return .currentPlan }
            // Both terms live in one subscription group, so the other term is a crossgrade and
            // the lifetime product is a buyout. A day pass adds nothing to unlimited access.
            return plan.isSubscription || plan == .lifetime ? .available : .redundant
        case .dayPass:
            return plan == .dayPass ? .currentPlan : .available
        case .trial:
            // The trial already grants unlimited conversions for 24 hours.
            return plan == .dayPass ? .redundant : .available
        case .none:
            return .available
        }
    }

    /// Plans the paywall renders. A lifetime owner sees no product at all: Apple refuses a second
    /// purchase of the same non-consumable and there is no longer plan to switch to.
    public static func visiblePlans(for access: ProAccessSnapshot,
                                    dayPassExpiry: Date? = nil,
                                    now: Date = Date()) -> [ProPlan] {
        guard !access.isLifetime else { return [] }
        return ProPlan.allCases.filter {
            availability(of: $0, access: access, dayPassExpiry: dayPassExpiry, now: now) != .redundant
        }
    }

    /// The plan the paywall preselects: the buyout first, then the first plan that is on sale.
    public static func defaultPlan(for access: ProAccessSnapshot,
                                   dayPassExpiry: Date? = nil,
                                   now: Date = Date()) -> ProPlan? {
        let purchasable = visiblePlans(for: access, dayPassExpiry: dayPassExpiry, now: now).filter {
            availability(of: $0, access: access, dayPassExpiry: dayPassExpiry, now: now) == .available
        }
        return purchasable.first { $0 == .lifetime } ?? purchasable.first
    }

    /// Short marker for a row that cannot be bought: the running plan, or one a purchase covers.
    public static func statusLabel(for availability: ProPlanAvailability) -> String? {
        switch availability {
        case .currentPlan:
            return String(localized: "pro.plan.current", defaultValue: "当前方案")
        case .included:
            return String(localized: "pro.plan.included", defaultValue: "已包含")
        case .available, .redundant:
            return nil
        }
    }

    /// What the customer has to know before paying for this plan. Returns nil when the purchase
    /// needs no explanation beyond the price.
    public static func notice(for plan: ProPlan,
                              access: ProAccessSnapshot,
                              dayPassExpiry: Date? = nil,
                              now: Date = Date()) -> String? {
        let access = resolved(access, dayPassExpiry: dayPassExpiry, now: now)
        switch (access.source, plan) {
        case (.dayPass, .weekly), (.dayPass, .monthly):
            // Apple starts the new subscription immediately; the unused day-pass hours are lost.
            return String(localized: "pro.notice.dayPassToSubscription",
                          defaultValue: "订阅会立即开始计费，日卡剩余时间不会自动抵扣。")
        case let (.subscription, plan) where plan.isSubscription && plan != access.plan:
            return String(localized: "pro.notice.crossgrade",
                          defaultValue: "切换在同一订阅组内完成，按 App Store 规则在下一个续费周期生效，权益保持不变。")
        case (.subscription, .lifetime):
            return String(localized: "pro.notice.subscriptionToLifetime",
                          defaultValue: "买断后立即获得永久权益；请前往 App Store「订阅」关闭原来的自动续费。")
        case (.trial, .dayPass), (.subscription, .dayPass):
            return String(localized: "pro.notice.dayPassNotNeeded",
                          defaultValue: "当前权益已经不限张数，日卡不会叠加时间。")
        default:
            return nil
        }
    }

    public static func refusalMessage(for availability: ProPlanAvailability) -> String {
        switch availability {
        case .currentPlan:
            return String(localized: "pro.refuse.current", defaultValue: "当前方案正在生效，不需要重复购买。")
        case .included:
            return String(localized: "pro.refuse.owned", defaultValue: "你已拥有永久版，不需要再次购买。")
        case .redundant:
            return String(localized: "pro.refuse.redundant", defaultValue: "当前权益已经不限张数，不需要再买日卡。")
        case .available:
            return ""
        }
    }

    /// Shown after a confirmed purchase. A buyout does not cancel the old subscription, so the
    /// confirmation has to say where to turn the auto-renewal off.
    public static func postPurchaseNotice(for plan: ProPlan, access: ProAccessSnapshot) -> String? {
        guard plan == .lifetime, access.hasActiveSubscription else { return nil }
        return String(localized: "pro.postPurchase.lifetime",
                      defaultValue: "已获得永久权益；请前往 App Store「订阅」关闭原来的自动续费。")
    }
}
