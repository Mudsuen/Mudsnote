import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore

@MainActor
final class PrefixAttachmentCell: NSTextAttachmentCell {
    enum Style {
        case bullet
        case checklist(checked: Bool)
    }

    private let style: Style
    private let strokeColor: NSColor
    private let fillColor: NSColor

    init(style: Style, strokeColor: NSColor, fillColor: NSColor) {
        self.style = style
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        switch style {
        case .bullet:
            return NSSize(width: 11, height: 12)
        case .checklist:
            return NSSize(width: 13, height: 13)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        switch style {
        case .bullet:
            drawBullet(in: cellFrame)
        case .checklist(let checked):
            drawChecklist(in: cellFrame, checked: checked, flipped: controlView?.isFlipped ?? false)
        }
    }

    private func drawBullet(in frame: NSRect) {
        let yOffset: CGFloat = 1.8
        let dotRect = NSRect(
            x: frame.midX - 3.25,
            y: frame.midY - 3.25 + yOffset,
            width: 6.5,
            height: 6.5
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        fillColor.setFill()
        dotPath.fill()
    }

    private func drawChecklist(in frame: NSRect, checked: Bool, flipped: Bool) {
        let yOffset: CGFloat = 1.45
        let boxRect = NSRect(
            x: frame.origin.x + 0.5,
            y: frame.origin.y + 0.5 + yOffset,
            width: 11.5,
            height: 11.5
        )
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3.1, yRadius: 3.1)
        boxPath.lineWidth = 1.35

        if checked {
            fillColor.setFill()
            boxPath.fill()
        } else {
            panelSubtleFillColor().withAlphaComponent(0.08).setFill()
            boxPath.fill()
        }

        strokeColor.setStroke()
        boxPath.stroke()

        guard checked else { return }

        func y(_ fractionFromTop: CGFloat) -> CGFloat {
            if flipped {
                return boxRect.minY + (boxRect.height * fractionFromTop)
            }
            return boxRect.maxY - (boxRect.height * fractionFromTop)
        }

        let checkPath = NSBezierPath()
        checkPath.lineWidth = 1.85
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.move(to: NSPoint(x: boxRect.minX + 2.45, y: y(0.58)))
        checkPath.line(to: NSPoint(x: boxRect.minX + 5.05, y: y(0.79)))
        checkPath.line(to: NSPoint(x: boxRect.maxX - 2.2, y: y(0.30)))
        NSColor.white.withAlphaComponent(0.98).setStroke()
        checkPath.stroke()
    }
}

@MainActor
final class FileAttachmentPreviewCell: NSTextAttachmentCell {
    private let displayTitle: String
    private let subtitle: String
    private let icon: NSImage

    init(fileURL: URL, label: String) {
        let fallbackTitle = fileURL.lastPathComponent.isEmpty ? "Attachment" : fileURL.lastPathComponent
        self.displayTitle = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : label
        self.subtitle = MarkdownRichTextCodec.attachmentMetadataText(for: fileURL)
        self.icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        self.icon.size = NSSize(width: 22, height: 22)
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        NSSize(width: 260, height: 38)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 1, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        panelSubtleFillColor().withAlphaComponent(0.22).setFill()
        path.fill()
        panelTertiaryTextColor().withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()

        let iconRect = NSRect(
            x: rect.minX + 9,
            y: rect.midY - 11,
            width: 22,
            height: 22
        )
        icon.draw(in: iconRect)

        let titleRect = NSRect(
            x: iconRect.maxX + 8,
            y: rect.minY + 16,
            width: rect.width - 48,
            height: 16
        )
        let subtitleRect = NSRect(
            x: iconRect.maxX + 8,
            y: rect.minY + 5,
            width: rect.width - 48,
            height: 13
        )
        drawClipped(displayTitle, in: titleRect, font: .systemFont(ofSize: 12, weight: .semibold), color: panelPrimaryTextColor())
        drawClipped(subtitle, in: subtitleRect, font: .systemFont(ofSize: 10, weight: .medium), color: panelTertiaryTextColor())
    }

