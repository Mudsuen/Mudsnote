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
    var isNote = false { didSet { if oldValue != isNote { syncAppearance() } } }
    var collapsed = false
    var dotColor = NSColor.gray { didSet { if oldValue != dotColor { syncAppearance() } } }
    var hoverDotColor = NSColor.labelColor { didSet { if oldValue != hoverDotColor { syncAppearance() } } }
    private(set) var isPointerHovered = false

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        target = self
        action = #selector(pressed)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }

    override func mouseEntered(with event: NSEvent) {
        guard !isPointerHovered else { return }
        isPointerHovered = true
        syncAppearance()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard isPointerHovered else { return }
        isPointerHovered = false
        syncAppearance()
        needsDisplay = true
    }

    func syncAppearance() {
        if isNote {
            image = OverviewTypography.symbol("doc.text", pointSize: 12, weight: .regular)
            contentTintColor = isPointerHovered ? hoverDotColor : dotColor
        } else {
            image = nil
        }
        needsDisplay = true
    }

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
        if isPointerHovered {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            if isNote {
                NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).fill()
            } else {
                NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
            }
        }
        if isNote {
            super.draw(dirtyRect)
            return
        }
        (isPointerHovered ? hoverDotColor : dotColor).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
    }
}

/// One tracking surface includes the text and its row actions so crossing from
/// a topic to its disclosure chevron, node icon, or trailing actions keeps them visible.
@MainActor final class OverviewTopicHost: NSView {
    static let outlineChevronWidth: CGFloat = 16
    static let outlineIconX: CGFloat = 16
    static let outlineIconSize: CGFloat = 18
    /// Vertical guide line drops straight down from the center of the node icon (16 + 9 = 25).
    /// With 28pt child indentation, parent guide sits at child.minX - 3, clearing child's chevron.
    static let outlineGuideCenterX: CGFloat = 25
    static let outlineTextInset: CGFloat = 38

    override var isFlipped: Bool { true }
    let node: OverviewNodeID
    let content: NSView
    let detail = OverviewDescriptionLabel(wrappingLabelWithString: "")
    let bullet = OverviewBulletButton()
    let fold = OverviewActionButton("", symbol: "chevron.down", action: {})
    let trailingBackdrop = NSView()
    let more = OverviewActionButton("", symbol: "ellipsis", action: {})
    let deleteButton = OverviewActionButton("", symbol: "trash", action: {})
    let addChild = OverviewActionButton("", symbol: "plus", action: {})
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
    var allowsDelete = false
    var isEditingInline = false
    var hovered = false
    var contextAction: (() -> Void)?

    private var lastDetailsText = ""
    private var lastDetailsDark = false
    private var lastDetailsMap = false
    private var lastFoldSymbolKey = ""
    private var lastAddChildMap: Bool?

