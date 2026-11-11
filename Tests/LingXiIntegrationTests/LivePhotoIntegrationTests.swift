import AVFoundation
import Photos
import XCTest
import LingXiKit
import LingXiEngine
import LingXiServices

/// End-to-end checks for the 1.8.1 Live Photo pipelines: real service, real PhotoKit save,
/// and the "one Live Photo is one photo" quota rule.
final class LivePhotoIntegrationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiLivePhotoIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    // MARK: Fixtures

    private func livePhotoFixture() throws -> (still: URL, video: URL) {
        let bundle = Bundle(for: Self.self)
        let still = try XCTUnwrap(bundle.url(forResource: "IMG_5963", withExtension: "HEIC"),
                                  "IMG_5963.HEIC missing from the integration test bundle")
        let video = try XCTUnwrap(bundle.url(forResource: "IMG_5963", withExtension: "MOV"),
                                  "IMG_5963.MOV missing from the integration test bundle")
        return (still, video)
    }

    private func longLivePhotoFixture() throws -> (still: URL, video: URL) {
        let bundle = Bundle(for: Self.self)
        let still = try XCTUnwrap(bundle.url(forResource: "IMG_5963", withExtension: "HEIC"),
                                  "IMG_5963.HEIC missing from the integration test bundle")
        let video = try XCTUnwrap(bundle.url(forResource: "IMG_5963-long", withExtension: "MOV"),
                                  "IMG_5963-long.MOV missing from the integration test bundle")
        return (still, video)
    }

    private func quotaManager() throws -> QuotaManager {
        QuotaManager(databaseURL: temporaryRoot.appendingPathComponent("quota.sqlite"))
    }

    private func outputDirectory(_ name: String) -> URL {
        temporaryRoot.appendingPathComponent(name, isDirectory: true)
    }

    // MARK: Modes

    func testStillOnlyLivePhotoCopiesMovieBytesAndChargesOneSlot() throws {
        let fixture = try livePhotoFixture()
        let sourceMovie = try Data(contentsOf: fixture.video)
        let quota = try quotaManager()
        let service = ConversionService(quotaManager: quota)
        let stages = StageRecorder()

        let result = try awaitResult {
            try await service.convert(.init(fileURL: fixture.still,
                                            pairedVideoURL: fixture.video,
                                            livePhotoMode: .stillOnly,
                                            traits: AssetTraits(isLivePhoto: true),
                                            preferredName: "IMG_5963_TextureGrain.HEIC",
                                            saveToLibrary: false,
                                            returnsFile: true,
                                            outputDirectory: self.outputDirectory("still-only")),
                                   onStage: stages.record)
        }

        XCTAssertEqual(result.livePhotoMode, .stillOnly)
        XCTAssertEqual(result.videoFrameCount, 53)
        let outputVideo = try XCTUnwrap(result.outputVideoURL)
        XCTAssertEqual(try Data(contentsOf: outputVideo), sourceMovie,
                       "still-only mode must hand the original movie bytes to PhotoKit")
        XCTAssertEqual(result.inspectionAfter.container, .heic)
        XCTAssertTrue(result.integrity.passed, result.integrity.summary)
        XCTAssertFalse(stages.values.contains(.processingFrames))
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4,
                       "a Live Photo costs exactly one slot whatever the mode")
    }

    func testFullModeRendersEveryFrameAndStillChargesOneSlot() throws {
        let fixture = try livePhotoFixture()
        let sourceMovieBytes = try Data(contentsOf: fixture.video).count
        let quota = try quotaManager()
        let counting = CountingQuota(base: quota)
        let service = ConversionService(quotaManager: counting)
        let stages = StageRecorder()

        let result = try awaitResult(timeout: 240) {
            try await service.convert(.init(fileURL: fixture.still,
                                            pairedVideoURL: fixture.video,
                                            livePhotoMode: .full,
                                            traits: AssetTraits(isLivePhoto: true),
                                            preferredName: "IMG_5963_TextureGrain.HEIC",
                                            saveToLibrary: false,
                                            returnsFile: true,
                                            outputDirectory: self.outputDirectory("full")),
                                   onStage: stages.record)
        }

        XCTAssertEqual(result.livePhotoMode, .full)
        XCTAssertEqual(result.videoFrameCount, 53)
        let outputVideo = try XCTUnwrap(result.outputVideoURL)
        let outputMovie = try Data(contentsOf: outputVideo)
        XCTAssertGreaterThan(outputMovie.count, sourceMovieBytes,
                             "the styled movie must carry the added texture track")
        XCTAssertTrue(stages.values.contains(.processingFrames))
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4)
        let counts = counting.counts
        XCTAssertEqual(counts.reservations, 1, "one reservation per Live Photo, not per frame")
        XCTAssertEqual(counts.commits, 1)
        XCTAssertEqual(counts.releases, 0)
    }

    func testFullModeWithOverNinetyFramesStillChargesOneSlot() throws {
        let fixture = try longLivePhotoFixture()
        let sourceMovieBytes = try Data(contentsOf: fixture.video).count
        let quota = try quotaManager()
        let counting = CountingQuota(base: quota)
        let service = ConversionService(quotaManager: counting)
        let stages = StageRecorder()

        let result = try awaitResult(timeout: 300) {
            try await service.convert(.init(fileURL: fixture.still,
                                            pairedVideoURL: fixture.video,
                                            livePhotoMode: .full,
                                            traits: AssetTraits(isLivePhoto: true),
                                            preferredName: "IMG_5963_TextureGrain.HEIC",
                                            saveToLibrary: false,
                                            returnsFile: true,
                                            outputDirectory: self.outputDirectory("full-long")),
                                   onStage: stages.record)
        }

        XCTAssertEqual(result.videoFrameCount, 106,
                       "the long fixture must exercise a 90-plus frame Live Photo")
        let outputVideo = try XCTUnwrap(result.outputVideoURL)
        XCTAssertGreaterThan(try Data(contentsOf: outputVideo).count, sourceMovieBytes,
                             "the styled movie must carry the added texture track")
        XCTAssertTrue(stages.values.contains(.processingFrames))
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4,
                       "106 frames must still spend exactly one slot")
        let counts = counting.counts
        XCTAssertEqual(counts.reservations, 1, "one reservation per Live Photo, not per frame")
        XCTAssertEqual(counts.commits, 1)
        XCTAssertEqual(counts.releases, 0)
    }

    func testLivePhotoSavesPairedAssetToPhotoLibrary() throws {
        try requirePhotoPermissions()
        let fixture = try livePhotoFixture()
        let quota = try quotaManager()
        let service = ConversionService(quotaManager: quota)

        let result = try awaitResult(timeout: 300) {
            try await service.convert(.init(fileURL: fixture.still,
                                            pairedVideoURL: fixture.video,
                                            livePhotoMode: .full,
                                            traits: AssetTraits(isLivePhoto: true),
                                            preferredName: "IMG_5963_TextureGrain.HEIC",
                                            saveToLibrary: true,
                                            returnsFile: false),
                                   onStage: { _ in })
        }

        let identifier = try XCTUnwrap(result.savedAssetIdentifier,
                                       "PhotoKit must return the new asset identifier")
        XCTAssertNil(result.saveWarning, result.saveWarning ?? "")
        let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject)
        XCTAssertTrue(asset.mediaSubtypes.contains(.photoLive),
                      "the saved asset must come back as a Live Photo, got \(asset.mediaSubtypes)")
        let resources = PHAssetResource.assetResources(for: asset)
        XCTAssertTrue(resources.contains { $0.type == .photo })
        XCTAssertTrue(resources.contains { $0.type == .pairedVideo },
                      "resources: \(resources.map(\.type))")
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4)

        // The system "delete photo" confirmation blocks unattended runs, so the saved asset stays
        // in the simulator library on purpose.
    }

    func testBrokenMovieReleasesQuota() throws {
        let fixture = try livePhotoFixture()
        let brokenMovie = temporaryRoot.appendingPathComponent("broken.MOV")
        try Data([0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70]).write(to: brokenMovie)
        let quota = try quotaManager()
        let service = ConversionService(quotaManager: quota)

        do {
            _ = try awaitResult {
                try await service.convert(.init(fileURL: fixture.still,
                                                pairedVideoURL: brokenMovie,
                                                livePhotoMode: .full,
                                                traits: AssetTraits(isLivePhoto: true),
                                                preferredName: "broken_TextureGrain.HEIC",
                                                saveToLibrary: false,
                                                returnsFile: true,
                                                outputDirectory: self.outputDirectory("broken")),
                                       onStage: { _ in })
            }
            XCTFail("a Live Photo with an unreadable movie must fail")
        } catch {
            XCTAssertTrue(error is ConversionFailure)
        }
        XCTAssertEqual(try quota.status(isPro: false).remaining, 5,
                       "a failed Live Photo conversion must not spend a slot")
    }

    // MARK: Helpers

    private func requirePhotoPermissions() throws {
        let readWrite = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let addOnly = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let granted: (PHAuthorizationStatus) -> Bool = { $0 == .authorized || $0 == .limited }
        guard granted(readWrite), granted(addOnly) else {
            XCTFail("""
                PhotoKit permission missing for the integration host (readWrite=\(readWrite.rawValue),                 addOnly=\(addOnly.rawValue), bundle=\(Bundle.main.bundleIdentifier ?? "nil")). Grant                 photos and photos-add to com.lingxifox.Texel.IntegrationHost before running.
                """)
            throw XCTSkip("PhotoKit permission missing")
        }
    }

    private func awaitResult<T>(timeout: TimeInterval = 120,
                                _ operation: @escaping () async throws -> T,
                                file: StaticString = #filePath,
                                line: UInt = #line) throws -> T {
        let expectation = expectation(description: "async conversion")
        var result: Result<T, Error>?
        Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        case .none:
            XCTFail("async operation produced no result", file: file, line: line)
            throw NSError(domain: "LingXiLivePhotoIntegrationTests", code: 2)
        }
    }
}

private final class StageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversionStage] = []

    func record(_ stage: ConversionStage) {
        lock.lock()
        storage.append(stage)
        lock.unlock()
    }

    var values: [ConversionStage] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class CountingQuota: QuotaManaging, @unchecked Sendable {
    private let base: QuotaManager
    private let lock = NSLock()
    private var reservations = 0
    private var commits = 0
    private var releases = 0

    init(base: QuotaManager) { self.base = base }

    func status(isPro: Bool) throws -> QuotaStatus { try base.status(isPro: isPro) }

    func reserve(isPro: Bool) throws -> QuotaReservation? {
        lock.lock()
        reservations += 1
        lock.unlock()
        return try base.reserve(isPro: isPro)
    }

    func commit(_ reservation: QuotaReservation?) throws {
        lock.lock()
        commits += 1
        lock.unlock()
        try base.commit(reservation)
    }

    func release(_ reservation: QuotaReservation?) throws {
        lock.lock()
        releases += 1
        lock.unlock()
        try base.release(reservation)
    }

    var counts: (reservations: Int, commits: Int, releases: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (reservations, commits, releases)
    }
}
