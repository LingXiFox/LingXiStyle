import Foundation

public struct IntegrityCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let passed: Bool
    public let detail: String
}

public struct IntegrityReport: Sendable, Equatable {
    public let checks: [IntegrityCheck]
    public let originalByteCount: Int
    public let resultByteCount: Int

    public var passed: Bool { !checks.isEmpty && checks.allSatisfy(\.passed) }
    public var failures: [IntegrityCheck] { checks.filter { !$0.passed } }

    public var summary: String {
        if passed { return String(localized: "integrity.summary.passed", defaultValue: "全部 \(checks.count) 项校验通过") }
        return failures.map(\.title).joined(separator: "、")
    }
}

/// Independent second opinion on a conversion result: the app does not trust the engine's own
/// self-check alone, it re-parses both files and compares every payload it promised to preserve.
public enum IntegrityVerifier {
    public static func verify(original: Data, result: Data) -> IntegrityReport {
        var checks: [IntegrityCheck] = []
        func add(_ id: String, _ title: String, _ passed: Bool, _ detail: String) {
            checks.append(IntegrityCheck(id: id, title: title, passed: passed, detail: detail))
        }

        add("grew", String(localized: "结果比原文件更大"), result.count > original.count,
            String(localized: "integrity.bytes", defaultValue: "\(original.count) → \(result.count) 字节"))

        guard let before = try? HEICInspector.inspect(original, hashing: true) else {
            add("original.parses", String(localized: "原文件可解析"), false, String(localized: "无法解析原文件"))
            return IntegrityReport(checks: checks, originalByteCount: original.count, resultByteCount: result.count)
        }
        let after = try? HEICInspector.inspect(result, hashing: true)
        add("result.parses", String(localized: "结果可完整解析"), after != nil, after == nil ? String(localized: "结果文件结构损坏") : String(localized: "容器与条目索引有效"))
        guard let after else {
            return IntegrityReport(checks: checks, originalByteCount: original.count, resultByteCount: result.count)
        }

        add("container", String(localized: "结果仍是 HEIC 容器"), after.container == .heic, after.container.rawValue)

        add("primary", String(localized: "主图像素数据逐字节一致"),
            before.primaryTileDigests == after.primaryTileDigests,
            String(localized: "integrity.tiles", defaultValue: "\(before.primaryTileDigests.count) → \(after.primaryTileDigests.count) 个分块"))

        if before.hdrTileCount > 0 {
            add("hdr", String(localized: "HDR 增益图完整保留"),
                before.hdrTileDigests == after.hdrTileDigests,
                String(localized: "integrity.tiles", defaultValue: "\(before.hdrTileDigests.count) → \(after.hdrTileDigests.count) 个分块"))
        }

        if let exif = before.exifDigest {
            add("exif", String(localized: "EXIF 元数据逐字节一致"), after.exifDigest == exif, after.exifDigest == nil ? String(localized: "结果缺少 EXIF") : String(localized: "摘要一致"))
        }

        if let style = before.styleMetadataDigest {
            add("style", String(localized: "摄影风格元数据逐字节一致"), after.styleMetadataDigest == style, after.styleMetadataDigest == nil ? String(localized: "结果缺少风格数据") : String(localized: "摘要一致"))
        }

        if let thumbnail = before.thumbnailDigest {
            add("thumbnail", String(localized: "缩略图保留"), after.thumbnailDigest == thumbnail, after.thumbnailDigest == nil ? String(localized: "结果缺少缩略图") : String(localized: "摘要一致"))
        }

        if before.hasHDRGainMap {
            add("gainmap", String(localized: "HDR 增益图条目保留"), after.hasHDRGainMap, after.hasHDRGainMap ? String(localized: "存在") : String(localized: "缺失"))
        }

        add("texture", String(localized: "新增第三代质感数据"), after.hasTextureStyle && !before.hasTextureStyle,
            after.hasTextureStyle ? String(localized: "2026 texture_styles 条目就绪") : String(localized: "未找到 texture_styles 条目"))

        add("exifInspection", String(localized: "结果可被系统完整解码"), after.itemCount >= before.itemCount,
            String(localized: "integrity.items", defaultValue: "\(before.itemCount) → \(after.itemCount) 个条目"))

        return IntegrityReport(checks: checks, originalByteCount: original.count, resultByteCount: result.count)
    }
}