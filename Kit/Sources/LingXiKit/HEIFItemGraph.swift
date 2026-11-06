import Foundation

public enum HEIFParseError: Error, Equatable, CustomStringConvertible {
    case notISOBaseMedia
    case missingMeta
    case missingPrimaryItem
    case malformed(String)

    public var description: String {
        switch self {
        case .notISOBaseMedia: return "not an ISO base media file"
        case .missingMeta: return "missing meta box"
        case .missingPrimaryItem: return "missing primary item"
        case .malformed(let detail): return "malformed HEIF: \(detail)"
        }
    }
}

/// One property box from `ipco`, addressed by its 1-based index.
struct HEIFProperty {
    let type: String
    let width: Int?
    let height: Int?
    let rotationQuarterTurns: Int?
    let auxiliaryType: String?

    init(box: ISOBox, in data: Data) {
        type = box.type
        var width: Int?
        var height: Int?
        var rotation: Int?
        var auxiliary: String?
        switch box.type {
        case "ispe":
            if box.payloadLength >= 12 {
                width = Int(readUInt32(data, box.payloadStart + 4))
                height = Int(readUInt32(data, box.payloadStart + 8))
            }
        case "irot":
            if box.payloadLength >= 1 { rotation = Int(data[data.startIndex + box.payloadStart] & 0x03) }
        case "auxC":
            if box.payloadLength >= 5 {
                let (uri, _) = readCString(data, box.payloadStart + 4, box.payloadEnd)
                auxiliary = uri
            }
        default:
            break
        }
        self.width = width
        self.height = height
        rotationQuarterTurns = rotation
        auxiliaryType = auxiliary
    }
}

struct HEIFItemRecord {
    let id: Int
    let type: String
    let name: String
    let contentType: String?
    let uri: String?
    var properties: [HEIFProperty] = []
    var extents: [Range<Int>] = []

    var byteCount: Int { extents.reduce(0) { $0 + $1.count } }
    var width: Int? { properties.compactMap(\.width).first }
    var height: Int? { properties.compactMap(\.height).first }
    var rotationQuarterTurns: Int? { properties.compactMap(\.rotationQuarterTurns).first }
    var auxiliaryType: String? { properties.compactMap(\.auxiliaryType).first }
}

struct HEIFReference {
    let type: String
    let from: Int
    let to: [Int]
}

struct ILOClayout: Equatable {
    let version: Int
    let offsetSize: Int
    let lengthSize: Int
    let baseOffsetSize: Int
    let indexSize: Int

    /// StylePortCore's addTexture path only supports this exact layout.
    var isSupportedByGraft: Bool {
        version == 1 && offsetSize == 4 && lengthSize == 4 && baseOffsetSize == 0 && indexSize == 0
    }
}

struct HEIFGraph {
    let brands: [String]
    let primaryItemID: Int
    let items: [Int: HEIFItemRecord]
    let references: [HEIFReference]
    let iloc: ILOClayout
    /// Structural problems that are worth surfacing but do not prevent parsing.
    let warnings: [String]

    func tiles(of id: Int) -> [Int] { references.first { $0.type == "dimg" && $0.from == id }?.to ?? [] }
    func references(ofType type: String, to id: Int) -> [Int] {
        references.filter { $0.type == type && $0.to.contains(id) }.map(\.from)
    }

    var primaryItem: HEIFItemRecord? { items[primaryItemID] }
    var primaryTiles: [Int] { tiles(of: primaryItemID) }
    var thumbnailItem: Int? { references.first { $0.type == "thmb" }?.from }
    var hdrGainMapItem: Int? {
        items.values.first { $0.auxiliaryType == HEICInspector.hdrGainMapURI }?.id
    }
    var linearThumbnailItem: Int? {
        items.values.first { $0.auxiliaryType == HEICInspector.linearThumbnailURI }?.id
    }
    var styleItem: Int? {
        items.values.first { $0.type == "uri " && $0.uri == HEICInspector.stylesURI }?.id
    }
    var textureStyleItem: Int? {
        items.values.first { $0.uri == HEICInspector.textureStylesURI }?.id
    }
    var exifItem: Int? { items.values.first { $0.type == "Exif" }?.id }
}

