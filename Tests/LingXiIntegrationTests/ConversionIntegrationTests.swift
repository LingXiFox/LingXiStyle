import XCTest
import CryptoKit
import Photos
import UniformTypeIdentifiers
import LingXiKit
import LingXiEngine
import LingXiServices

final class ConversionIntegrationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    // MARK: Fixture

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "IMG_5296", withExtension: "HEIC"),
                                "IMG_5296.HEIC missing from test bundle")
        return url
    }

    private func fixtureData() throws -> Data {
        try Data(contentsOf: fixtureURL())
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testFixtureMatchesDocumentedChecksum() throws {
        let data = try fixtureData()
        XCTAssertEqual(data.count, 5_924_047)
        XCTAssertEqual(sha256(data), "7edf1625cc05836dadb1749ad92860abc04ebb21e4848d587cf39cf345c5c2db")
        let inspection = try HEICInspector.inspect(data)
        XCTAssertEqual(inspection.container, .heic)
        XCTAssertEqual(inspection.pixelWidth, 8064)
        XCTAssertEqual(inspection.pixelHeight, 6048)
        XCTAssertGreaterThan(inspection.primaryTileCount, 1)
        XCTAssertTrue(inspection.hasHDRGainMap)
    }

    // MARK: Real service

    func testInspectRealHEICIsReady() throws {
        let service = ConversionService(quotaManager: try quotaManager())
        let outcome = try service.inspect(fileURL: fixtureURL(), traits: AssetTraits(originalIsHEIC: true))
        XCTAssertTrue(outcome.verdict.isReady)
        XCTAssertEqual(outcome.inspection.container, .heic)
        XCTAssertEqual(outcome.inspection.pixelWidth, 8064)
        XCTAssertEqual(outcome.inspection.pixelHeight, 6048)
        XCTAssertGreaterThan(outcome.inspection.primaryTileCount, 1)
        XCTAssertTrue(outcome.inspection.hasHDRGainMap)
        XCTAssertTrue(outcome.inspection.hasStyleMetadata)
    }

    func testConvertRealHEICProducesVerifiedHEICAndKeepsOriginal() throws {
        let originalData = try fixtureData()
        let originalHash = sha256(originalData)
        let quota = try quotaManager()
        let service = ConversionService(quotaManager: quota)
        let before = try quota.status(isPro: false)
        XCTAssertEqual(before.remaining, 5)

        let outputDirectory = temporaryRoot.appendingPathComponent("out", isDirectory: true)
        let result = try awaitResult {
            try await service.convert(.init(fileURL: self.fixtureURL(),
                                            traits: AssetTraits(originalIsHEIC: true),
                                            preferredName: "IMG_5296_TextureGrain.HEIC",
                                            saveToLibrary: false,
                                            returnsFile: true,
                                            outputDirectory: outputDirectory)) { _ in }
        }

        let outputURL = try XCTUnwrap(result.outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan(result.outputByteCount, 0)
        XCTAssertTrue(result.integrity.passed, result.integrity.summary)
        XCTAssertEqual(result.inspectionAfter.container, .heic)
        XCTAssertEqual(result.inspectionAfter.pixelWidth, 8064)
        XCTAssertEqual(result.inspectionAfter.pixelHeight, 6048)
        XCTAssertEqual(result.mode, "add-texture")
        XCTAssertTrue(result.integrity.checks.allSatisfy(\.passed))
        XCTAssertEqual(try sha256(Data(contentsOf: fixtureURL())), originalHash, "the source file must not change")
        XCTAssertEqual(ImageContainerClassifier.classify(try Data(contentsOf: outputURL)), .heic)

        let after = try quota.status(isPro: false)
        XCTAssertEqual(after.remaining, 4, "a successful free conversion consumes exactly one slot")
    }

    func testQuotaPersistsAcrossServiceAndManagerInstances() throws {
        let database = temporaryRoot.appendingPathComponent("shared.sqlite")
        let first = QuotaManager(databaseURL: database)
        let service = ConversionService(quotaManager: first)
        _ = try awaitResult {
            try await service.convert(.init(fileURL: self.fixtureURL(),
                                            traits: AssetTraits(originalIsHEIC: true),
                                            preferredName: "IMG_5296_TextureGrain.HEIC",
                                            saveToLibrary: false,
                                            returnsFile: true,
                                            outputDirectory: self.temporaryRoot.appendingPathComponent("out2")),
                                   onStage: { _ in })
        }
        XCTAssertEqual(try first.status(isPro: false).remaining, 4)
        let reopened = QuotaManager(databaseURL: database)
        XCTAssertEqual(try reopened.status(isPro: false).remaining, 4)
    }

    func testCorruptedInputDoesNotConsumeQuota() throws {
        let bad = temporaryRoot.appendingPathComponent("broken.HEIC")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]).write(to: bad)
        let quota = try quotaManager()
        let service = ConversionService(quotaManager: quota)
        do {
            _ = try awaitResult {
                try await service.convert(.init(fileURL: bad,
                                                traits: AssetTraits(originalIsHEIC: true),
                                                preferredName: "broken_TextureGrain.HEIC",
                                                saveToLibrary: false,
                                                returnsFile: true,
                                                outputDirectory: self.temporaryRoot.appendingPathComponent("bad-out")),
                                       onStage: { _ in })
            }
            XCTFail("corrupted input must fail")
        } catch {
            XCTAssertTrue(error is ConversionFailure)
        }
        XCTAssertEqual(try quota.status(isPro: false).remaining, 5)
    }

    func testAlreadyEnhancedOutputDoesNotConsumeQuota() throws {
        let quota = try quotaManager()
        let service = ConversionService(quotaManager: quota)
        let first = try awaitResult {
            try await service.convert(.init(fileURL: self.fixtureURL(),
                                            traits: AssetTraits(originalIsHEIC: true),
                                            preferredName: "IMG_5296_TextureGrain.HEIC",
                                            saveToLibrary: false,
                                            returnsFile: true,
                                            outputDirectory: self.temporaryRoot.appendingPathComponent("enhanced")),
                                   onStage: { _ in })
        }
        let output = try XCTUnwrap(first.outputURL)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4)

        let second = try service.inspect(fileURL: output, traits: AssetTraits(originalIsHEIC: true))
        XCTAssertFalse(second.verdict.isReady)
        XCTAssertEqual(second.verdict.status, .alreadyEnhanced)
        do {
            _ = try awaitResult {
                try await service.convert(.init(fileURL: output,
                                                traits: AssetTraits(originalIsHEIC: true),
                                                preferredName: "again_TextureGrain.HEIC",
                                                saveToLibrary: false,
                                                returnsFile: true,
                                                outputDirectory: self.temporaryRoot.appendingPathComponent("again")),
                                       onStage: { _ in })
            }
            XCTFail("an already enhanced file must not convert twice")
        } catch {
            XCTAssertTrue(error is ConversionFailure)
        }
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4, "a skipped file must not spend a slot")
    }

    func testProConversionLeavesFreeLedgerUntouched() throws {
        let quota = try quotaManager()
        let service = ConversionService(entitlementProvider: StubEntitlement(isPro: true), quotaManager: quota)
        XCTAssertEqual(try quota.status(isPro: true).remaining, Int.max)
        for index in 0..<2 {
            _ = try awaitResult {
                try await service.convert(.init(fileURL: self.fixtureURL(),
                                                traits: AssetTraits(originalIsHEIC: true),
                                                preferredName: "pro-\(index).HEIC",
                                                saveToLibrary: false,
                                                returnsFile: true,
                                                outputDirectory: self.temporaryRoot.appendingPathComponent("pro-\(index)")),
                                       onStage: { _ in })
            }
        }
        XCTAssertEqual(try quota.status(isPro: false).remaining, 5,
                       "Pro conversions must not consume free slots")
    }

    // MARK: PhotoKit save

    func testConvertAndSaveToPhotoLibrary() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw XCTSkip("PhotoKit read/write permission is not granted to the integration host; CI grants photos and photos-add before the test.")
        }
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard addStatus == .authorized || addStatus == .limited else {
            throw XCTSkip("PhotoKit add-only permission is not granted; CI grants photos-add before the test.")
        }

        let quota = try quotaManager()
        let service = ConversionService(quotaManager: quota)
        let result = try await service.convert(.init(fileURL: self.fixtureURL(),
                                                      traits: AssetTraits(originalIsHEIC: true),
                                                      preferredName: "IMG_5296_TextureGrain.HEIC",
                                                      saveToLibrary: true,
                                                      returnsFile: false),
                                                 onStage: { _ in })
        let identifier = try XCTUnwrap(result.savedAssetIdentifier, "PhotoKit must return the new asset identifier")
        XCTAssertNil(result.saveWarning)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        let asset = try XCTUnwrap(assets.firstObject)
        let photos = PHAssetResource.assetResources(for: asset).filter { $0.type == .photo }
        XCTAssertFalse(photos.isEmpty)
        XCTAssertTrue(photos.contains { PhotoLibraryService.isHEIF($0.uniformTypeIdentifier) },
                      "saved resources: \(photos.map(\.uniformTypeIdentifier))")
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4)

        // Deleting a PhotoKit asset shows a system confirmation that blocks an unattended
        // test run, so the saved asset is intentionally left in the simulator library.
    }

    // MARK: Helpers

    private func quotaManager() throws -> QuotaManager {
        let url = temporaryRoot.appendingPathComponent("quota.sqlite")
        return QuotaManager(databaseURL: url)
    }

    private func awaitResult<T>(_ operation: @escaping () async throws -> T,
                                timeout: TimeInterval = 120,
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
            throw NSError(domain: "LingXiIntegrationTests", code: 2)
        }
    }
}

private struct StubEntitlement: ProEntitlementProviding {
    let value: Bool
    init(isPro: Bool) { self.value = isPro }
    func isPro() async -> Bool { value }
}
