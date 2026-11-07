import XCTest
@testable import LingXiKit

final class QuotaTests: XCTestCase {
    private var databaseURL: URL!

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiQuotaTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
        databaseURL = nil
    }

    private func manager(limit: Int = QuotaConfiguration.freeDailyLimit, clock: TestClock) -> QuotaManager {
        QuotaManager(databaseURL: databaseURL, limit: limit, now: { clock.now() })
    }

    func testFreeUserStartsWithFullDailyAllowance() throws {
        let clock = TestClock()
        let quota = manager(clock: clock)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 0)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.limit, QuotaConfiguration.freeDailyLimit)
        XCTAssertEqual(QuotaConfiguration.freeDailyLimit, 5)
        XCTAssertEqual(status.remaining, 5)
        XCTAssertTrue(status.isAvailable)
        XCTAssertFalse(status.isExhausted)
        XCTAssertFalse(quota.usesAppGroupContainer)
    }

    func testSuccessfulConversionConsumesOneSlot() throws {
        let clock = TestClock()
        let quota = manager(clock: clock)
        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
        try quota.commit(reservation)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 1)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.remaining, 4)
    }

    func testReleasedReservationDoesNotConsumeQuota() throws {
        let clock = TestClock()
        let quota = manager(clock: clock)
        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
        try quota.release(reservation)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 0)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.remaining, 5)
    }

    func testCommitIsIdempotentForTheSameReservation() throws {
        let clock = TestClock()
        let quota = manager(clock: clock)
        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
        try quota.commit(reservation)
        try quota.commit(reservation)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 1)
        XCTAssertEqual(status.remaining, 4)
    }

    func testFifthConversionExhaustsAndSixthIsBlocked() throws {
        let clock = TestClock()
        let quota = manager(clock: clock)
        for _ in 0..<QuotaConfiguration.freeDailyLimit {
            let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
            try quota.commit(reservation)
        }
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.limit, 5)
        XCTAssertEqual(status.used, 5)
        XCTAssertEqual(status.remaining, 0)
        XCTAssertTrue(status.isExhausted)

        XCTAssertThrowsError(try quota.reserve(isPro: false)) { error in
            guard case QuotaError.exhausted(let limit) = error else {
                return XCTFail("expected exhausted, got \(error)")
            }
            XCTAssertEqual(limit, 5)
        }
    }

    func testAllowanceResetsOnNextLocalDay() throws {
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_767_225_600)) // 2026-01-01 12:00 UTC
        let quota = manager(limit: 2, clock: clock)
        for _ in 0..<2 {
            let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
            try quota.commit(reservation)
        }
        XCTAssertTrue(try quota.status(isPro: false).isExhausted)

        clock.advance(by: 24 * 60 * 60)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 0)
        XCTAssertEqual(status.remaining, 2)
        XCTAssertFalse(status.isExhausted)
    }

    func testExhaustedAllowanceRejectsFurtherReservations() throws {
        let clock = TestClock()
        let quota = manager(limit: 1, clock: clock)
        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
        try quota.commit(reservation)

        XCTAssertThrowsError(try quota.reserve(isPro: false)) { error in
            guard case QuotaError.exhausted(let limit) = error else {
                return XCTFail("expected exhausted, got \(error)")
            }
            XCTAssertEqual(limit, 1)
            XCTAssertEqual((error as? QuotaError)?.diagnosticCode, "E_QUOTA_EXHAUSTED")
        }
        XCTAssertEqual(try quota.status(isPro: false).remaining, 0)
    }

    func testTwoProcessesCannotBothSpendTheLastSlot() throws {
        let clock = TestClock()
        let first = manager(limit: 1, clock: clock)
        let second = manager(limit: 1, clock: clock)
        let group = DispatchGroup()
        let lock = NSLock()
        var winners: [QuotaReservation] = []
        var exhausted = 0
        let managers = [first, second]
        let attempts = 24

        for index in 0..<attempts {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    if let reservation = try managers[index % 2].reserve(isPro: false) {
                        lock.lock()
                        winners.append(reservation)
                        lock.unlock()
                    }
                } catch QuotaError.exhausted {
                    lock.lock()
                    exhausted += 1
                    lock.unlock()
                } catch {
                    XCTFail("unexpected reservation error: \(error)")
                }
            }
        }
        group.wait()

        XCTAssertEqual(winners.count, 1)
        XCTAssertEqual(exhausted, attempts - 1)
        if let winner = winners.first {
            try first.commit(winner)
        }
        XCTAssertEqual(try first.status(isPro: false).used, 1)
        XCTAssertEqual(try second.status(isPro: false).remaining, 0)
    }

    func testQuotaSurvivesANewManagerInstance() throws {
        let clock = TestClock()
        let first = manager(clock: clock)
        let reservation = try XCTUnwrap(try first.reserve(isPro: false))
        try first.commit(reservation)

        let restarted = manager(clock: clock)
        XCTAssertEqual(try restarted.status(isPro: false).used, 1)
    }

    func testProNeverConsumesOrChecksQuota() throws {
        let clock = TestClock()
        let quota = manager(limit: 1, clock: clock)
        XCTAssertNil(try quota.reserve(isPro: true))
        let status = try quota.status(isPro: true)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.remaining, Int.max)
        XCTAssertFalse(status.isExhausted)
        XCTAssertEqual(try quota.status(isPro: false).used, 0)
    }

    func testExpiredReservationIsReclaimed() throws {
        let clock = TestClock()
        let quota = manager(limit: 1, clock: clock)
        _ = try quota.reserve(isPro: false)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 0)

        clock.advance(by: QuotaConfiguration.reservationLifetime + 1)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.remaining, 1)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(date: Date = Date(timeIntervalSince1970: 1_767_225_600)) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}
