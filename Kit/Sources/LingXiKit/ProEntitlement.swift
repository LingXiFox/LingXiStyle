import Foundation
import Combine
import StoreKit

public enum ProProduct {
    public static let identifier = "com.lingxifox.LingXiStyle.pro"
    public static var displayName: String { Brand.proName }
    public static var description: String { String(localized: "一次购买，永久不限张数。") }
}

/// The only source of truth for Pro. A local bool, a button callback, or an unverified JWS can
/// never turn this into true.
public protocol ProEntitlementProviding: Sendable {
    func isPro() async -> Bool
    func snapshot() async -> ProAccessSnapshot
}

public extension ProEntitlementProviding {
    /// Fallback for providers that only know a single yes/no state (test stubs, integrations).
    func snapshot() async -> ProAccessSnapshot {
        let unlocked = await isPro()
        return unlocked
            ? ProAccessSnapshot(source: .lifetime, plan: .lifetime, expiresAt: nil)
            : .free
    }
}

public struct StoreKitEntitlementProvider: ProEntitlementProviding {
    private let trial: @Sendable () -> ProTrialState
    private let dayPass: @Sendable () -> Date?
    private let now: @Sendable () -> Date

    public init(trial: @escaping @Sendable () -> ProTrialState = { ProTrialService.live().state() },
                dayPass: @escaping @Sendable () -> Date? = { ProDayPassService.live().expiresAt() },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.trial = trial
        self.dayPass = dayPass
        self.now = now
    }

    public func isPro() async -> Bool {
        await snapshot().isActive
    }

    /// Combines the verified StoreKit entitlement with the Keychain trial and day pass ledgers.
    /// `Transaction.currentEntitlements` is the only grant source: Apple documents it as the latest
    /// transaction per entitled product, and a refunded or revoked product never appears there. A
    /// cleared sandbox purchase therefore drops Pro instead of leaving a stale local record behind.
    /// `Transaction.all` is a history, not an entitlement; it is read only to spot a revoked day
    /// pass, which is the one record that has to keep its Keychain mirror suppressed.
    public func snapshot() async -> ProAccessSnapshot {
        var entitled: [ProEntitlementRecord] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let plan = ProPlan.plan(forProductID: transaction.productID) else { continue }
            let record = Self.record(for: transaction)
            if plan.isSubscription {
                // StoreKit can keep serving the last subscription transaction after the term
                // ends, and the copy still carries the old expiration date. The subscription
                // status is authoritative: drop the record when Apple already reports the
                // subscription as expired or revoked, and extend it while a grace period runs.
                guard let current = await Self.subscriptionRecord(record, transaction: transaction) else {
                    continue
                }
                entitled.append(current)
            } else {
                entitled.append(record)
            }
        }

        let storedDayPassExpiry = dayPass()
        var revoked: [ProEntitlementRecord] = []
        if storedDayPassExpiry != nil {
            // Nothing else can be rescued from history, so skip the full scan when there is no
            // local mirror to reconcile. Long-lived subscriptions would otherwise replay years of
            // renewals on every foreground refresh.
            for await result in Transaction.all {
                guard case .verified(let transaction) = result,
                      transaction.revocationDate != nil,
                      ProPlan.plan(forProductID: transaction.productID) != nil else { continue }
                revoked.append(Self.record(for: transaction))
            }
        }

