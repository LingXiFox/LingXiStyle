import Foundation
import CryptoKit

public enum ImageContainerKind: String, Sendable, Equatable {
    case heic, heif, jpeg, png, tiff, dng, quickTime, unknown

    public var isHEIF: Bool { self == .heic || self == .heif }
}

/// A read-only snapshot of one HEIF file, produced without relying on StylePortCore so the app
/// can explain a photo before it touches it, and check the result afterwards.
public struct HEICInspection: Sendable, Equatable {
    public let fileByteCount: Int
    public let container: ImageContainerKind
    public let brands: [String]
    public let primaryItemID: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let rotationQuarterTurns: Int
    public let itemCount: Int
    public let primaryTileCount: Int
    public let hdrTileCount: Int
    public let hasPrimaryGrid: Bool
    public let hasStyleMetadata: Bool
    public let hasTextureStyle: Bool
    public let hasExif: Bool
    public let hasThumbnail: Bool
    public let hasHDRGainMap: Bool
    public let hasLinearThumbnail: Bool
    public let supportsGraftLayout: Bool
    public let ilocDescription: String
    public let warnings: [String]
    public let styleMetadataDigest: String?
    public let exifDigest: String?
    public let thumbnailDigest: String?
    public let primaryTileDigests: [String]
    public let hdrTileDigests: [String]

    public init(fileByteCount: Int = 0,
                container: ImageContainerKind = .heic,
                brands: [String] = ["heic"],
                primaryItemID: Int = 1,
                pixelWidth: Int = 0,
                pixelHeight: Int = 0,
                rotationQuarterTurns: Int = 0,
                itemCount: Int = 0,
                primaryTileCount: Int = 0,
                hdrTileCount: Int = 0,
                hasPrimaryGrid: Bool = false,
                hasStyleMetadata: Bool = false,
                hasTextureStyle: Bool = false,
                hasExif: Bool = false,
                hasThumbnail: Bool = false,
                hasHDRGainMap: Bool = false,
                hasLinearThumbnail: Bool = false,
                supportsGraftLayout: Bool = false,
                ilocDescription: String = "",
                warnings: [String] = [],
                styleMetadataDigest: String? = nil,
                exifDigest: String? = nil,
                thumbnailDigest: String? = nil,
                primaryTileDigests: [String] = [],
                hdrTileDigests: [String] = []) {
        self.fileByteCount = fileByteCount
        self.container = container
        self.brands = brands
        self.primaryItemID = primaryItemID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.rotationQuarterTurns = rotationQuarterTurns
        self.itemCount = itemCount
        self.primaryTileCount = primaryTileCount
        self.hdrTileCount = hdrTileCount
        self.hasPrimaryGrid = hasPrimaryGrid
        self.hasStyleMetadata = hasStyleMetadata
        self.hasTextureStyle = hasTextureStyle
        self.hasExif = hasExif
        self.hasThumbnail = hasThumbnail
        self.hasHDRGainMap = hasHDRGainMap
        self.hasLinearThumbnail = hasLinearThumbnail
        self.supportsGraftLayout = supportsGraftLayout
        self.ilocDescription = ilocDescription
        self.warnings = warnings
        self.styleMetadataDigest = styleMetadataDigest
        self.exifDigest = exifDigest
        self.thumbnailDigest = thumbnailDigest
        self.primaryTileDigests = primaryTileDigests
        self.hdrTileDigests = hdrTileDigests
    }

    public var pixelSizeDescription: String {
        pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth) × \(pixelHeight)" : "未知尺寸"
    }
}

public enum HEICInspector {
    public static let hdrGainMapURI = "urn:com:apple:photo:2020:aux:hdrgainmap"
    public static let linearThumbnailURI = "tag:apple.com,2023:photo:aux:linearthumbnail"
    public static let styleDeltaURI = "tag:apple.com,2023:photo:aux:styledeltamap"
    public static let stylesURI = "tag:apple.com,2023:photo:metadata:styles"
    public static let textureStylesURI = "tag:apple.com,2026:photo:metadata:texture_styles"

