import XCTest
@testable import LingXiKit

final class LivePhotoModeTests: XCTestCase {
    func testDefaultModeIsStillOnly() {
        XCTAssertEqual(LivePhotoProcessingMode.defaultMode, .stillOnly)
        XCTAssertEqual(LivePhotoProcessingMode.allCases, [.stillOnly, .full])
    }

    func testModesCarryUserFacingCopy() {
        for mode in LivePhotoProcessingMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.detail.isEmpty)
            XCTAssertFalse(mode.shortDetail.isEmpty)
        }
        XCTAssertNotEqual(LivePhotoProcessingMode.stillOnly.title, LivePhotoProcessingMode.full.title)
    }

    func testQuotaNoteSaysOnePhotoEvenForFullMode() {
        XCTAssertTrue(LivePhotoProcessingMode.quotaNote.contains("1"), LivePhotoProcessingMode.quotaNote)
    }

    func testFullModePipelineAddsTheFrameStageOnce() {
        let full = ConversionStage.pipeline(livePhotoMode: .full)
        XCTAssertEqual(full.filter { $0 == .processingFrames }.count, 1)
        XCTAssertEqual(full.first, .readingOriginal)
        XCTAssertEqual(full.last, .saving)
        XCTAssertLessThan(full.firstIndex(of: .converting)!, full.firstIndex(of: .processingFrames)!)
        XCTAssertLessThan(full.firstIndex(of: .processingFrames)!, full.firstIndex(of: .verifying)!)
    }

    func testStillOnlyAndStillPipelinesHaveNoFrameStage() {
        XCTAssertFalse(ConversionStage.pipeline(livePhotoMode: .stillOnly).contains(.processingFrames))
        XCTAssertFalse(ConversionStage.pipeline(livePhotoMode: nil).contains(.processingFrames))
        XCTAssertFalse(ConversionStage.pipeline.contains(.processingFrames))
    }

    func testTraitsRequireTheMovieForLivePhotoModes() {
        XCTAssertFalse(AssetTraits(isLivePhoto: true, livePhotoVideoAvailable: false).canProcessLivePhoto)
        XCTAssertTrue(AssetTraits(isLivePhoto: true).canProcessLivePhoto)
        XCTAssertFalse(AssetTraits().canProcessLivePhoto)
    }
}
