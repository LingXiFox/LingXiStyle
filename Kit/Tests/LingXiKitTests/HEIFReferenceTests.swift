import XCTest
@testable import LingXiKit

final class HEIFReferenceTests: XCTestCase {
    func testParsesIrefChildBoxesWith16BitIDs() throws {
        let graph = try HEIFGraphParser.parse(fixture(irefVersion: 0))
        XCTAssertEqual(graph.references.count, 1)
        XCTAssertEqual(graph.references[0].type, "dimg")
        XCTAssertEqual(graph.references[0].from, 1)
        XCTAssertEqual(graph.references[0].to, [2, 3])
        XCTAssertEqual(graph.primaryTiles, [2, 3])
    }

    func testParsesIrefChildBoxesWith32BitIDs() throws {
        let graph = try HEIFGraphParser.parse(fixture(irefVersion: 1))
        XCTAssertEqual(graph.references.count, 1)
        XCTAssertEqual(graph.references[0].type, "dimg")
        XCTAssertEqual(graph.references[0].from, 1)
        XCTAssertEqual(graph.references[0].to, [2, 3])
        XCTAssertEqual(graph.primaryTiles, [2, 3])
    }

    func testMalformedIrefEntryDoesNotCrash() throws {
        var data = fixture(irefVersion: 0)
        // Break the dimg child size so the parser cannot walk past it.
        let iref = try ISOBoxParser.boxes(in: data).first { $0.type == "meta" }!
        let children = try ISOBoxParser.children(of: iref, in: data, skip: 4)
        let irefBox = children.first { $0.type == "iref" }!
        data.replaceSubrange(irefBox.payloadStart + 4..<irefBox.payloadStart + 8,
                             with: [0xFF, 0xFF, 0xFF, 0xFF])
        let graph = try HEIFGraphParser.parse(data)
        XCTAssertTrue(graph.references.isEmpty)
        XCTAssertFalse(graph.warnings.isEmpty)
    }

    private func fixture(irefVersion: Int) -> Data {
        var ftypPayload = Data("heic".utf8)
        ftypPayload.append(contentsOf: [0, 0, 0, 0])
        ftypPayload.append(Data("mif1".utf8))
        let ftyp = box("ftyp", ftypPayload)

        let pitm = fullBox("pitm", version: 0, payload: uint16(1))
        let infe = fullBox("infe", version: 2, payload: uint16(1) + uint16(0) + Data("hvc1".utf8) + Data([0]))
        let iinf = fullBox("iinf", version: 0, payload: uint16(1) + infe)

        var refPayload = Data()
        if irefVersion == 0 {
            refPayload.append(uint16(1))
            refPayload.append(uint16(2))
            refPayload.append(uint16(2))
            refPayload.append(uint16(3))
        } else {
            refPayload.append(uint32(1))
            refPayload.append(uint16(2))
            refPayload.append(uint32(2))
            refPayload.append(uint32(3))
        }
        let irefChild = box("dimg", refPayload)
        let iref = fullBox("iref", version: UInt8(irefVersion), payload: irefChild)

        let meta = fullBox("meta", version: 0, payload: pitm + iinf + iref)
        return ftyp + meta
    }

    private func box(_ type: String, _ payload: Data) -> Data {
        var data = uint32(UInt32(8 + payload.count))
        data.append(Data(type.utf8))
        data.append(payload)
        return data
    }

    private func fullBox(_ type: String, version: UInt8, payload: Data) -> Data {
        box(type, Data([version, 0, 0, 0]) + payload)
    }

    private func uint16(_ value: UInt16) -> Data {
        var value = value.bigEndian
        return Data(bytes: &value, count: 2)
    }

    private func uint32(_ value: UInt32) -> Data {
        var value = value.bigEndian
        return Data(bytes: &value, count: 4)
    }
}
