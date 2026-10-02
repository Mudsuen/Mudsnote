import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

@MainActor
final class LibraryGroupHeaderCellView: NSTableCellView {
    static let titleLeadingInset: CGFloat = 16
    static let titleTrailingInset: CGFloat = 10
    static let firstTitleBottomInset: CGFloat = 6
    static let followingTitleBottomInset: CGFloat = 6

    let titleLabel = NSTextField(labelWithString: "")
    private var titleBottomConstraint: NSLayoutConstraint?

    var isFirstGroup = true {
        didSet {
            titleBottomConstraint?.constant = -titleBottomInset
        }
    }

    var titleBottomInset: CGFloat {
        isFirstGroup ? Self.firstTitleBottomInset : Self.followingTitleBottomInset
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(
            ofSize: LibraryNotesLayout.noteGroupFontSize,
            weight: LibraryNotesLayout.noteGroupFontWeight
        )
        titleLabel.textColor = panelSecondaryTextColor()
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let titleBottomConstraint = titleLabel.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -titleBottomInset
        )
        self.titleBottomConstraint = titleBottomConstraint
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.titleLeadingInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.titleTrailingInset),
            titleBottomConstraint
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class LibraryNoteCellView: NSTableCellView {
    static let contentTopInset: CGFloat = 4.5
    static let contentLeadingInset: CGFloat = 16
    static let contentBottomInset: CGFloat = 7.5
    static let contentTrailingInset: CGFloat = 18
    static let selectionTextTrailingPadding: CGFloat = 10
    static let stackTextTrailingAdjustment: CGFloat = 2
    static let minimumTextWidth: CGFloat = 40
    static let textRowSpacing: CGFloat = 2.5

    let titleLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(labelWithString: "")
    let metaLabel = NSTextField(labelWithString: "")
    let folderImageView = NSImageView()
    let attachmentImageView = NSImageView()
    let thumbnailImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(
            ofSize: LibraryNotesLayout.noteTitleFontSize,
            weight: LibraryNotesLayout.noteTitleFontWeight
        )
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.alignment = .left
        titleLabel.textColor = panelPrimaryTextColor()

        snippetLabel.font = .systemFont(
            ofSize: LibraryNotesLayout.noteSnippetFontSize,
            weight: LibraryNotesLayout.noteSnippetFontWeight
        )
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.maximumNumberOfLines = 1
        snippetLabel.alignment = .left
        snippetLabel.textColor = panelSecondaryTextColor()

        metaLabel.font = .systemFont(
            ofSize: LibraryNotesLayout.noteMetaFontSize,
            weight: LibraryNotesLayout.noteMetaFontWeight
        )
        metaLabel.lineBreakMode = .byTruncatingMiddle
        metaLabel.maximumNumberOfLines = 1
        metaLabel.alignment = .left
        metaLabel.textColor = panelTertiaryTextColor()

        folderImageView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteFolderIndicator")
        folderImageView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "文件夹")
        folderImageView.contentTintColor = panelTertiaryTextColor()
        folderImageView.imageScaling = .scaleProportionallyDown

        attachmentImageView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteAttachmentIndicator")
        attachmentImageView.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "有附件")
        attachmentImageView.contentTintColor = panelTertiaryTextColor()
        attachmentImageView.imageScaling = .scaleProportionallyDown
        attachmentImageView.isHidden = true

        thumbnailImageView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteThumbnailImage")
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.wantsLayer = true
        thumbnailImageView.layer?.cornerRadius = 6
        thumbnailImageView.layer?.masksToBounds = true
        thumbnailImageView.layer?.borderWidth = 1
        thumbnailImageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        thumbnailImageView.isHidden = true

        let metaRow = NSStackView(views: [folderImageView, metaLabel, attachmentImageView])
        metaRow.orientation = .horizontal
        metaRow.alignment = .centerY
        metaRow.spacing = 4

        let textStack = NSStackView(views: [titleLabel, snippetLabel, metaRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = Self.textRowSpacing
        textStack.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [titleLabel, snippetLabel, metaLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let stack = NSStackView(views: [textStack, thumbnailImageView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(
            top: Self.contentTopInset,
            left: Self.contentLeadingInset,
            bottom: Self.contentBottomInset,
            right: Self.contentTrailingInset
        )
        addSubview(stack)
        pin(stack, to: self)
        for label in [titleLabel, snippetLabel] {
            label.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        }
        textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumTextWidth).isActive = true
        metaRow.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        folderImageView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        folderImageView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        attachmentImageView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        attachmentImageView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        thumbnailImageView.widthAnchor.constraint(equalToConstant: 44).isActive = true
        thumbnailImageView.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class LibraryNoteRowView: NSTableRowView {
    static let selectionLeadingInset: CGFloat = 6
    static let selectionTrailingInset: CGFloat = 6
    static let selectionTopInset: CGFloat = 6
    static let selectionBottomInset: CGFloat = 4
    static let selectionCornerRadius: CGFloat = 8
    static var selectionFillColor = LibrarySourceSelectionPalette.noteBackgroundColor
    static let hoverLeadingInset: CGFloat = selectionLeadingInset
    static let hoverTrailingInset: CGFloat = selectionTrailingInset
    static let hoverVerticalInset: CGFloat = 3
    static let hoverCornerRadius: CGFloat = 8
    static let hoverFillColor = NSColor(calibratedWhite: 0.22, alpha: 0.24)
    static let separatorLeadingInset: CGFloat = 18
    static let separatorTrailingInset: CGFloat = 16
    static let separatorAlpha: CGFloat = 0.28

    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isPointerHovered = false

    var isGroupRow = false {
        didSet {
            if isGroupRow {
                setPointerHovered(false)
            }
            updateTrackingAreas()
        }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }
        super.updateTrackingAreas()
        guard !isGroupRow else { return }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        noteTableView?.setPointerHoveredRow(self)
    }

    override func mouseExited(with event: NSEvent) {
        guard noteTableView?.pointerHoveredRow === self else {
            setPointerHovered(false)
            return
        }
        noteTableView?.setPointerHoveredRow(nil)
    }

    func setPointerHovered(_ hovered: Bool) {
        let nextValue = isGroupRow ? false : hovered
        guard isPointerHovered != nextValue else { return }
        isPointerHovered = nextValue
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard !isGroupRow else { return }

        if !isSelected {
            let y = bounds.minY + 0.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: Self.separatorLeadingInset, y: y))
            path.line(to: NSPoint(
                x: max(Self.separatorLeadingInset, bounds.maxX - Self.separatorTrailingInset),
                y: y
            ))
            panelSeparatorColor(alpha: Self.separatorAlpha).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        guard isPointerHovered, !isSelected else { return }

        let hoverRect = insetRect(
            leading: Self.hoverLeadingInset,
            trailing: Self.hoverTrailingInset,
            top: Self.hoverVerticalInset,
            bottom: Self.hoverVerticalInset
        )
        let path = NSBezierPath(
            roundedRect: hoverRect,
            xRadius: Self.hoverCornerRadius,
            yRadius: Self.hoverCornerRadius
        )
        Self.hoverFillColor.setFill()
        path.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard !isGroupRow else { return }
        let selectionRect = insetRect(
            leading: Self.selectionLeadingInset,
            trailing: Self.selectionTrailingInset,
            top: Self.selectionTopInset,
            bottom: Self.selectionBottomInset
        )
        let path = NSBezierPath(
            roundedRect: selectionRect,
            xRadius: Self.selectionCornerRadius,
            yRadius: Self.selectionCornerRadius
        )
        Self.selectionFillColor.setFill()
        path.fill()
    }

    private func insetRect(
        leading: CGFloat,
        trailing: CGFloat,
        top: CGFloat,
        bottom: CGFloat
    ) -> NSRect {
        NSRect(
            x: bounds.minX + leading,
            y: bounds.minY + bottom,
            width: max(0, bounds.width - leading - trailing),
            height: max(0, bounds.height - top - bottom)
        )
    }

    private var noteTableView: LibraryNoteTableView? {
        var candidate = superview
        while let view = candidate {
            if let tableView = view as? LibraryNoteTableView {
                return tableView
            }
            candidate = view.superview
        }
        return nil
    }
}

enum LibraryNoteKeyCommand {
    case open
    case delete
    case moveDown
    case moveUp
}

@MainActor
final class LibraryNoteTableView: NSTableView {
    var onKeyCommand: ((LibraryNoteKeyCommand) -> Bool)?
    var onContextMenu: ((Int) -> NSMenu?)?
    private(set) weak var pointerHoveredRow: LibraryNoteRowView?

    func setPointerHoveredRow(_ rowView: LibraryNoteRowView?) {
        let nextRow = rowView?.isGroupRow == false ? rowView : nil
        guard pointerHoveredRow !== nextRow else {
            nextRow?.setPointerHovered(true)
            return
        }
        pointerHoveredRow?.setPointerHovered(false)
        pointerHoveredRow = nextRow
        nextRow?.setPointerHovered(true)
    }

    func reconcilePointerHover(at location: NSPoint?) {
        guard let location, visibleRect.contains(location) else {
            setPointerHoveredRow(nil)
            return
        }
        let row = row(at: location)
        guard row >= 0,
              let rowView = rowView(atRow: row, makeIfNecessary: false) as? LibraryNoteRowView else {
            setPointerHoveredRow(nil)
            return
        }
        setPointerHoveredRow(rowView)
    }

    func reconcilePointerHover() {
        guard let window, window.isKeyWindow else {
            setPointerHoveredRow(nil)
            return
        }
        reconcilePointerHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
            super.keyDown(with: event)
            return
        }

        let command: LibraryNoteKeyCommand?
        switch event.keyCode {
        case 36, 76:
            command = .open
        case 51, 117:
            command = .delete
        case 125:
            command = .moveDown
        case 126:
            command = .moveUp
        default:
            command = nil
        }

        if let command, onKeyCommand?(command) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        return onContextMenu?(row(at: location)) ?? super.menu(for: event)
    }
}

@MainActor
final class LibraryNoteScrollView: NSScrollView {
    static func suppressesHorizontalScroll(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        let horizontalMagnitude = abs(deltaX)
        return horizontalMagnitude > 0 && horizontalMagnitude >= abs(deltaY)
    }

    override func scrollWheel(with event: NSEvent) {
        guard !Self.suppressesHorizontalScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY
        ) else {
            contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y))
            reflectScrolledClipView(contentView)
            return
        }
        super.scrollWheel(with: event)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        (documentView as? LibraryNoteTableView)?.reconcilePointerHover()
    }

    override func layout() {
        super.layout()
        let targetWidth = max(LibraryNotesLayout.noteTableMinimumWidth, contentView.bounds.width)
        guard let tableView = documentView as? LibraryNoteTableView else { return }

        if let column = tableView.tableColumns.first,
           abs(column.width - targetWidth) > 0.5 {
            column.width = targetWidth
        }
        var frame = tableView.frame
        if abs(frame.origin.x) > 0.5 || abs(frame.width - targetWidth) > 0.5 {
            frame.origin.x = 0
            frame.size.width = targetWidth
            tableView.frame = frame
        }
    }
}

@MainActor
final class LibraryNoteClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        constrainedBounds.origin.x = 0
        return constrainedBounds
    }
}

@MainActor
final class LibraryEditorScrollView: NSScrollView {
    override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        if let relations = documentView?.subviews.first(where: { $0 is NoteLinksView }) {
            children.append(relations)
        }
        return children
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
            textView.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func tile() {
        super.tile()
        guard let verticalScroller else { return }
        var scrollerFrame = verticalScroller.frame
        scrollerFrame.origin.x = bounds.maxX - scrollerFrame.width
        verticalScroller.frame = scrollerFrame
    }
}
