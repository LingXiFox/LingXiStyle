import XCTest
import Photos
import LingXiKit
import LingXiEngine
import LingXiServices

/// Covers the 1.9.1 result vault and task journal on a real PhotoKit-backed run.
final class VaultJournalIntegrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiVaultJournal-\(UUID().uuidString)", isDirectory: true)
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

    private func quotaManager() -> QuotaManager {
        QuotaManager(databaseURL: root.appendingPathComponent("quota.sqlite"))
    }

    private func requireLibraryPermission() throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw XCTSkip("PhotoKit read/write permission missing (status=\(status.rawValue))")
        }
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard addStatus == .authorized || addStatus == .limited else {
            throw XCTSkip("PhotoKit add-only permission missing (status=\(addStatus.rawValue))")
        }
    }

    func testConvertedPhotoLandsInVaultAndJournal() throws {
        try requireLibraryPermission()
        let quota = quotaManager()
        let vault = VaultStore(rootURL: root.appendingPathComponent("vault", isDirectory: true))
        let journal = TaskJournal(storeURL: root.appendingPathComponent("tasks.json"))
        let service = ConversionService(quotaManager: quota)
        service.configureStorage(vault: vault, journal: journal)

        let itemID = UUID()
        let taskRecord = ConversionTaskRecord(origin: .app,
                                              items: [TaskItemRecord(id: itemID, displayName: "IMG_5296")])
        _ = try journal.upsert(taskRecord)

        let result = try awaitResult {
            try await service.convert(.init(fileURL: self.fixtureURL(),
                                            traits: AssetTraits(originalIsHEIC: true),
                                            preferredName: "IMG_5296_TextureGrain.HEIC",
                                            saveToLibrary: true,
                                            returnsFile: false,
                                            taskID: taskRecord.id,
                                            itemID: itemID,
                                            vaultRetention: .sevenDays),
                                   onStage: { _ in })
        }

        XCTAssertNotNil(result.savedAssetIdentifier)
        XCTAssertNil(result.saveWarning)

        let recordID = try XCTUnwrap(result.vaultRecordID, "a finished result must be kept in the vault")
        let record = try XCTUnwrap(try vault.record(id: recordID))
        XCTAssertEqual(record.photoByteCount, result.outputByteCount)
        XCTAssertEqual(record.sourceItemID, itemID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(vault.photoURL(for: record)).path))

        let stored = try XCTUnwrap(try journal.task(id: taskRecord.id))
        let item = try XCTUnwrap(stored.items.first)
        XCTAssertEqual(item.state, .saved)
        XCTAssertEqual(item.vaultRecordID, recordID)
        XCTAssertEqual(item.quotaState, .committed)
        XCTAssertEqual(item.savedAssetIdentifier, result.savedAssetIdentifier)

        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.remaining, 4)
        XCTAssertEqual(status.reserved, 0)
    }

    func testResaveFromVaultKeepsAllowanceAndSource() throws {
        try requireLibraryPermission()
        let quota = quotaManager()
        let vault = VaultStore(rootURL: root.appendingPathComponent("vault", isDirectory: true))
        let source = root.appendingPathComponent("vault-source.heic")
        try FileManager.default.copyItem(at: try fixtureURL(), to: source)
        let record = try vault.insert(photoURL: source, videoURL: nil, displayName: "IMG_5296",
                                      livePhotoMode: nil, sourceTaskID: nil, sourceItemID: nil,
                                      retention: .sevenDays)

        let before = try quota.status(isPro: false)
        let photoURL = try XCTUnwrap(vault.photoURL(for: record))
        let saved = try awaitResult {
            try await PhotoLibraryService().saveNewPhoto(from: photoURL,
                                                         preferredName: "IMG_5296_Vault.HEIC")
        }
        try vault.markSaved(id: record.id, assetIdentifier: saved.identifier)

        let after = try quota.status(isPro: false)
        XCTAssertEqual(after.used, before.used, "re-saving from the vault must not charge again")
        XCTAssertEqual(after.reserved, before.reserved)

        let reloaded = try XCTUnwrap(try vault.record(id: record.id))
        XCTAssertEqual(reloaded.saveCount, 1)
        XCTAssertEqual(reloaded.savedAssetIdentifier, saved.identifier)
    }

    func testInterruptedTaskReleasesReservationAndKeepsVaultResult() throws {
        let quota = quotaManager()
        let vault = VaultStore(rootURL: root.appendingPathComponent("vault", isDirectory: true))
        let journal = TaskJournal(storeURL: root.appendingPathComponent("tasks.json"))

        let source = root.appendingPathComponent("stored.heic")
        try FileManager.default.copyItem(at: try fixtureURL(), to: source)
        let record = try vault.insert(photoURL: source, videoURL: nil, displayName: "IMG_5296",
                                      livePhotoMode: nil, sourceTaskID: nil, sourceItemID: nil,
                                      retention: .sevenDays)

        let reservation = try XCTUnwrap(try quota.reserve(isPro: false))
        var savedItem = TaskItemRecord(id: UUID(), displayName: "IMG_5296")
        savedItem.attachReservation(reservation)
        savedItem.state = .saving
        savedItem.vaultRecordID = record.id

        var unsavedItem = TaskItemRecord(id: UUID(), displayName: "IMG_5296 copy")
        unsavedItem.attachReservation(try XCTUnwrap(try quota.reserve(isPro: false)))
        unsavedItem.state = .converting

        let task = ConversionTaskRecord(origin: .app, items: [savedItem, unsavedItem])
        _ = try journal.upsert(task)

        let recoveries = try journal.recoverInterrupted()
        let recovery = try XCTUnwrap(recoveries.first { $0.task.id == task.id })
        XCTAssertEqual(recovery.reservationsToCommit.count, 0, "an unconfirmed save must not settle a slot")
        XCTAssertEqual(recovery.reservationsToRelease.count, 2, "both unsettled slots go back")
        for reservation in recovery.reservationsToRelease { try quota.release(reservation) }
        for reservation in recovery.reservationsToCommit { try quota.commit(reservation) }

        let status = try quota.status(isPro: false)
        XCTAssertEqual(status.reserved, 0)
        XCTAssertEqual(status.used, 0, "a crash before the save is confirmed must not charge")

        let stored = try XCTUnwrap(try journal.task(id: task.id))
        XCTAssertEqual(stored.state, .interrupted)
        XCTAssertEqual(stored.recoverableItems.count, 1)
    }

    private func awaitResult<T>(_ operation: @escaping () async throws -> T,
                                timeout: TimeInterval = 120,
                                file: StaticString = #filePath,
                                line: UInt = #line) throws -> T {
        let expectation = expectation(description: "async operation")
        var result: Result<T, Error>?
        Task {
            do { result = .success(try await operation()) }
            catch { result = .failure(error) }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        case .none:
            XCTFail("async operation produced no result", file: file, line: line)
            throw NSError(domain: "LingXiVaultJournalTests", code: 2)
        }
    }
}
