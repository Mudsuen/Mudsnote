import AppKit
import Foundation
import MudsnoteCore
import UniformTypeIdentifiers

private enum LibraryScope: Equatable, Sendable {
    case all
    case recent
    case inbox
    case folder(URL)
    case tag(String)
    case trash

    var buttonTitle: String {
        switch self {
        case .all:
            return "所有笔记"
        case .recent:
            return "最近"
        case .inbox:
            return "Inbox"
        case .folder(let url):
            return url.lastPathComponent.isEmpty ? "Notes" : url.lastPathComponent
        case .tag(let tag):
            return libraryBareTag(tag)
        case .trash:
            return "最近删除"
        }
    }

    var listTitle: String {
        switch self {
        case .tag(let tag):
            return libraryDisplayTag(tag)
        default:
            return buttonTitle
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "folder"
        case .recent:
            return "clock"
        case .inbox:
            return "tray"
        case .folder:
            return "folder"
        case .tag:
            return "number"
        case .trash:
            return "trash"
        }
    }
}

private enum LibraryNoteListRow {
    case group(title: String)
    case note(NoteSearchResult)

    var note: NoteSearchResult? {
        guard case .note(let note) = self else { return nil }
        return note
    }
}

private func librarySearchResults(
    noteStore: NoteStore,
    scope: LibraryScope,
    query: String,
    limit: Int,
    searchesAllNotes: Bool
) -> [NoteSearchResult] {
    if searchesAllNotes {
        return noteStore.searchNotes(query: query, limit: limit)
    }

    switch scope {
    case .all, .recent:
        return noteStore.searchNotes(query: query, limit: limit)
    case .inbox:
        return noteStore.searchNotes(query: query, limit: limit).filter(libraryIsInboxNote)
    case .trash:
        return libraryFilteredTrashedNotes(noteStore: noteStore, query: query, limit: limit)
    case .folder(let url):
        return noteStore.searchNotes(query: query, limit: limit, roots: [url])
    case .tag(let tag):
        return noteStore.searchNotes(query: query, limit: limit).filter { note in
            note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }
    }
}

private func libraryFilteredTrashedNotes(noteStore: NoteStore, query: String, limit: Int) -> [NoteSearchResult] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return noteStore.listTrashedNotes(limit: limit) }

    return noteStore.listTrashedNotes(limit: limit).compactMap { note in
        guard let loaded = try? noteStore.loadNote(at: note.url) else {
            return note.title.localizedCaseInsensitiveContains(trimmedQuery) ? note : nil
        }

        let matchesTitle = loaded.title.localizedCaseInsensitiveContains(trimmedQuery)
        let matchingLine = loaded.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.localizedCaseInsensitiveContains(trimmedQuery) }
        let matchesTag = loaded.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        guard matchesTitle || matchingLine != nil || matchesTag else { return nil }

        return NoteSearchResult(
            url: note.url,
            title: loaded.title,
            snippet: matchingLine ?? libraryFirstMeaningfulLine(from: loaded.body) ?? "",
            modifiedAt: note.modifiedAt,
            tags: loaded.tags,
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: loaded.body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: loaded.body, relativeTo: note.url)
        )
    }
}

private func libraryIsInboxNote(_ note: NoteSearchResult) -> Bool {
    note.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
        || note.title.localizedCaseInsensitiveContains("Inbox")
}

private func libraryFirstMeaningfulLine(from body: String) -> String? {
    body.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
}

private struct LibraryFolderRow: Equatable, Sendable {
    let url: URL
    let depth: Int
    let hasChildren: Bool
}

private typealias LoadedLibraryNote = (title: String, body: String, tags: [String])

private enum LibrarySourceSection: Int {
    case folders = 0
    case tags = 1

    var title: String {
        switch self {
        case .folders:
            return "文件夹"
        case .tags:
            return "标签"
        }
    }

    var identifier: String {
        switch self {
        case .folders:
            return "Folders"
        case .tags:
            return "Tags"
        }
    }
}

enum LibraryNotesLayout {
    static let initialWindowSize = NSSize(width: 1720, height: 940)
    static let presentedWindowSize = NSSize(width: 1840, height: 1010)
    static let minimumWindowSize = NSSize(width: 1040, height: 620)
    static let sourceColumnWidth: CGFloat = 340
    static let noteColumnWidth: CGFloat = 430
    static let noteTableInitialWidth: CGFloat = 390
    static let noteTableMinimumWidth: CGFloat = 300
    static let sourceRowWidth: CGFloat = 312
    static let toolbarSearchWidth: CGFloat = 360
    static let toolbarSearchHeight: CGFloat = 32
    static let toolbarSearchWrapperWidth: CGFloat = 380
    static let toolbarSearchWrapperHeight: CGFloat = 36
    static let toolbarEditorToolsWidth: CGFloat = 200
    static let toolbarEditorToolsHeight: CGFloat = 36
    static let toolbarEditorToolButtonWidth: CGFloat = 39
    static let toolbarEditorToolButtonHeight: CGFloat = 30
    static let toolbarEditorToolsEnabledAlpha: CGFloat = 1.0
    static let toolbarEditorToolsDisabledAlpha: CGFloat = 0.42
    static let toolbarEditorToolsEnabledBorderAlpha: CGFloat = 0.55
    static let toolbarEditorToolsDisabledBorderAlpha: CGFloat = 0.25
    static let toolbarSymbolPointSize: CGFloat = 21
    static let windowScreenMargin: CGFloat = 72
    static let sourceRowHeight: CGFloat = 40
    static let noteGroupRowHeight: CGFloat = 66
    static let noteRowHeight: CGFloat = 92
    static let sourceGroupFontSize: CGFloat = 14.5
    static let sourceButtonFontSize: CGFloat = 16.5
    static let sourceCountFontSize: CGFloat = 15
    static let noteGroupFontSize: CGFloat = 20
    static let noteTitleFontSize: CGFloat = 17.5
    static let noteSnippetFontSize: CGFloat = 15.5
    static let noteMetaFontSize: CGFloat = 13
    static let noteListHeaderTitleFontSize: CGFloat = 23
    static let noteListHeaderCountFontSize: CGFloat = 14
    static let noteListLeadingInset: CGFloat = 20
    static let noteListTrailingInset: CGFloat = 16
    static let noteListTopInset: CGFloat = 18
    static let noteListBottomInset: CGFloat = 14
    static let editorTopInset: CGFloat = 34
    static let editorHorizontalInset: CGFloat = 52
    static let editorBottomInset: CGFloat = 20
    static let editorDateRowHeight: CGFloat = 20
    static let editorDateToTitleSpacing: CGFloat = 28
    static let editorTitleToBodySpacing: CGFloat = 8
    static let editorStatusFontSize: CGFloat = 14
    static let editorTitleFontSize: CGFloat = 34
    static let editorBodyFontSize: CGFloat = 16.5
    static let editorCodeFontSize: CGFloat = 15.5

    static func presentedWindowSize(in visibleFrame: NSRect) -> NSSize {
        let availableWidth = max(minimumWindowSize.width, visibleFrame.width - windowScreenMargin)
        let availableHeight = max(minimumWindowSize.height, visibleFrame.height - windowScreenMargin)
        return NSSize(
            width: min(presentedWindowSize.width, availableWidth),
            height: min(presentedWindowSize.height, availableHeight)
        )
    }
}

enum LibrarySourceSelectionPalette {
    static let backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.86)
    static let foregroundColor = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.16, alpha: 1)
}

private func libraryDisplayTag(_ tag: String) -> String {
    let trimmed = libraryBareTag(tag)
    guard !trimmed.isEmpty else { return "#" }
    return "#\(trimmed)"
}

private func libraryBareTag(_ tag: String) -> String {
    var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasPrefix("#") {
        trimmed.removeFirst()
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
}

private enum LibraryActionError: LocalizedError {
    case noFolderSelected
    case noNoteSelected

    var errorDescription: String? {
        switch self {
        case .noFolderSelected:
            return "没有选中文件夹"
        case .noNoteSelected:
            return "没有选中笔记"
        }
    }
}

private enum LibraryFormatCommand: Int {
    case heading = 1
    case bold
    case italic
    case underline
    case strikethrough
    case bullet
    case ordered
}

@MainActor
final class LibraryGroupHeaderCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteGroupFontSize, weight: .bold)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class LibraryNoteCellView: NSTableCellView {
    static let contentTopInset: CGFloat = 9
    static let contentLeadingInset: CGFloat = 20
    static let contentBottomInset: CGFloat = 9
    static let contentTrailingInset: CGFloat = 16

    let titleLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(labelWithString: "")
    let metaLabel = NSTextField(labelWithString: "")
    let attachmentImageView = NSImageView()
    let thumbnailImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteTitleFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.alignment = .left
        titleLabel.textColor = panelPrimaryTextColor()

        snippetLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteSnippetFontSize)
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.maximumNumberOfLines = 1
        snippetLabel.alignment = .left
        snippetLabel.textColor = panelSecondaryTextColor()

        metaLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteMetaFontSize, weight: .medium)
        metaLabel.lineBreakMode = .byTruncatingMiddle
        metaLabel.maximumNumberOfLines = 1
        metaLabel.alignment = .left
        metaLabel.textColor = panelTertiaryTextColor()

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

        let metaRow = NSStackView(views: [attachmentImageView, metaLabel])
        metaRow.orientation = .horizontal
        metaRow.alignment = .centerY
        metaRow.spacing = 4

        let textStack = NSStackView(views: [titleLabel, snippetLabel, metaRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let stack = NSStackView(views: [textStack, thumbnailImageView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
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
        textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        metaRow.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
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
    static let selectionHorizontalInset: CGFloat = 14
    static let selectionVerticalInset: CGFloat = 4
    static let selectionCornerRadius: CGFloat = 8
    static let hoverHorizontalInset: CGFloat = 14
    static let hoverVerticalInset: CGFloat = 5
    static let hoverCornerRadius: CGFloat = 8
    static let separatorLeadingInset: CGFloat = 32
    static let separatorTrailingInset: CGFloat = 18
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
        setPointerHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerHovered(false)
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

        let hoverRect = bounds.insetBy(
            dx: Self.hoverHorizontalInset,
            dy: Self.hoverVerticalInset
        )
        let path = NSBezierPath(
            roundedRect: hoverRect,
            xRadius: Self.hoverCornerRadius,
            yRadius: Self.hoverCornerRadius
        )
        NSColor(calibratedWhite: 0.20, alpha: 0.72).setFill()
        path.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard !isGroupRow else { return }
        let selectionRect = bounds.insetBy(
            dx: Self.selectionHorizontalInset,
            dy: Self.selectionVerticalInset
        )
        let path = NSBezierPath(
            roundedRect: selectionRect,
            xRadius: Self.selectionCornerRadius,
            yRadius: Self.selectionCornerRadius
        )
        NSColor(calibratedRed: 0.55, green: 0.43, blue: 0.08, alpha: 0.95).setFill()
        path.fill()
    }
}

@MainActor
final class LibrarySourceRowView: NSView {
    static let hoverHorizontalInset: CGFloat = 0
    static let hoverVerticalInset: CGFloat = 1
    static let hoverCornerRadius: CGFloat = 6
    static let hoverColor = NSColor(calibratedWhite: 0.20, alpha: 0.42)
    static let dropHighlightColor = NSColor(calibratedWhite: 0.24, alpha: 0.80)

    var targetDirectory: URL?
    var canDropNotes: (([URL], URL) -> Bool)?
    var onDropNotes: (([URL], URL) -> Bool)?
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isPointerHovered = false
    private(set) var isDropTargeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }
        super.updateTrackingAreas()

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
        setPointerHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerHovered(false)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropTargeted(false)
        let noteURLs = draggedFileURLs(from: sender.draggingPasteboard)
        guard let targetDirectory,
              !noteURLs.isEmpty else {
            return false
        }
        return onDropNotes?(noteURLs, targetDirectory) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isPointerHovered, !isDropTargeted {
            let hoverRect = bounds.insetBy(
                dx: Self.hoverHorizontalInset,
                dy: Self.hoverVerticalInset
            )
            let hoverPath = NSBezierPath(
                roundedRect: hoverRect,
                xRadius: Self.hoverCornerRadius,
                yRadius: Self.hoverCornerRadius
            )
            Self.hoverColor.setFill()
            hoverPath.fill()
        }

        guard isDropTargeted else { return }

        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: 6,
            yRadius: 6
        )
        Self.dropHighlightColor.setFill()
        path.fill()
    }

    func setPointerHovered(_ hovered: Bool) {
        guard isPointerHovered != hovered else { return }
        isPointerHovered = hovered
        needsDisplay = true
    }

    func setDropTargeted(_ targeted: Bool) {
        guard isDropTargeted != targeted else { return }
        isDropTargeted = targeted
        needsDisplay = true
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let noteURLs = draggedFileURLs(from: sender.draggingPasteboard)
        guard targetDirectory != nil,
              !noteURLs.isEmpty,
              let targetDirectory,
              canDropNotes?(noteURLs, targetDirectory) == true else {
            setDropTargeted(false)
            return []
        }
        setDropTargeted(true)
        return .move
    }

    private func draggedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        var seenPaths = Set<String>()
        return objects.compactMap { object -> URL? in
            let url: URL?
            if let swiftURL = object as? URL {
                url = swiftURL
            } else if let nsURL = object as? NSURL {
                url = nsURL as URL
            } else {
                url = nil
            }
            guard let url else { return nil }
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL, seenPaths.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }
}

fileprivate enum LibraryNoteKeyCommand {
    case open
    case delete
    case moveDown
    case moveUp
}

@MainActor
final class LibraryNoteTableView: NSTableView {
    fileprivate var onKeyCommand: ((LibraryNoteKeyCommand) -> Bool)?

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
}

@MainActor
final class LibraryNoteScrollView: NSScrollView {
    override func layout() {
        let targetWidth = max(LibraryNotesLayout.noteTableMinimumWidth, frame.width)
        super.layout()
        guard let tableView = documentView as? LibraryNoteTableView else { return }

        var frame = tableView.frame
        if abs(frame.origin.x) > 0.5 || abs(frame.width - targetWidth) > 0.5 {
            frame.origin.x = 0
            frame.size.width = targetWidth
            tableView.frame = frame
        }
        if let column = tableView.tableColumns.first,
           abs(column.width - targetWidth) > 0.5 {
            column.width = targetWidth
        }
    }
}

