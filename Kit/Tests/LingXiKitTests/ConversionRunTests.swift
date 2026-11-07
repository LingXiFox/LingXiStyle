import XCTest
@testable import LingXiKit

final class ConversionRunTests: XCTestCase {
    func testSavedItemsAreNeverConvertedAgain() {
        let saved = UUID()
        let retry = UUID()
        let pending = UUID()
        var run = ConversionRun(entries: [
            (saved, .saved),
            (retry, .pending),
            (pending, .pending)
        ])

        XCTAssertEqual(run.next(), .convert(retry))
        run.complete(retry, state: .saved)
        XCTAssertEqual(run.next(), .convert(pending))
        run.complete(pending, state: .saved)
        XCTAssertEqual(run.next(), .finished)
        XCTAssertEqual(run.state(of: saved), .saved)
        XCTAssertEqual(run.state(of: retry), .saved)
    }

    func testCancelKeepsCompletedItemAndCancelsRemaining() {
        let first = UUID()
        let second = UUID()
        var run = ConversionRun(entries: [(first, .pending), (second, .pending)])

        XCTAssertEqual(run.next(), .convert(first))
        run.complete(first, state: .saved)
        run.requestCancel()
        XCTAssertTrue(run.isCancelling)
        XCTAssertEqual(run.next(), .cancel(second))
        XCTAssertEqual(run.next(), .finished)
        XCTAssertEqual(run.state(of: first), .saved)
        XCTAssertEqual(run.state(of: second), .cancelled)
        XCTAssertTrue(run.hasSaved)
    }

    func testCancelBeforeStartYieldsCancelActionsInOrder() {
        let first = UUID()
        let second = UUID()
        var run = ConversionRun(entries: [(first, .pending), (second, .pending)])
        run.requestCancel()

        XCTAssertEqual(run.next(), .cancel(first))
        XCTAssertEqual(run.next(), .cancel(second))
        XCTAssertEqual(run.next(), .finished)
        XCTAssertEqual(run.pendingCount, 0)
    }

    func testStaleSessionCannotCompleteNewRun() {
        let item = UUID()
        let oldRun = ConversionRun(entries: [(item, .pending)])
        var newRun = ConversionRun(entries: [(item, .pending)])

        XCTAssertTrue(oldRun.accepts(sessionID: oldRun.id))
        XCTAssertFalse(oldRun.accepts(sessionID: newRun.id))
        XCTAssertEqual(newRun.next(), .convert(item))
        newRun.complete(item, state: .saved)
        XCTAssertEqual(newRun.state(of: item), .saved)
        // An old token is rejected before it can touch the new run.
        XCTAssertFalse(oldRun.accepts(sessionID: newRun.id))
        XCTAssertEqual(newRun.state(of: item), .saved)
    }

    func testUnsupportedAndUnavailableItemsDoNotBlockQueue() {
        let unsupported = UUID()
        let unavailable = UUID()
        let ready = UUID()
        var run = ConversionRun(entries: [
            (unsupported, .unsupported),
            (unavailable, .unavailable),
            (ready, .pending)
        ])

        XCTAssertEqual(run.next(), .skip(unsupported))
        XCTAssertEqual(run.next(), .cancel(unavailable))
        XCTAssertEqual(run.next(), .convert(ready))
        run.complete(ready, state: .saved)
        XCTAssertEqual(run.next(), .finished)
    }

    func testDeferRemainingLeavesCompletedItemsAlone() {
        let saved = UUID()
        let waiting = UUID()
        let later = UUID()
        var run = ConversionRun(entries: [
            (saved, .pending),
            (waiting, .pending),
            (later, .pending)
        ])

        XCTAssertEqual(run.next(), .convert(saved))
        run.complete(saved, state: .saved)
        let deferred = run.deferRemaining()

        XCTAssertEqual(Set(deferred), Set([waiting, later]))
        XCTAssertEqual(run.state(of: saved), .saved)
        XCTAssertEqual(run.state(of: waiting), .deferred)
        XCTAssertEqual(run.state(of: later), .deferred)
        XCTAssertEqual(run.next(), .finished)
    }

    func testCompletingNonPendingItemIsIgnored() {
        let item = UUID()
        var run = ConversionRun(entries: [(item, .saved)])
        run.complete(item, state: .failed)
        XCTAssertEqual(run.state(of: item), .saved)
    }
}