    private func drawClipped(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

enum MarkdownImageDecoding {
    static let maximumThumbnailPixelSize = 2_400

    static func pixelSize(at imageURL: URL) -> NSSize? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0,
              height.doubleValue > 0 else {
            return nil
        }
        return NSSize(width: width.doubleValue, height: height.doubleValue)
    }

    nonisolated static func thumbnail(
        at imageURL: URL,
        maximumPixelSize: Int = maximumThumbnailPixelSize
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

final class MarkdownDecodedImageCacheEntry: NSObject {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }
}

actor MarkdownImageDecodeService {
    static let shared = MarkdownImageDecodeService()

    private let cache: NSCache<NSString, MarkdownDecodedImageCacheEntry>
    private(set) var decodeCount = 0

    init() {
        cache = NSCache<NSString, MarkdownDecodedImageCacheEntry>()
        cache.countLimit = 64
        cache.totalCostLimit = 128 * 1_024 * 1_024
    }

    func thumbnail(
        at imageURL: URL,
        maximumPixelSize: Int = MarkdownImageDecoding.maximumThumbnailPixelSize,
        forceReload: Bool = false
    ) -> CGImage? {
        let standardizedURL = imageURL.standardizedFileURL
        let values = try? standardizedURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        let modifiedAt = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1
        let fileSize = values?.fileSize ?? -1
        let key = [
            standardizedURL.path,
            String(modifiedAt),
            String(fileSize),
            String(maximumPixelSize)
        ].joined(separator: "|") as NSString
        if !forceReload, let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let image = MarkdownImageDecoding.thumbnail(
            at: standardizedURL,
            maximumPixelSize: maximumPixelSize
        ) else {
            return nil
        }
        decodeCount += 1
        cache.setObject(
            MarkdownDecodedImageCacheEntry(image: image),
            forKey: key,
            cost: image.bytesPerRow * image.height
        )
        return image
    }

    func resetForTesting() {
        cache.removeAllObjects()
        decodeCount = 0
    }
}

@MainActor
final class AsyncImageAttachmentCell: NSTextAttachmentCell {
    private let imageURL: URL
    let naturalSize: NSSize
    private var decodeTask: Task<Void, Never>?
    private(set) var hasDecodedImage = false

    init(imageURL: URL, naturalSize: NSSize) {
        self.imageURL = imageURL
        self.naturalSize = naturalSize
        super.init(imageCell: NSImage(size: naturalSize))
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        decodeTask?.cancel()
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        beginDecodingIfNeeded(in: controlView)
        if hasDecodedImage {
            super.draw(withFrame: cellFrame, in: controlView)
        } else {
            let placeholder = NSBezierPath(roundedRect: cellFrame, xRadius: 8, yRadius: 8)
            panelSubtleFillColor().withAlphaComponent(0.18).setFill()
            placeholder.fill()
        }
    }

    func reloadImage(in controlView: NSView?) {
        decodeTask?.cancel()
        decodeTask = nil
        hasDecodedImage = false
        image = nil
        controlView?.needsDisplay = true
        beginDecodingIfNeeded(in: controlView, forceReload: true)
    }

    func beginDecodingIfNeeded(in controlView: NSView?, forceReload: Bool = false) {
        guard decodeTask == nil, !hasDecodedImage else { return }
        let imageURL = imageURL
        let naturalSize = naturalSize
        weak let textView = controlView as? NSTextView
        decodeTask = Task { [weak self, weak textView] in
            guard !Task.isCancelled,
                  let thumbnail = await MarkdownImageDecodeService.shared.thumbnail(at: imageURL, forceReload: forceReload),
                  !Task.isCancelled,
                  let self else {
                return
            }
            self.image = NSImage(cgImage: thumbnail, size: naturalSize)
            self.hasDecodedImage = true
            textView?.needsDisplay = true
        }
    }
}
