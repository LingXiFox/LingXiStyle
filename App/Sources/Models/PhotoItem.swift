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

    let id = UUID()
    let assetIdentifier: String?
    let displayName: String
    var image: UIImage
    var fileURL: URL?
    var traits: AssetTraits
    var inspection: HEICInspection?
    var verdict: CompatibilityVerdict?
    var integrity: IntegrityReport?
    var phase: Phase = .preparing
    var stage: ConversionStage?
    var failedDuringStage = false
    var outcome: Outcome?

    var isConvertible: Bool { verdict?.isReady == true && fileURL != nil }
    var badgeStatus: CompatibilityVerdict.Status? { verdict?.status }

    var accessibilityDescription: String {
        switch phase {
        case .preparing: return "正在读取原件"
        case .preparingFailed(let message): return "读取失败：\(message)"
        case .ready:
            switch verdict?.status {
            case .ready: return "可解锁第三代风格"
            case .alreadyEnhanced: return "已包含第三代风格，无需转换"
            case .unsupported: return "暂不支持"
            case nil: return "等待检查"
            }
        }
    }
}

extension PhotoItem.Phase {
    var label: String {
        switch self {
        case .preparing: return "正在下载原件"
        case .ready: return "已就绪"
        case .preparingFailed: return "原件读取失败"
        }
    }
}
