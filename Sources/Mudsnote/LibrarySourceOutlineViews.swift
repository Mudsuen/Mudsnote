import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

@MainActor
final class LibrarySourceOutlineItem: NSObject {
    enum Kind {
        case group(title: String, section: LibrarySourceSection?)
        case scope(LibraryScope)
        case note(NoteSearchResult)
        case status(String)
        case inlineFolderEdit(InlineFolderEditOperation)
    }

    let identifier: String
    let kind: Kind
    weak var parent: LibrarySourceOutlineItem?
    var children: [LibrarySourceOutlineItem] = []
    var count: Int?

    init(identifier: String, kind: Kind) {
        self.identifier = identifier
        self.kind = kind
    }

    func append(_ child: LibrarySourceOutlineItem) {
        child.parent = self
        children.append(child)
    }

    var scope: LibraryScope? {
        guard case .scope(let scope) = kind else { return nil }
        return scope
    }

    var note: NoteSearchResult? {
        guard case .note(let note) = kind else { return nil }
        return note
    }
}

@MainActor
final class LibrarySourceOutlineView: NSOutlineView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var onNoteKeyCommand: ((LibraryNoteKeyCommand) -> Bool)?
    var onPrimaryMouseSelectionPreviewChanged: (() -> Void)?
    var onPrimaryMouseSelectionCommitted: (() -> Void)?
    private(set) weak var pointerHoveredRow: LibrarySourceOutlineRowView?
    private(set) var isDeferringPrimaryMouseSelectionCommit = false
    private(set) var primaryMouseVisualSelectionRow: Int?
    private var selectionBeforePrimaryMouseDown = IndexSet()

    override func expandItem(_ item: Any?, expandChildren: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            super.expandItem(item, expandChildren: expandChildren)
        }
    }

    override func collapseItem(_ item: Any?, collapseChildren: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            super.collapseItem(item, collapseChildren: collapseChildren)
        }
    }

    func setPointerHoveredRow(_ rowView: LibrarySourceOutlineRowView?) {
        guard pointerHoveredRow !== rowView else {
            rowView?.setPointerHovered(true)
            return
        }
        pointerHoveredRow?.setPointerHovered(false)
        pointerHoveredRow = rowView
        rowView?.setPointerHovered(true)
    }

    func reconcilePointerHover(at location: NSPoint?) {
        guard let location, visibleRect.contains(location) else {
            setPointerHoveredRow(nil)
            return
        }
        let row = row(at: location)
        guard row >= 0,
              let rowView = rowView(atRow: row, makeIfNecessary: false)
                as? LibrarySourceOutlineRowView else {
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

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            super.mouseDown(with: event)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let pressedRow = row(at: location)
        let hitView = hitTest(location)
        let previewsSelectableRow = pressedRow >= 0
            && !(hitView is NSButton)
            && (item(atRow: pressedRow) as? LibrarySourceOutlineItem)?.scope != nil
        beginPrimaryMouseSelectionDeferral(
            visualSelectionRow: previewsSelectableRow ? pressedRow : selectedRow
        )
        super.mouseDown(with: event)
        finishPrimaryMouseSelectionDeferral()
    }

    func beginPrimaryMouseSelectionDeferral(visualSelectionRow: Int? = nil) {
        selectionBeforePrimaryMouseDown = selectedRowIndexes
        isDeferringPrimaryMouseSelectionCommit = true
        primaryMouseVisualSelectionRow = visualSelectionRow
    }

    func finishPrimaryMouseSelectionDeferral() {
        let shouldCommit = isDeferringPrimaryMouseSelectionCommit
            && selectedRowIndexes != selectionBeforePrimaryMouseDown
        isDeferringPrimaryMouseSelectionCommit = false
        primaryMouseVisualSelectionRow = nil
        selectionBeforePrimaryMouseDown = []
        onPrimaryMouseSelectionPreviewChanged?()
        if shouldCommit {
            onPrimaryMouseSelectionCommitted?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           (item(atRow: selectedRow) as? LibrarySourceOutlineItem)?.note != nil {
            let command: LibraryNoteKeyCommand? = switch event.keyCode {
            case 36, 76: .open
            case 51, 117: .delete
            default: nil
            }
            if let command, onNoteKeyCommand?(command) == true { return }
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: location)
        guard clickedRow >= 0 else { return nil }
        if !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return contextMenuProvider?(clickedRow)
    }
}

@MainActor
final class LibrarySourceOutlineCellView: NSTableCellView {
    let countLabel = NSTextField(labelWithString: "")
    var accessibilityPressHandler: (() -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let title = NSTextField(labelWithString: "")
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false
        textField = title

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        imageView = icon

        countLabel.setAccessibilityElement(false)
        countLabel.font = .systemFont(ofSize: LibraryNotesLayout.sourceCountFontSize, weight: .regular)
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(icon)
        addSubview(title)
        addSubview(countLabel)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: LibraryNotesLayout.sourceCellContentLeadingInset
            ),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceIconWidth),
            icon.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceIconHeight),
            title.leadingAnchor.constraint(
                equalTo: icon.trailingAnchor,
                constant: LibraryNotesLayout.sourceIconTitleSpacing
            ),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -6),
            countLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -LibraryNotesLayout.sourceCountTrailingInset
            ),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceCountWidth)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityPerformPress() -> Bool {
        accessibilityPressHandler?() ?? super.accessibilityPerformPress()
    }
}

