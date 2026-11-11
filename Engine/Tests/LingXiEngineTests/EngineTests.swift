import XCTest
@testable import LingXiEngine
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

    // MARK: Live Photo

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LingXiEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Engine
            .deletingLastPathComponent()   // repo
    }

    private struct LivePhotoFixture {
        let still: URL
        let video: URL
    }

    private func fixture() throws -> LivePhotoFixture {
        let directory = repoRoot
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("Test Photo", isDirectory: true)
            .appendingPathComponent("Live Photo", isDirectory: true)
        let still = directory.appendingPathComponent("IMG_5963.HEIC")
        let video = directory.appendingPathComponent("IMG_5963.MOV")
        guard FileManager.default.fileExists(atPath: still.path),
              FileManager.default.fileExists(atPath: video.path) else {
            throw XCTSkip("Live Photo fixture is not available in docs/Test Photo")
        }
        return LivePhotoFixture(still: still, video: video)
    }

    private func outputDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LivePhotoEngine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testStillOnlyKeepsMovieBytesUntouched() async throws {
        let fixture = try fixture()
        let directory = try outputDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalMovie = try Data(contentsOf: fixture.video)

        var stages: [ConversionStage] = []
        let output = try await ConversionEngine().convertLivePhoto(
            LivePhotoRequest(stillURL: fixture.still,
                             videoURL: fixture.video,
                             mode: .stillOnly,
                             outputDirectory: directory),
            onStage: { stage in stages.append(stage) })

        XCTAssertEqual(output.livePhotoMode, .stillOnly)
        XCTAssertTrue(output.integrity.passed)
        XCTAssertEqual(output.videoFrameCount, 53, "the sample table count must survive the copy")
        XCTAssertEqual(output.videoByteCount, originalMovie.count)

        let movieURL = try XCTUnwrap(output.pairedVideoURL)
        XCTAssertEqual(try Data(contentsOf: movieURL), originalMovie, "still-only must not touch the movie")
        XCTAssertFalse(stages.contains(.processingFrames), "the still-only pipeline never renders frames")
        XCTAssertTrue(try Data(contentsOf: output.outputURL).count > 0)
    }

    func testFullModeAddsTextureTrackAndKeepsFrameCount() async throws {
        let fixture = try fixture()
        let directory = try outputDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalMovie = try Data(contentsOf: fixture.video)

        var stages: [ConversionStage] = []
        let output = try await ConversionEngine().convertLivePhoto(
            LivePhotoRequest(stillURL: fixture.still,
                             videoURL: fixture.video,
                             mode: .full,
                             outputDirectory: directory),
            onStage: { stage in stages.append(stage) })

        XCTAssertEqual(output.livePhotoMode, .full)
        XCTAssertTrue(output.integrity.passed)
        XCTAssertEqual(output.videoFrameCount, 53, "frames must not be dropped or duplicated")
        XCTAssertTrue(stages.contains(.processingFrames))
        XCTAssertTrue(stages.firstIndex(of: .processingFrames)! < stages.firstIndex(of: .verifying)!)

        let movieURL = try XCTUnwrap(output.pairedVideoURL)
        let movie = try Data(contentsOf: movieURL)
        XCTAssertGreaterThan(movie.count, originalMovie.count, "the extra style track has to be written")
        // The original bytes stay at the front: mdat untouched, moov rebuilt with one more track.
        let prefix = originalMovie.prefix(min(1024, originalMovie.count))
        XCTAssertEqual(movie.prefix(prefix.count), prefix)
    }

    func testLivePhotoKeepsContentIdentifierAcrossModes() async throws {
        let fixture = try fixture()
        let stillData = try Data(contentsOf: fixture.still)
        // The movie carries exactly the pairing identifier; the still may contain other UUIDs.
        let uuid = try XCTUnwrap(ContentIdentifierScanner.uuids(in: try Data(contentsOf: fixture.video)).first)
        XCTAssertTrue(ContentIdentifierScanner.uuids(in: stillData).contains(uuid))

        for mode in [LivePhotoProcessingMode.stillOnly, .full] {
            let directory = try outputDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = try await ConversionEngine().convertLivePhoto(
                LivePhotoRequest(stillURL: fixture.still,
                                 videoURL: fixture.video,
                                 mode: mode,
                                 outputDirectory: directory))
            let movieURL = try XCTUnwrap(output.pairedVideoURL)
            let movie = try Data(contentsOf: movieURL)
            XCTAssertTrue(ContentIdentifierScanner.uuids(in: movie).contains(uuid),
                          "\(mode.rawValue) must keep the pairing identifier")
            XCTAssertTrue(ContentIdentifierScanner.uuids(in: try Data(contentsOf: output.outputURL)).contains(uuid))
        }
    }
}