enum HEIFGraphParser {
    static func parse(_ data: Data) throws -> HEIFGraph {
        let top = try ISOBoxParser.boxes(in: data)
        guard let ftyp = top.first(where: { $0.type == "ftyp" }) else { throw HEIFParseError.notISOBaseMedia }
        var brands = [fourCC(data, ftyp.payloadStart)]
        var cursor = ftyp.payloadStart + 8
        while cursor + 4 <= ftyp.payloadEnd {
            brands.append(fourCC(data, cursor))
            cursor += 4
        }
        guard let meta = top.first(where: { $0.type == "meta" }) else { throw HEIFParseError.missingMeta }
        let children = try ISOBoxParser.children(of: meta, in: data, skip: 4)
        var warnings: [String] = []

        guard let pitm = children.first(where: { $0.type == "pitm" }) else {
            throw HEIFParseError.missingPrimaryItem
        }
        let pitmVersion = data[data.startIndex + pitm.payloadStart]
        let primaryItemID = pitmVersion == 0
            ? Int(readUInt(data, pitm.payloadStart + 4, 2))
            : Int(readUInt(data, pitm.payloadStart + 4, 4))

        var infos: [Int: HEIFItemRecord] = [:]
        if let iinf = children.first(where: { $0.type == "iinf" }) {
            let version = data[data.startIndex + iinf.payloadStart]
            let countOffset = iinf.payloadStart + 4
            var entry = countOffset + (version == 0 ? 2 : 4)
            while entry + 4 <= iinf.payloadEnd {
                let entrySize = Int(readUInt32(data, entry))
                guard entrySize >= 8, entry + entrySize <= iinf.payloadEnd else { break }
                if fourCC(data, entry + 4) == "infe", let info = parseInfe(data, offset: entry, size: entrySize) {
                    infos[info.id] = info
                }
                entry += entrySize
            }
        } else {
            throw HEIFParseError.malformed("missing iinf")
        }

        var references: [HEIFReference] = []
        if let iref = children.first(where: { $0.type == "iref" }) {
            let version = data[data.startIndex + iref.payloadStart]
            let wide = version >= 1
            let idSize = wide ? 4 : 2
            // iref is a FullBox containing ordinary child boxes. Each child has its own
            // size/type header, so the reference payload starts eight bytes in.
            var entry = iref.payloadStart + 4
            while entry + 8 <= iref.payloadEnd {
                let entrySize = Int(readUInt32(data, entry))
                guard entrySize >= 8, entry + entrySize <= iref.payloadEnd else {
                    warnings.append("malformed iref entry at \(entry)")
                    break
                }
                let type = fourCC(data, entry + 4)
                let load = entry + 8
                guard load + idSize + 2 <= entry + entrySize else {
                    warnings.append("malformed iref entry for \(type)")
                    break
                }
                let from = Int(readUInt(data, load, idSize))
                let count = Int(readUInt(data, load + idSize, 2))
                let toStart = load + idSize + 2
                let toEnd = toStart + count * idSize
                guard toEnd <= entry + entrySize else {
                    warnings.append("malformed iref target list for \(type)")
                    break
                }
                var to: [Int] = []
                to.reserveCapacity(count)
                var ref = toStart
                for _ in 0..<count {
                    to.append(Int(readUInt(data, ref, idSize)))
                    ref += idSize
                }
                references.append(HEIFReference(type: type, from: from, to: to))
                entry += entrySize
            }
        }

        var properties: [HEIFProperty] = []
        var associations: [Int: [(index: Int, essential: Bool)]] = [:]
        if let iprp = children.first(where: { $0.type == "iprp" }) {
            let iprpChildren = try ISOBoxParser.children(of: iprp, in: data, skip: 0)
            if let ipco = iprpChildren.first(where: { $0.type == "ipco" }) {
                properties = try ISOBoxParser.children(of: ipco, in: data, skip: 0).map { HEIFProperty(box: $0, in: data) }
            }
            if let ipma = iprpChildren.first(where: { $0.type == "ipma" }) {
                associations = parseIpma(data, box: ipma)
            }
        }
        for (itemID, list) in associations {
            guard var record = infos[itemID] else { continue }
            record.properties = list.compactMap { property in
                guard property.index >= 1, property.index <= properties.count else { return nil }
                return properties[property.index - 1]
            }
            infos[itemID] = record
        }

        let iloc = parsedIloc(children.first { $0.type == "iloc" }.map { (box: $0, data: data) })
        let layout = iloc.layout
        let idat = children.first(where: { $0.type == "idat" })
        for (itemID, extents) in iloc.extents {
            guard var record = infos[itemID] else { continue }
            record.extents = extents.compactMap { extent -> Range<Int>? in
                let base: Int
                switch extent.constructionMethod {
                case 0: base = extent.offset
                case 1:
                    guard let idat else { return nil }
                    base = idat.payloadStart + extent.offset
                default: return nil
                }
                guard base >= 0, extent.length >= 0, base + extent.length <= data.count else {
                    warnings.append("extent out of bounds for item \(itemID)")
                    return nil
                }
                return base..<(base + extent.length)
            }
            infos[itemID] = record
        }

        return HEIFGraph(brands: brands, primaryItemID: primaryItemID, items: infos,
                         references: references, iloc: layout, warnings: warnings)
    }