    /// - Parameter hashing: digests every payload so before/after comparisons are byte exact.
    ///   Disable for a fast compatibility check while browsing.
    public static func inspect(_ data: Data, hashing: Bool = true) throws -> HEICInspection {
        let container = ImageContainerClassifier.classify(data)
        guard container.isHEIF else {
            return HEICInspection(
                fileByteCount: data.count, container: container, brands: [], primaryItemID: 0,
                pixelWidth: 0, pixelHeight: 0, rotationQuarterTurns: 0, itemCount: 0,
                primaryTileCount: 0, hdrTileCount: 0, hasPrimaryGrid: false,
                hasStyleMetadata: false, hasTextureStyle: false, hasExif: false, hasThumbnail: false,
                hasHDRGainMap: false, hasLinearThumbnail: false, supportsGraftLayout: false,
                ilocDescription: "n/a", warnings: ["not a HEIF container"],
                styleMetadataDigest: nil, exifDigest: nil, thumbnailDigest: nil,
                primaryTileDigests: [], hdrTileDigests: [])
        }
        let graph = try HEIFGraphParser.parse(data)
        let primaryTiles = graph.primaryTiles
        let hdrItem = graph.hdrGainMapItem
        let hdrTiles = hdrItem.map { graph.tiles(of: $0) } ?? []
        let primary = graph.primaryItem
        let fallbackTile = primaryTiles.first.flatMap { graph.items[$0] }
        return HEICInspection(
            fileByteCount: data.count,
            container: container,
            brands: graph.brands,
            primaryItemID: graph.primaryItemID,
            pixelWidth: primary?.width ?? fallbackTile?.width ?? 0,
            pixelHeight: primary?.height ?? fallbackTile?.height ?? 0,
            rotationQuarterTurns: primary?.rotationQuarterTurns ?? 0,
            itemCount: graph.items.count,
            primaryTileCount: primaryTiles.count,
            hdrTileCount: hdrTiles.count,
            hasPrimaryGrid: !primaryTiles.isEmpty,
            hasStyleMetadata: graph.styleItem != nil,
            hasTextureStyle: graph.textureStyleItem != nil,
            hasExif: graph.exifItem != nil,
            hasThumbnail: graph.thumbnailItem != nil,
            hasHDRGainMap: hdrItem != nil,
            hasLinearThumbnail: graph.linearThumbnailItem != nil,
            supportsGraftLayout: graph.iloc.isSupportedByGraft,
            ilocDescription: "v\(graph.iloc.version) off\(graph.iloc.offsetSize) len\(graph.iloc.lengthSize) base\(graph.iloc.baseOffsetSize) idx\(graph.iloc.indexSize)",
            warnings: graph.warnings,
            styleMetadataDigest: hashing ? graph.styleItem.flatMap { digest(data, extents: graph.items[$0]?.extents ?? []) } : nil,
            exifDigest: hashing ? graph.exifItem.flatMap { digest(data, extents: graph.items[$0]?.extents ?? []) } : nil,
            thumbnailDigest: hashing ? graph.thumbnailItem.flatMap { digest(data, extents: graph.items[$0]?.extents ?? []) } : nil,
            primaryTileDigests: hashing ? primaryTiles.compactMap { digest(data, extents: graph.items[$0]?.extents ?? []) }.sorted() : [],
            hdrTileDigests: hashing ? hdrTiles.compactMap { digest(data, extents: graph.items[$0]?.extents ?? []) }.sorted() : [])
    }

    static func digest(_ data: Data, extents: [Range<Int>]) -> String? {
        guard !extents.isEmpty else { return nil }
        var hasher = SHA256()
        for extent in extents {
            guard extent.lowerBound >= 0, extent.upperBound <= data.count else { return nil }
            hasher.update(data: data[extent])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum ImageContainerClassifier {
    public static func classify(_ data: Data) -> ImageContainerKind {
        let head = [UInt8](data.prefix(32))
        if head.count >= 3, head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return .jpeg }
        if head.count >= 8, head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 { return .png }
        if head.count >= 4, head[0] == 0x49, head[1] == 0x49, head[2] == 0x2A, head[3] == 0x00 { return .tiff }
        if head.count >= 4, head[0] == 0x4D, head[1] == 0x4D, head[2] == 0x00, head[3] == 0x2A { return .tiff }
        guard head.count >= 12, String(decoding: head[4..<8], as: UTF8.self) == "ftyp" else { return .unknown }
        let brand = String(decoding: head[8..<12], as: UTF8.self)
        switch brand {
        case "heic", "heix", "hevx", "hevc", "heim", "heis", "hevm", "hevs", "mif1", "msf1":
            if brand == "mif1" || brand == "msf1" { return .heif }
            return .heic
        case "qt  ", "isom": return .quickTime
        case "dng ": return .dng
        case "avif", "avis": return .heif
        default: return .heif
        }
    }
}
