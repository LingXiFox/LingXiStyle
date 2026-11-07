import XCTest
import UniformTypeIdentifiers
@testable import LingXiKit
@testable import LingXiEngine
import LingXiServices

@MainActor
final class ShareFlowTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiShareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    // MARK: Fixtures

    nonisolated private static func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: "IMG_5296", withExtension: "HEIC"))
    }

    nonisolated private static func fixtureData() throws -> Data {
        try Data(contentsOf: fixtureURL())
    }

    nonisolated private static func readyOutcome() -> InspectionOutcome {
        let inspection = HEICInspection(fileByteCount: 5_924_047,
                                        pixelWidth: 8064,
                                        pixelHeight: 6048,
                                        itemCount: 60,
                                        primaryTileCount: 54,
                                        hasPrimaryGrid: true,
                                        hasStyleMetadata: true,
                                        hasExif: true,
                                        hasThumbnail: true,
                                        hasHDRGainMap: true,
                                        supportsGraftLayout: true)
        return InspectionOutcome(inspection: inspection,
                                 verdict: CompatibilityVerdict(status: .ready, inspection: inspection),
                                 byteCount: inspection.fileByteCount)
    }

    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 3,
                           predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func shareDirectories() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: temporaryRoot,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]))?
            .filter { $0.lastPathComponent.hasPrefix("LingXiShare-") } ?? []
    }

    // MARK: Success and cancellation

    func testReadsAndConvertsSharedHEIC() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)
        var closed = false
        model.onClose = { closed = true }

        model.begin(items: [provider])
        await waitUntil("share success") { model.phase == .done }

        XCTAssertEqual(model.title, "已保存新照片")
        XCTAssertEqual(model.diagnosticCode, "SAVED:asset-1")
        XCTAssertEqual(runner.convertCalls, 1)
        XCTAssertFalse(closed)
        XCTAssertTrue(shareDirectories().isEmpty, "successful shares must remove their temporary copy")
    }

    func testUserCancelsWhileReading() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { _ in }
        provider.dataHandler = { _ in }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 5,
                               readTimeout: 5)

        model.begin(items: [provider])
        await waitUntil("reading") { model.phase == .reading }
        model.cancel()

        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertEqual(model.title, "已取消")
        XCTAssertEqual(runner.convertCalls, 0)
        XCTAssertTrue(shareDirectories().isEmpty)
    }

    func testUserCancelsWhileConverting() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in
                                         try? await Task.sleep(nanoseconds: 5_000_000_000)
                                         try Task.checkCancellation()
                                         return ShareConversionResult(savedAssetIdentifier: "asset-1")
                                     })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)

        model.begin(items: [provider])
        await waitUntil("converting") {
            if case .converting = model.phase { return true }
            return false
        }
        model.cancel()
        await waitUntil("cancelled") { model.phase == .cancelled }

        XCTAssertEqual(model.title, "已取消，没有保存新照片")
        XCTAssertEqual(runner.convertCalls, 1)
        XCTAssertTrue(shareDirectories().isEmpty)
    }

    // MARK: Read failures and fallback

    func testProviderWithoutFileFailsWithReadCode() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(nil, NSError(domain: "test", code: 1)) }
        provider.dataHandler = { completion in completion(nil, NSError(domain: "test", code: 2)) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)

        model.begin(items: [provider])
        await waitUntil("read failure") { model.phase == .failed }

        XCTAssertEqual(model.diagnosticCode, "E_SHARE_READ")
        XCTAssertTrue(model.canRetry)
        XCTAssertEqual(runner.convertCalls, 0)
    }

    func testDataFallbackCompletesWhenFileRepresentationIsDropped() async throws {
        let data = try Self.fixtureData()
        let provider = ControlledProvider()
        provider.fileHandler = { _ in }
        provider.dataHandler = { completion in completion(data, nil) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)

        model.begin(items: [provider])
        await waitUntil("data fallback success") { model.phase == .done }

        XCTAssertEqual(runner.convertCalls, 1)
        XCTAssertTrue(shareDirectories().isEmpty)
    }

    func testReadTimeoutFailsWithoutInfiniteWait() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { _ in }
        provider.dataHandler = { _ in }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.02,
                               readTimeout: 0.15)

        model.begin(items: [provider])
        await waitUntil("read timeout") { model.phase == .failed }

        XCTAssertEqual(model.diagnosticCode, "E_SHARE_READ_TIMEOUT")
        XCTAssertTrue(model.canRetry)
        XCTAssertEqual(runner.convertCalls, 0)
    }

    func testRetryAfterReadFailureUsesRetainedProvider() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(nil, NSError(domain: "test", code: 1)) }
        provider.dataHandler = { completion in completion(nil, NSError(domain: "test", code: 2)) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 0.5)

        model.begin(items: [provider])
        await waitUntil("first failure") { model.phase == .failed }
        XCTAssertTrue(model.canRetry)

        provider.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        model.retry()
        await waitUntil("retry success") { model.phase == .done }

        XCTAssertEqual(runner.convertCalls, 1)
    }

    // MARK: Conversion failures

    func testAlreadyEnhancedShareDoesNotConvert() async throws {
        let inspection = HEICInspection(container: .heic, hasPrimaryGrid: true, hasStyleMetadata: true, hasTextureStyle: true)
        let verdict = CompatibilityVerdict(status: .alreadyEnhanced, issues: [.alreadyHasTexture], inspection: inspection)
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        let runner = FakeShareRunner(inspect: { _ in
            InspectionOutcome(inspection: inspection, verdict: verdict, byteCount: inspection.fileByteCount)
        }, convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)

        model.begin(items: [provider])
        await waitUntil("already enhanced failure") { model.phase == .failed }

        XCTAssertEqual(model.title, verdict.headline)
        XCTAssertFalse(model.canRetry)
        XCTAssertEqual(runner.convertCalls, 0)
    }

    func testQuotaExhaustedFailsWithoutRetry() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in throw ConversionFailure.quota(.exhausted(limit: 5)) })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)

        model.begin(items: [provider])
        await waitUntil("quota failure") { model.phase == .failed }

        XCTAssertEqual(model.title, "今日免费额度已用完")
        XCTAssertEqual(model.diagnosticCode, "E_QUOTA_EXHAUSTED")
        XCTAssertFalse(model.canRetry)
        XCTAssertNotNil(model.failureHint)
    }

    func testPhotoLibraryPermissionDeniedIsRecoverable() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in throw PhotoLibraryError.addPermissionDenied })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)

        model.begin(items: [provider])
        await waitUntil("permission failure") { model.phase == .failed }

        XCTAssertEqual(model.title, "没有相册写入权限")
        XCTAssertTrue(model.canRetry)
    }

    func testCorruptedHEICMapsToUnsupportedMessage() async throws {
        let provider = ControlledProvider()
        provider.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        let runner = FakeShareRunner(inspect: { _ in throw ConversionFailure.corrupted("bad box") },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 0.05,
                               readTimeout: 1)

        model.begin(items: [provider])
        await waitUntil("corrupt failure") { model.phase == .failed }

        XCTAssertEqual(model.title, "这不是可处理的 HEIC 原片")
        XCTAssertFalse(model.canRetry)
        XCTAssertEqual(runner.convertCalls, 0)
    }

    func testSecondBeginSupersedesFirstRead() async throws {
        let stale = ControlledProvider()
        stale.fileHandler = { _ in }
        stale.dataHandler = { _ in }
        let fresh = ControlledProvider()
        fresh.fileHandler = { completion in completion(try? Self.fixtureURL(), nil) }
        let runner = FakeShareRunner(inspect: { _ in Self.readyOutcome() },
                                     convert: { _, _ in ShareConversionResult(savedAssetIdentifier: "asset-1") })
        let model = ShareModel(service: runner,
                               temporaryDirectory: temporaryRoot,
                               fallbackDelay: 5,
                               readTimeout: 5)

        model.begin(items: [stale])
        await waitUntil("first begin") { model.phase == .reading }
        model.begin(items: [fresh])
        await waitUntil("second begin success") { model.phase == .done }

        XCTAssertEqual(runner.convertCalls, 1)
    }
}

