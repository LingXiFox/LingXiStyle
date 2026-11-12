import XCTest
@testable import LingXiKit

final class VaultStoreTests: XCTestCase {
    private var root: URL!
    private var sourceDirectory: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultStoreTests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Vault", isDirectory: true)
        sourceDirectory = base.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func makeFile(_ name: String, bytes: Int) throws -> URL {
        let url = sourceDirectory.appendingPathComponent(name)
        let data = Data(repeating: 0x41, count: bytes)
        try data.write(to: url)
        return url
    }

    func testInsertCopiesStillAndSurvivesRelaunch() throws {
        let photo = try makeFile("result.heic", bytes: 4096)
        let store = VaultStore(rootURL: root)
        let record = try store.insert(photoURL: photo, displayName: "IMG_0001", now: Date())

        XCTAssertEqual(record.kind, .still)
        XCTAssertEqual(record.photoByteCount, 4096)
        XCTAssertNil(record.videoFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.photoURL(for: record).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: photo.path) == false)

        let reopened = VaultStore(rootURL: root)
        let listed = try reopened.records()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, record.id)
        XCTAssertEqual(listed.first?.displayName, "IMG_0001")
    }

    func testInsertLivePhotoKeepsPairedVideo() throws {
        let photo = try makeFile("live.heic", bytes: 2048)
        let video = try makeFile("live.mov", bytes: 8192)
        let store = VaultStore(rootURL: root)
        let record = try store.insert(
            photoURL: photo,
            videoURL: video,
            displayName: "IMG_0002",
            livePhotoMode: "full",
            now: Date()
        )

        XCTAssertEqual(record.kind, .livePhoto)
        XCTAssertEqual(record.videoByteCount, 8192)
        XCTAssertEqual(record.totalByteCount, 10240)
        let storedVideo = try XCTUnwrap(store.videoURL(for: record))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedVideo.path))
    }

    func testRetentionComputesExpiry() throws {
        let photo = try makeFile("result.heic", bytes: 16)
        let store = VaultStore(rootURL: root)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let timed = try store.insert(photoURL: photo, displayName: "A", retention: .threeDays, now: now)
        XCTAssertEqual(timed.expiresAt.timeIntervalSince1970, now.addingTimeInterval(3 * 86400).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(timed.remainingLifetime(at: now)), 3 * 86400, accuracy: 0.001)

        let forever = try store.insert(photoURL: photo, displayName: "B", retention: .forever, now: now)
        XCTAssertEqual(forever.expiresAt, .distantFuture)
        XCTAssertNil(forever.remainingLifetime(at: now))
        XCTAssertFalse(forever.isExpired(at: now.addingTimeInterval(10 * 365 * 86400)))
    }

    func testPurgeRemovesExpiredButKeepsRunningTaskResults() throws {
        let photo = try makeFile("result.heic", bytes: 1024)
        let store = VaultStore(rootURL: root)
        let old = Date().addingTimeInterval(-8 * 86400)
        let activeTask = UUID()

        let expired = try store.insert(photoURL: photo, displayName: "Expired", retention: .sevenDays, now: old)
        let active = try store.insert(
            photoURL: photo,
            displayName: "Active",
            sourceTaskID: activeTask,
            retention: .sevenDays,
            now: old
        )

        let result = try store.purgeExpired(keepingTaskIDs: [activeTask])
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.freedByteCount, 1024)
        XCTAssertEqual(result.failedCount, 0)

        let remaining = try store.records()
        XCTAssertEqual(remaining.map(\.id), [active.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directoryURL(for: expired).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directoryURL(for: active).path))
    }

    func testChangingRetentionRestartsTheWindow() throws {
        let photo = try makeFile("result.heic", bytes: 64)
        let store = VaultStore(rootURL: root)
        let old = Date().addingTimeInterval(-8 * 86400)
        let record = try store.insert(photoURL: photo, displayName: "Old", retention: .sevenDays, now: old)
        XCTAssertTrue(record.isExpired())

        XCTAssertEqual(try store.applyRetention(.thirtyDays), 1)
        let updated = try XCTUnwrap(try store.record(id: record.id))
        XCTAssertFalse(updated.isExpired())
        XCTAssertEqual(updated.retention, .thirtyDays)
        XCTAssertEqual(try store.purgeExpired().removedCount, 0)
    }

    func testMarkSavedTracksCountWithoutTouchingRetention() throws {
        let photo = try makeFile("result.heic", bytes: 64)
        let store = VaultStore(rootURL: root)
        let record = try store.insert(photoURL: photo, displayName: "Save me")

        let first = try store.markSaved(id: record.id, assetIdentifier: "asset-1")
        XCTAssertEqual(first.saveCount, 1)
        XCTAssertEqual(first.savedAssetIdentifier, "asset-1")
        let second = try store.markSaved(id: record.id, assetIdentifier: nil)
        XCTAssertEqual(second.saveCount, 2)
        XCTAssertEqual(second.savedAssetIdentifier, "asset-1")
        // The ledger persists dates with millisecond precision, so compare within 1 ms.
        XCTAssertEqual(second.expiresAt.timeIntervalSince1970,
                       record.expiresAt.timeIntervalSince1970,
                       accuracy: 0.001)

        try store.delete(id: record.id)
        XCTAssertTrue(try store.records().isEmpty)
        XCTAssertThrowsError(try store.delete(id: record.id))
    }

    func testCorruptRecordDoesNotHideHealthyOnes() throws {
        let photo = try makeFile("result.heic", bytes: 32)
        let store = VaultStore(rootURL: root)
        let healthy = try store.insert(photoURL: photo, displayName: "Healthy")

        let broken = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: broken.appendingPathComponent(VaultStore.metadataFileName))

        XCTAssertEqual(try store.records().map(\.id), [healthy.id])
        XCTAssertEqual(try store.totalByteCount(), 32)
    }

    func testMissingPhotoIsRejected() throws {
        let store = VaultStore(rootURL: root)
        let missing = sourceDirectory.appendingPathComponent("nope.heic")
        XCTAssertThrowsError(try store.insert(photoURL: missing, displayName: "Nope")) { error in
            XCTAssertEqual(error as? VaultError, .missingPhoto)
        }
        XCTAssertTrue(try store.records().isEmpty)
    }
}