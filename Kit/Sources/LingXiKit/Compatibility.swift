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
        case .notHEIC: return String(localized: "不是 HEIC 原片")
        case .livePhoto: return String(localized: "实况照片暂不支持")
        case .rawPlusHEIC: return String(localized: "ProRAW + HEIC 组合暂不支持")
        case .missingPrimaryGrid: return String(localized: "缺少主图分块数据")
        case .missingStyleMetadata: return String(localized: "没有 iPhone 16/17 的纹理与颗粒数据")
        case .alreadyHasTexture: return String(localized: "已带有纹理与颗粒")
        case .unsupportedItemLayout: return String(localized: "该文件的索引结构暂不受支持")
        case .corruptedFile: return String(localized: "文件结构损坏")
        }
    }

    public var guidance: String {
        switch self {
        case .notHEIC: return String(localized: "请选择 iPhone 相机直出的 HEIC 照片。")
        case .livePhoto: return String(localized: "在相册里把它转为静态照片后再试，原文件不会改动。")
        case .rawPlusHEIC: return String(localized: "请选择标准 HEIC 照片；ProRAW 组合留给后续版本。")
        case .missingPrimaryGrid: return String(localized: "这张照片不是分块编码的 HEIC，无法安全添加纹理与颗粒数据。")
        case .missingStyleMetadata: return String(localized: "它可能来自较旧的机型或第三方应用，没有可保留的纹理与颗粒信息。")
        case .alreadyHasTexture: return String(localized: "无需重复处理，直接使用原照片即可。")
        case .unsupportedItemLayout: return String(localized: "请把这张照片发给开发者，以补充兼容性。")
        case .corruptedFile: return String(localized: "文件可能未完整下载，请在相册里打开一次后再试。")
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
        case .ready: return String(localized: "可添加纹理与颗粒")
        case .alreadyEnhanced: return String(localized: "已带有纹理与颗粒")
        case .unsupported: return issues.first?.title ?? String(localized: "暂不支持")
        }
    }

    public var detail: String {
        switch status {
        case .ready:
            var line = String(localized: "将保留原图全部像素与元数据，只追加一层纹理与颗粒。")
            if let inspection {
                line += String(localized: "compatibility.readyGeometry", defaultValue: "\n\(inspection.pixelSizeDescription) · \(inspection.primaryTileCount) 个主图分块")
                line += inspection.hasHDRGainMap ? String(localized: " · 含 HDR 增益图") : " · SDR"
            }
            return line
        case .alreadyEnhanced:
            return String(localized: "这张照片已经包含纹理与颗粒数据，无需重复处理。")
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