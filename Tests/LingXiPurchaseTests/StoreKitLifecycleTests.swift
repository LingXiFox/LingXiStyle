import XCTest
import StoreKit
import StoreKitTest
import LingXiKit
import LingXiServices

/// Subscription and day pass lifecycle coverage on top of Apple's StoreKit Testing session.
///
/// Every case drives the real PurchaseManager against a local storekit configuration, so the
/// entitlement state machine is exercised end to end without touching a Sandbox account.
@MainActor
final class StoreKitLifecycleTests: XCTestCase {
    private static let groupID = "1A7C5D10"
    private var session: SKTestSession!
    private var temporaryFiles: [URL] = []

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: StoreKitLifecycleTests.self)
            .url(forResource: "Configuration", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        let cleared = await waitUntil(timeout: 20) {
            await self.entitlements().isEmpty
        }
        XCTAssertTrue(cleared, "StoreKit must clear the previous test's entitlements before the next purchase")
    }

    override func tearDownWithError() throws {
        session?.resetToDefaultState()
        session = nil
        for url in temporaryFiles {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        temporaryFiles = []
    }

    // MARK: - First purchase

    func testPurchaseManagerCanReleaseItsTransactionListener() async {
        var manager: PurchaseManager? = makeManager()
        await manager?.start()
        await Task.yield()
        let releasedManager = { [weak manager] in manager }
        manager = nil
        XCTAssertNil(releasedManager(), "The transaction stream must not retain the manager while it waits")
    }

    func testMonthlyPurchaseUnlocksImmediately() async throws {
        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .monthly)

        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.access.source, .subscription)
        XCTAssertEqual(manager.access.plan, .monthly)
        XCTAssertTrue(manager.access.hasActiveSubscription)
        let remaining = try XCTUnwrap(manager.access.expiresAt).timeIntervalSinceNow
        XCTAssertGreaterThan(remaining, 27 * 24 * 3600)
        XCTAssertLessThanOrEqual(remaining, 31 * 24 * 3600)
    }

    /// A running subscription must keep the whole ladder visible: crossgrade, lifetime buyout and
    /// the management entry. The old paywall hid every plan in this state.
    func testActiveSubscriptionKeepsTheUpgradeLadderReachable() async throws {
        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .weekly)

        XCTAssertTrue(manager.access.hasActiveSubscription)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .weekly, access: manager.access), .currentPlan)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .monthly, access: manager.access), .available)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .lifetime, access: manager.access), .available)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .dayPass, access: manager.access), .redundant)
        XCTAssertEqual(ProPurchasePolicy.visiblePlans(for: manager.access), [.weekly, .monthly, .lifetime])
        XCTAssertNotNil(ProPurchasePolicy.notice(for: .monthly, access: manager.access))
        XCTAssertNotNil(ProPurchasePolicy.notice(for: .lifetime, access: manager.access))
    }

    // MARK: - Renewal and expiration

    func testForcedRenewalKeepsAccessWithoutExtendingItTwice() async throws {
        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .weekly)
        let before = try XCTUnwrap(manager.access.expiresAt)

        try session.forceRenewalOfSubscription(productIdentifier: ProPlan.weekly.productID)
        let updated = await waitUntil(timeout: 20) {
            await manager.refreshEntitlement()
            let transactions = self.session.allTransactions().filter { $0.productIdentifier == ProPlan.weekly.productID }
            guard transactions.count == 2, let latest = transactions.compactMap(\.expirationDate).max(),
                  let accessEnd = manager.access.expiresAt else { return false }
            return abs(accessEnd.timeIntervalSince(latest)) <= 1
        }
        XCTAssertTrue(updated, "The renewed transaction must reach the entitlement snapshot")

        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.access.source, .subscription)
        let weekly = session.allTransactions().filter { $0.productIdentifier == ProPlan.weekly.productID }
        XCTAssertEqual(weekly.count, 2, "a renewal must add exactly one transaction")
        let after = try XCTUnwrap(manager.access.expiresAt)
        XCTAssertGreaterThanOrEqual(after, before.addingTimeInterval(-1))
        let latest = try XCTUnwrap(weekly.compactMap(\.expirationDate).max())
        XCTAssertEqual(after.timeIntervalSince1970, latest.timeIntervalSince1970, accuracy: 1,
                       "the entitlement must follow the newest transaction, not stack both periods")
    }

    func testDisablingAutoRenewKeepsThePaidTerm() async throws {
        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .weekly)

        let weekly = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == ProPlan.weekly.productID })
        try session.disableAutoRenewForTransaction(identifier: weekly.identifier)
        await manager.refreshEntitlement()

        XCTAssertTrue(manager.isPro, "cancelling auto-renew must not revoke the paid period")
        XCTAssertEqual(manager.access.source, .subscription)
    }

    func testACancelledSubscriptionExpiresIntoTheFreePlan() async throws {
        try await seedCancelledTerm(.weekly)

        let manager = makeManager()
        await manager.start()
        let active = await waitUntil(timeout: 20) {
            await manager.refreshEntitlement()
            return manager.isPro
        }
        XCTAssertTrue(active, "the seeded term must reach the app")

        let expired = await waitUntil(timeout: 50) {
            await manager.refreshEntitlement()
            guard !manager.isPro else { return false }
            return await self.entitlements().isEmpty
        }
        XCTAssertTrue(expired, "a cancelled term must end on its own")
        XCTAssertEqual(manager.access.source, .none)
        XCTAssertNil(manager.access.expiresAt)
        XCTAssertFalse(manager.access.hasActiveSubscription)
        let remainingEntitlements = await entitlements()
        XCTAssertTrue(remainingEntitlements.isEmpty, "an expired subscription must leave currentEntitlements")
    }

    func testExpiredSubscriptionDoesNotUnlockFromTransactionHistory() async throws {
        let start = Date().addingTimeInterval(-8 * 24 * 3600)
        _ = try await session.buyProduct(identifier: ProPlan.weekly.productID,
                                         options: [.purchaseDate(start, renewalBehavior: .cancelImmediately)])

        let manager = makeManager()
        await manager.start()

        XCTAssertFalse(manager.isPro, "a lapsed period must not unlock Pro from cached history")
        XCTAssertEqual(manager.access.source, .none)
        XCTAssertNil(manager.access.expiresAt)
    }

    func testBillingGracePeriodExtendsProToTheGraceDeadline() async throws {
        session.timeRate = .oneRenewalEveryThirtySeconds
        session.billingGracePeriodIsEnabled = true

        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .weekly)
        XCTAssertEqual(manager.purchaseState, .success)
        let paidExpiry = try XCTUnwrap(manager.access.expiresAt)
        let subscription = try XCTUnwrap(manager.planProducts[.weekly]?.subscription)

        session.shouldEnterBillingRetryOnRenewal = true
        // Forcing an early renewal can start the grace period before the paid term ends.
        var storeGraceEnd: Date?
        let graceApplied = await waitUntil(timeout: 60) {
            guard let statuses = try? await subscription.status else { return false }
            for status in statuses where status.state == .inGracePeriod {
                guard case .verified(let renewal) = status.renewalInfo,
                      renewal.currentProductID == ProPlan.weekly.productID else { continue }
                storeGraceEnd = renewal.gracePeriodExpirationDate
            }
            guard let storeGraceEnd else { return false }
            await manager.refreshEntitlement()
            return manager.isPro && manager.access.expiresAt == storeGraceEnd
        }

        XCTAssertTrue(graceApplied, "a failed renewal inside the grace period must keep Pro")
        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.access.source, .subscription)
        let graceEnd = try XCTUnwrap(manager.access.expiresAt)
        XCTAssertEqual(graceEnd, try XCTUnwrap(storeGraceEnd))
        XCTAssertGreaterThan(graceEnd, paidExpiry)
        XCTAssertTrue(manager.access.hasActiveSubscription)
    }

    // MARK: - Plan switching

    /// StoreKit Testing returns the running transaction instead of synthesising a crossgrade, so a
    /// weekly-to-monthly switch is replayed as "term ends, the other term starts". The entitlement
    /// half of the rule is what the app has to get right.
    func testSwitchingFromWeeklyToMonthlyKeepsSubscriptionAccess() async throws {
        try await seedCancelledTerm(.weekly)

        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        let active = await waitUntil(timeout: 20) {
            await manager.refreshEntitlement()
            return manager.access.plan == .weekly
        }
        XCTAssertTrue(active, "the seeded weekly term must reach the app")

        let lapsed = await waitUntil(timeout: 50) {
            await manager.refreshEntitlement()
            guard !manager.isPro else { return false }
            return await self.entitlements().isEmpty
        }
        XCTAssertTrue(lapsed)

        await manager.purchase(plan: .monthly)
        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertEqual(manager.access.plan, .monthly)
        XCTAssertTrue(manager.isPro)
    }

    func testSwitchingFromMonthlyToWeeklyKeepsSubscriptionAccess() async throws {
        try await seedCancelledTerm(.monthly)

        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        let active = await waitUntil(timeout: 20) {
            await manager.refreshEntitlement()
            return manager.access.plan == .monthly
        }
        XCTAssertTrue(active, "the seeded monthly term must reach the app")

        let lapsed = await waitUntil(timeout: 50) {
            await manager.refreshEntitlement()
            guard !manager.isPro else { return false }
            return await self.entitlements().isEmpty
        }
        XCTAssertTrue(lapsed)

        await manager.purchase(plan: .weekly)
        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertEqual(manager.access.plan, .weekly)
        XCTAssertTrue(manager.isPro)
    }

    func testMonthlyUpgradeToLifetimeKeepsTheSubscriptionManageable() async throws {
        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .monthly)

        await manager.purchase(plan: .lifetime)

        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertEqual(manager.access.source, .lifetime)
        XCTAssertEqual(manager.access.plan, .lifetime)
        XCTAssertTrue(manager.access.hasActiveSubscription, "the old subscription still needs a manage entry")
        XCTAssertNotNil(manager.postPurchaseNotice)
        XCTAssertTrue(ProPurchasePolicy.visiblePlans(for: manager.access).isEmpty,
                      "a lifetime owner must not be offered the same entitlement twice")

        let lifetime = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == ProPlan.lifetime.productID })
        try session.refundTransaction(identifier: lifetime.identifier)
        let fellBack = await waitUntil {
            await manager.refreshEntitlement()
            return manager.access.source == .subscription
        }
        XCTAssertTrue(fellBack, "a revoked lifetime purchase must fall back to the running subscription")
        XCTAssertEqual(manager.access.plan, .monthly)
        XCTAssertTrue(manager.isPro)
    }

    // MARK: - Day pass

    func testRepeatingADayPassPurchaseIsRefused() async throws {
        let trialStore = LifecycleTrialStore()
        let dayPassStore = LifecycleDayPassStore()
        let manager = PurchaseManager(
            entitlementProvider: StoreKitEntitlementProvider(
                trial: { ProTrialService(store: trialStore).state() },
                dayPass: { ProDayPassService(store: dayPassStore).expiresAt() }
            ),
            trialService: ProTrialService(store: trialStore),
            dayPassService: ProDayPassService(store: dayPassStore)
        )
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .dayPass)
        XCTAssertTrue(manager.isPro)

        await manager.purchase(plan: .dayPass)

        guard case .failed(let message) = manager.purchaseState else {
            return XCTFail("a second day pass must be refused, got \(manager.purchaseState)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == ProPlan.dayPass.productID }.count, 1,
                       "the refusal must happen before StoreKit is asked to charge again")
        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.access.source, .dayPass)
    }

    func testDayPassUpgradeStartsTheMonthlySubscription() async throws {
        let manager = makeManager()
        await manager.start()
        await manager.loadPlans()
        await manager.purchase(plan: .dayPass)
        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertEqual(manager.access.plan, .dayPass)
        let dayPassExpiry = try XCTUnwrap(manager.access.expiresAt)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .monthly, access: manager.access), .available)
        XCTAssertNotNil(ProPurchasePolicy.notice(for: .monthly, access: manager.access))

        await manager.purchase(plan: .monthly)

        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertEqual(manager.access.source, .subscription)
        XCTAssertEqual(manager.access.plan, .monthly)
        let subscriptionExpiry = try XCTUnwrap(manager.access.expiresAt)
        XCTAssertGreaterThan(subscriptionExpiry, dayPassExpiry)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == ProPlan.monthly.productID }.count, 1)
    }

    func testExpiredDayPassFromHistoryDoesNotUnlock() async throws {
        _ = try await session.buyProduct(identifier: ProPlan.dayPass.productID,
                                         options: [.purchaseDate(Date().addingTimeInterval(-25 * 3600),
                                                                renewalBehavior: .cancelImmediately)])

        let manager = PurchaseManager(
            entitlementProvider: StoreKitEntitlementProvider(
                trial: { ProTrialService(store: LifecycleTrialStore()).state() },
                dayPass: { ProDayPassService(store: LifecycleDayPassStore()).expiresAt() }
            ),
            trialService: ProTrialService(store: LifecycleTrialStore()),
            dayPassService: ProDayPassService(store: LifecycleDayPassStore())
        )
        await manager.start()

        XCTAssertFalse(manager.isPro, "a day pass older than 24 hours must not grant access")
        XCTAssertEqual(manager.access.source, .none)
        XCTAssertNil(manager.access.expiresAt)
    }

    func testExpiredSubscriptionRestoresTheFreeAllowance() async throws {
        try await seedCancelledTerm(.weekly)

        let manager = makeManager()
        await manager.start()
        let active = await waitUntil(timeout: 20) {
            await manager.refreshEntitlement()
            return manager.access.plan == .weekly
        }
        XCTAssertTrue(active, "The seeded term must grant Pro before testing the quota fallback")
        let expired = await waitUntil(timeout: 50) {
            await manager.refreshEntitlement()
            return !manager.isPro
        }
        XCTAssertTrue(expired, "the weekly term must end")

        let quota = QuotaManager(databaseURL: makeDatabaseURL())
        let status = try quota.status(isPro: manager.isPro)
        XCTAssertEqual(status.remaining, QuotaConfiguration.freeDailyLimit)
        XCTAssertFalse(status.isExhausted)
    }

    // MARK: - Helpers
    /// Seeds a transaction that ends a few seconds from now so StoreKit runs its normal expiration
    /// path. `expireSubscription` rewrites the stored transaction but the app keeps reading the stale
    /// active copy on iOS 27.2, which makes that API unusable for expiry assertions.
    private func seedCancelledTerm(_ plan: ProPlan) async throws {
        session.timeRate = .oneRenewalEveryThirtySeconds
        _ = try await session.buyProduct(
            identifier: plan.productID,
            options: [.purchaseDate(Date(), renewalBehavior: .cancelImmediately)]
        )
    }

    /// Each test gets its own stores so a day pass bought in one case cannot leak Pro into the next.
    private func makeManager() -> PurchaseManager {
        let trialStore = LifecycleTrialStore()
        let dayPassStore = LifecycleDayPassStore()
        return PurchaseManager(
            entitlementProvider: StoreKitEntitlementProvider(
                trial: { ProTrialService(store: trialStore).state() },
                dayPass: { ProDayPassService(store: dayPassStore).expiresAt() }
            ),
            trialService: ProTrialService(store: trialStore),
            dayPassService: ProDayPassService(store: dayPassStore)
        )
    }

    private func entitlements() async -> [String] {
        var productIDs: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                productIDs.append(transaction.productID)
            }
        }
        return productIDs
    }

    private func makeDatabaseURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiLifecycleQuota-\(UUID().uuidString).sqlite")
        temporaryFiles.append(url)
        return url
    }

    private func waitUntil(timeout: TimeInterval = 8, _ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // Transaction.currentEntitlements serves a cached copy for a moment after an expiry or
            // refund, so give StoreKit a beat before polling the updated entitlement list.
            try? await Task.sleep(for: .milliseconds(300))
            if await condition() { return true }
        }
        return await condition()
    }
}

private final class LifecycleTrialStore: ProTrialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ProTrial?

    func load() -> ProTrial? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func save(_ trial: ProTrial) throws {
        lock.lock(); defer { lock.unlock() }
        value = trial
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}

private final class LifecycleDayPassStore: ProDayPassStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ProDayPass?

    func load() -> ProDayPass? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func save(_ pass: ProDayPass) throws {
        lock.lock(); defer { lock.unlock() }
        value = pass
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}