        let records = ProEntitlementResolver.records(entitled: entitled, revoked: revoked)
        return ProAccessEvaluator.snapshot(records: records,
                                           trial: trial().trial,
                                           storedDayPassExpiry: storedDayPassExpiry,
                                           now: now())
    }

    private static func record(for transaction: Transaction) -> ProEntitlementRecord {
        ProEntitlementRecord(productID: transaction.productID,
                             purchaseDate: transaction.purchaseDate,
                             expirationDate: transaction.expirationDate,
                             revocationDate: transaction.revocationDate)
    }

    /// A renewal Apple keeps alive with a billing grace period stays in current entitlements, but
    /// its transaction keeps the original expiration date. The subscription status is the only
    /// place that reports the real end of access, so it is read for every verified subscription.
    /// The API arrived in iOS 18.4 / macOS 15.4; older systems fall back to the transaction date.
    ///
    /// Returns nil when Apple reports the subscription as expired or revoked. Finishing a
    /// transaction does not remove it from `currentEntitlements`, so the status is what keeps a
    /// lapsed term from unlocking Pro. A status lookup that fails keeps the transaction: a
    /// flaky network must not revoke access the customer paid for.
    private static func subscriptionRecord(_ record: ProEntitlementRecord,
                                           transaction: Transaction) async -> ProEntitlementRecord? {
        guard #available(iOS 18.4, macOS 15.4, *) else { return record }
        guard let status = try? await Product.SubscriptionInfo.status(transactionID: transaction.id) else {
            return record
        }
        if status.state == .expired || status.state == .revoked {
            return nil
        }
        guard status.state == .inGracePeriod,
              case .verified(let renewal) = status.renewalInfo,
              let graceEnd = renewal.gracePeriodExpirationDate else { return record }
        return ProEntitlementRecord(productID: record.productID,
                                    purchaseDate: record.purchaseDate,
                                    expirationDate: record.expirationDate,
                                    revocationDate: record.revocationDate,
                                    gracePeriodEndsAt: graceEnd)
    }
}

@MainActor
public final class PurchaseManager: ObservableObject {
    public enum PurchaseState: Equatable {
        case idle
        case purchasing
        case awaitingApproval
        case success
        case cancelled
        case failed(String)
    }

    /// Official App Store subscription management page. Used for the "manage subscription" row so
    /// the app never guesses at a private scheme.
    public static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// Kept for the 1.8 paywall and its tests: the lifetime product.
    @Published public private(set) var product: Product?
    @Published public private(set) var planProducts: [ProPlan: Product] = [:]
    /// Plans StoreKit has answered for at least once. `planProducts` is sparse because the App
    /// Store silently drops identifiers it cannot resolve, so an empty dictionary is not the only
    /// sign that no load has happened yet.
    @Published public private(set) var loadedPlans: Set<ProPlan> = []
    @Published public private(set) var access: ProAccessSnapshot = .free
    @Published public private(set) var isPro = false
    @Published public private(set) var isLoadingProduct = false
    @Published public private(set) var productLoadError: String?
    @Published public private(set) var purchaseState: PurchaseState = .idle
    @Published public private(set) var isRestoring = false
    @Published public private(set) var restoreMessage: String?
    @Published public private(set) var trialState: ProTrialState = .eligible
    @Published public private(set) var trialError: String?
    @Published public private(set) var dayPassError: String?
    /// Confirmation copy shown after a successful purchase that leaves something to do, such as
    /// turning off the old auto-renewal after a lifetime buyout.
    @Published public private(set) var postPurchaseNotice: String?
    public let productID: String
    public let trialService: ProTrialService
    public let dayPassService: ProDayPassService
    private let entitlementProvider: any ProEntitlementProviding
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    public init(productID: String = ProProduct.identifier,
                entitlementProvider: any ProEntitlementProviding = StoreKitEntitlementProvider(),
                trialService: ProTrialService = ProTrialService.live(),
                dayPassService: ProDayPassService = ProDayPassService.live()) {
        self.productID = productID
        self.entitlementProvider = entitlementProvider
        self.trialService = trialService
        self.dayPassService = dayPassService
        self.trialState = trialService.state()
    }

    /// Access the paywall works with. The Keychain day-pass mirror can be ahead of the entitlement
    /// snapshot for the moment between a purchase and StoreKit publishing the transaction.
    public var effectiveAccess: ProAccessSnapshot {
        ProPurchasePolicy.resolved(access, dayPassExpiry: dayPassService.expiresAt(), now: Date())
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Starts the transaction listener and refreshes the verified entitlement. Safe to call on
    /// every foreground transition; it does not present a paywall or a purchase dialog.
    public func start() async {
        if !hasStarted {
            hasStarted = true
            updatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in Transaction.updates {
                    await self.handle(update)
                }
            }
        }
        await refreshEntitlement()
    }

