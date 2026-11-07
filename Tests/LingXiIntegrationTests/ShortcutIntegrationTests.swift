import XCTest
import CryptoKit
import Photos
import UniformTypeIdentifiers
import AppIntents
@testable import LingXiKit
@testable import LingXiEngine
import LingXiServices

@MainActor
final class ShortcutIntegrationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiShortcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    // MARK: Fixtures and helpers

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: "IMG_5296", withExtension: "HEIC"))
    }

    private func fixtureData() throws -> Data {
        try Data(contentsOf: fixtureURL())
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func quotaManager() -> QuotaManager {
        QuotaManager(databaseURL: temporaryRoot.appendingPathComponent("quota.sqlite"))
    }

    private func input(_ data: Data, name: String = "IMG_5296.HEIC") -> IntentFile {
        IntentFile(data: data, filename: name, type: .heic)
    }

    // MARK: Real ConversionService through the shortcut orchestration

    func testSingleHEICReturnsValidHEICBytesAndConsumesOneSlot() async throws {
        let original = try fixtureData()
        let originalHash = sha256(original)
        let quota = quotaManager()
        let service = ConversionService(quotaManager: quota)

        let result = try await UnlockTextureIntent.run(photos: [input(original)],
                                                       saveToLibrary: false,
                                                       returnsFiles: true,
                                                       checkOnly: false,
                                                       service: service)

        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(result.converted, 1)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.dialog.contains("已转换 1 张"))

        let output = try XCTUnwrap(result.outputs.first)
        XCTAssertEqual(output.filename, "IMG_5296_TextureGrain.HEIC")
        let outputData = try XCTUnwrap(output.data)
        XCTAssertEqual(ImageContainerClassifier.classify(outputData), .heic)
        let inspection = try HEICInspector.inspect(outputData)
        XCTAssertEqual(inspection.pixelWidth, 8064)
        XCTAssertEqual(inspection.pixelHeight, 6048)
        XCTAssertGreaterThan(inspection.primaryTileCount, 1)

        XCTAssertEqual(try quota.status(isPro: false).remaining, 4)
        XCTAssertEqual(sha256(try fixtureData()), originalHash,
                       "the shortcut must never rewrite the supplied original")
    }

    func testTwoInputsWithTheSameNameBothProduceIndependentFiles() async throws {
        let data = try fixtureData()
        let quota = quotaManager()
        let service = ConversionService(quotaManager: quota)

        let result = try await UnlockTextureIntent.run(photos: [input(data), input(data)],
                                                       saveToLibrary: false,
                                                       returnsFiles: true,
                                                       checkOnly: false,
                                                       service: service)

        XCTAssertEqual(result.outputs.count, 2)
        XCTAssertEqual(result.converted, 2)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 3)
        for output in result.outputs {
            let bytes = try XCTUnwrap(output.data)
            XCTAssertEqual(ImageContainerClassifier.classify(bytes), .heic)
        }
    }

    func testCheckOnlyDoesNotConvertOrConsumeQuota() async throws {
        let quota = quotaManager()
        let service = ConversionService(quotaManager: quota)

        let result = try await UnlockTextureIntent.run(photos: [input(try fixtureData())],
                                                       saveToLibrary: false,
                                                       returnsFiles: false,
                                                       checkOnly: true,
                                                       service: service)

        XCTAssertEqual(result.ready, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.converted, 0)
        XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertTrue(result.dialog.contains("可处理 1 张"))
        XCTAssertEqual(try quota.status(isPro: false).remaining, 5)
    }

    func testSaveOnlyDoesNotReturnAFileButDoesSave() async throws {
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard readStatus == .authorized || readStatus == .limited else {
            throw XCTSkip("PhotoKit permission is not granted to the integration host.")
        }
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard addStatus == .authorized || addStatus == .limited else {
            throw XCTSkip("PhotoKit add-only permission is not granted to the integration host.")
        }

        let quota = quotaManager()
        let service = ConversionService(quotaManager: quota)
        let result = try await UnlockTextureIntent.run(photos: [input(try fixtureData())],
                                                       saveToLibrary: true,
                                                       returnsFiles: false,
                                                       checkOnly: false,
                                                       service: service)

        XCTAssertEqual(result.outputs.count, 0, "returnsFiles is off, so Shortcuts must not receive a file")
        XCTAssertEqual(result.savedToLibrary, 1)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 4)
        XCTAssertTrue(result.dialog.contains("1 张已存入相册"))
    }

    func testCorruptedInputIsSkippedWithoutConsumingQuota() async throws {
        let quota = quotaManager()
        let service = ConversionService(quotaManager: quota)
        let bad = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])

        let result = try await UnlockTextureIntent.run(photos: [input(bad, name: "broken.HEIC")],
                                                       saveToLibrary: false,
                                                       returnsFiles: true,
                                                       checkOnly: false,
                                                       service: service)

        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.skipped, 1, "an unreadable HEIC is incompatible, not a billed failure")
        XCTAssertEqual(result.converted, 0)
        XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 5,
                       "a skipped shortcut input must not consume a slot")
    }

    func testProShortcutDoesNotTouchTheFreeLedger() async throws {
        let quota = quotaManager()
        let service = ConversionService(entitlementProvider: ShortcutStubEntitlement(isPro: true),
                                        quotaManager: quota)

        let result = try await UnlockTextureIntent.run(photos: [input(try fixtureData())],
                                                       saveToLibrary: false,
                                                       returnsFiles: true,
                                                       checkOnly: false,
                                                       service: service)

        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(try quota.status(isPro: false).remaining, 5)
    }

    // MARK: Controlled failure paths

    func testQuotaExhaustionStopsTheBatchAndReportsUnprocessedInputs() async throws {
        let data = try fixtureData()
        let service = ShortcutControlledService(inspect: { _ in try Self.readyOutcome() },
                                                convert: { _, _ in throw ConversionFailure.quota(.exhausted(limit: 5)) })

        let result = try await UnlockTextureIntent.run(photos: [input(data, name: "a.HEIC"), input(data, name: "b.HEIC")],
                                                       saveToLibrary: false,
                                                       returnsFiles: true,
                                                       checkOnly: false,
                                                       service: service)

        XCTAssertEqual(result.converted, 0)
        XCTAssertEqual(result.unprocessed, 2)
        XCTAssertTrue(result.quotaExhausted)
        XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertTrue(result.dialog.contains("2 张因今日免费额度用完未处理"))
        XCTAssertEqual(service.convertCalls, 1, "the batch must stop at the first exhausted quota")
    }

    func testSkippedFileDoesNotConvert() async throws {
        let data = try fixtureData()
        let service = ShortcutControlledService(inspect: { _ in try Self.alreadyEnhancedOutcome() },
                                                convert: { _, _ in
                                                    XCTFail("an already enhanced input must not convert")
                                                    return ShortcutConversionOutcome(outputURL: nil)
                                                })

        let result = try await UnlockTextureIntent.run(photos: [input(data)],
                                                       saveToLibrary: false,
                                                       returnsFiles: true,
                                                       checkOnly: false,
                                                       service: service)

        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.converted, 0)
        XCTAssertEqual(service.convertCalls, 0)
        XCTAssertTrue(result.outputs.isEmpty)
    }

    func testMissingInputAndMissingOutputAreRejected() async throws {
        let service = ShortcutControlledService(inspect: { _ in try Self.readyOutcome() },
                                                convert: { _, _ in ShortcutConversionOutcome(outputURL: nil) })

        do {
            _ = try await UnlockTextureIntent.run(photos: [],
                                                  saveToLibrary: true,
                                                  returnsFiles: false,
                                                  checkOnly: false,
                                                  service: service)
            XCTFail("empty input must fail")
        } catch let error as UnlockTextureIntent.IntentError {
            XCTAssertEqual(error.errorDescription, "请先选择至少一张 HEIC 照片。")
        }

        do {
            _ = try await UnlockTextureIntent.run(photos: [input(try fixtureData())],
                                                  saveToLibrary: false,
                                                  returnsFiles: false,
                                                  checkOnly: false,
                                                  service: service)
            XCTFail("no visible output must fail")
        } catch let error as UnlockTextureIntent.IntentError {
            XCTAssertEqual(error.errorDescription, "请至少打开「保存到相册」或「返回转换后的文件」。")
        }
    }

    // MARK: Outcomes

    nonisolated private static func readyOutcome() throws -> InspectionOutcome {
        let bundle = Bundle(for: ShortcutIntegrationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "IMG_5296", withExtension: "HEIC"))
        let inspection = try HEICInspector.inspect(Data(contentsOf: url))
        return InspectionOutcome(inspection: inspection,
                                 verdict: CompatibilityVerdict(status: .ready, inspection: inspection),
                                 byteCount: inspection.fileByteCount)
    }

    nonisolated private static func alreadyEnhancedOutcome() throws -> InspectionOutcome {
        let inspection = HEICInspection(container: .heic,
                                        hasPrimaryGrid: true,
                                        hasStyleMetadata: true,
                                        hasTextureStyle: true)
        let verdict = CompatibilityVerdict(status: .alreadyEnhanced,
                                           issues: [.alreadyHasTexture],
                                           inspection: inspection)
        return InspectionOutcome(inspection: inspection, verdict: verdict, byteCount: inspection.fileByteCount)
    }
}

private struct ShortcutStubEntitlement: ProEntitlementProviding {
    let value: Bool
    init(isPro: Bool) { value = isPro }
    func isPro() async -> Bool { value }
}

private final class ShortcutControlledService: ShortcutConverting, @unchecked Sendable {
    private let inspectHandler: @Sendable (URL) throws -> InspectionOutcome
    private let convertHandler: @Sendable (ConversionService.Request,
                                            @escaping @Sendable (ConversionStage) -> Void) async throws -> ShortcutConversionOutcome
    private(set) var convertCalls = 0

    init(inspect: @escaping @Sendable (URL) throws -> InspectionOutcome,
         convert: @escaping @Sendable (ConversionService.Request,
                                        @escaping @Sendable (ConversionStage) -> Void) async throws -> ShortcutConversionOutcome) {
        inspectHandler = inspect
        convertHandler = convert
    }

    func inspectForShortcut(fileURL: URL, traits: AssetTraits) throws -> InspectionOutcome {
        try inspectHandler(fileURL)
    }

    func convertForShortcut(_ request: ConversionService.Request,
                            onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> ShortcutConversionOutcome {
        convertCalls += 1
        return try await convertHandler(request, onStage)
    }
}