    init(node: OverviewNodeID, content: NSView) {
        self.node = node
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
        detail.maximumNumberOfLines = 0
        detail.font = OverviewTypography.font(14)
        detail.setAccessibilityElement(false)
        trailingBackdrop.wantsLayer = true
        trailingBackdrop.layer?.cornerRadius = 6
        trailingBackdrop.isHidden = true
        [detail, bullet, fold, trailingBackdrop, addChild, deleteButton, more].forEach(addSubview)
        fold.setAccessibilityLabel("折叠主题")
        more.setAccessibilityLabel("更多操作")
        more.toolTip = "更多操作"
        deleteButton.setAccessibilityLabel("删除")
        addChild.setAccessibilityLabel("添加子主题")
        addChild.toolTip = "添加子主题"
        if case .card = node {
            bullet.isNote = true
            deleteButton.setAccessibilityLabel("删除笔记")
            deleteButton.toolTip = "删除笔记"
        } else if case .area = node {
            deleteButton.setAccessibilityLabel("删除主题")
            deleteButton.toolTip = "删除主题"
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        nodeFrame: NSRect,
        presentation: OverviewPresentation,
        depth: Int,
        side: CGFloat,
        colors: OverviewColors,
        active: Bool,
        folded: Bool,
        children: Int,
        details: String,
        allowsChild: Bool,
        isEditingInline: Bool = false,
        frameOnly: Bool = false
    ) {
        let isMap = presentation == .mindMap
        let newFrame = isMap ? nodeFrame.insetBy(dx: -44, dy: 0) : nodeFrame
        let oldContentRect = contentRect
        let newContentRect = isMap
            ? NSRect(x: 44, y: 0, width: nodeFrame.width, height: nodeFrame.height)
            : NSRect(x: 0, y: 0, width: nodeFrame.width, height: nodeFrame.height)

        frame = newFrame
        contentRect = newContentRect
        map = isMap
        self.depth = depth
        self.side = side
        self.colors = colors
        self.active = active
        self.folded = folded
        hasChildren = children > 0
        childCount = children
        self.allowsChild = allowsChild
        self.allowsDelete = {
            switch node {
            case .area, .card: return depth > 0
            case .root, .unassigned: return false
            }
        }()
        self.isEditingInline = isEditingInline

        let inset: CGFloat = isMap ? (depth == 0 ? 24 : depth == 1 ? 16 : 32) : (depth == 0 ? 0 : Self.outlineTextInset)
        let top: CGFloat = isMap ? (depth < 2 ? 12 : 11) : 0
        let detailWidth = max(1, contentRect.width - (isMap ? (depth == 0 ? 32 : inset * 2 + 10) : Self.outlineTextInset))
        let detailHeight = depth == 0 && !isMap ? 0 : OverviewTypography.detailHeight(details, width: detailWidth)
        let headingHeight = max(22, contentRect.height - detailHeight - top * 2)
        textRect = NSRect(
            x: contentRect.minX + inset,
            y: top,
            width: max(1, contentRect.width - (isMap ? inset * 2 : Self.outlineTextInset)),
            height: headingHeight
        )
        detailRect = NSRect(
            x: contentRect.minX + (isMap ? inset + 10 : Self.outlineTextInset),
            y: isMap ? top + headingHeight : headingHeight,
            width: max(1, contentRect.width - (isMap ? inset * 2 + 10 : Self.outlineTextInset)),
            height: detailHeight
        )

        if content is OverviewCardView || content is OverviewRootTitle {
            content.frame = contentRect
        } else {
            content.frame = textRect
        }

        if !frameOnly {
            if lastDetailsText != details || lastDetailsDark != colors.dark || lastDetailsMap != isMap {
                lastDetailsText = details
                lastDetailsDark = colors.dark
                lastDetailsMap = isMap
                detail.stringValue = details
                let detailColor = isMap ? colors.mapDetail : colors.detail
                detail.textColor = detailColor
                if !details.isEmpty {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.minimumLineHeight = 24
                    paragraph.maximumLineHeight = 24
                    paragraph.lineBreakMode = .byWordWrapping
                    detail.attributedStringValue = NSAttributedString(
                        string: details,
                        attributes: [
                            .font: OverviewTypography.font(14, map: isMap),
                            .foregroundColor: detailColor,
                            .paragraphStyle: paragraph
                        ]
                    )
                }
            }
            detail.isHidden = details.isEmpty || depth == 0
        }
        detail.frame = detailRect

        // Left-side 2-slot outline gutter: [chevron 0..16] [node icon 16..34] [text 38..]
        bullet.frame = NSRect(
            x: contentRect.minX + Self.outlineIconX,
            y: 31.6 / 2 - Self.outlineIconSize / 2,
            width: Self.outlineIconSize,
            height: Self.outlineIconSize
        )
        bullet.collapsed = folded
        bullet.dotColor = bullet.isNote ? colors.detail : colors.bullet
        bullet.hoverDotColor = colors.text
        bullet.isHidden = isMap || depth == 0

        let anchor = isMap && depth >= 2 ? contentRect.maxY : contentRect.midY
        fold.frame = isMap
            ? NSRect(x: side > 0 ? contentRect.maxX + 2 : contentRect.minX - 22, y: anchor - 10, width: 20, height: 20)
            : NSRect(x: contentRect.minX, y: 31.6 / 2 - 8, width: Self.outlineChevronWidth, height: 16)

        let foldKey = "\(isMap)|\(folded)|\(childCount)"
        if lastFoldSymbolKey != foldKey {
            lastFoldSymbolKey = foldKey
            fold.title = isMap && folded ? String(childCount) : ""
            fold.imagePosition = isMap && folded ? .noImage : .imageOnly
            fold.image = isMap && folded
                ? nil
                : OverviewTypography.symbol(
                    isMap ? "minus.circle" : (folded ? "chevron.right" : "chevron.down"),
                    pointSize: isMap ? 12 : 9,
                    weight: .medium
                )
            fold.setAccessibilityLabel(folded ? "展开主题" : "折叠主题")
        }
        fold.contentTintColor = isMap ? colors.mapLine : colors.detail

        if isMap {
            if lastAddChildMap != true {
                lastAddChildMap = true
                addChild.image = OverviewTypography.symbol("plus.circle.fill", pointSize: 14, weight: .regular)
            }
            addChild.frame = NSRect(
                x: side > 0 ? contentRect.maxX + 20 : contentRect.minX - 40,
                y: anchor - 11,
                width: 22,
                height: 22
            )
            addChild.contentTintColor = colors.mapLine
            more.frame = .zero
            deleteButton.frame = .zero
            trailingBackdrop.frame = .zero
        } else {
            if lastAddChildMap != false {
                lastAddChildMap = false
                addChild.image = OverviewTypography.symbol("plus", pointSize: 12, weight: .regular)
                deleteButton.image = OverviewTypography.symbol("trash", pointSize: 12, weight: .regular)
                more.image = OverviewTypography.symbol("ellipsis", pointSize: 12, weight: .regular)
            }
            let actionY: CGFloat = 31.6 / 2 - 11
            var trailingX = contentRect.maxX - 2
            trailingX -= 22
            more.frame = NSRect(x: trailingX, y: actionY, width: 22, height: 22)
            more.contentTintColor = colors.detail

            if allowsDelete {
                trailingX -= 24
                deleteButton.frame = NSRect(x: trailingX, y: actionY, width: 22, height: 22)
                deleteButton.contentTintColor = colors.detail
            } else {
                deleteButton.frame = .zero
            }

            if allowsChild {
                trailingX -= 24
                addChild.frame = NSRect(x: trailingX, y: actionY, width: 22, height: 22)
                addChild.contentTintColor = colors.detail
            } else {
                addChild.frame = .zero
            }

            let pillLeft = trailingX - 4
            trailingBackdrop.frame = NSRect(
                x: pillLeft,
                y: actionY - 1,
                width: contentRect.maxX - pillLeft,
                height: 24
            )
            trailingBackdrop.layer?.backgroundColor = colors.outlineBackground.withAlphaComponent(0.92).cgColor
        }

        updateActions()
        if !frameOnly || oldContentRect != newContentRect {
            needsDisplay = true
        }
    }

    func updateActions() {
        let cardHasInlineEditor = (content as? OverviewCardView)?.editor != nil
        if map {
            fold.isHidden = depth == 0 || !hasChildren
            more.isHidden = true
            deleteButton.isHidden = true
            trailingBackdrop.isHidden = true
            addChild.isHidden = !allowsChild || (!hovered && !active)
        } else {
            fold.isHidden = depth == 0 || !hasChildren || (!folded && !hovered && !active)
            let showTrailing = depth > 0 && (hovered || active) && !isEditingInline && !cardHasInlineEditor
            trailingBackdrop.isHidden = !showTrailing
            more.isHidden = !showTrailing
            deleteButton.isHidden = !showTrailing || !allowsDelete
            addChild.isHidden = !showTrailing || !allowsChild
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateActions()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateActions()
    }

    override func rightMouseDown(with event: NSEvent) { contextAction?() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard !isHidden, bounds.contains(p) else { return nil }
        for button in [more, deleteButton, addChild, fold, bullet] where !button.isHidden && button.frame.contains(p) {
            return button
        }
        for control in subviews.reversed().compactMap({ $0 as? NSControl }) where !control.isHidden && control.frame.contains(p) {
            return control
        }
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
                path.lineWidth = 1.5
                path.stroke()
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
            NSRect(
                x: contentRect.minX + Self.outlineGuideCenterX - 0.5,
                y: textRect.maxY,
                width: 1,
                height: max(0, contentRect.height - textRect.maxY)
            ).fill()
        }
    }
}