    private static func parseInfe(_ data: Data, offset: Int, size: Int) -> HEIFItemRecord? {
        let version = data[data.startIndex + offset + 8]
        let payload = offset + 12
        let end = offset + size
        var cursor = payload
        let id: Int
        var type = ""
        var name = ""
        var contentType: String?
        var uri: String?
        if version >= 2 {
            id = Int(readUInt(data, cursor, version == 2 ? 2 : 4))
            cursor += version == 2 ? 2 : 4
            cursor += 2 // protection index
            type = fourCC(data, cursor)
            cursor += 4
            (name, cursor) = readCString(data, cursor, end)
            if type == "mime" {
                (contentType, cursor) = readCString(data, cursor, end)
            } else if type == "uri " {
                (uri, cursor) = readCString(data, cursor, end)
            }
        } else {
            id = Int(readUInt(data, cursor, 2))
            cursor += 4
            (name, _) = readCString(data, cursor, end)
        }
        return HEIFItemRecord(id: id, type: type, name: name, contentType: contentType, uri: uri)
    }

    private static func parseIpma(_ data: Data, box: ISOBox) -> [Int: [(index: Int, essential: Bool)]] {
        let version = data[data.startIndex + box.payloadStart]
        let flags = readUInt(data, box.payloadStart + 1, 3)
        let wideIndex = flags & 1 == 1
        var cursor = box.payloadStart + 4
        let entryCount = Int(readUInt32(data, cursor))
        cursor += 4
        var result: [Int: [(index: Int, essential: Bool)]] = [:]
        for _ in 0..<entryCount {
            guard cursor < box.payloadEnd else { break }
            let itemID = Int(readUInt(data, cursor, version < 1 ? 2 : 4))
            cursor += version < 1 ? 2 : 4
            guard cursor < box.payloadEnd else { break }
            let count = Int(data[data.startIndex + cursor])
            cursor += 1
            var list: [(index: Int, essential: Bool)] = []
            for _ in 0..<count {
                guard cursor + (wideIndex ? 2 : 1) <= box.payloadEnd else { break }
                if wideIndex {
                    let value = Int(readUInt(data, cursor, 2))
                    list.append((value & 0x7FFF, (value & 0x8000) != 0))
                } else {
                    let value = Int(data[data.startIndex + cursor])
                    list.append((value & 0x7F, (value & 0x80) != 0))
                }
                cursor += wideIndex ? 2 : 1
            }
            result[itemID] = list
        }
        return result
    }

    private struct Extent {
        let constructionMethod: Int
        let offset: Int
        let length: Int
    }

    private static func parsedIloc(_ input: (box: ISOBox, data: Data)?) -> (layout: ILOClayout, extents: [Int: [Extent]]) {
        guard let input else {
            return (ILOClayout(version: 0, offsetSize: 0, lengthSize: 0, baseOffsetSize: 0, indexSize: 0), [:])
        }
        let data = input.data
        let box = input.box
        let version = Int(data[data.startIndex + box.payloadStart])
        let sizes = readUInt(data, box.payloadStart + 4, 2)
        let offsetSize = Int(sizes >> 12)
        let lengthSize = Int((sizes >> 8) & 0xF)
        let baseOffsetSize = Int((sizes >> 4) & 0xF)
        let indexSize = (version == 1 || version == 2) ? Int(sizes & 0xF) : 0
        var cursor = box.payloadStart + 6
        let count = Int(readUInt(data, cursor, version < 2 ? 2 : 4))
        cursor += version < 2 ? 2 : 4
        var extents: [Int: [Extent]] = [:]
        for _ in 0..<count {
            guard cursor < box.payloadEnd else { break }
            let itemID = Int(readUInt(data, cursor, version < 2 ? 2 : 4))
            cursor += version < 2 ? 2 : 4
            var constructionMethod = 0
            if version == 1 || version == 2 {
                constructionMethod = Int(readUInt(data, cursor, 2) & 0xF)
                cursor += 2
            }
            cursor += 2 // data reference index
            let baseOffset = Int(readUInt(data, cursor, baseOffsetSize))
            cursor += baseOffsetSize
            let extentCount = Int(readUInt(data, cursor, 2))
            cursor += 2
            var list: [Extent] = []
            for _ in 0..<extentCount {
                if (version == 1 || version == 2), indexSize > 0 { cursor += indexSize }
                let offset = Int(readUInt(data, cursor, offsetSize))
                cursor += offsetSize
                let length = Int(readUInt(data, cursor, lengthSize))
                cursor += lengthSize
                list.append(Extent(constructionMethod: constructionMethod, offset: baseOffset + offset, length: length))
            }
            extents[itemID] = list
        }
        return (ILOClayout(version: version, offsetSize: offsetSize, lengthSize: lengthSize, baseOffsetSize: baseOffsetSize, indexSize: indexSize), extents)
    }
}
