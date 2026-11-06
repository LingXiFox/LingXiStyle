import XCTest
import LingXiEngine
import LingXiKit

final class EngineTests: XCTestCase {
    func testRejectsNonHEIF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = ConversionEngine()
        XCTAssertThrowsError(try engine.convert(fileURL: url)) { error in
            guard let failure = error as? ConversionFailure else { return XCTFail("wrong error") }
            XCTAssertEqual(failure.diagnosticCode, "E_UNSUPPORTED:notHEIC")
        }
        let verdict = engine.quickCheck(fileURL: url)
        XCTAssertEqual(verdict?.status, .unsupported)
    }

    func testOutputNameIsStable() {
        let engine = ConversionEngine()
        let input = URL(fileURLWithPath: "/tmp/IMG_0001.HEIC")
        XCTAssertEqual(engine.outputName(for: input), "IMG_0001_TextureGrain.heic")
        let again = URL(fileURLWithPath: "/tmp/IMG_0001_TextureGrain.heic")
        XCTAssertEqual(engine.outputName(for: again), "IMG_0001_TextureGrain.heic")
    }
}