// MARK: - Controlled provider

private final class ControlledProvider: ShareItemProviding {
    let registeredTypeIdentifiers = [UTType.heic.identifier]
    var suggestedName: String? = "IMG_5296.HEIC"
    var fileHandler: (@Sendable (@escaping @Sendable (URL?, Error?) -> Void) -> Void)?
    var dataHandler: (@Sendable (@escaping @Sendable (Data?, Error?) -> Void) -> Void)?

    func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        UTType(typeIdentifier)?.conforms(to: .image) == true
            || typeIdentifier == UTType.fileURL.identifier
    }

    @discardableResult
    func loadFileRepresentation(forTypeIdentifier typeIdentifier: String,
                                completionHandler: @escaping @Sendable (URL?, Error?) -> Void) -> Progress {
        fileHandler?(completionHandler)
        return Progress()
    }

    @discardableResult
    func loadDataRepresentation(forTypeIdentifier typeIdentifier: String,
                                completionHandler: @escaping @Sendable (Data?, Error?) -> Void) -> Progress {
        dataHandler?(completionHandler)
        return Progress()
    }
}

// MARK: - Controlled conversion runner

private final class FakeShareRunner: ShareConversionRunning, @unchecked Sendable {
    private let inspectHandler: @Sendable (URL) async throws -> InspectionOutcome
    private let convertHandler: @Sendable (URL, @escaping @Sendable (ConversionStage) -> Void) async throws -> ShareConversionResult
    private(set) var convertCalls = 0

    init(inspect: @escaping @Sendable (URL) async throws -> InspectionOutcome,
         convert: @escaping @Sendable (URL, @escaping @Sendable (ConversionStage) -> Void) async throws -> ShareConversionResult) {
        inspectHandler = inspect
        convertHandler = convert
    }

    func inspect(fileURL: URL, traits: AssetTraits) async throws -> InspectionOutcome {
        try await inspectHandler(fileURL)
    }

    func convert(fileURL: URL,
                 traits: AssetTraits,
                 preferredName: String,
                 onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> ShareConversionResult {
        convertCalls += 1
        return try await convertHandler(fileURL, onStage)
    }
}