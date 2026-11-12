import XCTest
@testable import LingXiKit

final class ProPlansTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ plan: ProPlan,
                        purchased: TimeInterval = 0,
                        expires: TimeInterval? = nil,
                        revoked: TimeInterval? = nil) -> ProEntitlementRecord {
        ProEntitlementRecord(productID: plan.productID,
                             purchaseDate: now.addingTimeInterval(purchased),
                             expirationDate: expires.map { now.addingTimeInterval($0) },
                             revocationDate: revoked.map { now.addingTimeInterval($0) })
    }

    // MARK: - Access evaluation

    func testLifetimeWinsAndHasNoExpiry() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.lifetime), record(.monthly, expires: 86_400)],
            trial: nil,
            now: now
        )
        XCTAssertEqual(snapshot.source, .lifetime)
        XCTAssertEqual(snapshot.plan, .lifetime)
        XCTAssertNil(snapshot.expiresAt)
        XCTAssertTrue(snapshot.isActive)
    }

    func testActiveSubscriptionSetsExpiry() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.weekly, expires: 7 * 86_400)],
            trial: nil,
            now: now
        )
        XCTAssertEqual(snapshot.source, .subscription)
        XCTAssertEqual(snapshot.plan, .weekly)
        XCTAssertEqual(snapshot.expiresAt?.timeIntervalSince(now), 7 * 86_400)
    }

    func testSwitchingPlansUsesTheMostRecentSubscription() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.monthly, purchased: -10 * 86_400, expires: 20 * 86_400),
                      record(.weekly, purchased: -86_400, expires: 6 * 86_400)],
            trial: nil,
            now: now
        )
        XCTAssertEqual(snapshot.plan, .weekly)
        XCTAssertEqual(snapshot.expiresAt?.timeIntervalSince(now), 6 * 86_400)
    }

    func testExpiredOrRevokedPurchasesGiveFreeAccess() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.weekly, expires: -60), record(.lifetime, revoked: -60)],
            trial: nil,
            now: now
        )
        XCTAssertEqual(snapshot, .free)
        XCTAssertFalse(snapshot.isActive)
    }

    func testDayPassLastsTwentyFourHours() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.dayPass, purchased: -3_600)],
            trial: nil,
            now: now
        )
        XCTAssertEqual(snapshot.source, .dayPass)
        XCTAssertEqual(snapshot.expiresAt?.timeIntervalSince(now), 23 * 3_600)
    }

    func testExpiredDayPassFallsBackToFree() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.dayPass, purchased: -90_000)],
            trial: nil,
            now: now
        )
        XCTAssertEqual(snapshot, .free)
    }

    func testLaterDayPassExtendsWindow() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.dayPass, purchased: -3_600), record(.dayPass, purchased: -600)],
            trial: nil,
            now: now
        )
        XCTAssertEqual(snapshot.expiresAt?.timeIntervalSince(now), 86_400 - 600)
    }

    func testRevokedDayPassIgnoresTheStoredMirror() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.dayPass, purchased: -86_400, revoked: -60)],
            trial: nil,
            storedDayPassExpiry: now.addingTimeInterval(3 * 3_600),
            now: now
        )
        XCTAssertEqual(snapshot, .free, "a refund must not leave the Keychain mirror in charge")
    }

    func testNewerDayPassAfterRefundUsesTheActivePurchase() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [record(.dayPass, purchased: -90_000, revoked: -80_000),
                      record(.dayPass, purchased: -3_600)],
            trial: nil,
            storedDayPassExpiry: now.addingTimeInterval(600),
            now: now
        )
        XCTAssertEqual(snapshot.source, .dayPass)
        XCTAssertEqual(snapshot.expiresAt?.timeIntervalSince(now), 23 * 3_600)
    }

    func testTrialIsUsedOnlyWithoutPurchase() {
        let trial = ProTrial(claimedAt: now.addingTimeInterval(-3_600),
                             expiresAt: now.addingTimeInterval(3_600),
                             deviceSeed: "seed")
        XCTAssertEqual(ProAccessEvaluator.snapshot(records: [], trial: trial, now: now).source, .trial)
        XCTAssertEqual(ProAccessEvaluator.snapshot(records: [record(.dayPass, purchased: -60)],
                                                   trial: trial,
                                                   now: now).source, .dayPass)
    }

    func testUnknownProductIsIgnored() {
        let unknown = ProEntitlementRecord(productID: "com.example.other",
                                           purchaseDate: now,
                                           expirationDate: nil,
                                           revocationDate: nil)
        XCTAssertEqual(ProAccessEvaluator.snapshot(records: [unknown], trial: nil, now: now), .free)
    }

    // MARK: - Trial ledger

    func testTrialCanBeClaimedOnceAndExpires() throws {
        let store = MemoryTrialStore()
        var clock = now
        let service = ProTrialService(store: store, now: { clock })

        XCTAssertEqual(service.state(), .eligible)
        let trial = try service.claim()
        XCTAssertEqual(trial.expiresAt.timeIntervalSince(trial.claimedAt), 24 * 3_600)
        XCTAssertEqual(service.state(), .active(trial))
        XCTAssertThrowsError(try service.claim()) { error in
            XCTAssertEqual(error as? ProTrialError, .alreadyClaimed)
        }

        clock = trial.expiresAt.addingTimeInterval(1)
        guard case .expired(let expired) = service.state() else {
            return XCTFail("Expected the trial to expire")
        }
        XCTAssertEqual(expired, trial)
        XCTAssertThrowsError(try service.claim())
    }

    func testTrialSurvivesANewServiceInstance() throws {
        let store = MemoryTrialStore()
        let first = ProTrialService(store: store, now: { self.now })
        let trial = try first.claim()
        let relaunched = ProTrialService(store: store, now: { self.now.addingTimeInterval(60) })
        XCTAssertEqual(relaunched.state(), .active(trial))
    }

    // MARK: - Product identifiers

    func testPlanIdentifiersAreStableAndUnique() {
        XCTAssertEqual(ProPlan.lifetime.productID, "com.lingxifox.LingXiStyle.pro")
        XCTAssertEqual(ProPlan.dayPass.productID, "com.lingxifox.LingXiStyle.pro.day")
        XCTAssertEqual(ProPlan.weekly.productID, "com.lingxifox.LingXiStyle.pro.weekly")
        XCTAssertEqual(ProPlan.monthly.productID, "com.lingxifox.LingXiStyle.pro.monthly")
        XCTAssertEqual(Set(ProPlan.allCases.map(\.productID)).count, ProPlan.allCases.count)
        for plan in ProPlan.allCases {
            XCTAssertEqual(ProPlan.plan(forProductID: plan.productID), plan)
        }
    }

    // MARK: - Day pass ledger

    func testDayPassActivationLastsTwentyFourHours() throws {
        let store = MemoryDayPassStore()
        let service = ProDayPassService(store: store, now: { self.now })
        let expiry = try service.activate(transactionID: "42")
        XCTAssertEqual(expiry.timeIntervalSince(now), 24 * 3_600)
        XCTAssertEqual(service.expiresAt(), expiry)
        XCTAssertEqual(store.load()?.transactionID, "42")
    }

    func testDayPassUsesStoreKitPurchaseDateForTheWindow() throws {
        let store = MemoryDayPassStore()
        let service = ProDayPassService(store: store, now: { self.now })
        let purchasedAt = now.addingTimeInterval(-6 * 3_600)
        let expiry = try service.activate(transactionID: "43", purchasedAt: purchasedAt)
        XCTAssertEqual(expiry.timeIntervalSince(now), 18 * 3_600,
                       "a late-applied transaction must not restart the 24-hour window")
    }

    func testSecondDayPassExtendsFromTheRemainingWindow() throws {
        let store = MemoryDayPassStore()
        var clock = now
        let service = ProDayPassService(store: store, now: { clock })
        let first = try service.activate(transactionID: "1")
        clock = now.addingTimeInterval(6 * 3_600)
        let second = try service.activate(transactionID: "2")
        XCTAssertEqual(second.timeIntervalSince(first), 24 * 3_600)
        XCTAssertEqual(second.timeIntervalSince(clock), 42 * 3_600)
    }

    func testReplayingTheSameTransactionNeverStacksTime() throws {
        let store = MemoryDayPassStore()
        var clock = now
        let service = ProDayPassService(store: store, now: { clock })
        let first = try service.activate(transactionID: "7")
        clock = now.addingTimeInterval(3_600)
        let replay = try service.activate(transactionID: "7")
        XCTAssertEqual(replay, first)
    }

    func testExpiredDayPassIsDropped() throws {
        let store = MemoryDayPassStore()
        var clock = now
        let service = ProDayPassService(store: store, now: { clock })
        _ = try service.activate(transactionID: "9")
        clock = now.addingTimeInterval(25 * 3_600)
        XCTAssertNil(service.expiresAt())
        XCTAssertNotNil(service.record())
    }

    func testStoredDayPassExpiryUnlocksWithoutAStoreKitRecord() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [],
            trial: nil,
            storedDayPassExpiry: now.addingTimeInterval(3 * 3_600),
            now: now
        )
        XCTAssertEqual(snapshot.source, .dayPass)
        XCTAssertEqual(snapshot.plan, .dayPass)
        XCTAssertEqual(snapshot.expiresAt?.timeIntervalSince(now), 3 * 3_600)
    }

    func testExpiredStoredDayPassFallsBackToTheTrial() {
        let trial = ProTrial(claimedAt: now, expiresAt: now.addingTimeInterval(3_600), deviceSeed: "seed")
        let snapshot = ProAccessEvaluator.snapshot(
            records: [],
            trial: trial,
            storedDayPassExpiry: now.addingTimeInterval(-60),
            now: now
        )
        XCTAssertEqual(snapshot.source, .trial)
    }

    func testLifetimeStillBeatsAStoredDayPass() {
        let snapshot = ProAccessEvaluator.snapshot(
            records: [ProEntitlementRecord(productID: ProPlan.lifetime.productID,
                                           purchaseDate: now.addingTimeInterval(-100_000),
                                           expirationDate: nil,
                                           revocationDate: nil)],
            trial: nil,
            storedDayPassExpiry: now.addingTimeInterval(3_600),
            now: now
        )
        XCTAssertEqual(snapshot.source, .lifetime)
    }
    func testShareExtensionReadsTheHostAppLedger() {
        XCTAssertEqual(ProLedgerScope.ownerBundleID(for: "com.lingxifox.Texel"), "com.lingxifox.Texel")
        XCTAssertEqual(ProLedgerScope.ownerBundleID(for: "com.lingxifox.Texel.Share"), "com.lingxifox.Texel")
        XCTAssertEqual(ProLedgerScope.ownerBundleID(for: "com.lingxifox.Texel.PurchaseHost"),
                       "com.lingxifox.Texel.PurchaseHost")
    }
}

private final class MemoryTrialStore: ProTrialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var trial: ProTrial?

    func load() -> ProTrial? {
        lock.lock()
        defer { lock.unlock() }
        return trial
    }

    func save(_ trial: ProTrial) throws {
        lock.lock()
        defer { lock.unlock() }
        self.trial = trial
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        trial = nil
    }
}
private final class MemoryDayPassStore: ProDayPassStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var pass: ProDayPass?

    func load() -> ProDayPass? {
        lock.lock()
        defer { lock.unlock() }
        return pass
    }

    func save(_ pass: ProDayPass) throws {
        lock.lock()
        defer { lock.unlock() }
        self.pass = pass
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        pass = nil
    }
}
