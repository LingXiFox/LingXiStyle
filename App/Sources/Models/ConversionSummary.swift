import Foundation

struct ConversionSummary {
    var savedCount: Int
    var skippedCount: Int
    var failedCount: Int
    var cancelledCount: Int
    var savedAssetIdentifiers: [String]
    var failures: [FailureRow]
    var skippedReasons: [String]

    struct FailureRow: Identifiable {
        let id = UUID()
        let name: String
        let message: String
        let code: String
    }

    var total: Int { savedCount + skippedCount + failedCount + cancelledCount }
    /// A skipped photo is not a success: the result card must not show a green check for it.
    var isCompletelySuccessful: Bool {
        savedCount > 0 && failedCount == 0 && cancelledCount == 0 && skippedCount == 0
    }
    var headline: String {
        if savedCount > 0 {
            if failedCount > 0 { return String(localized: "summary.savedPartial", defaultValue: "已保存 \(savedCount) 张，\(failedCount) 张未完成") }
            return savedCount > 1 ? String(localized: "summary.savedMany", defaultValue: "已保存 \(savedCount) 张新照片") : String(localized: "已保存新照片")
        }
        if failedCount > 0 { return String(localized: "这次没有保存成功") }
        if cancelledCount > 0 { return String(localized: "已取消，没有保存新照片") }
        return String(localized: "没有需要转换的照片")
    }

    init(items: [PhotoItem]) {
        var saved: [String] = []
        var failures: [FailureRow] = []
        var skipped: [String] = []
        var skippedCount = 0
        var failedCount = 0
        var cancelledCount = 0

        for item in items {
            switch item.outcome {
            case .saved(let identifier, _):
                if let identifier { saved.append(identifier) }
            case .failed(let message, let code):
                failedCount += 1
                failures.append(.init(name: item.displayName, message: message, code: code))
            case .skipped(let issue):
                skippedCount += 1
                skipped.append("\(item.displayName)：\(issue.title)")
            case .cancelled:
                cancelledCount += 1
            case nil:
                continue
            }
        }

        self.savedCount = items.filter { if case .saved? = $0.outcome { return true } else { return false } }.count
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.cancelledCount = cancelledCount
        self.savedAssetIdentifiers = saved
        self.failures = failures
        self.skippedReasons = skipped
    }
}