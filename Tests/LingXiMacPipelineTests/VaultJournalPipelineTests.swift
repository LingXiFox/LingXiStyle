import XCTest
import LingXiKit
import LingXiEngine
import LingXiServices

/// Exercises the macOS build of the conversion pipeline: no PhotoKit, exports only,
/// with the vault and task journal attached exactly like TexelMac does at launch.
final class VaultJournalPipelineTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiMacPipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: "IMG_5296", withExtension: "HEIC"),
                             "IMG_5296.HEIC missing from test bundle")
    }

    private func makeQuota() throws -> any QuotaManaging {
        QuotaManager(databaseURL: root.appendingPathComponent("quota.sqlite"))
    }

    private func makeService(quota: any QuotaManaging) -> ConversionService {
        ConversionService(entitlementProvider: FreeEntitlement(), quotaManager: quota)
    }

    private func task(_ item: TaskItemRecord) -> ConversionTaskRecord {
        ConversionTaskRecord(id: UUID(), createdAt: Date(), origin: .mac, isPro: false, items: [item])
    }

    func testConversionWritesVaultAndJournalOnMacOS() async throws {
        let quota = try makeQuota()
        let vault = VaultStore(rootURL: root.appendingPathComponent("vault", isDirectory: true))
        let journal = TaskJournal(storeURL: root.appendingPathComponent("tasks.json"))
        let service = makeService(quota: quota)
        service.configureStorage(vault: vault, journal: journal)

        let itemID = UUID()
        let taskRecord = task(TaskItemRecord(id: itemID, displayName: "IMG_5296", isLivePhoto: false))
        _ = try journal.upsert(taskRecord)
        let taskID = taskRecord.id

        let before = try quota.status(isPro: false)
        let outputDirectory = root.appendingPathComponent("out", isDirectory: true)
        let result = try await service.convert(.init(fileURL: try fixtureURL(),
                                                      traits: AssetTraits(originalIsHEIC: true),
                                                      preferredName: "IMG_5296_Texel.HEIC",
                                                      saveToLibrary: false,
                                                      returnsFile: true,
                                                      outputDirectory: outputDirectory,
                                                      taskID: taskID,
                                                      itemID: itemID,
                                                      vaultRetention: .sevenDays),
                       onStage: { _ in })

        XCTAssertNil(result.saveWarning)
        let outputURL = try XCTUnwrap(result.outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(outputURL.pathExtension.lowercased(), "heic")

        // Vault keeps the finished result so a re-save never pays twice.
        let recordID = try XCTUnwrap(result.vaultRecordID)
        let record = try XCTUnwrap(try vault.record(id: recordID))
        XCTAssertEqual(record.photoByteCount, result.outputByteCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(vault.photoURL(for: record)).path))
        XCTAssertEqual(record.sourceTaskID, taskID)

        // Journal mirrors the same state the desktop UI renders.
        let stored = try XCTUnwrap(try journal.task(id: taskID))
        let item = try XCTUnwrap(stored.items.first)
        XCTAssertEqual(item.state, .saved)
        XCTAssertEqual(item.vaultRecordID, recordID)
        XCTAssertEqual(item.quotaState, .committed)
        XCTAssertEqual(stored.savedCount, 1)

        // Exactly one allowance was spent and it is committed, not still reserved.
        let after = try quota.status(isPro: false)
        XCTAssertEqual(after.used, before.used + 1)
        XCTAssertEqual(after.reserved, 0)
    }

    func testVaultResaveDoesNotTouchAllowance() async throws {
        let quota = try makeQuota()
        let vault = VaultStore(rootURL: root.appendingPathComponent("vault", isDirectory: true))
        let photo = root.appendingPathComponent("still.heic")
        try FileManager.default.copyItem(at: try fixtureURL(), to: photo)

        let record = try vault.insert(photoURL: photo, videoURL: nil, displayName: "IMG_5296",
                                      livePhotoMode: nil, sourceTaskID: nil, sourceItemID: nil,
                                      retention: .sevenDays)
        let before = try quota.status(isPro: false)

        try vault.markSaved(id: record.id, assetIdentifier: "exported:(record.id)")
        let reloaded = try XCTUnwrap(try vault.record(id: record.id))
        XCTAssertEqual(reloaded.saveCount, 1)
        XCTAssertEqual(reloaded.savedAssetIdentifier, "exported:(record.id)")

        let after = try quota.status(isPro: false)
        XCTAssertEqual(after.used, before.used)
        XCTAssertEqual(after.reserved, before.reserved)
    }

    func testRecoveredTaskReleasesStaleReservation() async throws {
        let quota = try makeQuota()
        let journal = TaskJournal(storeURL: root.appendingPathComponent("tasks.json"))
        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))

        var item = TaskItemRecord(id: UUID(), displayName: "IMG_5296", isLivePhoto: false)
        item.state = .converting
        item.attachReservation(reservation)
        let record = task(item)
        _ = try journal.upsert(record)

        XCTAssertEqual(try quota.status(isPro: false).reserved, 1)

        let recoveries = try journal.recoverInterrupted()
        XCTAssertEqual(recoveries.count, 1)
        for recovery in recoveries {
            for stale in recovery.reservationsToRelease { try quota.release(stale) }
            for settled in recovery.reservationsToCommit { try quota.commit(settled) }
        }

        XCTAssertEqual(try quota.status(isPro: false).reserved, 0)
        XCTAssertEqual(try quota.status(isPro: false).used, 0, "an interrupted conversion must not be charged")
        XCTAssertEqual(try journal.task(id: record.id)?.state, .interrupted)
    }
}

private struct FreeEntitlement: ProEntitlementProviding {
    func isPro() async -> Bool { false }
}