@MainActor
final class LibraryWindowController: NSWindowController,
    NSWindowDelegate,
    NSToolbarDelegate,
    NSToolbarItemValidation,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSSearchFieldDelegate,
    NSTextFieldDelegate,
    NSTextViewDelegate,
    MarkdownTextViewCommands,
    WindowOpacityAdjusting
{
    let noteStore: NoteStore
    let tableView = LibraryNoteTableView()
    let searchField = NSSearchField(string: "")
    let searchScopeControl = NSSegmentedControl(
        labels: ["当前", "所有"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    let noteListTitleLabel = NSTextField(labelWithString: "")
    let noteListCountLabel = NSTextField(labelWithString: "")
    let noteListEmptyLabel = NSTextField(labelWithString: "")
    let titleField = NSTextField(string: "")
    let editorTextView = MarkdownTextView(frame: .zero)
    let statusLabel = NSTextField(labelWithString: "")
    let emptyLabel = NSTextField(labelWithString: "选择或新建一条笔记")

    private static let toolbarIdentifier = NSToolbar.Identifier("mudsnote.library.toolbar")
    private static let addFolderToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.add-folder")
    private static let toggleSidebarToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.toggle-sidebar")
    private static let sourceTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.source-separator")
    private static let noteTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-separator")
    private static let newNoteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.new-note")
    private static let openSeparateToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.open-separate")
    private static let moveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.move")
    private static let saveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.save")
    private static let deleteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.delete")
    private static let restoreToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.restore")
    private static let editorToolsToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.editor-tools")
    private static let formatToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.format")
    private static let checklistToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.checklist")
    private static let tableToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.table")
    private static let linkToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.link")
    private static let attachmentToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.attachment")
    private static let exportToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.export")
    private static let moreToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.more")
    private static let searchToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.search")

    private let onOpenInSeparateWindow: (URL) -> Void
    private let onSave: (URL) -> Void
    private let onClose: () -> Void
    private var notes: [NoteSearchResult] = []
    private var listRows: [LibraryNoteListRow] = []
    private var sourceCountSnapshot: [NoteSearchResult] = []
    private var selectedURL: URL?
    private var selectedTags: [String] = []
    private var isDirty = false
    private var autosaveTask: Task<Void, Never>?
    private var searchReloadWorkItem: DispatchWorkItem?
    private var searchResultsTask: Task<Void, Never>?
    private var searchResultsGeneration = 0
    private var hasPendingSearchReload = false
    private var isLoadingInitialNote = false
    private var suppressEditorChanges = false
    private var suppressSelectionChanges = false
    private var hasCenteredWindow = false
    private var hasHydratedInitialNoteList = false
    private var selectedScope: LibraryScope = .all
    private var sourceButtons: [NSButton] = []
    private var sourceCountLabels: [Int: NSTextField] = [:]
    private var sourceFolderRows: [LibraryFolderRow] = []
    private var sourceTagNames: [String] = []
    private var collapsedFolderPaths = Set<String>()
    private var expandedFolderPaths = Set<String>()
    private var sourceFoldersLoaded = false
    private var sourceFoldersLoading = false
    private var sourceTagsLoaded = false
    private var fullLibrarySnapshotReloadScheduled = false
    private var isFullLibrarySnapshotLoading = false
    private var movableNotePathCache: Set<String>?
    private var sourceFoldersSectionCollapsed = false
    private var sourceTagsSectionCollapsed = false
    private weak var librarySplitView: NSSplitView?
    private weak var sourceListView: NSView?
    private let sourcePrimaryStack = NSStackView()
    private let sourceFolderStack = NSStackView()
    private let sourceTagStack = NSStackView()
    private let sourceFolderStatusLabel = NSTextField(labelWithString: "")
    private let sourceTagStatusLabel = NSTextField(labelWithString: "")
    private static let sourceCountSnapshotLimit = 10_000

    let theme = MarkdownEditorTheme(
        textColor: panelPrimaryTextColor(),
        mutedTextColor: panelSecondaryTextColor(),
        accentColor: panelAccentColor(),
        bodyFont: .systemFont(ofSize: LibraryNotesLayout.editorBodyFontSize, weight: .regular),
        boldFont: .systemFont(ofSize: LibraryNotesLayout.editorBodyFontSize, weight: .bold),
        italicFont: NSFontManager.shared.convert(
            .systemFont(ofSize: LibraryNotesLayout.editorBodyFontSize, weight: .regular),
            toHaveTrait: .italicFontMask
        ),
        codeFont: .monospacedSystemFont(ofSize: LibraryNotesLayout.editorCodeFontSize, weight: .medium)
    )

    init(
        noteStore: NoteStore,
        defersInitialNoteHydration: Bool = false,
        onOpenInSeparateWindow: @escaping (URL) -> Void,
        onSave: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.onOpenInSeparateWindow = onOpenInSeparateWindow
        self.onSave = onSave
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: LibraryNotesLayout.initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(MudsnoteBrand.appName) 笔记"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = LibraryNotesLayout.minimumWindowSize
        window.toolbarStyle = .expanded
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        buildUI()
        configureToolbar()
        if defersInitialNoteHydration {
            reloadNotes(
                loadFirstIfNeeded: false,
                hydratePreviews: false,
                allNotesSnapshot: recentNoteResults(limit: 240, hydratePreview: false),
                refreshCounts: false
            )
        } else {
            hasHydratedInitialNoteList = true
            reloadNotes(loadFirstIfNeeded: true, hydratePreviews: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndFocus() {
        showWindow(nil)
        guard let window else { return }
        if !hasCenteredWindow {
            let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
            let targetSize = LibraryNotesLayout.presentedWindowSize(in: visibleFrame)
            let targetOrigin = NSPoint(
                x: visibleFrame.midX - targetSize.width / 2,
                y: visibleFrame.midY - targetSize.height / 2
            )
            window.setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
            hasCenteredWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if selectedURL == nil {
            window.makeFirstResponder(tableView)
        } else {
            editorTextView.window?.makeFirstResponder(editorTextView)
        }
        scheduleDeferredSourceFolderLoad()
        scheduleDeferredSourceTagLoad()
        hydrateInitialNoteListIfNeeded()
    }

    private func hydrateInitialNoteListIfNeeded() {
        guard !hasHydratedInitialNoteList else { return }
        hasHydratedInitialNoteList = true
        if selectedURL == nil,
           let firstNoteRow = listRows.firstIndex(where: { $0.note != nil }),
           let noteToLoad = note(at: firstNoteRow) {
            suppressSelectionChanges = true
            tableView.selectRowIndexes(IndexSet(integer: firstNoteRow), byExtendingSelection: false)
            suppressSelectionChanges = false
            showInitialNoteLoadingShell(for: noteToLoad)
            loadInitialNoteAfterLaunch(noteToLoad)
        }
        scheduleFullLibrarySnapshotReload()
    }

    private func showInitialNoteLoadingShell(for note: NoteSearchResult) {
        isLoadingInitialNote = true
        selectedURL = nil
        setEditorEditable(false)
        applyDocument(title: note.title, body: "", tags: note.tags)
        isDirty = false
        statusLabel.stringValue = editorDateText(for: note.modifiedAt)
        updateEmptyState()
        updateToolbarActionState()
    }

    private func loadInitialNoteAfterLaunch(_ note: NoteSearchResult) {
        let noteStore = noteStore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result<LoadedLibraryNote, Error> {
                try noteStore.loadNote(at: note.url)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyInitialNoteLoadResult(result, for: note)
            }
        }
    }

    private func selectedNoteStillMatchesInitialLoad(_ note: NoteSearchResult) -> Bool {
        if let selectedNote = self.note(at: tableView.selectedRow),
           selectedNote.url.standardizedFileURL.path != note.url.standardizedFileURL.path {
            return false
        }

        if let selectedURL,
           selectedURL.standardizedFileURL.path != note.url.standardizedFileURL.path {
            return false
        }

        return true
    }

    private func applyInitialNoteLoadResult(_ result: Result<LoadedLibraryNote, Error>, for note: NoteSearchResult) {
        guard window?.isVisible == true else { return }
        guard selectedNoteStillMatchesInitialLoad(note) else { return }
        applyLoadedNoteResult(result, for: note)
    }

    private func scheduleFullLibrarySnapshotReload() {
        guard !fullLibrarySnapshotReloadScheduled else { return }
        fullLibrarySnapshotReloadScheduled = true
        isFullLibrarySnapshotLoading = true
        updateNoteListHeader(query: searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let noteStore = noteStore
        let snapshotLimit = Self.sourceCountSnapshotLimit
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let allNotes = noteStore.listNotes(limit: snapshotLimit)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFullLibrarySnapshotLoading = false
                guard self.window?.isVisible == true else { return }
                let currentQuery = self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !currentQuery.isEmpty {
                    self.sourceCountSnapshot = allNotes
                    self.refreshSourceCounts(using: allNotes)
                    self.updateNoteListHeader(query: currentQuery)
                    return
                }
                self.reloadNotes(
                    selecting: self.selectedURL,
                    loadFirstIfNeeded: false,
                    hydratePreviews: false,
                    allNotesSnapshot: allNotes
                )
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        autosaveTask?.cancel()
        autosaveTask = nil
        searchReloadWorkItem?.cancel()
        searchReloadWorkItem = nil
        cancelActiveSearchResultReload()
        hasPendingSearchReload = false
        try? saveCurrentNoteIfNeeded()
        onClose()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        librarySplitView = splitView
        contentView.addSubview(splitView)
        pin(splitView, to: contentView)

        let sourceList = buildSourceList()
        let sidebar = buildSidebar()
        let editor = buildEditor()
        splitView.addArrangedSubview(sourceList)
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(editor)
        sourceList.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceColumnWidth).isActive = true
        sidebar.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.noteColumnWidth).isActive = true
    }

    private func buildSourceList() -> NSView {
        let sourceList = NSVisualEffectView()
        sourceList.material = .sidebar
        sourceList.blendingMode = .withinWindow
        sourceList.state = .active
        sourceList.translatesAutoresizingMaskIntoConstraints = false
        sourceListView = sourceList

        configureSourceStack(sourcePrimaryStack)
        configureSourceStack(sourceFolderStack)
        configureSourceStack(sourceTagStack)
        configureSourceStatusLabel(
            sourceFolderStatusLabel,
            identifier: "LibrarySourceFolderStatus"
        )
        configureSourceStatusLabel(
            sourceTagStatusLabel,
            identifier: "LibrarySourceTagStatus"
        )

        let libraryHeader = makeSourceGroupLabel("Mudsnote", identifier: "LibrarySourceGroup-Mudsnote")
        let folderHeader = makeSourceSectionHeader(.folders)
        let tagHeader = makeSourceSectionHeader(.tags)

        sourceFolderRows = rootFolderRowsForSourceList()
        rebuildSourceRows(includeTags: sourceTagsLoaded)

        let stack = NSStackView(views: [
            libraryHeader,
            sourcePrimaryStack,
            folderHeader,
            sourceFolderStack,
            tagHeader,
            sourceTagStack,
            NSView()
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 14, bottom: 14, right: 12)
        sourceList.addSubview(stack)
        pin(stack, to: sourceList)
        refreshSourceSelection()

        return sourceList
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        configureNoteListHeaderLabels()
        configureSearchScopeControl()

        let titleStack = NSStackView(views: [noteListTitleLabel, noteListCountLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 0

        let header = NSStackView(views: [titleStack, NSView(), searchScopeControl])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = LibraryNotesLayout.noteTableInitialWidth
        column.minWidth = LibraryNotesLayout.noteTableMinimumWidth
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
        tableView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTable")
        tableView.headerView = nil
        tableView.rowHeight = 68
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedInSeparateWindow)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.onKeyCommand = { [weak self] command in
            self?.handleNoteListKeyCommand(command) ?? false
        }
        tableView.menu = makeNoteContextMenu()

        let scrollView = LibraryNoteScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.documentView = tableView

        noteListEmptyLabel.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListEmptyLabel")
        noteListEmptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        noteListEmptyLabel.textColor = panelTertiaryTextColor()
        noteListEmptyLabel.alignment = .center
        noteListEmptyLabel.lineBreakMode = .byWordWrapping
        noteListEmptyLabel.maximumNumberOfLines = 2
        noteListEmptyLabel.isHidden = true

        let listContainer = NSView()
        listContainer.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListContainer")
        listContainer.addSubview(scrollView)
        listContainer.addSubview(noteListEmptyLabel)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        noteListEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            noteListEmptyLabel.leadingAnchor.constraint(
                equalTo: listContainer.leadingAnchor,
                constant: LibraryNotesLayout.noteListLeadingInset
            ),
            noteListEmptyLabel.trailingAnchor.constraint(
                equalTo: listContainer.trailingAnchor,
                constant: -LibraryNotesLayout.noteListLeadingInset
            ),
            noteListEmptyLabel.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor, constant: -20)
        ])

        let stack = NSStackView(views: [header, listContainer])
        stack.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListStack")
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(
            top: LibraryNotesLayout.noteListTopInset,
            left: LibraryNotesLayout.noteListLeadingInset,
            bottom: LibraryNotesLayout.noteListBottomInset,
            right: LibraryNotesLayout.noteListTrailingInset
        )
        sidebar.addSubview(stack)
        pin(stack, to: sidebar)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        listContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return sidebar
    }

    private func buildEditor() -> NSView {
        let editor = NSView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        titleField.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTitleField")
        titleField.placeholderString = "无标题"
        titleField.font = .systemFont(ofSize: LibraryNotesLayout.editorTitleFontSize, weight: .bold)
        titleField.textColor = panelPrimaryTextColor()
        titleField.alignment = .left
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.delegate = self

        statusLabel.identifier = NSUserInterfaceItemIdentifier("LibraryEditorStatusLabel")
        statusLabel.font = .systemFont(ofSize: LibraryNotesLayout.editorStatusFontSize, weight: .semibold)
        statusLabel.textColor = panelTertiaryTextColor()
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        configureEditorTextView()
        let scrollView = EditorScrollView()
        let clipView = EditorClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = editorTextView

        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = panelTertiaryTextColor()
        emptyLabel.alignment = .center

        let bodyContainer = NSView()
        bodyContainer.identifier = NSUserInterfaceItemIdentifier("LibraryEditorBodyContainer")
        bodyContainer.addSubview(scrollView)
        bodyContainer.addSubview(emptyLabel)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: bodyContainer.centerYAnchor)
        ])

        let dateRow = NSView()
        dateRow.identifier = NSUserInterfaceItemIdentifier("LibraryEditorDateRow")
        dateRow.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: dateRow.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: dateRow.topAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: dateRow.bottomAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: dateRow.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateRow.trailingAnchor, constant: -20),
            dateRow.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.editorDateRowHeight)
        ])

        let stack = NSStackView(views: [dateRow, titleField, bodyContainer])
        stack.identifier = NSUserInterfaceItemIdentifier("LibraryEditorStack")
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setCustomSpacing(LibraryNotesLayout.editorDateToTitleSpacing, after: dateRow)
        stack.setCustomSpacing(LibraryNotesLayout.editorTitleToBodySpacing, after: titleField)
        stack.edgeInsets = NSEdgeInsets(
            top: LibraryNotesLayout.editorTopInset,
            left: LibraryNotesLayout.editorHorizontalInset,
            bottom: LibraryNotesLayout.editorBottomInset,
            right: LibraryNotesLayout.editorHorizontalInset
        )
        editor.addSubview(stack)
        pin(stack, to: editor)
        bodyContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        return editor
    }

    private func configureToolbar() {
        searchField.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarSearchField")
        searchField.placeholderString = "搜索"
        searchField.font = .systemFont(ofSize: 14)
        searchField.delegate = self
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.frame = NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarSearchWidth,
            height: LibraryNotesLayout.toolbarSearchHeight
        )
        searchField.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarSearchWidth).isActive = true
        searchField.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarSearchHeight).isActive = true

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbar = toolbar
    }

    private func configureSearchScopeControl() {
        searchScopeControl.identifier = NSUserInterfaceItemIdentifier("LibrarySearchScopeControl")
        searchScopeControl.target = self
        searchScopeControl.action = #selector(searchScopeChanged(_:))
        searchScopeControl.selectedSegment = 0
        searchScopeControl.segmentStyle = .capsule
        searchScopeControl.controlSize = .small
        searchScopeControl.font = .systemFont(ofSize: 11, weight: .medium)
        searchScopeControl.setWidth(44, forSegment: 0)
        searchScopeControl.setWidth(44, forSegment: 1)
        searchScopeControl.toolTip = "切换搜索范围"
        searchScopeControl.isHidden = true
    }

    private func configureNoteListHeaderLabels() {
        noteListTitleLabel.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListTitle")
        noteListTitleLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteListHeaderTitleFontSize, weight: .bold)
        noteListTitleLabel.textColor = panelPrimaryTextColor()
        noteListTitleLabel.lineBreakMode = .byTruncatingTail

        noteListCountLabel.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListCount")
        noteListCountLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteListHeaderCountFontSize, weight: .semibold)
        noteListCountLabel.textColor = panelTertiaryTextColor()
        noteListCountLabel.lineBreakMode = .byTruncatingTail
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.addFolderToolbarItemIdentifier,
            Self.toggleSidebarToolbarItemIdentifier,
            Self.sourceTrackingSeparatorToolbarItemIdentifier,
            Self.newNoteToolbarItemIdentifier,
            Self.noteTrackingSeparatorToolbarItemIdentifier,
            .flexibleSpace,
            Self.editorToolsToolbarItemIdentifier,
            .space,
            Self.exportToolbarItemIdentifier,
            Self.moreToolbarItemIdentifier,
            Self.searchToolbarItemIdentifier
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [
            Self.sourceTrackingSeparatorToolbarItemIdentifier,
            Self.noteTrackingSeparatorToolbarItemIdentifier,
            Self.openSeparateToolbarItemIdentifier,
            Self.moveToolbarItemIdentifier,
            Self.saveToolbarItemIdentifier,
            Self.deleteToolbarItemIdentifier,
            Self.restoreToolbarItemIdentifier,
            Self.formatToolbarItemIdentifier,
            Self.checklistToolbarItemIdentifier,
            Self.tableToolbarItemIdentifier,
            Self.linkToolbarItemIdentifier,
            Self.attachmentToolbarItemIdentifier
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.sourceTrackingSeparatorToolbarItemIdentifier:
            return toolbarTrackingSeparatorItem(identifier: itemIdentifier, dividerIndex: 0)
        case Self.noteTrackingSeparatorToolbarItemIdentifier:
            return toolbarTrackingSeparatorItem(identifier: itemIdentifier, dividerIndex: 1)
        case Self.addFolderToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "添加文件夹",
                symbolName: "folder.badge.plus",
                action: #selector(addFolderPressed)
            )
        case Self.toggleSidebarToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "隐藏资料库",
                symbolName: "sidebar.left",
                action: #selector(toggleSourceListPressed)
            )
        case Self.newNoteToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "新建笔记",
                symbolName: "square.and.pencil",
                action: #selector(newNotePressed)
            )
        case Self.openSeparateToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "独立窗口打开",
                symbolName: "rectangle.on.rectangle",
                action: #selector(openSelectedInSeparateWindow),
                visibilityPriority: .low
            )
        case Self.editorToolsToolbarItemIdentifier:
            return toolbarEditorToolsItem(identifier: itemIdentifier)
        case Self.formatToolbarItemIdentifier:
            let item = toolbarImageItem(
                identifier: itemIdentifier,
                label: "格式",
                image: makeFormatToolbarImage(),
                action: #selector(formatPressed(_:))
            )
            return item
        case Self.checklistToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "待办列表",
                symbolName: "checklist",
                action: #selector(checklistPressed)
            )
        case Self.tableToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "插入表格",
                symbolName: "tablecells",
                action: #selector(tablePressed)
            )
        case Self.linkToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "插入链接",
                symbolName: "link",
                action: #selector(linkPressed)
            )
        case Self.attachmentToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "添加附件",
                symbolName: "paperclip",
                action: #selector(attachmentPressed)
            )
        case Self.exportToolbarItemIdentifier:
            return toolbarMenuItem(
                identifier: itemIdentifier,
                label: "分享与导出",
                symbolName: "square.and.arrow.up",
                menu: makeShareExportMenuForLibrary()
            )
        case Self.moveToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "移动到文件夹",
                symbolName: "folder",
                action: #selector(moveSelectedNotePressed(_:)),
                visibilityPriority: .low
            )
        case Self.saveToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "保存",
                symbolName: "checkmark.circle",
                action: #selector(savePressed),
                visibilityPriority: .low
            )
        case Self.deleteToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "删除",
                symbolName: "trash",
                action: #selector(deleteSelectedNotePressed),
                visibilityPriority: .low
            )
        case Self.restoreToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "恢复",
                symbolName: "arrow.uturn.backward",
                action: #selector(restoreSelectedNotePressed),
                visibilityPriority: .low
            )
        case Self.moreToolbarItemIdentifier:
            return toolbarMenuItem(
                identifier: itemIdentifier,
                label: "更多",
                symbolName: "ellipsis.circle",
                menu: makeMoreActionsMenuForLibrary()
            )
        case Self.searchToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "搜索"
            item.paletteLabel = "搜索"
            item.toolTip = "搜索笔记"
            item.visibilityPriority = .high
            let wrapper = NSView(frame: NSRect(
                x: 0,
                y: 0,
                width: LibraryNotesLayout.toolbarSearchWrapperWidth,
                height: LibraryNotesLayout.toolbarSearchWrapperHeight
            ))
            wrapper.addSubview(searchField)
            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                searchField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
                searchField.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
            ])
            item.view = wrapper
            return item
        default:
            return nil
        }
    }

    private func toolbarTrackingSeparatorItem(
        identifier: NSToolbarItem.Identifier,
        dividerIndex: Int
    ) -> NSToolbarItem {
        guard let librarySplitView else {
            return NSToolbarItem(itemIdentifier: identifier)
        }
        return NSTrackingSeparatorToolbarItem(
            identifier: identifier,
            splitView: librarySplitView,
            dividerIndex: dividerIndex
        )
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.moreToolbarItemIdentifier:
            return canShowMoreActions
        case Self.openSeparateToolbarItemIdentifier:
            return canUseSingleSelectedNote
        case Self.editorToolsToolbarItemIdentifier,
             Self.formatToolbarItemIdentifier,
             Self.checklistToolbarItemIdentifier,
             Self.tableToolbarItemIdentifier,
             Self.linkToolbarItemIdentifier,
             Self.attachmentToolbarItemIdentifier:
            return canEditCurrentDocument
        case Self.moveToolbarItemIdentifier:
            return canMoveSelectedNote
        case Self.saveToolbarItemIdentifier:
            return canEditCurrentDocument
        case Self.exportToolbarItemIdentifier:
            return canExportSelectedNote
        case Self.deleteToolbarItemIdentifier:
            return canUseSelectedNote
        case Self.restoreToolbarItemIdentifier:
            return canRestoreSelectedNote
        default:
            return true
        }
    }

    private func toolbarButtonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .standard
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = toolbarSymbolImage(symbolName: symbolName, label: label)
        item.target = self
        item.action = action
        item.visibilityPriority = visibilityPriority
        return item
    }

    private func toolbarEditorToolsItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "编辑工具"
        item.paletteLabel = "编辑工具"
        item.toolTip = "编辑工具"
        item.visibilityPriority = .high

        let capsule = NSVisualEffectView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarEditorToolsWidth,
            height: LibraryNotesLayout.toolbarEditorToolsHeight
        ))
        capsule.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarEditorTools")
        capsule.blendingMode = .withinWindow
        capsule.material = .titlebar
        capsule.state = .active
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = LibraryNotesLayout.toolbarEditorToolsHeight / 2
        capsule.layer?.borderWidth = 1
        capsule.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        capsule.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let buttons = [
            toolbarEditorToolButton(
                identifier: Self.formatToolbarItemIdentifier,
                label: "格式",
                image: makeFormatToolbarImage(),
                action: #selector(formatPressed(_:))
            ),
            toolbarEditorToolButton(
                identifier: Self.checklistToolbarItemIdentifier,
                label: "待办列表",
                symbolName: "checklist",
                action: #selector(checklistPressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.tableToolbarItemIdentifier,
                label: "插入表格",
                symbolName: "tablecells",
                action: #selector(tablePressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.linkToolbarItemIdentifier,
                label: "插入链接",
                symbolName: "link",
                action: #selector(linkPressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.attachmentToolbarItemIdentifier,
                label: "添加附件",
                symbolName: "paperclip",
                action: #selector(attachmentPressed)
            )
        ]
        buttons.forEach { stack.addArrangedSubview($0) }

        capsule.addSubview(stack)
        NSLayoutConstraint.activate([
            capsule.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolsWidth),
            capsule.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolsHeight),
            stack.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolButtonHeight)
        ])

        item.view = capsule
        setEditorToolsToolbarGroupEnabled(canEditCurrentDocument, in: item)
        return item
    }

    private func toolbarEditorToolButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSButton {
        let image = toolbarSymbolImage(symbolName: symbolName, label: label)
        image?.isTemplate = true
        return toolbarEditorToolButton(identifier: identifier, label: label, image: image, action: action)
    }

    private func toolbarEditorToolButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        image: NSImage?,
        action: Selector
    ) -> NSButton {
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolButtonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolButtonHeight).isActive = true
        return button
    }

    private func toolbarImageItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        image: NSImage,
        action: Selector,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .standard
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = image
        item.target = self
        item.action = action
        item.visibilityPriority = visibilityPriority
        return item
    }

    private func toolbarMenuItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        menu: NSMenu,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .standard
    ) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = toolbarSymbolImage(symbolName: symbolName, label: label)
        item.menu = menu
        item.visibilityPriority = visibilityPriority
        return item
    }

    private func toolbarSymbolImage(symbolName: String, label: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.toolbarSymbolPointSize,
            weight: .regular
        )) ?? image
    }

    private func makeFormatToolbarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 18))
        image.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        ("Aa" as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "格式"
        return image
    }

    private func configureEditorTextView() {
        editorTextView.commandDelegate = self
        editorTextView.delegate = self
        editorTextView.configureContextMenu = { [weak self] menu, event in
            if let attachment = self?.editorTextView.fileAttachmentReference(at: event) {
                self?.configureAttachmentContextMenu(menu, forAttachment: attachment)
            }
        }
        editorTextView.isRichText = true
        editorTextView.importsGraphics = false
        editorTextView.usesFontPanel = false
        editorTextView.isAutomaticDataDetectionEnabled = false
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isAutomaticTextReplacementEnabled = false
        editorTextView.isContinuousSpellCheckingEnabled = noteStore.spellCheckingEnabled
        editorTextView.allowsUndo = true
        editorTextView.font = theme.bodyFont
        editorTextView.backgroundColor = .clear
        editorTextView.drawsBackground = false
        editorTextView.textColor = theme.textColor
        editorTextView.insertionPointColor = theme.accentColor
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainerInset = NSSize(width: 4, height: 4)
        editorTextView.textContainer?.lineFragmentPadding = 0
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
    }

    private func configureSourceStack(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
    }

    private func configureSourceStatusLabel(_ label: NSTextField, identifier: String) {
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = panelTertiaryTextColor().withAlphaComponent(0.82)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: 24).isActive = true
        label.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceRowWidth).isActive = true
    }

    private func makeSourceGroupLabel(_ title: String, identifier: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.font = .systemFont(ofSize: LibraryNotesLayout.sourceGroupFontSize, weight: .semibold)
        label.textColor = panelTertiaryTextColor()
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeSourceSectionHeader(_ section: LibrarySourceSection) -> NSButton {
        let isCollapsed = isSourceSectionCollapsed(section)
        let symbolName = isCollapsed ? "chevron.right" : "chevron.down"
        let button = NSButton(
            title: section.title,
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: section.title) ?? NSImage(),
            target: self,
            action: #selector(sourceSectionDisclosurePressed(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier("LibrarySourceGroup-\(section.identifier)")
        button.tag = section.rawValue
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.font = .systemFont(ofSize: LibraryNotesLayout.sourceGroupFontSize, weight: .semibold)
        button.contentTintColor = panelTertiaryTextColor()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceRowWidth).isActive = true
        return button
    }

    private func rebuildSourceRows(includeTags: Bool) {
        sourceButtons.removeAll()
        sourceCountLabels.removeAll()
        removeArrangedSubviews(from: sourcePrimaryStack)
        removeArrangedSubviews(from: sourceFolderStack)
        removeArrangedSubviews(from: sourceTagStack)

        for scope in [LibraryScope.all, .recent, .inbox, .trash] {
            sourcePrimaryStack.addArrangedSubview(makeScopeRow(scope, tag: sourceButtons.count))
        }

        updateSourceFolderStatus()
        if !sourceFoldersSectionCollapsed {
            for (index, folderRow) in sourceFolderRows.enumerated() {
                sourceFolderStack.addArrangedSubview(makeScopeRow(
                    .folder(folderRow.url),
                    tag: 10 + index,
                    folderRow: folderRow
                ))
            }
            if !sourceFolderStatusLabel.stringValue.isEmpty {
                sourceFolderStack.addArrangedSubview(sourceFolderStatusLabel)
            }
        }

        if !includeTags {
            sourceTagNames = []
        }
        updateSourceTagStatus()
        if !sourceTagsSectionCollapsed {
            for (index, tag) in sourceTagNames.enumerated() {
                sourceTagStack.addArrangedSubview(makeScopeRow(.tag(tag), tag: 100 + index))
            }
            if !sourceTagStatusLabel.stringValue.isEmpty {
                sourceTagStack.addArrangedSubview(sourceTagStatusLabel)
            }
        }
        tableView.menu = makeNoteContextMenu()
    }

    private func isSourceSectionCollapsed(_ section: LibrarySourceSection) -> Bool {
        switch section {
        case .folders:
            return sourceFoldersSectionCollapsed
        case .tags:
            return sourceTagsSectionCollapsed
        }
    }

    private func updateSourceFolderStatus() {
        if !sourceFoldersLoaded && sourceFolderRows.isEmpty {
            sourceFolderStatusLabel.stringValue = "正在载入文件夹..."
        } else if sourceFolderRows.isEmpty {
            sourceFolderStatusLabel.stringValue = "没有文件夹"
        } else {
            sourceFolderStatusLabel.stringValue = ""
        }
    }

    private func updateSourceTagStatus() {
        if sourceTagsLoaded && sourceTagNames.isEmpty {
            sourceTagStatusLabel.stringValue = "没有标签"
        } else {
            sourceTagStatusLabel.stringValue = ""
        }
    }

    private func scheduleDeferredSourceFolderLoad() {
        guard !sourceFoldersLoaded, !sourceFoldersLoading else { return }
        sourceFoldersLoading = true
        let preferredDirectories = noteStore.preferredDirectories
        let collapsedPaths = collapsedFolderPaths
        let expandedPaths = expandedFolderPaths
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let rows = Self.folderRowsForSourceList(
                from: preferredDirectories,
                collapsedFolderPaths: collapsedPaths,
                expandedFolderPaths: expandedPaths
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.sourceFoldersLoaded = true
                self.sourceFoldersLoading = false
                self.sourceFolderRows = rows
                self.rebuildSourceRows(includeTags: self.sourceTagsLoaded)
                self.reloadNotes(selecting: self.selectedURL, loadFirstIfNeeded: false)
            }
        }
    }

    func loadSourceFoldersForLibrary() {
        reloadSourceFolderRowsForCurrentState()
        reloadNotes(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    private func scheduleDeferredSourceTagLoad() {
        guard !sourceTagsLoaded else { return }
        let noteStore = noteStore
        DispatchQueue.global(qos: .utility).async { [weak self] in
            noteStore.prewarmSearchIndex()
            let tags = noteStore.knownTags(limit: 12)
            DispatchQueue.main.async {
                self?.applySourceTagsForLibrary(tags)
            }
        }
    }

    func loadSourceTagsForLibrary() {
        guard !sourceTagsLoaded else { return }
        applySourceTagsForLibrary(noteStore.knownTags(limit: 12))
    }

    private func applySourceTagsForLibrary(_ tags: [String]) {
        guard !sourceTagsLoaded else { return }
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
        reloadNotes(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    private func removeArrangedSubviews(from stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func reloadSourceFolderRowsForCurrentState() {
        sourceFoldersLoaded = true
        sourceFoldersLoading = false
        sourceFolderRows = folderRowsForSourceList()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
    }

    private func rootFolderRowsForSourceList() -> [LibraryFolderRow] {
        Self.rootFolderRowsForSourceList(from: noteStore.preferredDirectories)
    }

    private func folderRowsForSourceList() -> [LibraryFolderRow] {
        Self.folderRowsForSourceList(
            from: noteStore.preferredDirectories,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
    }

    nonisolated private static func rootFolderRowsForSourceList(from directories: [URL]) -> [LibraryFolderRow] {
        rootPreferredDirectories(from: directories).map {
            LibraryFolderRow(url: $0, depth: 0, hasChildren: false)
        }
    }

    nonisolated private static func folderRowsForSourceList(
        from directories: [URL],
        collapsedFolderPaths: Set<String>,
        expandedFolderPaths: Set<String>
    ) -> [LibraryFolderRow] {
        let preferredRoots = rootPreferredDirectories(from: directories)
        var seenPaths = Set<String>()
        var rows: [LibraryFolderRow] = []

        for root in preferredRoots {
            appendFolderRows(
                root,
                depth: 0,
                maxDepth: 3,
                collapsedFolderPaths: collapsedFolderPaths,
                expandedFolderPaths: expandedFolderPaths,
                seenPaths: &seenPaths,
                rows: &rows
            )
        }

        return rows
    }

    nonisolated private static func rootPreferredDirectories(from directories: [URL]) -> [URL] {
        let standardized = directories.map(\.standardizedFileURL)
        return standardized.filter { candidate in
            !standardized.contains { other in
                other != candidate && candidate.path.hasPrefix(other.path + "/")
            }
        }
    }

    nonisolated private static func appendFolderRows(
        _ folderURL: URL,
        depth: Int,
        maxDepth: Int,
        collapsedFolderPaths: Set<String>,
        expandedFolderPaths: Set<String>,
        seenPaths: inout Set<String>,
        rows: inout [LibraryFolderRow]
    ) {
        let standardized = folderURL.standardizedFileURL
        guard seenPaths.insert(standardized.path).inserted else { return }
        let children = childFolderURLs(of: standardized)
        rows.append(LibraryFolderRow(url: standardized, depth: depth, hasChildren: !children.isEmpty))
        guard depth < maxDepth, isSourceFolderExpanded(
            path: standardized.path,
            depth: depth,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        ) else { return }

        for child in children {
            appendFolderRows(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                collapsedFolderPaths: collapsedFolderPaths,
                expandedFolderPaths: expandedFolderPaths,
                seenPaths: &seenPaths,
                rows: &rows
            )
        }
    }

    private func isSourceFolderExpanded(path: String, depth: Int) -> Bool {
        Self.isSourceFolderExpanded(
            path: path,
            depth: depth,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
    }

    nonisolated private static func isSourceFolderExpanded(
        path: String,
        depth: Int,
        collapsedFolderPaths: Set<String>,
        expandedFolderPaths: Set<String>
    ) -> Bool {
        if depth == 0 {
            return !collapsedFolderPaths.contains(path)
        }
        return expandedFolderPaths.contains(path)
    }

    nonisolated private static func childFolderURLs(of folderURL: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        return children.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isDirectory == true && values.isHidden != true
        }
        .sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func makeScopeRow(_ scope: LibraryScope, tag: Int, folderRow: LibraryFolderRow? = nil) -> NSView {
        let row = LibrarySourceRowView()
        row.identifier = NSUserInterfaceItemIdentifier("LibrarySourceRow-\(tag)")
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceRowHeight).isActive = true
        row.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceRowWidth).isActive = true

        let button = makeScopeButton(scope, tag: tag)
        if case .folder(let folderURL) = scope {
            let menu = makeFolderContextMenu(for: folderURL)
            row.menu = menu
            row.targetDirectory = folderURL
            row.canDropNotes = { [weak self] noteURLs, targetDirectory in
                self?.canMoveDraggedNotesForLibrary(at: noteURLs, to: targetDirectory) ?? false
            }
            row.onDropNotes = { [weak self] noteURLs, targetDirectory in
                guard let movedURLs = try? self?.moveDraggedNotesForLibrary(at: noteURLs, to: targetDirectory) else {
                    return false
                }
                return !movedURLs.isEmpty
            }
            button.menu = menu
        }
        let overlay = PassthroughOverlayView()
        let countLabel = NSTextField(labelWithString: "")
        countLabel.identifier = NSUserInterfaceItemIdentifier("LibrarySourceCount-\(tag)")
        countLabel.font = .systemFont(ofSize: LibraryNotesLayout.sourceCountFontSize, weight: .medium)
        countLabel.textColor = panelTertiaryTextColor()
        countLabel.alignment = .right
        let depth = folderRow?.depth ?? 0
        let leadingInset = CGFloat(depth * 16)

        row.addSubview(button)
        row.addSubview(overlay)
        overlay.addSubview(countLabel)
        let chevronButton = folderRow.flatMap { makeFolderDisclosureButton(for: $0, tag: tag) }
        if let chevronButton {
            row.addSubview(chevronButton)
            chevronButton.translatesAutoresizingMaskIntoConstraints = false
        }

        button.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: row.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            countLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 44)
        ]
        if let chevronButton {
            constraints.append(contentsOf: [
                chevronButton.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: leadingInset),
                chevronButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevronButton.widthAnchor.constraint(equalToConstant: 16),
                chevronButton.heightAnchor.constraint(equalToConstant: 18),
                button.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: 2)
            ])
        } else {
            constraints.append(button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: leadingInset))
        }
        NSLayoutConstraint.activate(constraints)

        sourceButtons.append(button)
        sourceCountLabels[tag] = countLabel
        return row
    }

    private func makeFolderDisclosureButton(for folderRow: LibraryFolderRow, tag: Int) -> NSButton? {
        guard folderRow.hasChildren else { return nil }
        let isCollapsed = !isSourceFolderExpanded(path: folderRow.url.standardizedFileURL.path, depth: folderRow.depth)
        let symbolName = isCollapsed ? "chevron.right" : "chevron.down"
        let button = NSButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: "展开或折叠文件夹") ?? NSImage(),
            target: self,
            action: #selector(folderDisclosurePressed(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier("LibraryFolderDisclosure-\(tag)")
        button.tag = tag
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = panelTertiaryTextColor()
        return button
    }

    private func makeScopeButton(_ scope: LibraryScope, tag: Int) -> NSButton {
        let button = NSButton(title: scope.buttonTitle, target: self, action: #selector(scopeButtonPressed(_:)))
        button.tag = tag
        button.image = NSImage(systemSymbolName: scope.symbolName, accessibilityDescription: scope.buttonTitle)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.font = .systemFont(ofSize: LibraryNotesLayout.sourceButtonFontSize, weight: .medium)
        button.contentTintColor = panelSecondaryTextColor()
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.cornerCurve = .continuous
        return button
    }

    private func refreshSourceSelection() {
        for button in sourceButtons {
            let isSelected = scope(for: button) == selectedScope
            button.layer?.backgroundColor = isSelected
                ? LibrarySourceSelectionPalette.backgroundColor.cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected
                ? LibrarySourceSelectionPalette.foregroundColor
                : panelSecondaryTextColor()
            sourceCountLabels[button.tag]?.textColor = isSelected
                ? LibrarySourceSelectionPalette.foregroundColor
                : panelTertiaryTextColor()
        }
    }

    private func refreshSourceCounts(using allNotes: [NoteSearchResult]) {
        let recentCount = noteStore.listRecentFiles(limit: 80).count

        for button in sourceButtons {
            let count: Int
            switch scope(for: button) {
            case .all:
                count = allNotes.count
            case .recent:
                count = recentCount
            case .inbox:
                count = allNotes.filter { note in
                    note.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
                        || note.title.localizedCaseInsensitiveContains("Inbox")
                }.count
            case .trash:
                count = noteStore.listTrashedNotes(limit: 10_000).count
            case .folder(let url):
                let folderPath = url.standardizedFileURL.path
                count = allNotes.filter { note in
                    let noteFolderPath = note.url.deletingLastPathComponent().standardizedFileURL.path
                    return noteFolderPath == folderPath || noteFolderPath.hasPrefix(folderPath + "/")
                }.count
            case .tag(let tag):
                count = allNotes.filter { note in
                    note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                }.count
            }
            sourceCountLabels[button.tag]?.stringValue = count > 0 ? String(count) : ""
        }
    }

    private func reloadNotes(
        selecting preferredURL: URL? = nil,
        loadFirstIfNeeded: Bool,
        hydratePreviews: Bool = true,
        allNotesSnapshot: [NoteSearchResult]? = nil,
        refreshCounts: Bool = true
    ) {
        cancelActiveSearchResultReload()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsAllNotes = query.isEmpty || refreshCounts
        let allNotes = allNotesSnapshot ?? (needsAllNotes ? allNoteResults(limit: Self.sourceCountSnapshotLimit) : [])
        searchScopeControl.isHidden = query.isEmpty
        notes = query.isEmpty
            ? notesForSelectedScope(limit: 240, hydratePreviews: hydratePreviews, allNotes: allNotes)
            : searchResultsForSelectedScope(query: query, limit: 240)
        listRows = buildGroupedRows(for: notes)
        updateNoteListHeader(query: query)

        suppressSelectionChanges = true
        tableView.reloadData()
        updateNoteListEmptyState(query: query)

        let preferredPath = preferredURL?.standardizedFileURL.path
        var noteToLoad: NoteSearchResult?
        if let preferredPath,
           let row = rowIndex(for: preferredPath) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            noteToLoad = note(at: row)
        } else if loadFirstIfNeeded,
                  let firstNoteRow = listRows.firstIndex(where: { $0.note != nil }) {
            tableView.selectRowIndexes(IndexSet(integer: firstNoteRow), byExtendingSelection: false)
            noteToLoad = note(at: firstNoteRow)
        } else {
            tableView.deselectAll(nil)
        }

        suppressSelectionChanges = false

        if loadFirstIfNeeded, let noteToLoad {
            load(note: noteToLoad)
        } else if selectedURL == nil {
            updateEmptyState()
        }
        if refreshCounts {
            sourceCountSnapshot = allNotes
            refreshSourceCounts(using: allNotes)
        }
        refreshSourceSelection()
        updateToolbarActionState()
    }

    private func updateNoteListHeader(query: String) {
        let title = query.isEmpty
            ? selectedScope.listTitle
            : (searchScopeControl.selectedSegment == 1 ? LibraryScope.all.listTitle : selectedScope.listTitle)
        noteListTitleLabel.stringValue = title
        if query.isEmpty {
            noteListCountLabel.stringValue = isFullLibrarySnapshotLoading
                ? "\(notes.count) 条笔记 · 正在索引..."
                : "\(notes.count) 条笔记"
        } else {
            noteListCountLabel.stringValue = "\(notes.count) 个结果"
        }
    }

    private func updateNoteListEmptyState(query: String) {
        let isEmpty = listRows.isEmpty
        noteListEmptyLabel.isHidden = !isEmpty
        guard isEmpty else { return }

        if !query.isEmpty {
            noteListEmptyLabel.stringValue = "未找到结果"
        } else if selectedScope == .trash {
            noteListEmptyLabel.stringValue = "最近删除为空"
        } else {
            noteListEmptyLabel.stringValue = "没有笔记"
        }
    }

    private func notesForSelectedScope(limit: Int, hydratePreviews: Bool = true, allNotes: [NoteSearchResult]) -> [NoteSearchResult] {
        switch selectedScope {
        case .all:
            return Array(allNotes.prefix(limit))
        case .recent:
            return recentNoteResults(limit: min(limit, 80), hydratePreview: hydratePreviews)
        case .inbox:
            return Array(allNotes.filter { note in
                note.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
                    || note.title.localizedCaseInsensitiveContains("Inbox")
            }.prefix(limit))
        case .trash:
            return noteStore.listTrashedNotes(limit: limit)
        case .folder(let url):
            let folderPath = url.standardizedFileURL.path
            return Array(allNotes.filter { note in
                let noteFolderPath = note.url.deletingLastPathComponent().standardizedFileURL.path
                return noteFolderPath == folderPath || noteFolderPath.hasPrefix(folderPath + "/")
            }.prefix(limit))
        case .tag(let tag):
            return Array(allNotes.filter { note in
                note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }.prefix(limit))
        }
    }

    private func searchResultsForSelectedScope(query: String, limit: Int) -> [NoteSearchResult] {
        searchResults(
            for: selectedScope,
            query: query,
            limit: limit,
            searchesAllNotes: searchScopeControl.selectedSegment == 1
        )
    }

    private func searchResults(
        for scope: LibraryScope,
        query: String,
        limit: Int,
        searchesAllNotes: Bool
    ) -> [NoteSearchResult] {
        librarySearchResults(
            noteStore: noteStore,
            scope: scope,
            query: query,
            limit: limit,
            searchesAllNotes: searchesAllNotes
        )
    }

    private func allNoteResults(limit: Int) -> [NoteSearchResult] {
        noteStore.listNotes(limit: limit)
    }

    private func recentNoteResults(limit: Int, hydratePreview: Bool) -> [NoteSearchResult] {
        noteStore.listRecentFiles(limit: limit).enumerated().map { index, note in
            let loaded = hydratePreview && index < 80 ? try? noteStore.loadNote(at: note.url) : nil
            return NoteSearchResult(
                url: note.url,
                title: loaded?.title ?? note.title,
                snippet: loaded.flatMap { firstMeaningfulLine(from: $0.body) } ?? "",
                modifiedAt: note.modifiedAt,
                tags: loaded?.tags ?? [],
                hasAttachments: loaded.map { MarkdownEditorDocument.containsAttachmentReference(in: $0.body) } ?? false,
                thumbnailURL: loaded.flatMap { MarkdownEditorDocument.firstLocalImageURL(in: $0.body, relativeTo: note.url) }
            )
        }
    }

    private func firstMeaningfulLine(from body: String) -> String? {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func buildGroupedRows(for notes: [NoteSearchResult], now: Date = Date()) -> [LibraryNoteListRow] {
        var rows: [LibraryNoteListRow] = []
        var currentGroup: String?
        for note in notes {
            let group = groupTitle(for: note.modifiedAt, now: now)
            if group != currentGroup {
                rows.append(.group(title: group))
                currentGroup = group
            }
            rows.append(.note(note))
        }
        return rows
    }

    private func rowIndex(for standardizedPath: String) -> Int? {
        listRows.firstIndex { row in
            row.note?.url.standardizedFileURL.path == standardizedPath
        }
    }

    private func note(at row: Int) -> NoteSearchResult? {
        guard listRows.indices.contains(row) else { return nil }
        return listRows[row].note
    }

    private func groupTitle(for date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if (2...7).contains(daysAgo) {
            return "过去 7 天"
        }
        if (8...30).contains(daysAgo) {
            return "过去 30 天"
        }
        return String(calendar.component(.year, from: date))
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        listRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch listRows[row] {
        case .group(let title):
            let identifier = NSUserInterfaceItemIdentifier("LibraryGroupHeaderCell")
            let cell: LibraryGroupHeaderCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? LibraryGroupHeaderCellView {
                cell = reused
            } else {
                cell = LibraryGroupHeaderCellView()
                cell.identifier = identifier
            }
            cell.titleLabel.stringValue = title
            return cell
        case .note(let note):
            return noteCell(for: note, tableView: tableView)
        }
    }

    private func noteCell(for note: NoteSearchResult, tableView: NSTableView) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("LibraryNoteCell")
        let cell: LibraryNoteCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? LibraryNoteCellView {
            cell = reused
        } else {
            cell = LibraryNoteCellView()
            cell.identifier = identifier
        }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cell.titleLabel.attributedStringValue = highlightedSearchString(
            note.title.isEmpty ? "无标题" : note.title,
            font: cell.titleLabel.font ?? .systemFont(ofSize: LibraryNotesLayout.noteTitleFontSize, weight: .semibold),
            baseColor: panelPrimaryTextColor(),
            query: query
        )
        cell.snippetLabel.attributedStringValue = highlightedSearchString(
            note.snippet.isEmpty ? " " : note.snippet,
            font: cell.snippetLabel.font ?? .systemFont(ofSize: LibraryNotesLayout.noteSnippetFontSize),
            baseColor: panelSecondaryTextColor(),
            query: query
        )
        let thumbnailImage = thumbnailImage(for: note)
        cell.thumbnailImageView.image = thumbnailImage
        cell.thumbnailImageView.isHidden = thumbnailImage == nil
        cell.attachmentImageView.isHidden = !note.hasAttachments || thumbnailImage != nil
        cell.metaLabel.stringValue = metadataText(for: note)
        return cell
    }

    private func thumbnailImage(for note: NoteSearchResult) -> NSImage? {
        guard let thumbnailURL = note.thumbnailURL,
              FileManager.default.fileExists(atPath: thumbnailURL.path) else {
            return nil
        }
        return NSImage(contentsOf: thumbnailURL)
    }

    func highlightedSearchString(
        _ text: String,
        font: NSFont,
        baseColor: NSColor,
        query: String
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: baseColor
        ])
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !text.isEmpty else { return attributed }

        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let match = nsText.range(
                of: trimmedQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound, match.length > 0 else { break }

            attributed.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.34),
                .foregroundColor: panelPrimaryTextColor()
            ], range: match)

            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return attributed
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard listRows.indices.contains(row) else { return false }
        if case .group = listRows[row] {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        note(at: row) != nil
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let note = note(at: row) else { return nil }
        return note.url as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        draggingImageForRowsWith rowIndexes: IndexSet,
        tableColumns: [NSTableColumn],
        event: NSEvent,
        offset dragImageOffset: UnsafeMutablePointer<NSPoint>
    ) -> NSImage {
        if let image = noteDragPreviewImageForLibrary(rowIndexes: rowIndexes) {
            dragImageOffset.pointee = NSPoint(x: -18, y: 18)
            return image
        }

        return tableView.dragImageForRows(with: rowIndexes, tableColumns: tableColumns, event: event, offset: dragImageOffset)
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        session.draggingFormation = noteDragPreviewCountForLibrary(rowIndexes: rowIndexes) > 1 ? .pile : .default
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if note(at: row) == nil {
            return LibraryNotesLayout.noteGroupRowHeight
        }
        return LibraryNotesLayout.noteRowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LibraryNoteRowView()
        rowView.isGroupRow = note(at: row) == nil
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionChanges else { return }
        do {
            try saveCurrentNoteIfNeeded()
            if preservesCurrentLoadedNoteForMultiSelection() {
                updateToolbarActionState()
            } else {
                loadSelectedRow()
            }
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let object = obj.object as AnyObject? else { return }

        if object === searchField {
            scheduleSearchReloadFromTyping()
            return
        }

        if object === titleField {
            markDirty()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField else { return false }
        flushPendingSearchReload()

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            return clearSearchFromKeyboard()
        }

        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            return stepSearchResult(.next)
        }

        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            return stepSearchResult(.previous)
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return loadFocusedNoteListResultFromSearch()
        }

        return false
    }

    func textDidChange(_ notification: Notification) {
        if let object = notification.object as AnyObject?, object === editorTextView {
            libraryUserDidEdit()
        } else {
            markDirty()
        }
    }

    @objc
    private func searchScopeChanged(_ sender: NSSegmentedControl) {
        cancelPendingSearchReload()
        performSearchReload()
    }

    @objc
    private func scopeButtonPressed(_ sender: NSButton) {
        do {
            try saveCurrentNoteIfNeeded()
            selectedScope = scope(for: sender)
            reloadNotes(loadFirstIfNeeded: true)
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    @objc
    private func folderDisclosurePressed(_ sender: NSButton) {
        let index = sender.tag - 10
        guard sourceFolderRows.indices.contains(index) else { return }
        let folderURL = sourceFolderRows[index].url.standardizedFileURL
        let folderPath = folderURL.path
        let isExpanded = isSourceFolderExpanded(path: folderPath, depth: sourceFolderRows[index].depth)

        if isExpanded {
            if sourceFolderRows[index].depth == 0 {
                collapsedFolderPaths.insert(folderPath)
            } else {
                expandedFolderPaths.remove(folderPath)
            }
            expandedFolderPaths = expandedFolderPaths.filter { !$0.hasPrefix(folderPath + "/") }
            if case .folder(let selectedFolderURL) = selectedScope {
                let selectedPath = selectedFolderURL.standardizedFileURL.path
                if selectedPath.hasPrefix(folderPath + "/") {
                    selectedScope = .folder(folderURL)
                }
            }
        } else if sourceFolderRows[index].depth == 0 {
            collapsedFolderPaths.remove(folderPath)
        } else {
            expandedFolderPaths.insert(folderPath)
        }

        reloadSourceFolderRowsForCurrentState()
        reloadNotes(loadFirstIfNeeded: true)
    }

    @objc
    private func sourceSectionDisclosurePressed(_ sender: NSButton) {
        guard let section = LibrarySourceSection(rawValue: sender.tag) else { return }

        switch section {
        case .folders:
            sourceFoldersSectionCollapsed.toggle()
            if !sourceFoldersSectionCollapsed {
                scheduleDeferredSourceFolderLoad()
            }
        case .tags:
            sourceTagsSectionCollapsed.toggle()
            if !sourceTagsSectionCollapsed {
                scheduleDeferredSourceTagLoad()
            }
        }

        sender.image = NSImage(
            systemSymbolName: isSourceSectionCollapsed(section) ? "chevron.right" : "chevron.down",
            accessibilityDescription: section.title
        )
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        refreshSourceCounts(using: sourceCountSnapshot)
        refreshSourceSelection()
    }

    private func scope(for button: NSButton) -> LibraryScope {
        switch button.tag {
        case 0:
            return .all
        case 1:
            return .recent
        case 2:
            return .inbox
        case 3:
            return .trash
        case 10..<100:
            let index = button.tag - 10
            guard sourceFolderRows.indices.contains(index) else { return .all }
            return .folder(sourceFolderRows[index].url)
        case 100...:
            let index = button.tag - 100
            guard sourceTagNames.indices.contains(index) else { return .all }
            return .tag(sourceTagNames[index])
        default:
            return .all
        }
    }

    @objc
    private func addFolderPressed() {
        guard let folderName = promptForText(
            title: "新建文件夹",
            message: "输入文件夹名称。",
            placeholder: "新建文件夹",
            defaultValue: "新建文件夹"
        ) else { return }

        do {
            _ = try createLibraryFolder(named: folderName)
        } catch {
            presentErrorAlert(message: "无法新建文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func toggleSourceListPressed() {
        toggleSourceListForLibrary()
    }

    @objc
    private func newNotePressed() {
        do {
            try saveCurrentNoteIfNeeded()
            if selectedScope == .trash {
                selectedScope = .all
            }
            isLoadingInitialNote = false
            selectedURL = nil
            selectedTags = []
            suppressSelectionChanges = true
            tableView.deselectAll(nil)
            suppressSelectionChanges = false
            setEditorEditable(true)
            applyDocument(title: "", body: "", tags: [])
            isDirty = false
            statusLabel.stringValue = "新笔记"
            updateEmptyState()
            refreshSourceSelection()
            updateToolbarActionState()
            titleField.becomeFirstResponder()
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    @objc
    private func savePressed() {
        do {
            _ = try saveCurrentNoteForLibrary()
        } catch {
            presentErrorAlert(message: "保存失败", details: error.localizedDescription)
        }
    }

    @objc
    private func openSelectedInSeparateWindow() {
        guard canUseSingleSelectedNote, let selectedURL else { return }
        onOpenInSeparateWindow(selectedURL)
    }

    private func handleNoteListKeyCommand(_ command: LibraryNoteKeyCommand) -> Bool {
        switch command {
        case .open:
            guard selectedURL != nil else { return false }
            openSelectedInSeparateWindow()
            return true
        case .delete:
            guard selectedURL != nil else { return false }
            do {
                try deleteSelectedNoteForLibrary()
                return true
            } catch {
                presentErrorAlert(message: selectedScope == .trash ? "永久删除失败" : "删除失败", details: error.localizedDescription)
                return true
            }
        case .moveDown:
            return moveNoteListSelection(.next)
        case .moveUp:
            return moveNoteListSelection(.previous)
        }
    }

    private func clearSearchFromKeyboard() -> Bool {
        guard !searchField.stringValue.isEmpty else { return false }
        searchField.stringValue = ""
        cancelPendingSearchReload()
        performSearchReload()
        removeEditorSearchHighlights()
        return true
    }

    private func scheduleSearchReloadFromTyping() {
        searchReloadWorkItem?.cancel()
        hasPendingSearchReload = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSearchReload()
        }
        searchReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(140), execute: workItem)
    }

    private func flushPendingSearchReload() {
        guard hasPendingSearchReload else { return }
        cancelPendingSearchReload()
        performSearchReload(synchronously: true)
    }

    private func cancelPendingSearchReload() {
        searchReloadWorkItem?.cancel()
        searchReloadWorkItem = nil
        hasPendingSearchReload = false
    }

    private func cancelActiveSearchResultReload() {
        searchResultsTask?.cancel()
        searchResultsTask = nil
        searchResultsGeneration += 1
    }

    private func performSearchReload(synchronously: Bool = false) {
        cancelPendingSearchReload()
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            reloadNotes(selecting: selectedURL, loadFirstIfNeeded: false, refreshCounts: true)
            applyEditorSearchHighlightsForCurrentQuery()
        } else if synchronously {
            reloadNotes(selecting: selectedURL, loadFirstIfNeeded: false, refreshCounts: false)
            applyEditorSearchHighlightsForCurrentQuery()
        } else {
            scheduleSearchResultReload(query: query, selecting: selectedURL)
        }
    }

    private func scheduleSearchResultReload(query: String, selecting preferredURL: URL?) {
        cancelActiveSearchResultReload()
        let generation = searchResultsGeneration
        let scope = selectedScope
        let searchesAllNotes = searchScopeControl.selectedSegment == 1
        let noteStore = noteStore
        searchScopeControl.isHidden = false
        updateNoteListHeader(query: query)

        let task = Task.detached(priority: .userInitiated) { [noteStore, scope, query, searchesAllNotes, generation, preferredURL] in
            guard !Task.isCancelled else { return }
            let results = librarySearchResults(
                noteStore: noteStore,
                scope: scope,
                query: query,
                limit: 240,
                searchesAllNotes: searchesAllNotes
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.searchResultsGeneration == generation,
                      self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                      self.selectedScope == scope,
                      (self.searchScopeControl.selectedSegment == 1) == searchesAllNotes else {
                    return
                }
                self.applySearchResults(results, query: query, selecting: preferredURL)
            }
        }
        searchResultsTask = task
    }

    private func applySearchResults(_ results: [NoteSearchResult], query: String, selecting preferredURL: URL?) {
        notes = results
        listRows = buildGroupedRows(for: notes)
        updateNoteListHeader(query: query)

        suppressSelectionChanges = true
        tableView.reloadData()
        updateNoteListEmptyState(query: query)

        if let preferredPath = preferredURL?.standardizedFileURL.path,
           let row = rowIndex(for: preferredPath) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        suppressSelectionChanges = false

        if selectedURL == nil {
            updateEmptyState()
        }
        refreshSourceSelection()
        updateToolbarActionState()
        applyEditorSearchHighlightsForCurrentQuery()
    }

    private enum NoteListResultDirection {
        case next
        case previous
    }

    private func moveNoteListSelection(_ direction: NoteListResultDirection) -> Bool {
        let noteRows = listRows.indices.filter { listRows[$0].note != nil }
        guard !noteRows.isEmpty else { return false }

        let selectedRow = tableView.selectedRow
        let targetRow: Int
        if let currentIndex = noteRows.firstIndex(of: selectedRow) {
            switch direction {
            case .next:
                targetRow = noteRows[min(currentIndex + 1, noteRows.count - 1)]
            case .previous:
                targetRow = noteRows[max(currentIndex - 1, 0)]
            }
        } else if selectedRow >= 0 {
            switch direction {
            case .next:
                targetRow = noteRows.first(where: { $0 > selectedRow }) ?? noteRows[noteRows.count - 1]
            case .previous:
                targetRow = noteRows.last(where: { $0 < selectedRow }) ?? noteRows[0]
            }
        } else {
            targetRow = direction == .next ? noteRows[0] : noteRows[noteRows.count - 1]
        }

        do {
            try saveCurrentNoteIfNeeded()
            suppressSelectionChanges = true
            tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
            suppressSelectionChanges = false
            tableView.scrollRowToVisible(targetRow)
            loadSelectedRow()
            return true
        } catch {
            suppressSelectionChanges = false
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return true
        }
    }

    private func loadFocusedNoteListResultFromSearch() -> Bool {
        guard selectNoteListRowIfNeeded() else { return false }
        loadSelectedRow()
        editorTextView.window?.makeFirstResponder(editorTextView)
        return true
    }

    private func stepSearchResult(_ direction: NoteListResultDirection) -> Bool {
        let noteRows = listRows.indices.filter { listRows[$0].note != nil }
        guard !noteRows.isEmpty else { return false }

        let selectedRow = tableView.selectedRow
        let targetRow: Int
        if let currentIndex = noteRows.firstIndex(of: selectedRow) {
            switch direction {
            case .next:
                targetRow = noteRows[min(currentIndex + 1, noteRows.count - 1)]
            case .previous:
                targetRow = noteRows[max(currentIndex - 1, 0)]
            }
        } else {
            targetRow = direction == .next ? noteRows[0] : noteRows[noteRows.count - 1]
        }

        tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(targetRow)
        return true
    }

    private func selectNoteListRowIfNeeded() -> Bool {
        if tableView.selectedRow >= 0, note(at: tableView.selectedRow) != nil {
            return true
        }

        let row = listRows.firstIndex(where: { $0.note != nil })
        guard let row else {
            return false
        }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        return true
    }

    @objc
    private func formatPressed(_ sender: Any?) {
        guard canEditCurrentDocument else { return }
        let menu = makeFormatMenu()
        guard !menu.items.isEmpty else { return }

        if let item = sender as? NSToolbarItem,
           let view = item.view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY - 4), in: view)
        } else if let view = sender as? NSView {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY - 4), in: view)
        } else if let contentView = window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 40), in: contentView)
        }
    }

    @objc
    private func formatMenuItemPressed(_ sender: NSMenuItem) {
        guard let command = LibraryFormatCommand(rawValue: sender.tag) else { return }
        applyFormatCommand(command)
    }

    @objc
    private func checklistPressed() {
        guard canEditCurrentDocument else { return }
        focusEditorForLibraryAction()
        toggleParagraphKind(.checklist(checked: false))
    }

    @objc
    private func tablePressed() {
        guard canEditCurrentDocument else { return }
        insertTableForLibrary()
    }

    @objc
    private func linkPressed() {
        guard canEditCurrentDocument else { return }
        let defaultLabel = selectedTextForLinkDefault()
        guard let url = promptForText(
            title: "插入链接",
            message: "输入链接地址。",
            placeholder: "https://example.com",
            defaultValue: ""
        ) else { return }
        insertLinkForLibrary(label: defaultLabel.isEmpty ? url : defaultLabel, url: url)
    }

    @objc
    private func attachmentPressed() {
        guard canEditCurrentDocument else { return }
        let panel = NSOpenPanel()
        panel.title = "添加附件"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        do {
            for url in panel.urls {
                _ = try insertAttachmentReferenceForLibrary(from: url)
            }
        } catch {
            presentErrorAlert(message: "添加附件失败", details: error.localizedDescription)
        }
    }

    @objc
    private func moveSelectedNotePressed(_ sender: Any?) {
        guard canMoveSelectedNote else { return }
        let menu = makeMoveNoteMenu()
        guard !menu.items.isEmpty else { return }

        if let item = sender as? NSToolbarItem,
           let view = item.view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY - 4), in: view)
        } else if let contentView = window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 40), in: contentView)
        }
    }

    @objc
    private func moveNoteMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }
        do {
            _ = try moveSelectedNotesForLibrary(to: directory)
        } catch {
            presentErrorAlert(message: "移动失败", details: error.localizedDescription)
        }
    }

    @objc
    private func deleteSelectedNotePressed() {
        do {
            try deleteSelectedNotesForLibrary()
        } catch {
            presentErrorAlert(message: "删除失败", details: error.localizedDescription)
        }
    }

    @objc
    private func renameFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL,
              let folderName = promptForText(
                title: "重命名文件夹",
                message: "输入新的文件夹名称。",
                placeholder: "文件夹名称",
                defaultValue: directory.lastPathComponent
              ) else { return }

        do {
            selectedScope = .folder(directory)
            _ = try renameSelectedFolderForLibrary(to: folderName)
        } catch {
            presentErrorAlert(message: "无法重命名文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func deleteFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL,
              confirmDestructiveAction(
                title: "删除文件夹？",
                message: "文件夹中的 Markdown 笔记会移动到最近删除。"
              ) else { return }

        do {
            selectedScope = .folder(directory)
            try deleteSelectedFolderForLibrary()
        } catch {
            presentErrorAlert(message: "无法删除文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func restoreSelectedNotePressed() {
        do {
            _ = try restoreSelectedNoteForLibrary()
        } catch {
            presentErrorAlert(message: "恢复失败", details: error.localizedDescription)
        }
    }

    @objc
    private func revealSelectedNoteInFinderPressed() {
        let urls = revealSelectedNotesInFinderForLibrary()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc
    private func copySelectedMarkdownPathPressed() {
        _ = copySelectedMarkdownPathForLibrary()
    }

    @objc
    private func copySelectedMarkdownContentPressed() {
        do {
            _ = try copySelectedMarkdownContentForLibrary()
        } catch {
            presentErrorAlert(message: "复制失败", details: error.localizedDescription)
        }
    }

    @objc
    private func shareSelectedMarkdownPressed(_ sender: Any?) {
        do {
            let sourceURLs = try shareSelectedMarkdownFilesForLibrary()
            guard !sourceURLs.isEmpty else { return }
            let picker = NSSharingServicePicker(items: sourceURLs)
            if let item = sender as? NSToolbarItem,
               let view = item.view {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            } else if let contentView = window?.contentView {
                let anchor = NSRect(x: contentView.bounds.midX, y: contentView.bounds.maxY - 44, width: 1, height: 1)
                picker.show(relativeTo: anchor, of: contentView, preferredEdge: .maxY)
            }
        } catch {
            presentErrorAlert(message: "分享失败", details: error.localizedDescription)
        }
    }

    @objc
    private func exportSelectedMarkdownPressed() {
        guard canExportSelectedNote else { return }

        let sourceURLs = selectedMarkdownFileURLsForLibrary()
        if sourceURLs.count > 1 {
            let panel = NSOpenPanel()
            panel.title = "导出 Markdown 笔记"
            panel.prompt = "导出"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false

            guard panel.runModal() == .OK,
                  let destinationDirectory = panel.url else { return }

            do {
                _ = try exportSelectedMarkdownFilesForLibrary(to: destinationDirectory)
            } catch {
                presentErrorAlert(message: "导出失败", details: error.localizedDescription)
            }
            return
        }

        guard let sourceURL = sourceURLs.first else { return }

        let panel = NSSavePanel()
        panel.title = "导出 Markdown"
        panel.prompt = "导出"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText
        ].compactMap { $0 }
        panel.nameFieldStringValue = sourceURL.lastPathComponent

        guard panel.runModal() == .OK,
              let destinationURL = panel.url else { return }

        do {
            _ = try exportSelectedMarkdownForLibrary(to: destinationURL)
        } catch {
            presentErrorAlert(message: "导出失败", details: error.localizedDescription)
        }
    }

    private func loadSelectedRow() {
        let row = tableView.selectedRow
        guard let note = note(at: row) else {
            updateEmptyState()
            return
        }
        load(note: note)
    }

    private func load(note: NoteSearchResult) {
        isLoadingInitialNote = false
        do {
            let loaded = try noteStore.loadNote(at: note.url)
            applyLoadedNoteResult(.success(loaded), for: note)
        } catch {
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    private func applyLoadedNoteResult(_ result: Result<LoadedLibraryNote, Error>, for note: NoteSearchResult) {
        isLoadingInitialNote = false
        switch result {
        case .success(let loaded):
            selectedURL = note.url
            setEditorEditable(selectedScope != .trash)
            applyDocument(title: loaded.title, body: loaded.body, tags: loaded.tags)
            isDirty = false
            statusLabel.stringValue = editorDateText(for: note.modifiedAt)
            applyEditorSearchHighlightsForCurrentQuery()
            updateEmptyState()
            updateToolbarActionState()
        case .failure(let error):
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    private func applyDocument(title: String, body: String, tags: [String]) {
        suppressEditorChanges = true
        titleField.stringValue = title
        selectedTags = tags
        editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(markdown: body, theme: theme, baseURL: selectedURL))
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
        editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        suppressEditorChanges = false
    }

    func applyEditorSearchHighlightsForCurrentQuery() {
        applyEditorSearchHighlights(query: searchField.stringValue)
    }

    func applyEditorSearchHighlights(query: String) {
        guard let storage = editorTextView.textStorage else { return }
        let wasSuppressingEditorChanges = suppressEditorChanges
        suppressEditorChanges = true
        defer { suppressEditorChanges = wasSuppressingEditorChanges }

        removeEditorSearchHighlights()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, storage.length > 0 else { return }

        let nsText = storage.string as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let match = nsText.range(
                of: trimmedQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound, match.length > 0 else { break }

            storage.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.30),
                .qmSearchHighlight: true
            ], range: match)

            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
    }

    func removeEditorSearchHighlights() {
        guard let storage = editorTextView.textStorage, storage.length > 0 else { return }
        let wasSuppressingEditorChanges = suppressEditorChanges
        suppressEditorChanges = true
        defer { suppressEditorChanges = wasSuppressingEditorChanges }

        let fullRange = NSRange(location: 0, length: storage.length)
        var highlightedRanges: [NSRange] = []
        storage.enumerateAttribute(.qmSearchHighlight, in: fullRange, options: []) { value, range, _ in
            if value != nil {
                highlightedRanges.append(range)
            }
        }
        for range in highlightedRanges {
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(.qmSearchHighlight, range: range)
        }
    }

    private func markDirty() {
        guard !suppressEditorChanges, selectedScope != .trash else { return }
        isDirty = true
        updateEmptyState()
        statusLabel.stringValue = selectedURL == nil ? "新笔记，正在保存..." : "正在保存..."
        updateToolbarActionState()
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.autosaveCurrentNote()
            }
        }
    }

    private func autosaveCurrentNote() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard isDirty, selectedScope != .trash else { return }

        do {
            _ = try saveCurrentNote(force: false)
        } catch {
            statusLabel.stringValue = "自动保存失败"
        }
    }

    private func saveCurrentNoteIfNeeded() throws {
        guard isDirty else { return }
        _ = try saveCurrentNote(force: false)
    }

    @discardableResult
    private func saveCurrentNote(force: Bool) throws -> URL? {
        guard force || isDirty else { return selectedURL }
        guard selectedScope != .trash else { return selectedURL }
        autosaveTask?.cancel()
        autosaveTask = nil

        let rawTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "无标题" : rawTitle
        guard selectedURL != nil || !title.isEmpty || !body.isEmpty else { return nil }

        let savedURL: URL
        if let selectedURL {
            savedURL = try noteStore.updateNote(at: selectedURL, title: title, body: body, tags: selectedTags)
        } else {
            savedURL = try noteStore.saveNewNote(
                title: title,
                body: body,
                tags: selectedTags,
                in: targetDirectoryForNewNote()
            )
        }

        selectedURL = savedURL
        isDirty = false
        invalidateMovableNotePathCache()
        statusLabel.stringValue = editorDateText(for: Date())
        onSave(savedURL)
        updateEmptyState()
        updateToolbarActionState()
        return savedURL
    }

    @discardableResult
    func saveCurrentNoteForLibrary() throws -> URL? {
        let savedURL = try saveCurrentNote(force: true)
        if let savedURL {
            reloadNotes(selecting: savedURL, loadFirstIfNeeded: false)
        }
        return savedURL
    }

    func deleteSelectedNoteForLibrary() throws {
        try deleteSelectedNotesForLibrary()
    }

    func deleteSelectedNotesForLibrary() throws {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard !urls.isEmpty else { return }
        if selectedScope == .trash {
            for url in urls {
                try noteStore.permanentlyDeleteTrashedNote(at: url)
            }
        } else {
            try saveCurrentNoteIfNeeded()
            for url in urls {
                _ = try noteStore.trashNote(at: url)
            }
        }
        invalidateMovableNotePathCache()
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(loadFirstIfNeeded: true)
    }

    @discardableResult
    func restoreSelectedNoteForLibrary() throws -> URL? {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard selectedScope == .trash, !urls.isEmpty else { return nil }
        let restoredURLs = try urls.map { try noteStore.restoreTrashedNote(at: $0) }
        let restoredURL = restoredURLs.first
        invalidateMovableNotePathCache()
        selectedScope = .all
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(selecting: restoredURL, loadFirstIfNeeded: true)
        return restoredURL
    }

    func selectedMarkdownFileURLForLibrary() -> URL? {
        selectedMarkdownFileURLsForLibrary().first
    }

    func selectedMarkdownFileURLsForLibrary() -> [URL] {
        var urls: [URL] = []
        var seenPaths = Set<String>()

        for row in tableView.selectedRowIndexes.sorted() {
            guard let url = note(at: row)?.url.standardizedFileURL else { continue }
            if seenPaths.insert(url.path).inserted {
                urls.append(url)
            }
        }

        if urls.isEmpty,
           let selectedURL = selectedURL?.standardizedFileURL,
           seenPaths.insert(selectedURL.path).inserted {
            urls.append(selectedURL)
        }

        return urls
    }

    func noteDragPreviewCountForLibrary(rowIndexes: IndexSet) -> Int {
        var seenPaths = Set<String>()
        var count = 0
        for row in rowIndexes.sorted() {
            guard let path = note(at: row)?.url.standardizedFileURL.path,
                  seenPaths.insert(path).inserted else {
                continue
            }
            count += 1
        }
        return count
    }

    func noteDragPreviewBadgeTitleForLibrary(rowIndexes: IndexSet) -> String? {
        let count = noteDragPreviewCountForLibrary(rowIndexes: rowIndexes)
        return count > 1 ? String(count) : nil
    }

    func noteDragPreviewImageForLibrary(rowIndexes: IndexSet) -> NSImage? {
        let draggedNotes = rowIndexes.sorted().compactMap { note(at: $0) }
        guard let firstNote = draggedNotes.first else { return nil }

        let count = noteDragPreviewCountForLibrary(rowIndexes: rowIndexes)
        let imageSize = NSSize(width: 248, height: 64)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        if count > 1 {
            let shadowRect = NSRect(x: 8, y: 2, width: 232, height: 52)
            let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: 8, yRadius: 8)
            NSColor(calibratedWhite: 0.08, alpha: 0.78).setFill()
            shadowPath.fill()
        }

        let cardRect = NSRect(x: 0, y: 8, width: 232, height: 52)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8)
        NSColor(calibratedRed: 0.55, green: 0.43, blue: 0.08, alpha: 0.96).setFill()
        cardPath.fill()

        let title = firstNote.title.isEmpty ? "无标题" : firstNote.title
        let snippet = firstNote.snippet.isEmpty ? metadataText(for: firstNote) : firstNote.snippet
        (title as NSString).draw(
            in: NSRect(x: 16, y: 31, width: 176, height: 18),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        (snippet as NSString).draw(
            in: NSRect(x: 16, y: 15, width: 176, height: 14),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.72)
            ]
        )

        if let badgeTitle = noteDragPreviewBadgeTitleForLibrary(rowIndexes: rowIndexes) {
            let badgeRect = NSRect(x: 206, y: 38, width: 28, height: 22)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 11, yRadius: 11)
            NSColor.white.withAlphaComponent(0.96).setFill()
            badgePath.fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (badgeTitle as NSString).draw(
                in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 3, width: badgeRect.width, height: 16),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: NSColor(calibratedRed: 0.38, green: 0.28, blue: 0.04, alpha: 1),
                    .paragraphStyle: paragraph
                ]
            )
        }

        return image
    }

    @discardableResult
    func copySelectedMarkdownPathForLibrary() -> String? {
        let paths = selectedMarkdownFileURLsForLibrary().map(\.path)
        guard !paths.isEmpty else { return nil }
        let path = paths.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        return path
    }

    func revealSelectedNoteInFinderForLibrary() -> URL? {
        revealSelectedNotesInFinderForLibrary().first
    }

    func revealSelectedNotesInFinderForLibrary() -> [URL] {
        selectedMarkdownFileURLsForLibrary()
    }

    @discardableResult
    func copySelectedMarkdownContentForLibrary() throws -> String? {
        guard canExportSelectedNote else { return nil }

        try saveCurrentNoteIfNeeded()
        let markdown = try selectedMarkdownFileURLsForLibrary()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        return markdown
    }

    @discardableResult
    func shareSelectedMarkdownFileForLibrary() throws -> URL? {
        (try shareSelectedMarkdownFilesForLibrary()).first
    }

    @discardableResult
    func shareSelectedMarkdownFilesForLibrary() throws -> [URL] {
        guard canExportSelectedNote else { return [] }

        try saveCurrentNoteIfNeeded()
        return selectedMarkdownFileURLsForLibrary()
    }

    @discardableResult
    func exportSelectedMarkdownForLibrary(to destinationURL: URL) throws -> URL? {
        guard canExportSelectedNote,
              let sourceURL = selectedMarkdownFileURLForLibrary() else { return nil }

        try saveCurrentNoteIfNeeded()
        let destination = destinationURL.standardizedFileURL
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    @discardableResult
    func exportSelectedMarkdownFilesForLibrary(to destinationDirectoryURL: URL) throws -> [URL] {
        guard canExportSelectedNote else { return [] }

        try saveCurrentNoteIfNeeded()
        let destinationDirectory = destinationDirectoryURL.standardizedFileURL
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var reservedNames = Set<String>()
        return try selectedMarkdownFileURLsForLibrary().map { sourceURL in
            let destination = uniqueExportDestination(
                for: sourceURL,
                in: destinationDirectory,
                reservedNames: &reservedNames
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        }
    }

    private func preservesCurrentLoadedNoteForMultiSelection() -> Bool {
        guard tableView.selectedRowIndexes.count > 1,
              let selectedPath = selectedURL?.standardizedFileURL.path else {
            return false
        }
        return selectedMarkdownFileURLsForLibrary().contains {
            $0.standardizedFileURL.path == selectedPath
        }
    }

    private func uniqueExportDestination(
        for sourceURL: URL,
        in destinationDirectory: URL,
        reservedNames: inout Set<String>
    ) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidateName = sourceURL.lastPathComponent
        var suffix = 2

        while reservedNames.contains(candidateName)
            || FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(candidateName).path) {
            candidateName = pathExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(pathExtension)"
            suffix += 1
        }

        reservedNames.insert(candidateName)
        return destinationDirectory.appendingPathComponent(candidateName)
    }

    func searchForLibrary(query: String, allNotes: Bool) {
        cancelPendingSearchReload()
        cancelActiveSearchResultReload()
        searchField.stringValue = query
        searchScopeControl.selectedSegment = allNotes ? 1 : 0
        reloadNotes(
            loadFirstIfNeeded: false,
            refreshCounts: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        applyEditorSearchHighlightsForCurrentQuery()
    }

    func noteListSearchResultsForLibrary() -> [NoteSearchResult] {
        notes
    }

    var isSourceListVisibleForLibrary: Bool {
        sourceListView?.isHidden == false
    }

    @discardableResult
    func toggleSourceListForLibrary() -> Bool {
        setSourceListVisibleForLibrary(!isSourceListVisibleForLibrary)
    }

    @discardableResult
    func setSourceListVisibleForLibrary(_ isVisible: Bool) -> Bool {
        guard let sourceListView else { return false }
        sourceListView.isHidden = !isVisible
        sourceListView.superview?.needsLayout = true
        sourceListView.superview?.layoutSubtreeIfNeeded()
        updateToolbarActionState()
        return isSourceListVisibleForLibrary
    }

    @discardableResult
    func createLibraryFolder(named name: String) throws -> URL {
        let folderURL = try noteStore.createFolder(named: name, in: targetDirectoryForNewFolder())
        invalidateMovableNotePathCache()
        selectedScope = .folder(folderURL)
        reloadSourceFolderRowsForCurrentState()
        reloadNotes(loadFirstIfNeeded: true)
        return folderURL
    }

    @discardableResult
    func renameSelectedFolderForLibrary(to name: String) throws -> URL {
        guard case .folder(let folderURL) = selectedScope else {
            throw LibraryActionError.noFolderSelected
        }

        let renamedURL = try noteStore.renamePreferredDirectory(folderURL, to: name)
        invalidateMovableNotePathCache()
        selectedScope = .folder(renamedURL)
        reloadSourceFolderRowsForCurrentState()
        reloadNotes(loadFirstIfNeeded: true)
        return renamedURL
    }

    func deleteSelectedFolderForLibrary() throws {
        guard case .folder(let folderURL) = selectedScope else {
            throw LibraryActionError.noFolderSelected
        }

        _ = try noteStore.trashFolder(at: folderURL)
        invalidateMovableNotePathCache()
        selectedScope = .all
        clearCurrentDocumentAfterRemoval()
        reloadSourceFolderRowsForCurrentState()
        reloadNotes(loadFirstIfNeeded: true)
    }

    @discardableResult
    func moveSelectedNoteForLibrary(to directory: URL) throws -> URL {
        guard let movedURL = try moveSelectedNotesForLibrary(to: directory).first else {
            throw LibraryActionError.noNoteSelected
        }
        return movedURL
    }

    @discardableResult
    func moveSelectedNotesForLibrary(to directory: URL) throws -> [URL] {
        try saveCurrentNoteIfNeeded()
        guard selectedScope != .trash else {
            throw LibraryActionError.noNoteSelected
        }
        let sourceURLs = selectedMarkdownFileURLsForLibrary()
        guard !sourceURLs.isEmpty else {
            throw LibraryActionError.noNoteSelected
        }

        let targetDirectory = directory.standardizedFileURL
        let movedURLs = try sourceURLs.map { sourceURL in
            try noteStore.moveNote(at: sourceURL, to: targetDirectory)
        }
        invalidateMovableNotePathCache()
        selectedURL = movedURLs.first
        selectedScope = .folder(targetDirectory)
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(selecting: movedURLs.first, loadFirstIfNeeded: true)
        return movedURLs
    }

    func canMoveDraggedNoteForLibrary(at noteURL: URL, to directory: URL) -> Bool {
        canMoveDraggedNotesForLibrary(at: [noteURL], to: directory)
    }

    func canMoveDraggedNotesForLibrary(at noteURLs: [URL], to directory: URL) -> Bool {
        let sourceURLs = uniqueStandardizedFileURLs(from: noteURLs)
        guard !sourceURLs.isEmpty else { return false }
        return sourceURLs.allSatisfy { sourceURL in
            canMoveDraggedNoteForLibrary(sourceURL: sourceURL, to: directory)
        }
    }

    private func canMoveDraggedNoteForLibrary(sourceURL: URL, to directory: URL) -> Bool {
        let targetDirectory = directory.standardizedFileURL
        guard sourceURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
              FileManager.default.fileExists(atPath: sourceURL.path),
              sourceURL.deletingLastPathComponent().standardizedFileURL.path != targetDirectory.path,
              !isTrashURL(sourceURL) else {
            return false
        }

        return movableNotePathsForLibrary().contains(sourceURL.path)
    }

    @discardableResult
    func moveDraggedNoteForLibrary(at noteURL: URL, to directory: URL) throws -> URL {
        guard let movedURL = try moveDraggedNotesForLibrary(at: [noteURL], to: directory).first else {
            throw LibraryActionError.noNoteSelected
        }
        return movedURL
    }

    @discardableResult
    func moveDraggedNotesForLibrary(at noteURLs: [URL], to directory: URL) throws -> [URL] {
        let sourceURLs = uniqueStandardizedFileURLs(from: noteURLs)
        let targetDirectory = directory.standardizedFileURL
        guard canMoveDraggedNotesForLibrary(at: sourceURLs, to: targetDirectory) else {
            throw LibraryActionError.noNoteSelected
        }

        let selectedPath = selectedURL?.standardizedFileURL.path
        if sourceURLs.contains(where: { $0.path == selectedPath }) {
            try saveCurrentNoteIfNeeded()
        }

        let movedURLs = try sourceURLs.map { sourceURL in
            try noteStore.moveNote(at: sourceURL, to: targetDirectory)
        }
        invalidateMovableNotePathCache()
        selectedURL = movedURLs.first
        selectedScope = .folder(targetDirectory)
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(selecting: movedURLs.first, loadFirstIfNeeded: true)
        return movedURLs
    }

    private func uniqueStandardizedFileURLs(from urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }

    private func movableNotePathsForLibrary() -> Set<String> {
        if let movableNotePathCache {
            return movableNotePathCache
        }

        let paths = Set(noteStore.listNotes(limit: 10_000).map {
            $0.url.standardizedFileURL.path
        })
        movableNotePathCache = paths
        return paths
    }

    private func invalidateMovableNotePathCache() {
        movableNotePathCache = nil
    }

    private func clearCurrentDocumentAfterRemoval() {
        isLoadingInitialNote = false
        selectedURL = nil
        selectedTags = []
        isDirty = false
        setEditorEditable(selectedScope != .trash)
        applyDocument(title: "", body: "", tags: [])
        updateEmptyState()
    }

    private func setEditorEditable(_ isEditable: Bool) {
        titleField.isEditable = isEditable
        editorTextView.isEditable = isEditable
    }

    private func targetDirectoryForNewNote() -> URL {
        if case .folder(let folderURL) = selectedScope {
            return folderURL
        }
        return noteStore.notesDirectory
    }

    private func targetDirectoryForNewFolder() -> URL {
        if case .folder(let folderURL) = selectedScope {
            return folderURL
        }
        return noteStore.notesDirectory
    }

    private func updateEmptyState() {
        let hasContent = selectedURL != nil
            || !titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !editorTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        emptyLabel.isHidden = hasContent
    }

    private func metadataText(for note: NoteSearchResult) -> String {
        let folder = isTrashURL(note.url) ? "最近删除" : note.url.deletingLastPathComponent().lastPathComponent
        let tags = note.tags.prefix(3).map(libraryDisplayTag).joined(separator: " ")
        if tags.isEmpty {
            return "\(relativeDateText(for: note.modifiedAt)) · \(folder)"
        }
        return "\(relativeDateText(for: note.modifiedAt)) · \(folder) · \(tags)"
    }

    private func relativeDateText(for date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 {
            return "刚刚"
        }
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func editorDateText(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func isTrashURL(_ url: URL) -> Bool {
        let trashPath = noteStore.trashDirectory().standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    private var canUseSelectedNote: Bool {
        !selectedMarkdownFileURLsForLibrary().isEmpty
    }

    private var canUseSingleSelectedNote: Bool {
        selectedMarkdownFileURLsForLibrary().count == 1
    }

    private var canEditCurrentDocument: Bool {
        guard selectedScope != .trash else { return false }
        guard !isLoadingInitialNote else { return false }
        return selectedURL != nil
            || isDirty
            || statusLabel.stringValue == "新笔记"
            || !titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !editorTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canMoveSelectedNote: Bool {
        canUseSelectedNote && selectedScope != .trash && !sourceFolderRows.isEmpty
    }

    private var canExportSelectedNote: Bool {
        canUseSelectedNote && selectedScope != .trash
    }

    private var canRestoreSelectedNote: Bool {
        selectedScope == .trash && canUseSelectedNote
    }

    private var canShowMoreActions: Bool {
        canUseSelectedNote || canEditCurrentDocument
    }

    private func updateToolbarActionState() {
        let isTrashScope = selectedScope == .trash
        let selectionCount = selectedMarkdownFileURLsForLibrary().count
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.toggleSidebarToolbarItemIdentifier:
                let label = isSourceListVisibleForLibrary ? "隐藏资料库" : "显示资料库"
                item.label = label
                item.paletteLabel = label
                item.toolTip = label
                item.image = NSImage(
                    systemSymbolName: "sidebar.left",
                    accessibilityDescription: label
                )
            case Self.deleteToolbarItemIdentifier:
                item.label = isTrashScope
                    ? noteActionTitle(single: "永久删除", multiple: "永久删除 %d 条笔记", count: selectionCount)
                    : noteActionTitle(single: "删除", multiple: "删除 %d 条笔记", count: selectionCount)
                item.paletteLabel = item.label
                item.toolTip = item.label
                item.image = NSImage(
                    systemSymbolName: isTrashScope ? "trash.slash" : "trash",
                    accessibilityDescription: item.label
                )
            case Self.restoreToolbarItemIdentifier:
                let label = noteActionTitle(single: "恢复", multiple: "恢复 %d 条笔记", count: selectionCount)
                item.label = label
                item.paletteLabel = label
                item.toolTip = label
            case Self.exportToolbarItemIdentifier:
                (item as? NSMenuToolbarItem)?.menu = makeShareExportMenuForLibrary()
            case Self.moreToolbarItemIdentifier:
                (item as? NSMenuToolbarItem)?.menu = makeMoreActionsMenuForLibrary()
            case Self.editorToolsToolbarItemIdentifier:
                setEditorToolsToolbarGroupEnabled(canEditCurrentDocument, in: item)
            default:
                continue
            }
        }
        window?.toolbar?.validateVisibleItems()
        updateVisibleEditorToolsToolbarGroupEnabled()
    }

    private func updateVisibleEditorToolsToolbarGroupEnabled() {
        for item in window?.toolbar?.items ?? [] where item.itemIdentifier == Self.editorToolsToolbarItemIdentifier {
            setEditorToolsToolbarGroupEnabled(canEditCurrentDocument, in: item)
        }
    }

    private func setEditorToolsToolbarGroupEnabled(_ isEnabled: Bool, in item: NSToolbarItem) {
        item.isEnabled = isEnabled
        guard let view = item.view else { return }
        view.alphaValue = isEnabled
            ? LibraryNotesLayout.toolbarEditorToolsEnabledAlpha
            : LibraryNotesLayout.toolbarEditorToolsDisabledAlpha
        view.layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(
                isEnabled
                    ? LibraryNotesLayout.toolbarEditorToolsEnabledBorderAlpha
                    : LibraryNotesLayout.toolbarEditorToolsDisabledBorderAlpha
            )
            .cgColor
        setControls(in: view, enabled: isEnabled)
    }

    private func setControls(in view: NSView, enabled isEnabled: Bool) {
        if let control = view as? NSControl {
            control.isEnabled = isEnabled
        }
        view.subviews.forEach { setControls(in: $0, enabled: isEnabled) }
    }

    private func makeFolderContextMenu(for folderURL: URL) -> NSMenu {
        let menu = NSMenu()

        let renameItem = NSMenuItem(title: "重命名文件夹", action: #selector(renameFolderMenuItemPressed(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = folderURL
        menu.addItem(renameItem)

        let deleteItem = NSMenuItem(title: "删除文件夹", action: #selector(deleteFolderMenuItemPressed(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = folderURL
        deleteItem.isEnabled = folderURL.standardizedFileURL.path != noteStore.notesDirectory.standardizedFileURL.path
        menu.addItem(deleteItem)

        return menu
    }

    private func makeNoteContextMenu() -> NSMenu {
        let menu = NSMenu()
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        let moveItem = NSMenuItem(title: noteActionTitle(single: "移到文件夹", multiple: "移动 %d 条笔记到文件夹", count: selectionCount), action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveNoteMenu()
        moveItem.isEnabled = canMoveSelectedNote
        menu.addItem(moveItem)
        menu.addItem(.separator())

        let revealItem = NSMenuItem(title: noteActionTitle(single: "在 Finder 中显示", multiple: "在 Finder 中显示 %d 个文件", count: selectionCount), action: #selector(revealSelectedNoteInFinderPressed), keyEquivalent: "")
        revealItem.target = self
        revealItem.isEnabled = canUseSelectedNote
        menu.addItem(revealItem)

        let shareItem = NSMenuItem(title: noteActionTitle(single: "分享...", multiple: "分享 %d 个 Markdown 文件...", count: selectionCount), action: #selector(shareSelectedMarkdownPressed(_:)), keyEquivalent: "")
        shareItem.target = self
        shareItem.isEnabled = canExportSelectedNote
        menu.addItem(shareItem)

        let copyPathItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 路径", multiple: "复制 %d 个 Markdown 路径", count: selectionCount), action: #selector(copySelectedMarkdownPathPressed), keyEquivalent: "")
        copyPathItem.target = self
        copyPathItem.isEnabled = canUseSelectedNote
        menu.addItem(copyPathItem)

        let copyContentItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 内容", multiple: "复制 %d 条 Markdown 内容", count: selectionCount), action: #selector(copySelectedMarkdownContentPressed), keyEquivalent: "")
        copyContentItem.target = self
        copyContentItem.isEnabled = canExportSelectedNote
        menu.addItem(copyContentItem)

        let exportItem = NSMenuItem(title: noteActionTitle(single: "导出 Markdown...", multiple: "导出 %d 个 Markdown 文件...", count: selectionCount), action: #selector(exportSelectedMarkdownPressed), keyEquivalent: "")
        exportItem.target = self
        exportItem.isEnabled = canExportSelectedNote
        menu.addItem(exportItem)
        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: noteActionTitle(single: "删除", multiple: "删除 %d 条笔记", count: selectionCount), action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = canUseSelectedNote
        menu.addItem(deleteItem)

        return menu
    }

    func makeShareExportMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        let shareItem = NSMenuItem(title: noteActionTitle(single: "分享...", multiple: "分享 %d 个 Markdown 文件...", count: selectionCount), action: #selector(shareSelectedMarkdownPressed(_:)), keyEquivalent: "")
        shareItem.target = self
        shareItem.isEnabled = canExportSelectedNote
        menu.addItem(shareItem)

        let copyContentItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 内容", multiple: "复制 %d 条 Markdown 内容", count: selectionCount), action: #selector(copySelectedMarkdownContentPressed), keyEquivalent: "")
        copyContentItem.target = self
        copyContentItem.isEnabled = canExportSelectedNote
        menu.addItem(copyContentItem)

        let exportItem = NSMenuItem(title: noteActionTitle(single: "导出 Markdown...", multiple: "导出 %d 个 Markdown 文件...", count: selectionCount), action: #selector(exportSelectedMarkdownPressed), keyEquivalent: "")
        exportItem.target = self
        exportItem.isEnabled = canExportSelectedNote
        menu.addItem(exportItem)

        return menu
    }

    func makeMoreActionsMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let isTrashScope = selectedScope == .trash
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        let openItem = NSMenuItem(title: "独立窗口打开", action: #selector(openSelectedInSeparateWindow), keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = canUseSingleSelectedNote
        menu.addItem(openItem)

        let moveItem = NSMenuItem(title: noteActionTitle(single: "移到文件夹", multiple: "移动 %d 条笔记到文件夹", count: selectionCount), action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveNoteMenu()
        moveItem.isEnabled = canMoveSelectedNote
        menu.addItem(moveItem)

        let saveItem = NSMenuItem(title: "保存", action: #selector(savePressed), keyEquivalent: "s")
        saveItem.target = self
        saveItem.keyEquivalentModifierMask = [.command]
        saveItem.isEnabled = canEditCurrentDocument
        menu.addItem(saveItem)

        menu.addItem(.separator())

        let revealItem = NSMenuItem(title: noteActionTitle(single: "在 Finder 中显示", multiple: "在 Finder 中显示 %d 个文件", count: selectionCount), action: #selector(revealSelectedNoteInFinderPressed), keyEquivalent: "")
        revealItem.target = self
        revealItem.isEnabled = canUseSelectedNote
        menu.addItem(revealItem)

        let shareItem = NSMenuItem(title: noteActionTitle(single: "分享...", multiple: "分享 %d 个 Markdown 文件...", count: selectionCount), action: #selector(shareSelectedMarkdownPressed(_:)), keyEquivalent: "")
        shareItem.target = self
        shareItem.isEnabled = canExportSelectedNote
        menu.addItem(shareItem)

        let copyPathItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 路径", multiple: "复制 %d 个 Markdown 路径", count: selectionCount), action: #selector(copySelectedMarkdownPathPressed), keyEquivalent: "")
        copyPathItem.target = self
        copyPathItem.isEnabled = canUseSelectedNote
        menu.addItem(copyPathItem)

        let copyContentItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 内容", multiple: "复制 %d 条 Markdown 内容", count: selectionCount), action: #selector(copySelectedMarkdownContentPressed), keyEquivalent: "")
        copyContentItem.target = self
        copyContentItem.isEnabled = canExportSelectedNote
        menu.addItem(copyContentItem)

        let exportItem = NSMenuItem(title: noteActionTitle(single: "导出 Markdown...", multiple: "导出 %d 个 Markdown 文件...", count: selectionCount), action: #selector(exportSelectedMarkdownPressed), keyEquivalent: "")
        exportItem.target = self
        exportItem.isEnabled = canExportSelectedNote
        menu.addItem(exportItem)

        menu.addItem(.separator())

        if isTrashScope {
            let restoreItem = NSMenuItem(title: noteActionTitle(single: "恢复", multiple: "恢复 %d 条笔记", count: selectionCount), action: #selector(restoreSelectedNotePressed), keyEquivalent: "")
            restoreItem.target = self
            restoreItem.isEnabled = canRestoreSelectedNote
            menu.addItem(restoreItem)

            let permanentlyDeleteItem = NSMenuItem(title: noteActionTitle(single: "永久删除", multiple: "永久删除 %d 条笔记", count: selectionCount), action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
            permanentlyDeleteItem.target = self
            permanentlyDeleteItem.isEnabled = canUseSelectedNote
            menu.addItem(permanentlyDeleteItem)
        } else {
            let deleteItem = NSMenuItem(title: noteActionTitle(single: "删除", multiple: "删除 %d 条笔记", count: selectionCount), action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.isEnabled = canUseSelectedNote
            menu.addItem(deleteItem)
        }

        return menu
    }

    private func noteActionTitle(single: String, multiple: String, count: Int) -> String {
        count > 1 ? String(format: multiple, count) : single
    }

    private func makeFormatMenu() -> NSMenu {
        let menu = NSMenu()
        let items: [(String, LibraryFormatCommand, String)] = [
            ("标题", .heading, "1"),
            ("加粗", .bold, "b"),
            ("斜体", .italic, "i"),
            ("下划线", .underline, "u"),
            ("删除线", .strikethrough, ""),
            ("项目符号列表", .bullet, ""),
            ("编号列表", .ordered, "")
        ]

        for (title, command, keyEquivalent) in items {
            let item = NSMenuItem(title: title, action: #selector(formatMenuItemPressed(_:)), keyEquivalent: keyEquivalent)
            item.target = self
            item.tag = command.rawValue
            if command == .heading {
                item.keyEquivalentModifierMask = [.command, .option]
            } else if command == .strikethrough {
                item.keyEquivalentModifierMask = [.command, .shift]
                item.keyEquivalent = "x"
            } else if [.bold, .italic, .underline].contains(command) {
                item.keyEquivalentModifierMask = [.command]
            }
            menu.addItem(item)
            if command == .strikethrough {
                menu.addItem(.separator())
            }
        }

        return menu
    }

    private func makeMoveNoteMenu() -> NSMenu {
        let menu = NSMenu()
        for folderRow in sourceFolderRows {
            let folderURL = folderRow.url
            let title = String(repeating: "  ", count: folderRow.depth) + folderURL.lastPathComponent
            let item = NSMenuItem(title: title, action: #selector(moveNoteMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = folderURL
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    private func promptForText(title: String, message: String, placeholder: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(string: defaultValue)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 28)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func confirmDestructiveAction(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }

    func updatePanelOpacity(_ opacity: Double) {
        window?.alphaValue = 1
    }

    private func libraryUserDidEdit() {
        guard !suppressEditorChanges else { return }
        let activeSearchQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        removeEditorSearchHighlights()
        if !normalizeCurrentLineAfterListPrefixEdit() {
            interpretTypedMarkdownIfNeeded()
        }
        updateTypingAttributesFromInsertionPoint()
        markDirty()
        if !activeSearchQuery.isEmpty {
            applyEditorSearchHighlights(query: activeSearchQuery)
        }
    }

    private func interpretTypedMarkdownIfNeeded() {
        guard let storage = editorTextView.textStorage else { return }

        let currentLineRange = visibleLineRangeForSelection()
        let currentText = (storage.string as NSString).substring(with: currentLineRange)
        guard MarkdownRichTextCodec.shouldInterpretMarkdown(in: currentText) else { return }

        let selection = editorTextView.selectedRange()
        let selectionStartOffset = max(selection.location - currentLineRange.location, 0)
        let selectionEndOffset = max(NSMaxRange(selection) - currentLineRange.location, 0)
        let rendered = MarkdownRichTextCodec.renderLine(currentText, theme: theme)
        let clampedStart = min(selectionStartOffset, rendered.length)
        let clampedEnd = min(selectionEndOffset, rendered.length)

        suppressEditorChanges = true
        storage.replaceCharacters(in: currentLineRange, with: rendered)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(
            location: currentLineRange.location + clampedStart,
            length: max(clampedEnd - clampedStart, 0)
        ))
    }

    private func normalizeCurrentLineAfterListPrefixEdit() -> Bool {
        guard let storage = editorTextView.textStorage else { return false }

        let lineRange = visibleLineRangeForSelection()
        guard MarkdownRichTextCodec.needsParagraphResetAfterListPrefixEdit(range: lineRange, in: storage) else {
            return false
        }

        let storedKind = MarkdownRichTextCodec.storedParagraphKind(at: lineRange, in: storage) ?? .paragraph
        let contentRange = MarkdownRichTextCodec.paragraphContentRangeAfterListPrefixEdit(
            for: lineRange,
            in: storage,
            storedKind: storedKind
        )
        let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
            range: contentRange,
            in: storage,
            paragraphKind: .paragraph,
            theme: theme
        )
        let replacement = MarkdownRichTextCodec.renderLine(
            MarkdownRichTextCodec.markdownLine(for: .paragraph, inlineContent: inlineMarkdown),
            theme: theme
        )

        let selection = editorTextView.selectedRange()
        let removedPrefixLength = max(contentRange.location - lineRange.location, 0)
        let selectionStartOffset = max(selection.location - lineRange.location - removedPrefixLength, 0)
        let selectionEndOffset = max(NSMaxRange(selection) - lineRange.location - removedPrefixLength, 0)
        let clampedStart = min(selectionStartOffset, replacement.length)
        let clampedEnd = min(selectionEndOffset, replacement.length)

        suppressEditorChanges = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(
            location: lineRange.location + clampedStart,
            length: max(clampedEnd - clampedStart, 0)
        ))
        return true
    }

    private func updateTypingAttributesFromInsertionPoint() {
        guard let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        let location = max(min(selection.location, storage.length), 0)

        if storage.length == 0 || location == 0 {
            editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
            return
        }

        let lineRange = visibleLineRangeForSelection()
        let paragraphKind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: paragraphKind)

        if location <= contentRange.location {
            editorTextView.typingAttributes = theme.baseAttributes(for: paragraphKind)
            return
        }

        let probeLocation = max(min(location - 1, storage.length - 1), contentRange.location)
        editorTextView.typingAttributes = storage.attributes(at: probeLocation, effectiveRange: nil)
    }

    private func visibleLineRangeForSelection() -> NSRange {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let paragraphRange = string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: 0))
        let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
        return NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0))
    }

    private func selectedLineRanges() -> [NSRange] {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let fullRange = string.lineRange(for: selection)
        var ranges: [NSRange] = []
        var location = fullRange.location

        while location < NSMaxRange(fullRange) {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
            ranges.append(NSRange(
                location: paragraphRange.location,
                length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
            ))
            location = NSMaxRange(paragraphRange)
        }

        if ranges.isEmpty {
            ranges.append(NSRange(location: min(selection.location, string.length), length: 0))
        }
        return ranges
    }

    private func handleStructuredNewline() -> Bool {
        guard let storage = editorTextView.textStorage else { return false }

        let lineRange = visibleLineRangeForSelection()
        let kind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: kind)
        let content = (storage.string as NSString)
            .substring(with: contentRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .paragraph:
            return false
        case .heading:
            insertStructuredLine(kind: .paragraph, inlineMarkdown: "")
            return true
        case .bullet, .ordered, .checklist:
            if content.isEmpty {
                convertCurrentLineToParagraph()
            } else {
                let nextKind: MarkdownParagraphKind
                switch kind {
                case .ordered(let index):
                    nextKind = .ordered(index: index + 1)
                case .checklist:
                    nextKind = .checklist(checked: false)
                default:
                    nextKind = kind
                }
                insertStructuredLine(kind: nextKind, inlineMarkdown: "")
            }
            return true
        }
    }

    private func convertCurrentLineToParagraph() {
        guard let storage = editorTextView.textStorage else { return }
        let lineRange = visibleLineRangeForSelection()
        let replacement = MarkdownRichTextCodec.renderLine("", theme: theme)

        suppressEditorChanges = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    private func insertStructuredLine(kind: MarkdownParagraphKind, inlineMarkdown: String) {
        guard let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        let markdownLine = MarkdownRichTextCodec.markdownLine(for: kind, inlineContent: inlineMarkdown)
        let renderedLine = MarkdownRichTextCodec.renderLine(markdownLine, theme: theme)
        let replacement = NSMutableAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph))
        replacement.append(renderedLine)

        suppressEditorChanges = true
        storage.replaceCharacters(in: selection, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: selection.location + 1 + kind.prefixLength, length: 0))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    private func toggleParagraphKind(_ target: MarkdownParagraphKind) {
        guard selectedScope != .trash, let storage = editorTextView.textStorage else { return }
        let ranges = selectedLineRanges()
        let currentKinds = ranges.map { MarkdownRichTextCodec.paragraphKind(at: $0, in: storage) }
        let shouldResetToParagraph = currentKinds.allSatisfy { sameParagraphCategory($0, target) }
        var renderedLines: [NSAttributedString] = []

        for (index, lineRange) in ranges.enumerated() {
            let currentKind = currentKinds[index]
            let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: currentKind)
            let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
                range: contentRange,
                in: storage,
                paragraphKind: currentKind,
                theme: theme
            )
            let nextKind: MarkdownParagraphKind
            if shouldResetToParagraph {
                nextKind = .paragraph
            } else if case .ordered = target {
                nextKind = .ordered(index: index + 1)
            } else {
                nextKind = target
            }
            let lineMarkdown = MarkdownRichTextCodec.markdownLine(for: nextKind, inlineContent: inlineMarkdown)
            renderedLines.append(MarkdownRichTextCodec.renderLine(lineMarkdown, theme: theme))
        }

        let replacement = joinRenderedLines(renderedLines)
        let fullRange = combinedRange(of: ranges)
        suppressEditorChanges = true
        storage.replaceCharacters(in: fullRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: fullRange.location + replacement.length, length: 0))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    private func toggleChecklistIfNeeded(atCharacterIndex index: Int) -> Bool {
        guard let storage = editorTextView.textStorage, storage.length > 0 else { return false }

        let safeIndex = min(max(index, 0), max(storage.length - 1, 0))
        let string = storage.string as NSString
        let paragraphRange = string.paragraphRange(for: NSRange(location: safeIndex, length: 0))
        let visibleRange = NSRange(
            location: paragraphRange.location,
            length: max(paragraphRange.length - (string.substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0), 0)
        )
        let kind = MarkdownRichTextCodec.paragraphKind(at: visibleRange, in: storage)

        guard case .checklist(let checked) = kind else { return false }
        let prefixRange = NSRange(location: visibleRange.location, length: min(kind.prefixLength, visibleRange.length))
        guard NSLocationInRange(safeIndex, prefixRange) else { return false }

        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: visibleRange, in: storage, kind: kind)
        let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
            range: contentRange,
            in: storage,
            paragraphKind: kind,
            theme: theme
        )
        let replacement = MarkdownRichTextCodec.renderLine(
            MarkdownRichTextCodec.markdownLine(for: .checklist(checked: !checked), inlineContent: inlineMarkdown),
            theme: theme
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: visibleRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: min(visibleRange.location + replacement.length, storage.length), length: 0))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
        return true
    }

    private func applyFormatCommand(_ command: LibraryFormatCommand) {
        focusEditorForLibraryAction()
        switch command {
        case .heading:
            toggleParagraphKind(.heading(level: 1))
        case .bold:
            toggleInlineFontTrait(.boldFontMask)
        case .italic:
            toggleInlineFontTrait(.italicFontMask)
        case .underline:
            toggleIntAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue, actionName: "下划线")
        case .strikethrough:
            toggleIntAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue, actionName: "删除线")
        case .bullet:
            toggleParagraphKind(.bullet)
        case .ordered:
            toggleParagraphKind(.ordered(index: 1))
        }
    }

    private func toggleInlineFontTrait(_ trait: NSFontTraitMask) {
        guard selectedScope != .trash else { return }

        if trait.contains(.italicFontMask) {
            toggleItalicFormatting()
            return
        }

        let selection = editorTextView.selectedRange()
        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            typing[.font] = toggledFont(from: currentFont, trait: trait)
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        suppressEditorChanges = true
        storage.beginEditing()
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let font = (storage.attribute(.font, at: location, effectiveRange: &effectiveRange) as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            storage.addAttribute(.font, value: toggledFont(from: font, trait: trait), range: clippedRange)
            location = NSMaxRange(clippedRange)
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        markDirty()
    }

    private func toggleItalicFormatting() {
        let selection = editorTextView.selectedRange()
        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            if isItalicActive(font: currentFont, obliqueness: typing[.obliqueness]) {
                typing[.font] = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
                typing.removeValue(forKey: .obliqueness)
            } else {
                typing[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                typing[.obliqueness] = markdownItalicObliqueness
            }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        suppressEditorChanges = true
        storage.beginEditing()
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = storage.attributes(at: location, effectiveRange: &effectiveRange)
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            if isItalicActive(font: font, obliqueness: attributes[.obliqueness]) {
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask), range: clippedRange)
                storage.removeAttribute(.obliqueness, range: clippedRange)
            } else {
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: clippedRange)
                storage.addAttribute(.obliqueness, value: markdownItalicObliqueness, range: clippedRange)
            }
            location = NSMaxRange(clippedRange)
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        markDirty()
    }

    private func toggleIntAttribute(_ key: NSAttributedString.Key, enabledValue: Int, actionName: String) {
        guard selectedScope != .trash else { return }
        let selection = editorTextView.selectedRange()
        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            if (typing[key] as? Int) == enabledValue {
                typing.removeValue(forKey: key)
            } else {
                typing[key] = enabledValue
            }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let enabled = (storage.attribute(key, at: selection.location, effectiveRange: nil) as? Int) == enabledValue
        suppressEditorChanges = true
        if enabled {
            storage.removeAttribute(key, range: selection)
        } else {
            storage.addAttribute(key, value: enabledValue, range: selection)
        }
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        _ = actionName
        markDirty()
    }

    private func toggledFont(from font: NSFont, trait: NSFontTraitMask) -> NSFont {
        if NSFontManager.shared.traits(of: font).contains(trait) {
            return NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        }
        return NSFontManager.shared.convert(font, toHaveTrait: trait)
    }

    private func isItalicActive(font: NSFont, obliqueness: Any?) -> Bool {
        if NSFontManager.shared.traits(of: font).contains(.italicFontMask) {
            return true
        }
        if let number = obliqueness as? NSNumber {
            return abs(number.doubleValue) > 0.001
        }
        if let value = obliqueness as? CGFloat {
            return abs(value) > 0.001
        }
        if let value = obliqueness as? Double {
            return abs(value) > 0.001
        }
        return false
    }

    private func sameParagraphCategory(_ lhs: MarkdownParagraphKind, _ rhs: MarkdownParagraphKind) -> Bool {
        switch (lhs, rhs) {
        case (.heading(let lhsLevel), .heading(let rhsLevel)):
            return lhsLevel == rhsLevel
        case (.bullet, .bullet), (.ordered, .ordered), (.checklist, .checklist), (.paragraph, .paragraph):
            return true
        default:
            return false
        }
    }

    private func joinRenderedLines(_ lines: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph)))
            }
            result.append(line)
        }
        return result
    }

    private func combinedRange(of ranges: [NSRange]) -> NSRange {
        guard let first = ranges.first, let last = ranges.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    private func focusEditorForLibraryAction() {
        guard selectedScope != .trash else { return }
        window?.makeFirstResponder(editorTextView)
    }

    func insertTableForLibrary() {
        let markdown = """
        | Column 1 | Column 2 |
        | --- | --- |
        |  |  |
        """
        insertMarkdownBlockForLibrary(markdown)
    }

    func insertLinkForLibrary(label: String, url: String) {
        guard selectedScope != .trash else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let linkLabel = trimmedLabel.isEmpty ? trimmedURL : trimmedLabel
        replaceSelectionWithRenderedMarkdown("[\(escapedMarkdownLabel(linkLabel))](\(escapedMarkdownURL(trimmedURL)))")
    }

    @discardableResult
    func insertAttachmentReferenceForLibrary(from fileURL: URL) throws -> URL {
        guard selectedScope != .trash else { return fileURL }
        let noteDirectory = targetDirectoryForAttachment()
        let copiedURL = try copyAttachment(fileURL, intoNoteDirectory: noteDirectory)
        let relativePath = relativeMarkdownPath(for: copiedURL, from: noteDirectory)
        let markdown: String
        if isImageAttachment(copiedURL) {
            markdown = "![Image](\(relativePath))"
        } else {
            let label = copiedURL.deletingPathExtension().lastPathComponent
            markdown = "[\(escapedMarkdownLabel(label.isEmpty ? "Attachment" : label))](\(relativePath))"
        }
        insertMarkdownBlockForLibrary(markdown)
        return copiedURL
    }

    private func selectedTextForLinkDefault() -> String {
        let selection = editorTextView.selectedRange()
        guard selection.length > 0, NSMaxRange(selection) <= (editorTextView.string as NSString).length else {
            return ""
        }
        return (editorTextView.string as NSString).substring(with: selection)
    }

    private func insertMarkdownBlockForLibrary(_ markdown: String) {
        guard selectedScope != .trash else { return }
        focusEditorForLibraryAction()
        let selection = editorTextView.selectedRange()
        let nsString = editorTextView.string as NSString
        var block = markdown

        if selection.location > 0,
           nsString.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n" {
            block = "\n" + block
        }
        if NSMaxRange(selection) < nsString.length,
           !block.hasSuffix("\n") {
            block += "\n"
        }

        replaceSelectionWithRenderedMarkdown(block)
    }

    private func replaceSelectionWithRenderedMarkdown(_ markdown: String) {
        guard selectedScope != .trash, let storage = editorTextView.textStorage else { return }
        focusEditorForLibraryAction()
        let selection = editorTextView.selectedRange()
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme, baseURL: selectedURL)

        suppressEditorChanges = true
        storage.replaceCharacters(in: selection, with: rendered)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: selection.location + rendered.length, length: 0))
        updateTypingAttributesFromInsertionPoint()
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
        markDirty()
    }

    private func targetDirectoryForAttachment() -> URL {
        if let selectedURL {
            return selectedURL.deletingLastPathComponent()
        }
        return targetDirectoryForNewNote()
    }

    private func copyAttachment(_ sourceURL: URL, intoNoteDirectory noteDirectory: URL) throws -> URL {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        let year = String(components.year ?? 1970)
        let month = String(format: "%02d", components.month ?? 1)
        let attachmentDirectory = noteDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)

        let destination = uniqueAttachmentDestination(for: sourceURL, in: attachmentDirectory)
        if sourceURL.standardizedFileURL.path != destination.standardizedFileURL.path {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
        return destination
    }

    private func uniqueAttachmentDestination(for sourceURL: URL, in directory: URL) -> URL {
        let fileName = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension
        let baseName = fileExtension.isEmpty
            ? fileName
            : sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(fileName)
        var copyIndex = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName)-\(copyIndex)"
                : "\(baseName)-\(copyIndex).\(fileExtension)"
            candidate = directory.appendingPathComponent(candidateName)
            copyIndex += 1
        }
        return candidate
    }

    private func relativeMarkdownPath(for fileURL: URL, from noteDirectory: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let basePath = noteDirectory.standardizedFileURL.path
        let relativePath: String
        if filePath.hasPrefix(basePath + "/") {
            relativePath = String(filePath.dropFirst(basePath.count + 1))
        } else {
            relativePath = fileURL.lastPathComponent
        }
        return relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
    }

    private func isImageAttachment(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff"].contains(url.pathExtension.lowercased())
    }

    private func escapedMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private func escapedMarkdownURL(_ url: String) -> String {
        url
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: ")", with: "%29")
    }

    func markdownTextViewInsertNewline(_ textView: MarkdownTextView) {
        guard handleStructuredNewline() else {
            textView.insertNewlineIgnoringFieldEditor(self)
            updateTypingAttributesFromInsertionPoint()
            return
        }
    }

    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool {
        false
    }

    func markdownTextViewToggleBold(_ textView: MarkdownTextView) { toggleInlineFontTrait(.boldFontMask) }
    func markdownTextViewToggleItalic(_ textView: MarkdownTextView) { toggleInlineFontTrait(.italicFontMask) }
    func markdownTextViewToggleHeading(_ textView: MarkdownTextView) { toggleParagraphKind(.heading(level: 1)) }
    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView) { toggleParagraphKind(.bullet) }
    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView) { toggleParagraphKind(.ordered(index: 1)) }
    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView) { toggleParagraphKind(.checklist(checked: false)) }

    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool {
        toggleChecklistIfNeeded(atCharacterIndex: index)
    }

    func markdownTextView(_ textView: MarkdownTextView, didDoubleClickAttachmentAt index: Int) -> Bool {
        guard
            let storage = textView.textStorage,
            index >= 0,
            index < storage.length,
            let path = storage.attribute(.qmAttachmentFilePath, at: index, effectiveRange: nil) as? String
        else { return false }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        return true
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachment attachment: MarkdownAttachmentReference) -> Bool {
        configureAttachmentContextMenu(menu, forAttachmentPath: attachment.path, markdown: attachment.markdown)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachmentPath path: String, markdown: String? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }

        let openItem = NSMenuItem(title: "打开附件", action: #selector(openAttachmentMenuItemPressed(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = path

        let revealItem = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealAttachmentMenuItemPressed(_:)), keyEquivalent: "")
        revealItem.target = self
        revealItem.representedObject = path

        let copyPathItem = NSMenuItem(title: "复制附件路径", action: #selector(copyAttachmentPathMenuItemPressed(_:)), keyEquivalent: "")
        copyPathItem.target = self
        copyPathItem.representedObject = path

        let copyMarkdownItem = NSMenuItem(title: "复制 Markdown 链接", action: #selector(copyAttachmentMarkdownMenuItemPressed(_:)), keyEquivalent: "")
        copyMarkdownItem.target = self
        copyMarkdownItem.representedObject = markdown
        copyMarkdownItem.isEnabled = !(markdown?.isEmpty ?? true)

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [copyPathItem, copyMarkdownItem, revealItem, openItem] {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    private func openAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func revealAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc
    private func copyAttachmentPathMenuItemPressed(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc
    private func copyAttachmentMarkdownMenuItemPressed(_ sender: NSMenuItem) {
        guard let markdown = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func attachmentURL(from sender: NSMenuItem) -> URL? {
        guard let path = sender.representedObject as? String else { return nil }
        return URL(fileURLWithPath: path)
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