@MainActor
final class LibrarySourceOutlineRowView: NSTableRowView {
    static let hoverColor = NSColor(calibratedWhite: 0.20, alpha: 0.52)
    static let dropTargetColor = NSColor.systemYellow.withAlphaComponent(0.24)
    static let dropTargetBorderColor = NSColor.systemYellow.withAlphaComponent(0.88)
    static let leadingInset: CGFloat = LibraryNotesLayout.sourceRowHighlightLeadingInset
    static let trailingInset: CGFloat = LibraryNotesLayout.sourceRowHighlightTrailingInset
    static let verticalInset: CGFloat = LibraryNotesLayout.sourceRowHighlightVerticalInset
    private var trackingAreaForHover: NSTrackingArea?
    private(set) var isPointerHovered = false
    private(set) var isVisuallySelected = false
    private(set) var dropTargetFeedbackDrawCountForLibrary = 0

    override func updateTrackingAreas() {
        if let trackingAreaForHover {
            removeTrackingArea(trackingAreaForHover)
        }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaForHover = area
    }

    override func mouseEntered(with event: NSEvent) {
        sourceOutlineView?.setPointerHoveredRow(self)
    }

    override func mouseExited(with event: NSEvent) {
        guard sourceOutlineView?.pointerHoveredRow === self else {
            setPointerHovered(false)
            return
        }
        sourceOutlineView?.setPointerHoveredRow(nil)
    }

    func setPointerHovered(_ hovered: Bool) {
        guard isPointerHovered != hovered else { return }
        isPointerHovered = hovered
        needsDisplay = true
    }

    func setVisuallySelected(_ selected: Bool) {
        guard isVisuallySelected != selected else { return }
        isVisuallySelected = selected
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isVisuallySelected {
            LibrarySourceSelectionPalette.backgroundColor.setFill()
        } else if isPointerHovered {
            Self.hoverColor.setFill()
        } else {
            return
        }
        NSBezierPath(
            roundedRect: highlightBounds,
            xRadius: LibraryNotesLayout.sourceRowCornerRadius,
            yRadius: LibraryNotesLayout.sourceRowCornerRadius
        ).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // The row background uses the immediate preview selection so its
        // appearance stays in sync with the icon and title while clicking.
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        dropTargetFeedbackDrawCountForLibrary += 1
        let path = NSBezierPath(
            roundedRect: highlightBounds,
            xRadius: LibraryNotesLayout.sourceRowCornerRadius,
            yRadius: LibraryNotesLayout.sourceRowCornerRadius
        )
        Self.dropTargetColor.setFill()
        path.fill()
        path.lineWidth = 2
        Self.dropTargetBorderColor.setStroke()
        path.stroke()
    }

    private var highlightBounds: NSRect {
        NSRect(
            x: bounds.minX + Self.leadingInset,
            y: bounds.minY + Self.verticalInset,
            width: max(0, bounds.width - Self.leadingInset - Self.trailingInset),
            height: max(0, bounds.height - (Self.verticalInset * 2))
        )
    }

    private var sourceOutlineView: LibrarySourceOutlineView? {
        var candidate = superview
        while let view = candidate {
            if let outlineView = view as? LibrarySourceOutlineView {
                return outlineView
            }
            candidate = view.superview
        }
        return nil
    }
}

@MainActor
final class LibrarySourceScrollView: NSScrollView {
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        (documentView as? LibrarySourceOutlineView)?.reconcilePointerHover()
    }
}

@MainActor
final class LibraryPassthroughTintView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
