import Foundation

/// A parsed ISO-BMFF box header. Offsets are absolute within the file.
public struct ISOBox: Sendable, Equatable {
    public let type: String
    public let offset: Int
    public let headerSize: Int
    public let size: Int

    public var payloadStart: Int { offset + headerSize }
    public var payloadEnd: Int { offset + size }
    public var payloadLength: Int { max(0, size - headerSize) }
}

public enum ISOBoxError: Error, Equatable, CustomStringConvertible {
    case truncated(offset: Int)
    case invalidSize(offset: Int)

    public var description: String {
        switch self {
        case .truncated(let offset): return "truncated box at \(offset)"
        case .invalidSize(let offset): return "invalid box size at \(offset)"
        }
    }
}

public enum ISOBoxParser {
    /// Parses the sibling boxes in `range`. A trailing fragment shorter than a box header is
    /// ignored, as ISO-BMFF files may be padded.
    public static func boxes(in data: Data, range: Range<Int>? = nil) throws -> [ISOBox] {
        let lower = range?.lowerBound ?? 0
        let upper = range?.upperBound ?? data.count
        guard lower >= 0, upper <= data.count, lower <= upper else { throw ISOBoxError.invalidSize(offset: lower) }
        var boxes: [ISOBox] = []
        var cursor = lower
        while cursor + 8 <= upper {
            let size32 = Int(readUInt32(data, cursor))
            let type = fourCC(data, cursor + 4)
            var headerSize = 8
            var size = size32
            if size32 == 1 {
                guard cursor + 16 <= upper else { throw ISOBoxError.truncated(offset: cursor) }
                size = Int(readUInt64(data, cursor + 8))
                headerSize = 16
            } else if size32 == 0 {
                size = upper - cursor
            }
            guard size >= headerSize, cursor + size <= upper else { throw ISOBoxError.invalidSize(offset: cursor) }
            boxes.append(ISOBox(type: type, offset: cursor, headerSize: headerSize, size: size))
            cursor += size
        }
        return boxes
    }

    /// Children of a container box, starting after `skip` bytes of box-specific header.
    public static func children(of box: ISOBox, in data: Data, skip: Int) throws -> [ISOBox] {
        let start = box.payloadStart + skip
        guard start <= box.payloadEnd else { throw ISOBoxError.invalidSize(offset: box.offset) }
        return try boxes(in: data, range: start..<box.payloadEnd)
    }
}

// MARK: - Primitive readers

func readUInt(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<count { value = (value << 8) | UInt64(data[data.startIndex + offset + index]) }
    return value
}

func readUInt32(_ data: Data, _ offset: Int) -> UInt32 { UInt32(truncatingIfNeeded: readUInt(data, offset, 4)) }

func readUInt64(_ data: Data, _ offset: Int) -> UInt64 { readUInt(data, offset, 8) }

func fourCC(_ data: Data, _ offset: Int) -> String {
    let start = data.startIndex + offset
    guard start + 4 <= data.endIndex else { return "????" }
    return String(decoding: data[start..<start + 4], as: UTF8.self)
}

/// Reads a NUL-terminated UTF-8 string starting at `offset`, limited by `end`.
func readCString(_ data: Data, _ offset: Int, _ end: Int) -> (String, Int) {
    var cursor = offset
    while cursor < end, data[data.startIndex + cursor] != 0 { cursor += 1 }
    let text = String(decoding: data[data.startIndex + offset..<data.startIndex + cursor], as: UTF8.self)
    return (text, min(cursor + 1, end))
}
