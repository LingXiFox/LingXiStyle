import AppKit
import ImageIO
import SwiftUI

enum MacThumbnail {
    nonisolated static func image(at url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Downsampled preview. The conversion path never touches this; it only feeds the lists.
struct MacThumbnailView: View {
    let url: URL?
    var side: CGFloat = 44
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MacRadius.thumbnail, style: .continuous)
                .fill(MacPalette.fillControl)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: side * 0.32))
                    .foregroundStyle(MacPalette.textTertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.thumbnail, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MacRadius.thumbnail, style: .continuous)
            .strokeBorder(MacPalette.hairline.opacity(0.5), lineWidth: 0.5))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await Task.detached(priority: .utility) {
                ThumbnailBox(image: MacThumbnail.image(at: url, maxPixel: Int(side * 2)))
            }.value
            image = loaded.image
        }
    }
}

private final class ThumbnailBox: @unchecked Sendable {
    let image: NSImage?
    init(image: NSImage?) { self.image = image }
}
