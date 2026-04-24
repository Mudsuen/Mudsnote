import AppKit
import Foundation

enum MudsnoteBrand {
    static let appName = "Mudsnote"
    private static let statusLogicalSize = NSSize(width: 18, height: 18)

    @MainActor
    static func statusItemImage() -> NSImage {
        if let image = vectorStatusItemImage() {
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "note.text",
            accessibilityDescription: appName
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    @MainActor
    private static func vectorStatusItemImage(scale: CGFloat = 2) -> NSImage? {
        let pixelsWide = Int(statusLogicalSize.width * scale)
        let pixelsHigh = Int(statusLogicalSize.height * scale)

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        representation.size = statusLogicalSize

        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: statusLogicalSize)).fill()

        let outline = NSBezierPath()
        outline.lineWidth = 1.65
        outline.lineJoinStyle = .round
        outline.lineCapStyle = .round
        outline.move(to: NSPoint(x: 4.0, y: 2.25))
        outline.line(to: NSPoint(x: 10.4, y: 2.25))
        outline.line(to: NSPoint(x: 14.0, y: 5.9))
        outline.line(to: NSPoint(x: 14.0, y: 14.35))
        outline.line(to: NSPoint(x: 4.0, y: 14.35))
        outline.close()

        let fold = NSBezierPath()
        fold.lineWidth = 1.65
        fold.lineJoinStyle = .round
        fold.lineCapStyle = .round
        fold.move(to: NSPoint(x: 10.4, y: 2.25))
        fold.line(to: NSPoint(x: 10.4, y: 5.1))
        fold.line(to: NSPoint(x: 14.0, y: 5.9))

        let mudLine = NSBezierPath()
        mudLine.lineWidth = 1.9
        mudLine.lineJoinStyle = .round
        mudLine.lineCapStyle = .round
        mudLine.move(to: NSPoint(x: 5.1, y: 10.7))
        mudLine.curve(
            to: NSPoint(x: 8.6, y: 10.15),
            controlPoint1: NSPoint(x: 6.0, y: 9.25),
            controlPoint2: NSPoint(x: 7.1, y: 9.2)
        )
        mudLine.curve(
            to: NSPoint(x: 12.9, y: 10.75),
            controlPoint1: NSPoint(x: 10.15, y: 11.25),
            controlPoint2: NSPoint(x: 11.4, y: 12.15)
        )

        NSColor.black.setStroke()
        outline.stroke()
        fold.stroke()
        mudLine.stroke()

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: statusLogicalSize)
        image.addRepresentation(representation)
        image.isTemplate = true
        return image
    }
}
