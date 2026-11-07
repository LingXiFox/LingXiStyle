import XCTest
@testable import LingXiKit

final class KeychainQuotaTests: XCTestCase {
    private var service: String!
    private var stores: [KeychainQuotaStore] = []

    override func setUpWithError() throws {
        service = "com.lingxifox.LingXiStyle.quota.tests.\(UUID().uuidString)"
        stores = []
    }

    override func tearDownWithError() throws {
        for store in stores { store.removeAllItems() }
        stores = []
        service = nil
    }

    private func store(limit: Int = QuotaConfiguration.freeDailyLimit, clock: KeychainTestClock) -> KeychainQuotaStore {
        let store = KeychainQuotaStore(service: service,
                                       accessGroup: nil,
                                       limit: limit,
                                       now: { clock.now() })
        stores.append(store)
        return store
    }

    func testDefaultAllowanceIsFive() throws {
        let clock = KeychainTestClock()
        let quota = store(clock: clock)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(QuotaConfiguration.freeDailyLimit, 5)
        XCTAssertEqual(status.limit, 5)
        XCTAssertEqual(status.remaining, 5)
    }

    func testReserveCommitAndReleaseUseOneSlot() throws {
        let clock = KeychainTestClock()
        let quota = store(clock: clock)

        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
        XCTAssertEqual(try quota.status(isPro: false).reserved, 1)
        try quota.commit(reservation)
        var status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 1)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.remaining, 4)

        let second = try XCTUnwrap(try quota.reserve(isPro: false))
        try quota.release(second)
        status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 1)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.remaining, 4)
    }

    func testCommitIsIdempotentAndLateReleaseCannotEraseIt() throws {
        let clock = KeychainTestClock()
        let quota = store(clock: clock)
        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))

        try quota.commit(reservation)
        try quota.commit(reservation)
        try quota.release(reservation)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 1)
        XCTAssertEqual(status.reserved, 0)
    }

    func testTwoStoresCannotBothSpendTheLastSlot() throws {
        let clock = KeychainTestClock()
        let first = store(limit: 1, clock: clock)
        let second = store(limit: 1, clock: clock)
        let group = DispatchGroup()
        let lock = NSLock()
        var winners: [QuotaReservation] = []
        var exhausted = 0
        let stores = [first, second]
        let attempts = 24

        for index in 0..<attempts {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    if let reservation = try stores[index % 2].reserve(isPro: false) {
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

    func testExpiredReservationIsReclaimed() throws {
        let clock = KeychainTestClock()
        let quota = store(limit: 1, clock: clock)
        _ = try quota.reserve(isPro: false)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 0)

        clock.advance(by: QuotaConfiguration.reservationLifetime + 1)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.remaining, 1)
        XCTAssertNotNil(try quota.reserve(isPro: false))
    }

    func testQuotaResetsOnNextLocalDay() throws {
        let clock = KeychainTestClock()
        let quota = store(limit: 2, clock: clock)
        for _ in 0..<2 {
            let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
            try quota.commit(reservation)
        }
        XCTAssertTrue(try quota.status(isPro: false).isExhausted)

        clock.advance(by: 24 * 60 * 60)
        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.used, 0)
        XCTAssertEqual(status.remaining, 2)
    }

    func testQuotaSurvivesANewStoreInstance() throws {
        let clock = KeychainTestClock()
        let first = store(clock: clock)
        let reservation = try XCTUnwrap(try first.reserve(isPro: false))
        try first.commit(reservation)

        let restarted = store(clock: clock)
        XCTAssertEqual(try restarted.status(isPro: false).used, 1)
    }

    func testProBypassesKeychainStore() throws {
        let clock = KeychainTestClock()
        let quota = store(limit: 1, clock: clock)
        XCTAssertNil(try quota.reserve(isPro: true))
        XCTAssertEqual(try quota.status(isPro: true).remaining, Int.max)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 1)
    }
}

private final class KeychainTestClock: @unchecked Sendable {
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
