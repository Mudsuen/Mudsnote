import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Background-downsampled `NSCache` for inline images inside `MarkdownPreviewView`.
/// Eliminates synchronous main-thread `UIImage(contentsOfFile:)` decoding inside SwiftUI `body`.
final class ReaderImageDecodeCache: @unchecked Sendable {
    static let shared = ReaderImageDecodeCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: max(cost, 1))
    }

    static func decodeDownsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return UIImage(contentsOfFile: url.path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxPixelSize), 64),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(cgImage: cgImage)
    }
}

struct ReaderAsyncImageView<Placeholder: View>: View {
    let url: URL?
    let maxPixelSize: CGFloat
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedKey: String?

    private var cacheKey: String? {
        guard let url else { return nil }
        return "\(url.standardizedFileURL.path)#\(Int(maxPixelSize))"
    }

    var body: some View {
        Group {
            if let image = resolvedImage {
                if contentMode == .fill {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                placeholder()
            }
        }
        .task(id: cacheKey) {
            guard let url, let key = cacheKey else {
                loadedImage = nil
                loadedKey = nil
                return
            }
            if let cached = ReaderImageDecodeCache.shared.image(forKey: key) {
                loadedImage = cached
                loadedKey = key
                return
            }
            let targetPixels = maxPixelSize
            let decoded = await Task.detached(priority: .userInitiated) {
                ReaderImageDecodeCache.decodeDownsampledImage(at: url, maxPixelSize: targetPixels)
            }.value
            guard !Task.isCancelled else { return }
            if let decoded {
                ReaderImageDecodeCache.shared.store(decoded, forKey: key)
            }
            loadedImage = decoded
            loadedKey = key
        }
    }

    private var resolvedImage: UIImage? {
        guard let key = cacheKey else { return nil }
        if loadedKey == key, let loadedImage {
            return loadedImage
        }
        return ReaderImageDecodeCache.shared.image(forKey: key)
    }
}