    public func refreshEntitlement() async {
        trialState = trialService.state()
        access = await entitlementProvider.snapshot()
        isPro = access.isActive
        // Ask to Buy approval can arrive while the app is backgrounded. iOS 18 does not always
        // replay that approval through Transaction.updates in a test host, so recover the visible
        // state from the verified entitlement instead of leaving the sheet on "awaiting approval".
        if isPro, purchaseState == .awaitingApproval {
            purchaseState = .success
        }
    }

    /// Loads the lifetime product only. Retained so 1.8 callers and tests keep working.
    public func loadProduct() async {
        await loadProducts(plans: [.lifetime])
    }

    /// Loads every Pro plan. The paywall calls this; prices always come from StoreKit.
    public func loadPlans() async {
        await loadProducts(plans: ProPlan.allCases)
    }

    /// Loads the plans no earlier call has seen yet. Every paywall entry point calls this, so the
    /// lifetime product fetched by `loadProduct()` can never hide the subscriptions behind it.
    public func loadPlansIfNeeded() async {
        guard !hasLoadedAllPlans else { return }
        await loadProducts(plans: ProPlan.allCases)
    }

    /// True once every Pro plan has been requested and answered at least once.
    public var hasLoadedAllPlans: Bool {
        loadedPlans.count >= ProPlan.allCases.count
    }

