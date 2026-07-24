import AppKit

enum MarkdownImageDisplaySizing {
    static let minimumWidth: CGFloat = 80
    static let maximumWidth: CGFloat = 1_200
    static let fitBounds = NSSize(width: 420, height: 240)

    static func fitSize(for naturalSize: NSSize) -> NSSize {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return .zero }
        let scale = min(
            fitBounds.width / naturalSize.width,
            fitBounds.height / naturalSize.height,
            1
        )
        return NSSize(
            width: max(1, naturalSize.width * scale),
            height: max(1, naturalSize.height * scale)
        )
    }

    static func displaySize(for naturalSize: NSSize, preferredWidth: Double?) -> NSSize {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return .zero }
        guard let preferredWidth, preferredWidth.isFinite, preferredWidth > 0 else {
            return fitSize(for: naturalSize)
        }
        let width = min(max(CGFloat(preferredWidth), minimumWidth), maximumWidth)
        return NSSize(width: width, height: width * naturalSize.height / naturalSize.width)
    }

    static func clampedWidth(_ width: CGFloat) -> Double {
        Double(min(maximumWidth, max(minimumWidth, width)))
    }
}
