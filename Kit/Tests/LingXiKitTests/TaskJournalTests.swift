import XCTest
@testable import LingXiKit

final class TaskJournalTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskJournalTests-\(UUID().uuidString)", isDirectory: true)
        storeURL = directory.appendingPathComponent(TaskJournal.fileName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    private func journal() -> TaskJournal { TaskJournal(storeURL: storeURL, maxRecords: 50) }

    func testUpsertPersistsAndSortsNewestFirst() throws {
        let journal = journal()
        let older = ConversionTaskRecord(createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        let newer = ConversionTaskRecord(createdAt: Date(timeIntervalSince1970: 1_800_000_100))
        try journal.upsert(older)
        try journal.upsert(newer)

        let reloaded = self.journal().tasks()
        XCTAssertEqual(reloaded.map(\.id), [newer.id, older.id])
    }

    func testUpsertReplacesExistingTask() throws {
        let journal = journal()
        var task = ConversionTaskRecord(items: [TaskItemRecord(displayName: "A")])
        try journal.upsert(task)
        task.items[0].state = .saved
        try journal.upsert(task)

        XCTAssertEqual(try journal.tasks().count, 1)
        XCTAssertEqual(journal.tasks().first?.items.first?.state, .saved)
    }

    func testRecoveryMarksInterruptedAndSettlesReservations() throws {
        let journal = journal()
        let vaulted = UUID()
        var savedItem = TaskItemRecord(displayName: "Saved")
        savedItem.state = .saved
        savedItem.attachReservation(QuotaReservation(id: "r-1", day: "2026-01-01"))
        var inFlight = TaskItemRecord(displayName: "In flight")
        inFlight.state = .converting
        inFlight.attachReservation(QuotaReservation(id: "r-2", day: "2026-01-01"))
        var vaultedItem = TaskItemRecord(displayName: "Vaulted")
        vaultedItem.state = .saving
        vaultedItem.vaultRecordID = vaulted
        vaultedItem.attachReservation(QuotaReservation(id: "r-3", day: "2026-01-01"))
        let task = ConversionTaskRecord(items: [savedItem, inFlight, vaultedItem])
        try journal.upsert(task)

        let recoveries = try journal.recoverInterrupted()
        XCTAssertEqual(recoveries.count, 1)
        let recovery = try XCTUnwrap(recoveries.first)
        XCTAssertEqual(recovery.task.state, .interrupted)
        XCTAssertEqual(recovery.task.items.map(\.state), [.saved, .interrupted, .interrupted])
        XCTAssertEqual(recovery.reservationsToCommit.map(\.id), ["r-1"])
        XCTAssertEqual(recovery.reservationsToRelease.map(\.id), ["r-2"])
        XCTAssertEqual(recovery.task.items[1].quotaState, .released)
        XCTAssertEqual(recovery.task.items[2].quotaState, .reserved)
        XCTAssertEqual(recovery.task.items[2].vaultRecordID, vaulted)
        XCTAssertEqual(recovery.task.recoverableItems.map(\.id), [vaultedItem.id])

        XCTAssertTrue(try journal.recoverInterrupted().isEmpty)
        XCTAssertEqual(journal.tasks().first?.state, .interrupted)
    }

    func testResolvedStateCoversBatchOutcomes() {
        var task = ConversionTaskRecord(items: [
            TaskItemRecord(displayName: "A"),
            TaskItemRecord(displayName: "B")
        ])
        XCTAssertEqual(task.resolvedState(isCancelled: false), .running)

        task.items[0].state = .saved
        task.items[1].state = .failed
        XCTAssertEqual(task.resolvedState(isCancelled: false), .partiallyCompleted)

        task.items[1].state = .saved
        XCTAssertEqual(task.resolvedState(isCancelled: false), .completed)

        task.items[1].state = .saved
        XCTAssertEqual(task.resolvedState(isCancelled: true), .cancelled)

        var allFailed = ConversionTaskRecord(items: [TaskItemRecord(displayName: "C")])
        allFailed.items[0].state = .failed
        XCTAssertEqual(allFailed.resolvedState(isCancelled: false), .failed)

        var allSkipped = ConversionTaskRecord(items: [TaskItemRecord(displayName: "D")])
        allSkipped.items[0].state = .skipped
        XCTAssertEqual(allSkipped.resolvedState(isCancelled: false), .completed)
    }

    func testCorruptLedgerIsQuarantinedInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ broken".utf8).write(to: storeURL)

        let journal = journal()
        XCTAssertTrue(journal.tasks().isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().path)
        XCTAssertTrue(files.contains { $0.hasPrefix("tasks.corrupt-") })

        try journal.upsert(ConversionTaskRecord())
        XCTAssertEqual(journal.tasks().count, 1)
    }

    func testPruneKeepsActiveTasks() throws {
        let journal = journal()
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        var finished = ConversionTaskRecord(createdAt: old, items: [TaskItemRecord(displayName: "A")])
        finished.items[0].state = .saved
        finished.state = .completed
        let running = ConversionTaskRecord(createdAt: old, items: [TaskItemRecord(displayName: "B")])
        try journal.upsert(finished)
        try journal.upsert(running)

        XCTAssertEqual(try journal.prune(olderThan: Date()), 1)
        XCTAssertEqual(journal.tasks().map(\.id), [running.id])
    }

    func testTrimKeepsRunningTaskBeyondRecordLimit() throws {
        let journal = TaskJournal(storeURL: storeURL, maxRecords: 2)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in 0..<4 {
            var task = ConversionTaskRecord(createdAt: base.addingTimeInterval(Double(offset)))
            task.state = .completed
            try journal.upsert(task)
        }
        let running = ConversionTaskRecord(createdAt: base)
        try journal.upsert(running)
        XCTAssertEqual(journal.tasks().count, 3)
        XCTAssertTrue(journal.tasks().contains { $0.id == running.id })
    }
}