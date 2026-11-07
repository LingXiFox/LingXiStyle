import Foundation

/// PhotoKit-level facts that the file itself cannot reveal.
public struct AssetTraits: Sendable, Equatable {
    public var isLivePhoto: Bool
    public var isRAWPlusHEIC: Bool
    public var isEdited: Bool
    public var originalIsHEIC: Bool

    public init(isLivePhoto: Bool = false, isRAWPlusHEIC: Bool = false, isEdited: Bool = false, originalIsHEIC: Bool = true) {
        self.isLivePhoto = isLivePhoto
        self.isRAWPlusHEIC = isRAWPlusHEIC
        self.isEdited = isEdited
        self.originalIsHEIC = originalIsHEIC
    }
}

public enum CompatibilityIssue: String, Sendable, Equatable, CaseIterable {
    case notHEIC
    case livePhoto
    case rawPlusHEIC
    case missingPrimaryGrid
    case missingStyleMetadata
    case alreadyHasTexture
    case unsupportedItemLayout
    case corruptedFile

    public var title: String {
        switch self {
        case .notHEIC: return "不是 HEIC 原片"
        case .livePhoto: return "实况照片暂不支持"
        case .rawPlusHEIC: return "ProRAW + HEIC 组合暂不支持"
        case .missingPrimaryGrid: return "缺少主图分块数据"
        case .missingStyleMetadata: return "没有 iPhone 16/17 摄影风格数据"
        case .alreadyHasTexture: return "已经带有第三代质感"
        case .unsupportedItemLayout: return "该文件的索引结构暂不受支持"
        case .corruptedFile: return "文件结构损坏"
        }
    }

    public var guidance: String {
        switch self {
        case .notHEIC: return "请选择 iPhone 相机直出的 HEIC 照片。"
        case .livePhoto: return "在相册里把它转为静态照片后再试，原文件不会改动。"
        case .rawPlusHEIC: return "请选择标准 HEIC 照片；ProRAW 组合留给后续版本。"
        case .missingPrimaryGrid: return "这张照片不是分块编码的 HEIC，无法安全追加质感数据。"
        case .missingStyleMetadata: return "它可能来自较旧的机型或第三方应用，没有可保留的摄影风格。"
        case .alreadyHasTexture: return "无需重复处理，直接使用原照片即可。"
        case .unsupportedItemLayout: return "请把这张照片发给开发者，以补充兼容性。"
        case .corruptedFile: return "文件可能未完整下载，请在相册里打开一次后再试。"
        }
    }
}

public struct CompatibilityVerdict: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case ready
        case alreadyEnhanced
        case unsupported
    }

    public let status: Status
    public let issues: [CompatibilityIssue]
    public let inspection: HEICInspection?

    public init(status: Status, issues: [CompatibilityIssue] = [], inspection: HEICInspection? = nil) {
        self.status = status
        self.issues = issues
        self.inspection = inspection
    }

    public var isReady: Bool { status == .ready }

    public var headline: String {
        switch status {
        case .ready: return "可以增强"
        case .alreadyEnhanced: return "已有第三代质感"
        case .unsupported: return issues.first?.title ?? "暂不支持"
        }
    }

    public var detail: String {
        switch status {
        case .ready:
            var line = "将保留原图全部像素与元数据，只追加第三代质感与颗粒。"
            if let inspection {
                line += "\n\(inspection.pixelSizeDescription) · \(inspection.primaryTileCount) 个主图分块"
                line += inspection.hasHDRGainMap ? " · 含 HDR 增益图" : " · SDR"
            }
            return line
        case .alreadyEnhanced:
            return "这张照片已经包含 2026 质感样式数据，重复处理不会带来变化。"
        case .unsupported:
            // The headline already names the first issue; keep this to actionable guidance so
            // the selection card does not repeat the same sentence three times.
            return issues.map(\.guidance).joined(separator: "\n")
        }
    }
}

public enum CompatibilityEvaluator {
    public static func evaluate(_ inspection: HEICInspection, traits: AssetTraits = AssetTraits()) -> CompatibilityVerdict {
        // A JPEG/PNG/RAW never reaches the item-level checks: those would only add noise
        // ("missing grid", "no style metadata") to what is really one problem.
        var issues: [CompatibilityIssue] = []
        if !traits.originalIsHEIC || !inspection.container.isHEIF {
            issues.append(.notHEIC)
            if traits.isLivePhoto { issues.append(.livePhoto) }
            return CompatibilityVerdict(status: .unsupported, issues: issues, inspection: inspection)
        }
        if traits.isLivePhoto { issues.append(.livePhoto) }
        if traits.isRAWPlusHEIC { issues.append(.rawPlusHEIC) }
        // An edited asset is allowed through: PhotoKit still hands us a resource file and the
        // app always writes a new asset. The UI shows a separate warning for `traits.isEdited`.
        if inspection.hasTextureStyle { issues.append(.alreadyHasTexture) }
        if !inspection.hasPrimaryGrid { issues.append(.missingPrimaryGrid) }
        if !inspection.hasStyleMetadata { issues.append(.missingStyleMetadata) }
        if !inspection.supportsGraftLayout { issues.append(.unsupportedItemLayout) }
        if !inspection.warnings.isEmpty { issues.append(.corruptedFile) }

        if issues.contains(.alreadyHasTexture), issues.count == 1 {
            return CompatibilityVerdict(status: .alreadyEnhanced, issues: issues, inspection: inspection)
        }
        if issues.isEmpty {
            return CompatibilityVerdict(status: .ready, issues: [], inspection: inspection)
        }
        return CompatibilityVerdict(status: .unsupported, issues: issues, inspection: inspection)
    }
}
