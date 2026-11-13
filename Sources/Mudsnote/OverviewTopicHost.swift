import AppKit

@MainActor class OverviewTextLabel: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        attributedStringValue.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

@MainActor final class OverviewDescriptionLabel: OverviewTextLabel {
    var pressed: (() -> Void)?
    override func mouseDown(with event: NSEvent) { pressed?() }
}

@MainActor final class OverviewBulletButton: NSButton {
    var invoke: (() -> Void)?
    var beginDrag: ((NSEvent, NSEvent) -> Void)?
    var collapsed = false
    var dotColor = NSColor.gray
    var ringColor = NSColor.clear
    init() {
        super.init(frame: .zero)
        isBordered = false; title = ""; target = self; action = #selector(pressed)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
    override func mouseDown(with event: NSEvent) {
        guard let beginDrag else { super.mouseDown(with: event); return }
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { invoke?(); return }
            if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) > 4 {
                beginDrag(next, event); return
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if collapsed {
            ringColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)).fill()
        }
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
    }
}

/// One tracking surface includes the text and its gutter actions. Crossing from
/// a topic to its fold/More/child button must not make the action disappear.
@MainActor final class OverviewTopicHost: NSView {
    override var isFlipped: Bool { true }
    let node: OverviewNodeID
    let content: NSView
    let detail = OverviewDescriptionLabel(wrappingLabelWithString: "")
    let bullet = OverviewBulletButton()
    let fold = OverviewActionButton("", symbol: "chevron.down", action: {})
    let more = OverviewActionButton("", symbol: "ellipsis", action: {})
    let addChild = OverviewActionButton("", symbol: "plus.circle.fill", action: {})
    var contentRect = NSRect.zero
    var textRect = NSRect.zero
    var detailRect = NSRect.zero
    var map = true
    var depth = 1
    var side: CGFloat = 1
    var colors = OverviewColors(dark: true, mapStyle: .ink)
    var active = false
    var folded = false
    var hasChildren = false
    var childCount = 0
    var allowsChild = true
    var hovered = false
    var tracks: NSTrackingArea?
    var contextAction: (() -> Void)?

