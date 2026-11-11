import Foundation

/// How the app handles a Live Photo. Both modes treat the still and the paired movie as one
/// asset: one free slot, one saved photo, no per-frame or per-resource accounting.
public enum LivePhotoProcessingMode: String, Sendable, CaseIterable, Equatable, Identifiable {
    /// Only the still gets the texture layer. The paired movie is copied byte for byte, so the
    /// motion, the sound and the pairing survive untouched.
    case stillOnly = "stillOnly"
    /// The still and every motion frame get the same Texture/Grain look. The movie keeps its own
    /// samples, sound, keyframes and pairing; only the style tracks that iOS renders with are added.
    case full = "full"

    public var id: String { rawValue }

    public static let defaultMode: LivePhotoProcessingMode = .stillOnly

    /// Shown everywhere the choice appears, including the tutorial and the settings page.
    public static let quotaNote = String(localized: "每张实况照片只计 1 张额度，完整处理也一样。")

    public var title: String {
        switch self {
        case .stillOnly: return String(localized: "只处理主帧")
        case .full: return String(localized: "完整处理")
        }
    }

    public var detail: String {
        switch self {
        case .stillOnly:
            return String(localized: "主照片获得纹理与颗粒，动态画面和声音保持原样。速度最快，也最稳妥。")
        case .full:
            return String(localized: "主照片和动态画面的每一帧获得同样的纹理与颗粒，声音、关键帧与配对关系保留。处理时间更长。")
        }
    }

    /// One line for the conversion confirmation sheet.
    public var shortDetail: String {
        switch self {
        case .stillOnly: return String(localized: "动态画面按原样保存")
        case .full: return String(localized: "逐帧应用同样的纹理与颗粒")
        }
    }
}
