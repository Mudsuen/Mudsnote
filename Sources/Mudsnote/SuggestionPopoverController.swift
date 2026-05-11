import AppKit

struct SuggestionItem: Equatable {
    let title: String
    let subtitle: String?
    let symbolName: String?
}

@MainActor
final class SuggestionListView: NSView {
    var onSelect: ((Int) -> Void)?
    var onAccept: ((Int) -> Void)?

    private(set) var items: [SuggestionItem] = []
    private var selectedIndex = 0
    private var mouseDownIndex: Int?
    private var trackingArea: NSTrackingArea?

    var rowHeight: CGFloat = 24
    var selectionInset: CGFloat = 1
    var titleLeading: CGFloat = 5
    var titleTrailing: CGFloat = 7
    var iconLeading: CGFloat = 4
    var iconWidth: CGFloat = 15
    var iconTitleGap: CGFloat = 5
    var titleFont: NSFont = .systemFont(ofSize: 12, weight: .semibold)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func update(items: [SuggestionItem], selectedIndex: Int, width: CGFloat) {
        self.items = items
        self.selectedIndex = selectedIndex
        frame.size = NSSize(width: width, height: CGFloat(items.count) * rowHeight)
        needsDisplay = true
    }

    func setSelectedIndex(_ index: Int) {
        guard selectedIndex != index else { return }
        selectedIndex = index
        needsDisplay = true
    }

    func rectForRow(at index: Int) -> NSRect {
        NSRect(
            x: 0,
            y: CGFloat(index) * rowHeight,
            width: bounds.width,
            height: rowHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !items.isEmpty else { return }

        for index in items.indices {
            let rowRect = rectForRow(at: index)
            guard dirtyRect.intersects(rowRect) else { continue }
            draw(item: items[index], in: rowRect, selected: index == selectedIndex)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let index = rowIndex(for: event) else { return }
        onSelect?(index)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownIndex = rowIndex(for: event)
        if let mouseDownIndex {
            onSelect?(mouseDownIndex)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let mouseDownIndex, rowIndex(for: event) == mouseDownIndex else {
            self.mouseDownIndex = nil
            return
        }
        self.mouseDownIndex = nil
        onAccept?(mouseDownIndex)
    }

    private func rowIndex(for event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(floor(point.y / max(rowHeight, 1)))
        return items.indices.contains(index) ? index : nil
    }

    private func draw(item: SuggestionItem, in rowRect: NSRect, selected: Bool) {
        if selected {
            let selectedRect = rowRect.insetBy(dx: selectionInset, dy: 1)
            let path = NSBezierPath(roundedRect: selectedRect, xRadius: 5, yRadius: 5)
            NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
            path.fill()
            NSColor(calibratedWhite: 0.28, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let hasIcon = item.symbolName != nil
        let textX = hasIcon ? iconLeading + iconWidth + iconTitleGap : titleLeading
        if let symbolName = item.symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) {
            let iconRect = NSRect(
                x: iconLeading,
                y: rowRect.midY - (iconWidth / 2) - 1,
                width: iconWidth,
                height: iconWidth
            )
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: selected ? 0.95 : 0.72)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: panelPrimaryTextColor(),
            .paragraphStyle: paragraphStyle
        ]
        let titleHeight = ceil(titleFont.boundingRectForFont.height) + 2
        let titleRect = NSRect(
            x: textX,
            y: rowRect.midY - (titleHeight / 2) - 1,
            width: max(rowRect.width - textX - titleTrailing, 1),
            height: titleHeight
        )
        (item.title as NSString).draw(in: titleRect, withAttributes: attributes)
    }
}

@MainActor
final class SuggestionPopoverController: NSViewController {
    private enum Metrics {
        static let rowHeight: CGFloat = 24
        static let outerInset: CGFloat = 0
        static let maxHeight: CGFloat = 120
        static let selectionInset: CGFloat = 1
        static let iconLeading: CGFloat = 4
        static let iconWidth: CGFloat = 15
        static let iconTitleGap: CGFloat = 5
        static let titleLeading: CGFloat = 5
        static let titleTrailing: CGFloat = 7
        static let fallbackWidth: CGFloat = 64
        static let maxWidth: CGFloat = 180
        static func titleFont() -> NSFont { .systemFont(ofSize: 12, weight: .semibold) }
    }

    var onSelect: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let listView = SuggestionListView()
    private var items: [SuggestionItem] = []
    private(set) var selectedIndex = 0
    private(set) var contentWidth: CGFloat = Metrics.fallbackWidth

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.fallbackWidth, height: Metrics.maxHeight))
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        view.layer?.borderWidth = 0
        view.layer?.borderColor = NSColor.clear.cgColor

        listView.rowHeight = Metrics.rowHeight
        listView.selectionInset = Metrics.selectionInset
        listView.titleLeading = Metrics.titleLeading
        listView.titleTrailing = Metrics.titleTrailing
        listView.iconLeading = Metrics.iconLeading
        listView.iconWidth = Metrics.iconWidth
        listView.iconTitleGap = Metrics.iconTitleGap
        listView.titleFont = Metrics.titleFont()
        listView.onSelect = { [weak self] index in self?.selectRow(at: index) }
        listView.onAccept = { [weak self] index in
            self?.selectRow(at: index)
            self?.acceptSelection()
        }

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .legacy
        scrollView.documentView = listView

        view.addSubview(scrollView)
        pin(scrollView, to: view, insets: .init(
            top: Metrics.outerInset,
            left: Metrics.outerInset,
            bottom: Metrics.outerInset,
            right: Metrics.outerInset
        ))
    }

