#if DEBUG
import SwiftUI
import UIKit
import LingXiKit

/// Decorative stand-ins for the canvas only. They are generated gradients, never copies of a
/// real photo, so no preview can imply a real before/after grain comparison.
enum PreviewFixtures {
    static let inspection = HEICInspection(
        fileByteCount: 4_820_000,
        brands: ["heic", "mif1", "miaf"],
        primaryItemID: 1,
        pixelWidth: 4032,
        pixelHeight: 3024,
        itemCount: 12,
        primaryTileCount: 24,
        hdrTileCount: 24,
        hasPrimaryGrid: true,
        hasStyleMetadata: true,
        hasExif: true,
        hasThumbnail: true,
        hasHDRGainMap: true,
        hasLinearThumbnail: true,
        supportsGraftLayout: true,
        ilocDescription: "iloc v1 · construction_method 0"
    )

    static func image(_ seed: Int, size: CGSize = CGSize(width: 1200, height: 1600)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors: [UIColor] = [
                UIColor(red: 0.17, green: 0.24, blue: 0.36, alpha: 1),
                UIColor(red: 0.36, green: 0.30, blue: 0.48, alpha: 1),
                UIColor(red: 0.12, green: 0.35, blue: 0.40, alpha: 1)
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [colors[seed % 3].cgColor, colors[(seed + 1) % 3].cgColor] as CFArray,
                                      locations: [0, 1])
            context.cgContext.drawLinearGradient(gradient!,
                                                 start: .zero,
                                                 end: CGPoint(x: size.width, y: size.height),
                                                 options: [])
            for index in 0..<4 {
                let radius = size.width * (0.10 + CGFloat(index) * 0.05)
                let center = CGPoint(x: size.width * (0.25 + 0.18 * CGFloat(index)),
                                     y: size.height * (0.30 + 0.12 * CGFloat((index + seed) % 4)))
                UIColor.white.withAlphaComponent(0.06).setFill()
                UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)).fill()
            }
        }
    }

    static func readyItem(name: String = "IMG_4821.HEIC", seed: Int = 1) -> PhotoItem {
        PhotoItem(assetIdentifier: "preview-\(seed)",
                  displayName: name,
                  image: image(seed),
                  traits: AssetTraits(),
                  inspection: inspection,
                  verdict: CompatibilityVerdict(status: .ready, inspection: inspection),
                  phase: .ready)
    }

    static func downloadingItem(name: String = "IMG_4822.HEIC") -> PhotoItem {
        PhotoItem(assetIdentifier: "preview-download",
                  displayName: name,
                  image: image(2),
                  traits: AssetTraits(),
                  inspection: nil,
                  verdict: nil,
                  phase: .preparing)
    }

    static func alreadyEnhancedItem(name: String = "IMG_4823.HEIC") -> PhotoItem {
        var item = readyItem(name: name, seed: 3)
        item.verdict = CompatibilityVerdict(status: .alreadyEnhanced,
                                            issues: [.alreadyHasTexture],
                                            inspection: inspection)
        return item
    }

    static func unsupportedItem(name: String = "IMG_4824.JPG") -> PhotoItem {
        var item = readyItem(name: name, seed: 4)
        item.inspection = HEICInspection(container: .jpeg, brands: ["jpeg"], pixelWidth: 3024, pixelHeight: 4032)
        item.verdict = CompatibilityVerdict(status: .unsupported,
                                            issues: [.notHEIC],
                                            inspection: item.inspection)
        return item
    }

    static func savedItem(name: String = "IMG_4821.HEIC", seed: Int = 1) -> PhotoItem {
        var item = readyItem(name: name, seed: seed)
        item.stage = .finished
        item.outcome = .saved(assetIdentifier: "preview-saved-\(seed)", byteCount: 5_120_000)
        return item
    }

    static func failedItem(name: String = "IMG_4825.HEIC") -> PhotoItem {
        var item = readyItem(name: name, seed: 5)
        item.stage = .verifying
        item.failedDuringStage = true
        item.outcome = .failed(message: "校验没有通过：主图像素与原图不一致。", code: "E_VERIFY")
        return item
    }

    static func convertingItem(stage: ConversionStage) -> PhotoItem {
        var item = readyItem()
        item.stage = stage
        return item
    }

    @MainActor
    static func resultModel(_ items: [PhotoItem]) -> AppModel {
        model(screen: .result, items: items, summary: ConversionSummary(items: items))
    }

    @MainActor
    static func model(screen: AppModel.Screen,
                      items: [PhotoItem],
                      summary: ConversionSummary? = nil) -> AppModel {
        let model = AppModel()
        model.screen = screen
        model.items = items
        model.selectedID = items.first?.id
        model.summary = summary
        model.diagnosticsText = "LingXiStyle preview\nE_VERIFY — sample diagnostics"
        return model
    }
}

