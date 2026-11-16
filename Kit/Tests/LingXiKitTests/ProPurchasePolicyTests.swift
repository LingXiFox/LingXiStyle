import XCTest
@testable import LingXiKit

final class ProPurchasePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func access(_ source: ProAccessSnapshot.Source,
                        plan: ProPlan? = nil,
                        expires: TimeInterval? = nil,
                        hasSubscription: Bool = false) -> ProAccessSnapshot {
        ProAccessSnapshot(source: source,
                          plan: plan,
                          expiresAt: expires.map { now.addingTimeInterval($0) },
                          hasActiveSubscription: hasSubscription)
    }

    // MARK: - Availability

    func testFreeCustomerCanBuyEveryPlan() {
        for plan in ProPlan.allCases {
            XCTAssertEqual(ProPurchasePolicy.availability(of: plan, access: .free, now: now), .available)
        }
    }

    func testRunningDayPassBlocksOnlyAnotherDayPass() {
        let dayPass = access(.dayPass, plan: .dayPass, expires: 6 * 3_600)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .dayPass, access: dayPass, now: now), .currentPlan)
        for plan in [ProPlan.weekly, .monthly, .lifetime] {
            XCTAssertEqual(ProPurchasePolicy.availability(of: plan, access: dayPass, now: now), .available)
        }
    }

    func testSubscriptionKeepsTheCrossgradeAndTheBuyoutOnSale() {
        let weekly = access(.subscription, plan: .weekly, expires: 6 * 86_400, hasSubscription: true)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .weekly, access: weekly, now: now), .currentPlan)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .monthly, access: weekly, now: now), .available)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .lifetime, access: weekly, now: now), .available)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .dayPass, access: weekly, now: now), .redundant)
    }

    func testLifetimeOwnerOwnsEverything() {
        let lifetime = access(.lifetime, plan: .lifetime)
        for plan in ProPlan.allCases {
            XCTAssertEqual(ProPurchasePolicy.availability(of: plan, access: lifetime, now: now), .included)
        }
        XCTAssertEqual(ProPurchasePolicy.visiblePlans(for: lifetime, now: now), [])
    }

    func testTrialDoesNotNeedADayPass() {
        let trial = access(.trial, plan: nil, expires: 3_600)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .dayPass, access: trial, now: now), .redundant)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .monthly, access: trial, now: now), .available)
    }

    func testDayPassMirrorCountsWhileStoreKitHasNotCaughtUp() {
        let expiry = now.addingTimeInterval(3_600)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .dayPass,
                                                     access: .free,
                                                     dayPassExpiry: expiry,
                                                     now: now),
                       .currentPlan)
        XCTAssertEqual(ProPurchasePolicy.availability(of: .weekly,
                                                     access: access(.trial, plan: nil, expires: 60),
                                                     dayPassExpiry: expiry,
                                                     now: now),
                       .available)
    }

    func testExpiredMirrorIsIgnored() {
        let snapshot = ProPurchasePolicy.resolved(.free,
                                                  dayPassExpiry: now.addingTimeInterval(-60),
                                                  now: now)
        XCTAssertEqual(snapshot, .free)
    }

    // MARK: - Visible plans and preselection

    func testSubscriptionStillShowsLifetimeAndTheOtherTerm() {
        let weekly = access(.subscription, plan: .weekly, expires: 6 * 86_400, hasSubscription: true)
        let visible = Set(ProPurchasePolicy.visiblePlans(for: weekly, now: now))
        XCTAssertEqual(visible, Set([.lifetime, .weekly, .monthly]))
    }

    func testDayPassHidesNothingButItself() {
        let dayPass = access(.dayPass, plan: .dayPass, expires: 6 * 3_600)
        let visible = Set(ProPurchasePolicy.visiblePlans(for: dayPass, now: now))
        XCTAssertEqual(visible, Set(ProPlan.allCases))
    }

    func testLifetimeIsPreselectedWhenItIsOnSale() {
        XCTAssertEqual(ProPurchasePolicy.defaultPlan(for: .free, now: now), .lifetime)
        let dayPass = access(.dayPass, plan: .dayPass, expires: 6 * 3_600)
        XCTAssertEqual(ProPurchasePolicy.defaultPlan(for: dayPass, now: now), .lifetime)
    }

    func testCurrentPlanIsNeverPreselected() {
        let monthly = access(.subscription, plan: .monthly, expires: 20 * 86_400, hasSubscription: true)
        XCTAssertEqual(ProPurchasePolicy.defaultPlan(for: monthly, now: now), .lifetime)
    }

    // MARK: - Copy

    func testDayPassUpgradeWarnsThatTheRemainingTimeIsLost() {
        let dayPass = access(.dayPass, plan: .dayPass, expires: 6 * 3_600)
        XCTAssertNotNil(ProPurchasePolicy.notice(for: .weekly, access: dayPass, now: now))
        XCTAssertNotNil(ProPurchasePolicy.notice(for: .monthly, access: dayPass, now: now))
        XCTAssertNil(ProPurchasePolicy.notice(for: .dayPass, access: dayPass, now: now))
    }

    func testCrossgradeAndBuyoutEachCarryTheirOwnNotice() {
        let monthly = access(.subscription, plan: .monthly, expires: 20 * 86_400, hasSubscription: true)
        let crossgrade = ProPurchasePolicy.notice(for: .weekly, access: monthly, now: now)
        let buyout = ProPurchasePolicy.notice(for: .lifetime, access: monthly, now: now)
        XCTAssertNotNil(crossgrade)
        XCTAssertNotNil(buyout)
        XCTAssertNotEqual(crossgrade, buyout)
    }

    func testRefusalsExplainWhyTheRowIsDisabled() {
        XCTAssertFalse(ProPurchasePolicy.refusalMessage(for: .currentPlan).isEmpty)
        XCTAssertFalse(ProPurchasePolicy.refusalMessage(for: .included).isEmpty)
        XCTAssertFalse(ProPurchasePolicy.refusalMessage(for: .redundant).isEmpty)
        XCTAssertTrue(ProPurchasePolicy.refusalMessage(for: .available).isEmpty)
    }

    func testBuyoutRemindsAboutTheRunningSubscription() {
        let monthly = access(.subscription, plan: .monthly, expires: 20 * 86_400, hasSubscription: true)
        XCTAssertNotNil(ProPurchasePolicy.postPurchaseNotice(for: .lifetime, access: monthly))
        XCTAssertNil(ProPurchasePolicy.postPurchaseNotice(for: .lifetime, access: access(.lifetime, plan: .lifetime)))
    }
}