    func updateItems(_ items: [SuggestionItem]) {
        self.items = items
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
        contentWidth = preferredContentWidth(for: items)
        scrollView.hasVerticalScroller = false
        listView.update(items: items, selectedIndex: selectedIndex, width: contentWidth)
        preferredContentSize = NSSize(
            width: contentWidth,
            height: min(
                CGFloat(max(items.count, 1)) * Metrics.rowHeight + (Metrics.outerInset * 2),
                Metrics.maxHeight
            )
        )
        selectRow(at: selectedIndex)
    }

    private func preferredContentWidth(for items: [SuggestionItem]) -> CGFloat {
        let maxTitleWidth = items
            .map { ceil(($0.title as NSString).size(withAttributes: [.font: Metrics.titleFont()]).width) }
            .max() ?? 0
        let leadingSpace = items.contains { $0.symbolName != nil }
            ? Metrics.iconLeading + Metrics.iconWidth + Metrics.iconTitleGap
            : Metrics.titleLeading
        let horizontalPadding = leadingSpace + Metrics.titleTrailing
        let contentWidth = maxTitleWidth + horizontalPadding
        return min(max(ceil(contentWidth), Metrics.fallbackWidth), Metrics.maxWidth)
    }

    func moveSelection(delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
        selectRow(at: selectedIndex)
    }

    func acceptSelection() {
        guard items.indices.contains(selectedIndex) else { return }
        onSelect?(selectedIndex)
    }

    private func selectRow(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        listView.setSelectedIndex(index)
        listView.scrollToVisible(listView.rectForRow(at: index))
    }
}

@MainActor
func caretRectInWindow(for textView: NSTextView, at location: Int? = nil) -> NSRect {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
        return textView.bounds
    }

    let selectedRange = textView.selectedRange()
    layoutManager.ensureLayout(for: textContainer)
    let characterLocation = min(
        max(location ?? selectedRange.location, 0),
        textView.string.utf16.count
    )
    let glyphIndex = characterLocation >= textView.string.utf16.count
        ? layoutManager.numberOfGlyphs
        : layoutManager.glyphIndexForCharacter(at: characterLocation)
    var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 0), in: textContainer)
    rect.origin.x += textView.textContainerInset.width
    rect.origin.y += textView.textContainerInset.height
    return rect.insetBy(dx: -4, dy: -4)
}