// MARK: - Empty

#Preview("空状态 · 深色") {
    EmptyStateView(model: PreviewFixtures.model(screen: .idle, items: []))
        .preferredColorScheme(.dark)
}

#Preview("空状态 · 浅色") {
    EmptyStateView(model: PreviewFixtures.model(screen: .idle, items: []))
        .preferredColorScheme(.light)
}

#Preview("空状态 · 大字体") {
    EmptyStateView(model: PreviewFixtures.model(screen: .idle, items: []))
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}

// MARK: - Selection

#Preview("已选 1 张 · 深色") {
    SelectionView(model: PreviewFixtures.model(screen: .selecting,
                                               items: [PreviewFixtures.readyItem()]))
        .preferredColorScheme(.dark)
}

#Preview("已选 1 张 · 浅色") {
    SelectionView(model: PreviewFixtures.model(screen: .selecting,
                                               items: [PreviewFixtures.readyItem()]))
        .preferredColorScheme(.light)
}

#Preview("多选 · 深色") {
    SelectionView(model: PreviewFixtures.model(
        screen: .selecting,
        items: [PreviewFixtures.readyItem(),
                PreviewFixtures.alreadyEnhancedItem(),
                PreviewFixtures.unsupportedItem()]
    ))
    .preferredColorScheme(.dark)
}

#Preview("下载原件 · 深色") {
    SelectionView(model: PreviewFixtures.model(screen: .selecting,
                                               items: [PreviewFixtures.downloadingItem()]))
        .preferredColorScheme(.dark)
}

// MARK: - Converting

#Preview("转换中 · 深色") {
    ConvertingView(model: PreviewFixtures.model(screen: .converting,
                                                items: [PreviewFixtures.convertingItem(stage: .converting)]))
        .preferredColorScheme(.dark)
}

#Preview("转换中 · 减少动态效果") {
    ConvertingView(model: PreviewFixtures.model(screen: .converting,
                                                items: [PreviewFixtures.convertingItem(stage: .verifying)]))
        .environment(\.reduceMotionOverride, true)
        .preferredColorScheme(.light)
}

// MARK: - Result

#Preview("成功 · 深色") {
    ResultView(model: PreviewFixtures.resultModel([PreviewFixtures.savedItem()])) {}
        .preferredColorScheme(.dark)
}

#Preview("部分失败 · 深色") {
    ResultView(model: PreviewFixtures.resultModel([PreviewFixtures.savedItem(),
                                                   PreviewFixtures.failedItem()])) {}
        .preferredColorScheme(.dark)
}

#Preview("部分失败 · 浅色 · 大字体") {
    ResultView(model: PreviewFixtures.resultModel([PreviewFixtures.savedItem(),
                                                   PreviewFixtures.failedItem()])) {}
        .environment(\.dynamicTypeSize, .accessibility2)
        .preferredColorScheme(.light)
}

// MARK: - Permission

#Preview("权限拒绝 · 深色") {
    PermissionDeniedView {}
        .preferredColorScheme(.dark)
}

#Preview("权限拒绝 · 浅色") {
    PermissionDeniedView {}
        .preferredColorScheme(.light)
}
#endif