    init(node: OverviewNodeID, content: NSView) {
        self.node = node; self.content = content
        super.init(frame: .zero)
        addSubview(content)
        detail.maximumNumberOfLines = 0
        detail.font = OverviewTypography.font(14)
        detail.setAccessibilityElement(false)
        [detail, bullet, fold, more, addChild].forEach(addSubview)
        more.setAccessibilityLabel("主题操作")
        fold.setAccessibilityLabel("折叠主题")
        addChild.setAccessibilityLabel("添加子主题")
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(nodeFrame: NSRect, presentation: OverviewPresentation, depth: Int,
                   side: CGFloat, colors: OverviewColors, active: Bool, folded: Bool,
                   children: Int, details: String, allowsChild: Bool) {
        frame = nodeFrame.insetBy(dx: -44, dy: 0)
        contentRect = NSRect(x: 44, y: 0, width: nodeFrame.width, height: nodeFrame.height)
        map = presentation == .mindMap; self.depth = depth; self.side = side
        self.colors = colors; self.active = active; self.folded = folded
        hasChildren = children > 0; childCount = children; self.allowsChild = allowsChild
        let inset: CGFloat = map ? (depth == 0 ? 24 : depth == 1 ? 16 : 32) : (depth == 0 ? 0 : 31)
        let top: CGFloat = map ? (depth < 2 ? 12 : 11) : 0
        let detailWidth = max(1, contentRect.width - (map ? (depth == 0 ? 32 : inset * 2 + 10) : 31))
        let detailHeight = depth == 0 && !map ? 0 : OverviewTypography.detailHeight(details, width: detailWidth)
        let headingHeight = max(22, contentRect.height - detailHeight - top * 2)
        textRect = NSRect(x: contentRect.minX + inset, y: top,
                          width: max(1, contentRect.width - (map ? inset * 2 : 31)), height: headingHeight)
        detailRect = NSRect(x: contentRect.minX + (map ? inset + 10 : 31),
                            y: map ? top + headingHeight : headingHeight,
                            width: max(1, contentRect.width - (map ? inset * 2 + 10 : 31)),
                            height: detailHeight)
        if content is OverviewCardView { content.frame = contentRect }
        else if content is OverviewRootTitle { content.frame = contentRect }
        else { content.frame = textRect }
        detail.stringValue = details
        detail.textColor = map ? colors.mapDetail : colors.detail
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 24; paragraph.maximumLineHeight = 24
        paragraph.lineBreakMode = .byWordWrapping
        detail.attributedStringValue = NSAttributedString(string: details, attributes: [.font: OverviewTypography.font(14, map: map), .foregroundColor: map ? colors.mapDetail : colors.detail, .paragraphStyle: paragraph])
        detail.frame = detailRect
        detail.isHidden = details.isEmpty || depth == 0
        bullet.frame = NSRect(x: contentRect.minX + 3, y: 31.6 / 2 - 9, width: 18, height: 18)
        bullet.collapsed = folded; bullet.dotColor = colors.bullet; bullet.ringColor = colors.guide
        bullet.isHidden = map || depth == 0
        let anchor = map && depth >= 2 ? contentRect.maxY : contentRect.midY
        fold.frame = map
            ? NSRect(x: side > 0 ? contentRect.maxX + 2 : contentRect.minX - 22, y: anchor - 10, width: 20, height: 20)
            : NSRect(x: contentRect.minX - 22, y: 31.6 / 2 - 9, width: 18, height: 18)
        fold.title = map && folded ? String(childCount) : ""
        fold.imagePosition = map && folded ? .noImage : .imageOnly
        fold.image = map && folded ? nil : NSImage(systemSymbolName: map ? "minus.circle" : folded ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: map ? 12 : 9, weight: .regular))
        fold.contentTintColor = map ? colors.mapLine : colors.detail
        fold.setAccessibilityLabel(folded ? "展开主题" : "折叠主题")
        more.frame = NSRect(x: contentRect.minX - 44, y: (map ? contentRect.midY : 15.8) - 9, width: 22, height: 18)
        more.contentTintColor = map ? colors.mapDetail : colors.detail
        addChild.frame = NSRect(x: side > 0 ? contentRect.maxX + 20 : contentRect.minX - 40, y: anchor - 11, width: 22, height: 22)
        addChild.contentTintColor = colors.mapLine
        updateActions()
        needsDisplay = true; bullet.needsDisplay = true
        updateTrackingAreas()
    }
    func updateActions() {
        fold.isHidden = depth == 0 || !hasChildren
        more.isHidden = map || (!hovered && !active) || depth == 0
        addChild.isHidden = !map || !allowsChild || (!hovered && !active)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracks { removeTrackingArea(tracks) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); tracks = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateActions() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateActions() }
    override func rightMouseDown(with event: NSEvent) { contextAction?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard !isHidden, bounds.contains(p) else { return nil }
        for button in [addChild, fold, more, bullet] where !button.isHidden && button.frame.contains(p) { return button }
        for control in subviews.reversed().compactMap({ $0 as? NSControl }) where !control.isHidden && control.frame.contains(p) { return control }
        guard contentRect.contains(p) else { return nil }
        return super.hitTest(point)
    }
    override func draw(_ dirtyRect: NSRect) {
        if let card = content as? OverviewCardView, !card.isCompact { return }
        if map {
            if depth < 2 {
                (depth == 0 ? colors.mapRoot : colors.mapTopic).setFill()
                NSBezierPath(roundedRect: contentRect, xRadius: depth == 0 ? 14 : 10, yRadius: depth == 0 ? 14 : 10).fill()
            }
            if active && depth > 0 {
                colors.mapLine.setStroke()
                let path = NSBezierPath(roundedRect: contentRect.insetBy(dx: 0.75, dy: 0.75), xRadius: 14, yRadius: 14)
                path.lineWidth = 1.5; path.stroke()
            } else if depth >= 2 {
                colors.mapLine.setFill()
                NSRect(x: contentRect.minX, y: contentRect.maxY - 2, width: contentRect.width, height: 2).fill()
            }
            if !detail.isHidden {
                colors.mapDetail.withAlphaComponent(0.7).setFill()
                NSRect(x: detailRect.minX - 10, y: detailRect.minY + 3, width: 1, height: max(0, detailRect.height - 6)).fill()
            }
        } else if !detail.isHidden {
            colors.guide.setFill()
            NSRect(x: contentRect.minX + 11.5, y: textRect.maxY, width: 1, height: max(0, contentRect.height - textRect.maxY)).fill()
        }
    }
}
