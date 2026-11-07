import Foundation

/// The linear pipeline a single photo goes through. The UI renders exactly this, so a failure
/// always names the step it happened in.
public enum ConversionStage: String, Sendable, CaseIterable, Equatable {
    case readingOriginal
    case inspecting
    case converting
    case verifying
    case saving
    case finished
    case failed

    public var title: String {
        switch self {
        case .readingOriginal: return String(localized: "读取原片")
        case .inspecting: return String(localized: "检查结构")
        case .converting: return String(localized: "添加纹理与颗粒")
        case .verifying: return String(localized: "无损校验")
        case .saving: return String(localized: "写入相册")
        case .finished: return String(localized: "完成")
        case .failed: return String(localized: "未完成")
        }
    }

    /// Verb phrase for "currently doing X" labels. Keeping a separate string avoids the
    /// English/Japanese word-order problems of prefixing a localized noun with "正在".
    public var inProgressTitle: String {
        switch self {
        case .readingOriginal: return String(localized: "正在读取原片")
        case .inspecting: return String(localized: "正在检查结构")
        case .converting: return String(localized: "正在添加纹理与颗粒")
        case .verifying: return String(localized: "正在无损校验")
        case .saving: return String(localized: "正在写入相册")
        case .finished: return String(localized: "正在完成")
        case .failed: return String(localized: "未完成")
        }
    }

    public var symbolName: String {
        switch self {
        case .readingOriginal: return "square.and.arrow.down"
        case .inspecting: return "viewfinder"
        case .converting: return "wand.and.stars"
        case .verifying: return "checkmark.shield"
        case .saving: return "photo.badge.plus"
        case .finished: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// Fraction of the pipeline completed when this stage is active, for the progress rail.
    public var progress: Double {
        switch self {
        case .readingOriginal: return 0.1
        case .inspecting: return 0.3
        case .converting: return 0.55
        case .verifying: return 0.75
        case .saving: return 0.9
        case .finished: return 1
        case .failed: return 0
        }
    }

    public var isBusy: Bool {
        switch self {
        case .readingOriginal, .inspecting, .converting, .verifying, .saving: return true
        case .finished, .failed: return false
        }
    }

    /// Stages that have any work to show, in order.
    public static var pipeline: [ConversionStage] {
        [.readingOriginal, .inspecting, .converting, .verifying, .saving]
    }
}