import XCTest
@testable import LingXiKit

final class CompatibilityTests: XCTestCase {
    private func inspection(container: ImageContainerKind = .heic,
                            hasTextureStyle: Bool = false) -> HEICInspection {
        HEICInspection(container: container,
                       hasPrimaryGrid: true,
                       hasStyleMetadata: true,
                       hasTextureStyle: hasTextureStyle,
                       supportsGraftLayout: true)
    }

    func testCompleteHEICIsReady() {
        let verdict = CompatibilityEvaluator.evaluate(inspection())
        XCTAssertEqual(verdict.status, .ready)
        XCTAssertTrue(verdict.issues.isEmpty)
    }

    func testEditedAssetIsAllowedWithWarningLeftToUI() {
        let verdict = CompatibilityEvaluator.evaluate(inspection(), traits: AssetTraits(isEdited: true))
        XCTAssertEqual(verdict.status, .ready)
        XCTAssertTrue(verdict.issues.isEmpty)
    }

    func testLivePhotoIsUnsupported() {
        let verdict = CompatibilityEvaluator.evaluate(inspection(), traits: AssetTraits(isLivePhoto: true))
        XCTAssertEqual(verdict.status, .unsupported)
        XCTAssertEqual(verdict.issues, [.livePhoto])
    }

    func testAlreadyTexturedIsNotReprocessed() {
        let verdict = CompatibilityEvaluator.evaluate(inspection(hasTextureStyle: true))
        XCTAssertEqual(verdict.status, .alreadyEnhanced)
        XCTAssertEqual(verdict.issues, [.alreadyHasTexture])
    }

    func testNonHEIFReportsOnlyTheContainerProblem() {
        let verdict = CompatibilityEvaluator.evaluate(inspection(container: .jpeg),
                                                      traits: AssetTraits(originalIsHEIC: false))
        XCTAssertEqual(verdict.status, .unsupported)
        XCTAssertEqual(verdict.issues, [.notHEIC])
    }
}
