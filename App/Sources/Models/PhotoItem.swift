import Foundation
import UIKit
import LingXiKit

/// One candidate photo in the queue. Every phase here is reported by real work, never by a timer.
struct PhotoItem: Identifiable {
    enum Phase: Equatable {
        case preparing        // exporting / downloading the original resource
        case ready            // inspected, verdict known
        case preparingFailed(String)
    }

    enum Outcome: Equatable {
        case saved(assetIdentifier: String?, byteCount: Int)
        case skipped(CompatibilityIssue)
        case failed(message: String, code: String)
        case cancelled
    }

    let id: UUID
    let assetIdentifier: String?
    let displayName: String
    var image: UIImage
    var fileURL: URL?
    /// The paired movie exported next to `fileURL` for a Live Photo. Both mode pipelines need
    /// the original bytes; `nil` means the asset is a regular still.
    var videoURL: URL?
    /// Frame count reported by the movie's own sample table, filled in after a full run.
    var videoFrameCount: Int?
    /// The Live Photo mode this item was actually processed with. `nil` for a still.
    var livePhotoMode: LivePhotoProcessingMode?
    var traits: AssetTraits
    var inspection: HEICInspection?
    var verdict: CompatibilityVerdict?
    var integrity: IntegrityReport?
    var phase: Phase = .preparing
    var stage: ConversionStage?
    var failedDuringStage = false
    var outcome: Outcome?
    /// Real iCloud download progress (0...1), supplied by PhotoKit. Nil when the value is not
    /// measurable, in which case the UI shows an indeterminate state instead of a fake percentage.
    var downloadProgress: Double?
    /// The converted HEIC copy owned by the session workspace. Used for sharing the real result.
    var outputURL: URL?
    /// The photo is saved, but Photos returned something unexpected on re-read. Keep it visible
    /// in results and diagnostics instead of failing the item and risking a duplicate save.
    var saveWarning: String?

    init(id: UUID = UUID(),
         assetIdentifier: String?,
         displayName: String,
         image: UIImage,
         traits: AssetTraits) {
        self.id = id
        self.assetIdentifier = assetIdentifier
        self.displayName = displayName
        self.image = image
        self.traits = traits
    }

    var isConvertible: Bool { verdict?.isReady == true && fileURL != nil }
    /// A Live Photo that really has its movie on disk. Identity, not permission: the mode picker
    /// and the badges only show for these items.
    var isLivePhoto: Bool { traits.isLivePhoto }
    var hasLivePhotoVideo: Bool { traits.isLivePhoto && videoURL != nil }
    var isSaved: Bool {
        if case .saved = outcome { return true }
        return false
    }
    var badgeStatus: CompatibilityVerdict.Status? { verdict?.status }

    /// Saved, and the movie kept its own outcome (byte copy or styled tracks).
    var savedAsLivePhoto: Bool {
        guard case .saved? = outcome else { return false }
        return livePhotoMode != nil
    }

    var accessibilityDescription: String {
        switch phase {
        case .preparing: return String(localized: "正在读取原件")
        case .preparingFailed(let message): return String(localized: "phase.preparingFailed", defaultValue: "读取失败：\(message)")
        case .ready:
            switch verdict?.status {
            case .ready: return String(localized: "可添加纹理与颗粒")
            case .alreadyEnhanced: return String(localized: "已带有纹理与颗粒，无需处理")
            case .unsupported: return String(localized: "暂不支持")
            case nil: return String(localized: "等待检查")
            }
        }
    }
}

extension PhotoItem.Phase {
    var label: String {
        switch self {
        case .preparing: return String(localized: "正在读取原件")
        case .ready: return String(localized: "已就绪")
        case .preparingFailed: return String(localized: "原件读取失败")
        }
    }
}