    private func loadProducts(plans: [ProPlan]) async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        productLoadError = nil
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: plans.map(\.productID))
            for plan in plans {
                let loaded = products.first { $0.id == plan.productID }
                planProducts[plan] = loaded
                if loaded == nil {
                    loadedPlans.remove(plan)
                } else {
                    loadedPlans.insert(plan)
                }
            }
            product = planProducts[.lifetime]
            if plans.contains(where: { planProducts[$0] == nil }) {
                // The App Store omits identifiers it cannot resolve instead of throwing, so a
                // missing plan is a real failure the user has to see and retry.
                productLoadError = String(localized: "pro.error.missingPlans",
                                          defaultValue: "App Store 暂时没有返回部分商品，请稍后重试。")
            }
        } catch {
            for plan in plans {
                planProducts[plan] = nil
                loadedPlans.remove(plan)
            }
            product = nil
            productLoadError = Self.message(for: error, fallback: String(localized: "无法连接 App Store，请检查网络后重试。"))
        }
    }

    public func purchase() async {
        await purchase(plan: .lifetime)
    }

    public func purchase(plan: ProPlan) async {
        guard purchaseState != .purchasing else { return }
        purchaseState = .purchasing
        // The paywall hides plans that cannot be bought, but the manager is the last gate: an
        // access change while the sheet was open must never reach StoreKit.
        await refreshEntitlement()
        let availability = ProPurchasePolicy.availability(of: plan,
                                                          access: access,
                                                          dayPassExpiry: dayPassService.expiresAt())
        guard availability.isPurchasable else {
            purchaseState = .failed(ProPurchasePolicy.refusalMessage(for: availability))
            return
        }
        guard let product = planProducts[plan] ?? (plan == .lifetime ? product : nil) else {
            purchaseState = .failed(String(localized: "商品信息尚未加载，请稍后重试。"))
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == plan.productID,
                      transaction.revocationDate == nil else {
                    purchaseState = .failed(String(localized: "购买凭证未通过验证，未授予 Pro 权益。"))
                    return
                }
                await transaction.finish()
                if plan == .dayPass {
                    activateDayPass(transactionID: String(transaction.id),
                                    purchasedAt: transaction.purchaseDate)
                }
                await refreshEntitlement()
                if isPro {
                    postPurchaseNotice = ProPurchasePolicy.postPurchaseNotice(for: plan, access: access)
                    purchaseState = .success
                } else {
                    purchaseState = .failed(String(localized: "交易已验证，但权益尚未生效，请稍后重试。"))
                }
            case .pending:
                purchaseState = .awaitingApproval
            case .userCancelled:
                purchaseState = .cancelled
            @unknown default:
                purchaseState = .failed(String(localized: "购买返回了未知状态，请稍后重试。"))
            }
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError {
                purchaseState = .cancelled
            } else {
                purchaseState = .failed(Self.message(for: error, fallback: String(localized: "购买未完成，请稍后重试。")))
            }
        }
    }

    /// Claims the one-time, per-device trial. It starts now and is never renewed or charged.
    @discardableResult
    public func claimTrial() async -> Bool {
        trialError = nil
        do {
            _ = try trialService.claim()
            await refreshEntitlement()
            return isPro
        } catch {
            trialError = (error as? LocalizedError)?.errorDescription ?? String(localized: "无法领取免费体验，请稍后重试。")
            trialState = trialService.state()
            return false
        }
    }

    /// Mirrors a verified day pass purchase into the Keychain so the 24-hour window survives
    /// relaunches even after StoreKit stops listing the non-renewing product.
    private func activateDayPass(transactionID: String, purchasedAt: Date) {
        dayPassError = nil
        do {
            _ = try dayPassService.activate(transactionID: transactionID, purchasedAt: purchasedAt)
        } catch {
            dayPassError = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "无法保存通行证记录，请稍后重试。")
        }
    }

    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        restoreMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            restoreMessage = isPro
                ? String(localized: "restore.success", defaultValue: "已恢复 \(Brand.proName) 权益。")
                : String(localized: "没有找到可恢复的购买记录。")
        } catch {
            restoreMessage = Self.message(for: error, fallback: String(localized: "恢复购买失败，请稍后重试。"))
        }
    }

    public func clearPurchaseMessage() {
        purchaseState = .idle
        postPurchaseNotice = nil
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        guard ProPlan.plan(forProductID: transaction.productID) != nil else { return }
        // A refund or family-sharing revocation arrives as an update for the same transaction.
        // Never finish or celebrate it as a purchase; re-read StoreKit's current entitlement.
        if transaction.revocationDate != nil {
            if transaction.productID == ProPlan.dayPass.productID {
                try? dayPassService.clear(ifTransactionID: String(transaction.id))
            }
            await refreshEntitlement()
            if !isPro { purchaseState = .idle }
            return
        }
        await transaction.finish()
        if transaction.productID == ProPlan.dayPass.productID {
            activateDayPass(transactionID: String(transaction.id),
                            purchasedAt: transaction.purchaseDate)
        }
        await refreshEntitlement()
        if isPro { purchaseState = .success }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let storeError = error as? StoreKitError {
            // Pattern matching instead of a switch keeps this file buildable with both the
            // iOS 18.5 SDK (Xcode 16.4) and newer SDKs that add StoreKitError cases such as
            // invalidPresentationContext. Unknown future cases fall through to the caller copy.
            if case .networkError = storeError {
                return String(localized: "网络连接失败，请检查网络后重试。")
            }
            if case .notAvailableInStorefront = storeError {
                return String(localized: "当前 App Store 地区暂不支持这个商品。")
            }
            if case .userCancelled = storeError {
                return String(localized: "购买已取消。")
            }
            if case .systemError = storeError {
                return String(localized: "App Store 暂时不可用，请稍后重试。")
            }
            return fallback
        }
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return String(localized: "这个商品当前不可购买，请稍后重试。")
            case .purchaseNotAllowed:
                return String(localized: "当前设备不允许购买，请检查屏幕使用时间或家长控制。")
            default:
                return String(localized: "购买未完成，请稍后重试。")
            }
        }
        return fallback
    }
}
