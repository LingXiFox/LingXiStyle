import XCTest
@testable import LingXiKit

final class ISOBoxTests: XCTestCase {
    func testParsesSiblingBoxes() throws {
        var data = Data()
        data.append(contentsOf: [0, 0, 0, 16])
        data.append(Data("ftyp".utf8))
        data.append(Data("heic".utf8))
        data.append(contentsOf: [0, 0, 0, 0])
        let boxes = try ISOBoxParser.boxes(in: data)
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes[0].type, "ftyp")
        XCTAssertEqual(boxes[0].payloadLength, 8)
    }

    func testIgnoresTrailingPadding() throws {
        var data = Data([0, 0, 0, 8])
        data.append(Data("free".utf8))
        data.append(contentsOf: [0, 0])
        XCTAssertEqual(try ISOBoxParser.boxes(in: data).count, 1)
    }
}
