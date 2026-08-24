import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
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
            return LibraryCopy.home
        case .recent:
            return "最近"
        case .inbox:
            return LibraryCopy.inbox
        case .folder(let url):
            return url.lastPathComponent.isEmpty ? LibraryCopy.notes : url.lastPathComponent
        case .tag(let tag):
            return libraryBareTag(tag)
        case .trash:
            return LibraryCopy.recentlyDeleted
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
            return "house"
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

private func librarySearchResults(
    noteStore: NoteStore,
    searchSession: NoteSearchSession,
    scope: LibraryScope,
    query: String,
    limit: Int,
    searchesAllNotes: Bool,
    includesSubfolderNotes: Bool
) -> [NoteSearchResult] {
    let cancellationCheck: @Sendable () -> Bool = { Task.isCancelled }
    if searchesAllNotes {
        return searchSession.searchNotes(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        )
    }

    switch scope {
    case .all:
        return searchSession.searchNotes(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        )
    case .recent:
        return searchSession.searchRecentNotes(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        )
    case .inbox:
        return searchSession.searchInboxNotes(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        )
    case .trash:
        return libraryFilteredTrashedNotes(noteStore: noteStore, query: query, limit: limit)
    case .folder(let url):
        return searchSession.searchNotes(
            query: query,
            limit: limit,
            in: url,
            includingDescendants: includesSubfolderNotes,
            cancellationCheck: cancellationCheck
        )
    case .tag(let tag):
        return searchSession.searchNotes(
            query: query,
            limit: limit,
            tagged: tag,
            cancellationCheck: cancellationCheck
        )
    }
}

private func libraryNote(
    _ note: NoteSearchResult,
    isIn folderURL: URL,
    includingDescendants: Bool
) -> Bool {
    let noteFolderPath = note.url.deletingLastPathComponent().path
    let folderPath = folderURL.path
    return noteFolderPath == folderPath
        || (includingDescendants && noteFolderPath.hasPrefix(folderPath + "/"))
}

func libraryFilteredTrashedNotes(noteStore: NoteStore, query: String, limit: Int) -> [NoteSearchResult] {
    noteStore.searchTrashedNotes(
        query: query,
        limit: limit,
        cancellationCheck: { Task.isCancelled }
    )
}

private func libraryFirstMeaningfulLine(from body: String) -> String? {
    MarkdownEditorDocument.firstPreviewLine(in: body)
}

private enum InlineFolderEditOperation: Equatable {
    case create(parentURL: URL)
    case rename(folderURL: URL)

    var initialName: String {
        switch self {
        case .create:
            return "新建文件夹"
        case .rename(let folderURL):
            return folderURL.lastPathComponent
        }
    }
}

private typealias LoadedLibraryNote = LoadedNoteDocument

private struct LibraryBackgroundSaveSnapshot: Sendable {
    let generation: Int
    let editorRevision: Int
    let previousURL: URL?
    let title: String
    let body: String
    let tags: [String]
    let targetDirectory: URL
    let updatesInPlace: Bool
    let expectedContents: String?
}

private final class LibraryBackgroundEditorSnapshot: @unchecked Sendable {
    private let sourceMarkdown: String?
    private let attributedMarkdown: NSAttributedString?
    private let theme: MarkdownEditorTheme

    init(sourceMarkdown: String, theme: MarkdownEditorTheme) {
        self.sourceMarkdown = sourceMarkdown
        self.attributedMarkdown = nil
        self.theme = theme
    }

    init(attributedMarkdown: NSAttributedString, theme: MarkdownEditorTheme) {
        self.sourceMarkdown = nil
        self.attributedMarkdown = NSAttributedString(attributedString: attributedMarkdown)
        self.theme = theme
    }

    func markdown() -> String {
        if let sourceMarkdown {
            return sourceMarkdown
        }
        guard let attributedMarkdown else { return "" }
        return MarkdownRichTextCodec.serialize(attributedMarkdown, theme: theme)
    }
}

private struct LibraryBackgroundSaveSuccess: Sendable {
    let snapshot: LibraryBackgroundSaveSnapshot
    let savedURL: URL
    let savedAt: Date
    let snippet: String
    let hasAttachments: Bool
    let thumbnailURL: URL?
    let sourceContents: String
    let conflictedOriginalURL: URL?
}

private final class LibraryBackgroundSaveResultBox: @unchecked Sendable {
    let result: Result<LibraryBackgroundSaveSuccess, Error>

    init(_ result: Result<LibraryBackgroundSaveSuccess, Error>) {
        self.result = result
    }
}

private final class LibraryBackgroundSaveResultStore: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Int: LibraryBackgroundSaveResultBox] = [:]

    func insert(_ result: LibraryBackgroundSaveResultBox, for generation: Int) {
        lock.lock()
        results[generation] = result
        lock.unlock()
    }

    func remove(generation: Int) -> LibraryBackgroundSaveResultBox? {
        lock.lock()
        defer { lock.unlock() }
        return results.removeValue(forKey: generation)
    }

    func pendingGenerations() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return results.keys.sorted()
    }
}

private struct LibraryDeletedNote: Sendable {
    let sourceURL: URL
    let trashedURL: URL?
}

private struct LibraryDeletionFailure: Sendable {
    let sourceURL: URL
    let message: String
}

private struct LibraryDeletionPersistenceResult: Sendable {
    let deletedNotes: [LibraryDeletedNote]
    let failures: [LibraryDeletionFailure]
}

private final class LoadedLibraryNoteCacheEntry: NSObject {
    let loaded: LoadedLibraryNote
    let fileModifiedAt: Date
    var renderedBody: NSAttributedString?

    init(loaded: LoadedLibraryNote, fileModifiedAt: Date) {
        self.loaded = loaded
        self.fileModifiedAt = fileModifiedAt
    }
}

private final class LoadedLibraryNoteCache: @unchecked Sendable {
    private let storage: NSCache<NSString, LoadedLibraryNoteCacheEntry>

    init(countLimit: Int) {
        storage = NSCache<NSString, LoadedLibraryNoteCacheEntry>()
        storage.countLimit = countLimit
    }

    func entry(forKey key: NSString) -> LoadedLibraryNoteCacheEntry? {
        storage.object(forKey: key)
    }

    func insert(_ entry: LoadedLibraryNoteCacheEntry, forKey key: NSString) {
        storage.setObject(entry, forKey: key)
    }

    func removeEntry(forKey key: NSString) {
        storage.removeObject(forKey: key)
    }
}

private final class LibraryThumbnailCacheEntry: NSObject {
    let image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }
}

private final class LibraryThumbnailDecodeResult: @unchecked Sendable {
    let image: CGImage?

    init(image: CGImage?) {
        self.image = image
    }
}

private extension NoteSearchResult {
    func replacingURL(_ url: URL, modifiedAt replacementModifiedAt: Date? = nil) -> NoteSearchResult {
        let sourceDirectoryPath = self.url.deletingLastPathComponent().standardizedFileURL.path
        let remappedThumbnailURL = thumbnailURL.flatMap { thumbnailURL -> URL? in
            let thumbnailPath = thumbnailURL.standardizedFileURL.path
            guard thumbnailPath.hasPrefix(sourceDirectoryPath + "/") else { return thumbnailURL }
            let relativePath = String(thumbnailPath.dropFirst(sourceDirectoryPath.count + 1))
            return url.deletingLastPathComponent().appendingPathComponent(relativePath)
        }
        return NoteSearchResult(
            url: url,
            title: title,
            snippet: snippet,
            modifiedAt: replacementModifiedAt ?? modifiedAt,
            createdAt: createdAt,
            tags: tags,
            hasAttachments: hasAttachments,
            thumbnailURL: remappedThumbnailURL
        )
    }
}

private enum LibrarySourceSection: Int {
    case folders = 0
    case tags = 1

    var title: String {
        switch self {
        case .folders:
            return LibraryCopy.folders
        case .tags:
            return LibraryCopy.tags
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

@MainActor
private final class LibrarySourceOutlineItem: NSObject {
    enum Kind {
        case group(title: String, section: LibrarySourceSection?)
        case scope(LibraryScope)
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
}

@MainActor
final class LibrarySourceOutlineView: NSOutlineView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var onPrimaryMouseSelectionPreviewChanged: (() -> Void)?
    var onPrimaryMouseSelectionCommitted: (() -> Void)?
    private(set) weak var pointerHoveredRow: LibrarySourceOutlineRowView?
    private(set) var isDeferringPrimaryMouseSelectionCommit = false
    private(set) var primaryMouseVisualSelectionRow: Int?
    private var selectionBeforePrimaryMouseDown = IndexSet()

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
        countLabel.font = .systemFont(ofSize: LibraryNotesLayout.sourceCountFontSize, weight: .medium)
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

private enum LibraryNotesPalette {
    static let windowBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let sourceBackground = NSColor(calibratedWhite: 0.045, alpha: 1)
    static let noteListBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let editorBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
}

@MainActor
enum LibrarySourceSelectionPalette {
    static let backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 0.86)
    static let noteBackgroundColor = NSColor(
        calibratedRed: 0.492,
        green: 0.377,
        blue: 0.09,
        alpha: 0.96
    )
    static let foregroundColor = MudsnoteThemeColor.ocean.foregroundColor
    static let selectedCountColor = NSColor.labelColor.withAlphaComponent(0.42)
    static let unselectedForegroundColor = NSColor.labelColor.withAlphaComponent(0.92)
}

private struct LibraryFolderIconChoice {
    let title: String
    let symbolName: String

    static let all: [Self] = [
        Self(title: "文件夹", symbolName: "folder.fill"),
        Self(title: "笔记", symbolName: "books.vertical.fill"),
        Self(title: "工作", symbolName: "briefcase.fill"),
        Self(title: "灵感", symbolName: "lightbulb.fill"),
        Self(title: "学习", symbolName: "graduationcap.fill"),
        Self(title: "收藏", symbolName: "bookmark.fill"),
        Self(title: "归档", symbolName: "archivebox.fill"),
        Self(title: "生活", symbolName: "house.fill"),
        Self(title: "团队", symbolName: "person.2.fill"),
        Self(title: "重点", symbolName: "star.fill")
    ]
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
    case libraryFolderAlreadyRegistered
    case libraryFolderOverlapsRegisteredFolder
    case cannotRemoveDefaultLibraryFolder

    var errorDescription: String? {
        switch self {
        case .noFolderSelected:
            return "没有选中文件夹"
        case .noNoteSelected:
            return "没有选中笔记"
        case .libraryFolderAlreadyRegistered:
            return "该文件夹已经在资料库中"
        case .libraryFolderOverlapsRegisteredFolder:
            return "不能添加已注册文件夹的上级或下级文件夹"
        case .cannotRemoveDefaultLibraryFolder:
            return "默认笔记文件夹不能从资料库移除"
        }
    }
}

private final class LibraryFolderMoveRequest: NSObject {
    let source: URL
    let destinationParent: URL

    init(source: URL, destinationParent: URL) {
        self.source = source.standardizedFileURL
        self.destinationParent = destinationParent.standardizedFileURL
    }
}

private final class LibraryFolderIconRequest: NSObject {
    let folderURL: URL
    let symbolName: String?

    init(folderURL: URL, symbolName: String?) {
        self.folderURL = folderURL.standardizedFileURL
        self.symbolName = symbolName
    }
}

private enum LibraryFormatCommand: Int {
    case heading1 = 1
    case heading2
    case heading3
    case paragraph
    case bold
    case italic
    case underline
    case strikethrough
    case checklist
    case bullet
    case ordered
    case highlight
    case removeHighlight

    var paragraphKind: MarkdownParagraphKind? {
        switch self {
        case .heading1: return .heading(level: 1)
        case .heading2: return .heading(level: 2)
        case .heading3: return .heading(level: 3)
        case .paragraph: return .paragraph
        case .checklist: return .checklist(checked: false)
        case .bullet: return .bullet
        case .ordered: return .ordered(index: 1)
        case .bold, .italic, .underline, .strikethrough, .highlight, .removeHighlight: return nil
        }
    }

    var undoActionName: String {
        switch self {
        case .heading1: return "标题"
        case .heading2: return "副标题"
        case .heading3: return "小标题"
        case .paragraph: return "正文"
        case .bold: return "加粗"
        case .italic: return "斜体"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .checklist: return "待办列表"
        case .bullet: return "项目符号列表"
        case .ordered: return "编号列表"
        case .highlight: return "高亮"
        case .removeHighlight: return "移除高亮"
        }
    }
}

private struct LibraryFormattingUndoSnapshot {
    let content: NSAttributedString
    let selection: NSRange
}

@MainActor
final class LibraryGroupHeaderCellView: NSTableCellView {
    static let titleLeadingInset: CGFloat = 16
    static let titleTrailingInset: CGFloat = 10
    static let firstTitleBottomInset: CGFloat = 15
    static let followingTitleBottomInset: CGFloat = 2

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
        titleLabel.textColor = panelPrimaryTextColor()
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
    static let contentLeadingInset: CGFloat = 35
    static let contentBottomInset: CGFloat = 7.5
    static let contentTrailingInset: CGFloat = 39
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
    static let selectionLeadingInset: CGFloat = 10
    static let selectionTrailingInset: CGFloat = 27
    static let selectionTopInset: CGFloat = 6
    static let selectionBottomInset: CGFloat = 4
    static let selectionCornerRadius: CGFloat = 8
    static var selectionFillColor = LibrarySourceSelectionPalette.noteBackgroundColor
    static let hoverLeadingInset: CGFloat = selectionLeadingInset
    static let hoverTrailingInset: CGFloat = selectionTrailingInset
    static let hoverVerticalInset: CGFloat = 3
    static let hoverCornerRadius: CGFloat = 8
    static let hoverFillColor = NSColor(calibratedWhite: 0.22, alpha: 0.24)
    static let separatorLeadingInset: CGFloat = 37
    static let separatorTrailingInset: CGFloat = 28
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
    fileprivate var onKeyCommand: ((LibraryNoteKeyCommand) -> Bool)?
    fileprivate var onContextMenu: ((Int) -> NSMenu?)?
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
final class LibraryNoteClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        constrainedBounds.origin.x = 0
        return constrainedBounds
    }
}

@MainActor
final class LibraryEditorScrollView: NSScrollView {
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

@MainActor
final class LibraryWindowController: NSWindowController,
    NSWindowDelegate,
    NSSplitViewDelegate,
    NSToolbarDelegate,
    NSToolbarItemValidation,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSCollectionViewDataSource,
    NSCollectionViewDelegateFlowLayout,
    NSOutlineViewDataSource,
    NSOutlineViewDelegate,
    NSSearchFieldDelegate,
    NSTextFieldDelegate,
    NSTextViewDelegate,
    MarkdownTextViewCommands,
    WindowOpacityAdjusting
{
    let noteStore: NoteStore
    let sourceOutlineView = LibrarySourceOutlineView()
    let tableView = LibraryNoteTableView()
    let galleryCollectionView = LibraryGalleryCollectionView()
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
    let galleryEmptyLabel = NSTextField(labelWithString: "")
    let titleField = NSTextField(string: "")
    let editorTextView = MarkdownTextView(frame: .zero)
    let noteLinksView = NoteLinksView(frame: .zero)
    let attachmentQuickLookController = AttachmentQuickLookController()
    let createdDateLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let wordCountLabel = NSTextField(labelWithString: "")
    private var attachmentManagerWindowController: LibraryAttachmentManagerWindowController?
    private var knowledgeGraphWindowController: KnowledgeGraphWindowController?

    private static let toolbarIdentifier = NSToolbar.Identifier("mudsnote.library.toolbar")
    private static let addFolderToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.add-folder")
    private static let toggleSidebarToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.toggle-sidebar")
    private static let sourceTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.source-separator")
    private static let noteTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-separator")
    private static let noteListTitleToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-list-title")
    private static let newNoteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.new-note")
    private static let openSeparateToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.open-separate")
    private static let moveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.move")
    private static let saveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.save")
    private static let deleteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.delete")
    private static let restoreToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.restore")
    private static let editorToolsToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.editor-tools")
    private static let formatToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.format")
    private static let checklistToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.checklist")
    private static let linkToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.link")
    private static let sourceModeToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.source-mode")
    private static let revealToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.reveal")
    private static let exportToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.export")
    private static let moreToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.more")
    private static let searchToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.search")

    private enum EditorStatusKind {
        case normal
        case failure
    }

    private let onOpenInSeparateWindow: (URL) -> Void
    private let onSave: (URL) -> Void
    private let onClose: () -> Void
    private let noteLoader: @Sendable (URL) throws -> LoadedLibraryNote
    private let fileModificationDateLoader: @Sendable (URL) -> Date?
    private let thumbnailDecoder: @Sendable (URL) -> CGImage?
    private let backgroundAutosaveWillPersist: @Sendable () -> Void
    private let backgroundSourceCountWillLoad: @Sendable () -> Void
    private let backgroundDeletionWillPersist: @Sendable () -> Void
    private let usesCanonicalWindowSize: Bool
    private let prefersExternalScreen: Bool
    private var notes: [NoteSearchResult] = []
    private var listRows: [LibraryNoteListRow] = [] {
        didSet { rebuildThumbnailRowIndex() }
    }
    private var gallerySections: [LibraryGallerySection] = [] {
        didSet { rebuildThumbnailItemIndex() }
    }
    private var visualQASelectedURL: URL?
    private(set) var noteListSortOrder: LibraryNoteSortOrder = .dateEdited
    private(set) var groupsNoteListByDate = true
    private(set) var noteListViewMode: LibraryNoteViewMode = .list
    private var sourceCountSnapshot: [NoteSearchResult] = []
    private var trashedNotesSnapshot: [NoteSearchResult] = []
    private var externallyOpenedDocumentsByPath: [String: NoteSearchResult] = [:]
    private var selectedURL: URL?
    private var selectedSourceContents: String?
    private var selectedTags: [String] = []
    private var isDirty = false
    private var autosaveTask: Task<Void, Never>?
    private let autosavePersistenceQueue = DispatchQueue(
        label: "local.codex.mudsnote.library-autosave",
        qos: .utility
    )
    private let libraryMutationQueue = DispatchQueue(
        label: "local.codex.mudsnote.library-mutations",
        qos: .userInitiated
    )
    private let launchNoteCacheQueue = DispatchQueue(
        label: "local.codex.mudsnote.library-launch-note-cache",
        qos: .utility
    )
    private let backgroundAutosaveResultStore = LibraryBackgroundSaveResultStore()
    private var backgroundAutosaveGeneration = 0
    private var backgroundAutosaveIsActive = false
    private var backgroundAutosaveNeedsLatest = false
    private var backgroundAutosaveActiveEditorRevision: Int?
    private var backgroundAutosaveActivePreviousURL: URL?
    private var deferredFileSystemChangesDuringAutosave = Set<LibraryFileSystemChange>()
    private var noteLoadTask: Task<Void, Never>?
    private var noteLoadGeneration = 0
    private var noteLoadFallbackURL: URL?
    private var persistedLaunchFallbackURL: URL?
    private var notePrefetchTask: Task<Void, Never>?
    private var searchReloadWorkItem: DispatchWorkItem?
    private var searchResultsTask: Task<Void, Never>?
    private var editorSearchHighlightRefreshTask: Task<Void, Never>?
    private var noteLinksRefreshTask: Task<Void, Never>?
    private var noteLinksRefreshGeneration = 0
    private var knowledgeSynthesisTask: Task<Void, Never>?
    private var knowledgeSynthesisGeneration = 0
    private var knowledgeBackStack: [URL] = []
    private var knowledgeForwardStack: [URL] = []
    private var searchResultsGeneration = 0
    private var activeSearchSession: NoteSearchSession?
    private var sourceSnapshotValidationTask: Task<Void, Never>?
    private var sourceSnapshotValidationGeneration = 0
    private var sourceCountRefreshTask: Task<Void, Never>?
    private var sourceCountRefreshGeneration = 0
    private var hasLoadedSourceCounts = false
    private var pendingDeletionPaths = Set<String>()
    private var pendingDeletionBatchCount = 0
    private var pendingDeletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var sourceInboxDirectory: URL?
    private var noteListToolbarTitleLeadingConstraint: NSLayoutConstraint?
    private var hasPendingSearchReload = false
    private var isSearchResultReloading = false
    private var isLoadingInitialNote = false
    private var suppressEditorChanges = false
    private var hasEditorSearchHighlights = false
    private var editorSearchHighlightRemovalScanCount = 0
    private var editorContentRevision = 0
    private var isEditorShowingMarkdownSource = false
    private var suppressSelectionChanges = false
    private var suppressGallerySelectionChanges = false
    private var isCreatingNewNote = false
    private var hasCenteredWindow = false
    private var hasRequestedWindowPresentation = false
    private var hasHydratedInitialNoteList = false
    private var hasReleasedDeferredLaunchWork = false
    private var selectedScope: LibraryScope = .all
    private var sourceOutlineRootItems: [LibrarySourceOutlineItem] = []
    private var sourceOutlineItemsByIdentifier: [String: LibrarySourceOutlineItem] = [:]
    private var sourceOutlineItemsByScopeIdentifier: [String: LibrarySourceOutlineItem] = [:]
    private var isSynchronizingSourceOutlineSelection = false
    private var isRestoringSourceOutlineExpansion = false
    private var sourceFolderRows: [LibraryFolderRow] = []
    private var sourceFolderTreeRows: [LibraryFolderRow] = []
    private var sourceTagNames: [String] = []
    private var collapsedFolderPaths = Set<String>()
    private var expandedFolderPaths = Set<String>()
    private let loadedNoteCache = LoadedLibraryNoteCache(countLimit: 32)
    private let thumbnailImageCache: NSCache<NSString, LibraryThumbnailCacheEntry> = {
        let cache = NSCache<NSString, LibraryThumbnailCacheEntry>()
        cache.countLimit = 96
        cache.totalCostLimit = 96 * 88 * 88 * 4
        return cache
    }()
    private var thumbnailImageLoadTasks: [String: Task<Void, Never>] = [:]
    private var thumbnailRowsByPath: [String: IndexSet] = [:]
    private var thumbnailItemsByPath: [String: Set<IndexPath>] = [:]
    private var pendingThumbnailReloadPaths = Set<String>()
    private var thumbnailReloadScheduled = false
    private(set) var thumbnailImageDecodeCountForLibrary = 0
    private(set) var thumbnailReloadBatchCountForLibrary = 0
    private var sourceFoldersLoaded = false
    private var sourceFoldersLoading = false
    private var sourceFolderLoadGeneration = 0
    private var sourceTagsLoaded = false
    private var sourceTagsLoading = false
    private var sourceTagLoadGeneration = 0
    private var fullLibrarySnapshotReloadScheduled = false
    private var isFullLibrarySnapshotLoading = false
    private var fullLibrarySnapshotReloadGeneration = 0
    private var fileSystemMonitor: LibraryFileSystemMonitor?
    private var internallyMutatedPaths: [String: Date] = [:]
    private var internallyMutatedDirectoryPaths: [String: Date] = [:]
    private var sourceFoldersSectionCollapsed = false
    private var sourceTagsSectionCollapsed = false
    private var inlineFolderEditOperation: InlineFolderEditOperation?
    private var inlineFolderEditField: NSTextField?
    private var isCommittingInlineFolderEdit = false
    private var inlineFolderEditHasReceivedFocus = false
    private var linkEditorSheetController: LinkEditorSheetController?
    private let editorSuggestionController = SuggestionPopoverController()
    private var editorSlashSuggestion: (replacementRange: NSRange, commands: [SlashCommand])?
    private var editorNoteSuggestion: (replacementRange: NSRange, items: [NoteLinkItem])?
    private var editorNoteSuggestionQuery: String?
    private var editorNoteSuggestions: [NoteLinkItem] = []
    private var editorNoteSuggestionTask: Task<Void, Never>?
    private var editorSlashSuggestionLastInput: (caret: Int, prefixStart: Int, prefix: String)?
    var slashCommandInputSourceSession: any SlashCommandInputSourceSessioning = SlashCommandInputSourceSession()
    private(set) var editorSlashSuggestionInspectionLengthForLibrary = 0
    private var isApplyingStoredSplitLayout = false
    private var splitLayoutPersistenceWorkItem: DispatchWorkItem?
    private var windowFramePersistenceWorkItem: DispatchWorkItem?
    private weak var librarySplitView: NSSplitView?
    private var librarySplitViewController: NSSplitViewController?
    private weak var sourceSplitViewItem: NSSplitViewItem?
    private weak var noteListSplitViewItem: NSSplitViewItem?
    private weak var sourceListView: NSView?
    private weak var editorStackView: NSStackView?
    private weak var galleryScrollView: NSScrollView?
    static let sourceCountSnapshotLimit = Int.max

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
        codeFont: .monospacedSystemFont(ofSize: LibraryNotesLayout.editorCodeFontSize, weight: .medium),
        lineSpacing: LibraryNotesLayout.editorLineSpacing,
        paragraphSpacing: LibraryNotesLayout.editorParagraphSpacing
    )

    init(
        noteStore: NoteStore,
        defersInitialNoteHydration: Bool = false,
        usesCanonicalWindowSize: Bool = false,
        prefersExternalScreen: Bool = false,
        noteLoader: (@Sendable (URL) throws -> (title: String, body: String, tags: [String]))? = nil,
        fileModificationDateLoader: (@Sendable (URL) -> Date?)? = nil,
        thumbnailDecoder: (@Sendable (URL) -> CGImage?)? = nil,
        backgroundAutosaveWillPersist: @escaping @Sendable () -> Void = {},
        backgroundSourceCountWillLoad: @escaping @Sendable () -> Void = {},
        backgroundDeletionWillPersist: @escaping @Sendable () -> Void = {},
        onOpenInSeparateWindow: @escaping (URL) -> Void,
        onSave: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        let migratedLayout = noteStore.migrateLibraryLayoutScaleIfNeeded(
            to: LibraryNotesLayout.storedLayoutScaleVersion,
            replacingDefaultPaneWidths: (source: 205, note: 200)
        )
        if migratedLayout {
            noteStore.libraryWindowFrame = LibraryNotesLayout.migratedDefaultWindowFrame(noteStore.libraryWindowFrame)
        }
        if let noteLoader {
            self.noteLoader = { url in
                let loaded = try noteLoader(url)
                return LoadedNoteDocument(
                    title: loaded.title,
                    body: loaded.body,
                    tags: loaded.tags,
                    sourceContents: try String(contentsOf: url, encoding: .utf8)
                )
            }
        } else {
            self.noteLoader = { try noteStore.loadNoteDocument(at: $0) }
        }
        self.fileModificationDateLoader = fileModificationDateLoader ?? Self.fileModificationDate(at:)
        self.thumbnailDecoder = thumbnailDecoder ?? Self.makeListThumbnailCGImage(at:)
        self.backgroundAutosaveWillPersist = backgroundAutosaveWillPersist
        self.backgroundSourceCountWillLoad = backgroundSourceCountWillLoad
        self.backgroundDeletionWillPersist = backgroundDeletionWillPersist
        self.usesCanonicalWindowSize = usesCanonicalWindowSize
        self.prefersExternalScreen = prefersExternalScreen
        self.onOpenInSeparateWindow = onOpenInSeparateWindow
        self.onSave = onSave
        self.onClose = onClose
        self.noteListSortOrder = LibraryNoteSortOrder(rawValue: noteStore.libraryNoteSortOrderRawValue) ?? .dateEdited
        self.groupsNoteListByDate = noteStore.libraryGroupsNotesByDate
        self.noteListViewMode = LibraryNoteViewMode(rawValue: noteStore.libraryNoteViewModeRawValue) ?? .list
        self.collapsedFolderPaths = noteStore.libraryCollapsedFolderPaths
        self.expandedFolderPaths = noteStore.libraryExpandedFolderPaths
        self.sourceFoldersSectionCollapsed = noteStore.libraryFoldersSectionCollapsed
        self.sourceTagsSectionCollapsed = noteStore.libraryTagsSectionCollapsed

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: LibraryNotesLayout.initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(MudsnoteBrand.appName) 笔记"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = LibraryNotesLayout.minimumWindowSize
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        super.init(window: window)
        LibraryNoteRowView.selectionFillColor = selectedThemeColor.noteSelectionColor
        window.delegate = self
        buildUI()
        configureToolbar()
        if defersInitialNoteHydration {
            let preferredRootPaths = noteStore.preferredDirectories.map {
                $0.standardizedFileURL.path
            }
            let cachedPresentation = noteStore.cachedLibraryPresentationSnapshot(
                limit: Self.sourceCountSnapshotLimit
            ).filter { note in
                let notePath = note.url.standardizedFileURL.path
                return preferredRootPaths.contains {
                    notePath == $0 || notePath.hasPrefix($0 + "/")
                }
            }
            applyCachedSourceTags(from: cachedPresentation)
            reloadNotes(
                loadFirstIfNeeded: false,
                allNotesSnapshot: cachedPresentation.isEmpty
                    ? recentShellNoteResults(limit: 240)
                    : cachedPresentation,
                refreshCounts: true
            )
        } else {
            hasHydratedInitialNoteList = true
            trashedNotesSnapshot = noteStore.listTrashedNotes(limit: Self.sourceCountSnapshotLimit)
            reloadNotes(
                loadFirstIfNeeded: true,
                allNotesSnapshot: allNoteResults(limit: Self.sourceCountSnapshotLimit)
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndFocus() {
        hasRequestedWindowPresentation = true
        showWindow(nil)
        guard let window else { return }
        if !hasCenteredWindow {
            let preferredScreen = prefersExternalScreen ? Self.externalScreen() : nil
            let visibleFrame = (preferredScreen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
            if !usesCanonicalWindowSize, let storedFrame = noteStore.libraryWindowFrame {
                let restoredFrame = clampedPanelFrame(
                    NSRect(
                        x: storedFrame.x,
                        y: storedFrame.y,
                        width: storedFrame.width,
                        height: storedFrame.height
                    ),
                    fallbackSize: LibraryNotesLayout.presentedWindowSize,
                    visibleFrames: NSScreen.screens.map(\.visibleFrame),
                    minimumSize: LibraryNotesLayout.minimumWindowSize
                )
                window.setFrame(restoredFrame, display: true)
            } else {
                let targetSize = LibraryNotesLayout.presentedWindowSize(
                    in: visibleFrame,
                    usesCanonicalSize: usesCanonicalWindowSize
                )
                let targetOrigin = NSPoint(
                    x: visibleFrame.midX - targetSize.width / 2,
                    y: visibleFrame.midY - targetSize.height / 2
                )
                window.setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
            }
            hasCenteredWindow = true
        }
        window.contentView?.layoutSubtreeIfNeeded()
        applyStoredLibrarySplitLayoutForLibrary()
        if noteListViewMode == .gallery {
            reloadGalleryData()
            synchronizeGallerySelectionFromTable()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if noteListViewMode == .gallery {
            window.makeFirstResponder(galleryCollectionView)
        } else if selectedURL == nil {
            window.makeFirstResponder(tableView)
        } else {
            editorTextView.window?.makeFirstResponder(editorTextView)
        }
        hydrateInitialNoteListIfNeeded()
        releaseDeferredLaunchWorkIfReady()
        startLibraryFileSystemMonitorIfNeeded()
    }

    private func releaseDeferredLaunchWorkIfReady() {
        guard hasRequestedWindowPresentation,
              !hasReleasedDeferredLaunchWork,
              !isLoadingInitialNote else { return }
        hasReleasedDeferredLaunchWork = true
        scheduleDeferredSourceFolderLoad()
        scheduleDeferredSourceTagLoad()
        scheduleFullLibrarySnapshotReload()
    }

    private func hydrateInitialNoteListIfNeeded() {
        guard !hasHydratedInitialNoteList else { return }
        hasHydratedInitialNoteList = true
        if selectedURL == nil {
            let launchSnapshot = noteStore.cachedLibraryLaunchNote()
            let cachedPath = launchSnapshot?.url.standardizedFileURL.path
            let noteRow = cachedPath.flatMap(rowIndex(for:))
                ?? listRows.firstIndex(where: { $0.note != nil })
            guard let noteRow,
                  let noteToLoad = note(at: noteRow) else {
                scheduleFullLibrarySnapshotReload()
                return
            }
            suppressSelectionChanges = true
            tableView.selectRowIndexes(IndexSet(integer: noteRow), byExtendingSelection: false)
            suppressSelectionChanges = false
            if let launchSnapshot,
               launchSnapshot.url.standardizedFileURL.path
                    == noteToLoad.url.standardizedFileURL.path {
                showPersistedInitialNote(launchSnapshot, for: noteToLoad)
            } else {
                showInitialNoteLoadingShell(for: noteToLoad)
            }
            loadInitialNoteAfterLaunch(noteToLoad)
        }
    }

    private func showPersistedInitialNote(
        _ snapshot: LibraryLaunchNoteSnapshot,
        for note: NoteSearchResult
    ) {
        isLoadingInitialNote = true
        isCreatingNewNote = false
        persistedLaunchFallbackURL = note.url.standardizedFileURL
        setSelectedURLForLibrary(note.url)
        selectedSourceContents = snapshot.document.sourceContents
        noteLinksView.update(.empty)
        setEditorEditable(false)
        applyDocument(
            title: snapshot.document.title,
            body: snapshot.document.body,
            tags: snapshot.document.tags
        )
        isDirty = false
        updateEditorCreatedDate(snapshot.createdAt)
        updateEditorStatus(editorEditedDateText(for: snapshot.modifiedAt))
        updateToolbarActionState()
    }

    private func showInitialNoteLoadingShell(for note: NoteSearchResult) {
        isLoadingInitialNote = true
        isCreatingNewNote = false
        setSelectedURLForLibrary(note.url)
        selectedSourceContents = nil
        noteLinksView.update(.empty)
        setEditorEditable(false)
        applyDocument(title: note.title, body: "", tags: note.tags)
        isDirty = false
        updateEditorCreatedDate(note.createdAt)
        updateEditorStatus(editorEditedDateText(for: note.modifiedAt))
        updateToolbarActionState()
    }

    private func loadInitialNoteAfterLaunch(_ note: NoteSearchResult) {
        let noteStore = noteStore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result<LoadedLibraryNote, Error> {
                try noteStore.loadNoteDocument(at: note.url)
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
        guard window?.isVisible == true else {
            isLoadingInitialNote = false
            hasHydratedInitialNoteList = false
            return
        }
        if case .failure(let error) = result,
           isMissingInitialNoteError(error) {
            persistedLaunchFallbackURL = nil
            noteStore.removeRecentFileReference(at: note.url)
            guard selectedNoteStillMatchesInitialLoad(note) else {
                releaseDeferredLaunchWorkIfReady()
                return
            }
            recoverFromMissingInitialNote(note)
            releaseDeferredLaunchWorkIfReady()
            return
        }
        guard selectedNoteStillMatchesInitialLoad(note) else {
            releaseDeferredLaunchWorkIfReady()
            return
        }
        if case .failure(let error) = result,
           persistedLaunchFallbackURL?.standardizedFileURL.path
                == note.url.standardizedFileURL.path {
            isLoadingInitialNote = false
            updateEditorStatus(
                "暂时无法刷新",
                kind: .failure,
                toolTip: error.localizedDescription
            )
            updateToolbarActionState()
            releaseDeferredLaunchWorkIfReady()
            return
        }
        persistedLaunchFallbackURL = nil
        applyLoadedNoteResult(result, for: note)
    }

    private func isMissingInitialNoteError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           (nsError.code == CocoaError.Code.fileNoSuchFile.rawValue
            || nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue) {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(POSIXErrorCode.ENOENT.rawValue) {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isMissingInitialNoteError(underlyingError)
        }
        return false
    }

    private func recoverFromMissingInitialNote(_ missingNote: NoteSearchResult) {
        let missingPath = missingNote.url.standardizedFileURL.path
        notes.removeAll { $0.url.standardizedFileURL.path == missingPath }
        listRows = buildGroupedRows(for: notes)

        suppressSelectionChanges = true
        reloadNoteBrowserData()
        tableView.deselectAll(nil)
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
        clearCurrentDocumentAfterRemoval()
        updateEditorStatus("")
        updateNoteListHeader(query: "")
        updateNoteListEmptyState(query: "")

        guard let nextNoteRow = listRows.firstIndex(where: { $0.note != nil }),
              let nextNote = note(at: nextNoteRow) else {
            updateToolbarActionState()
            return
        }

        suppressSelectionChanges = true
        tableView.selectRowIndexes(IndexSet(integer: nextNoteRow), byExtendingSelection: false)
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
        showInitialNoteLoadingShell(for: nextNote)
        loadInitialNoteAfterLaunch(nextNote)
    }

    private func scheduleFullLibrarySnapshotReload() {
        guard !fullLibrarySnapshotReloadScheduled else { return }
        fullLibrarySnapshotReloadScheduled = true
        fullLibrarySnapshotReloadGeneration += 1
        let generation = fullLibrarySnapshotReloadGeneration
        isFullLibrarySnapshotLoading = true
        updateNoteListHeader(query: searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let noteStore = noteStore
        let snapshotLimit = Self.sourceCountSnapshotLimit
        let preferredDirectories = noteStore.preferredDirectories
        let sourceFolderPaths = currentSourceFolderPaths()
        let externalDocumentPaths = Set(externallyOpenedDocumentsByPath.keys)
        Task.detached(priority: .utility) { [weak self] in
            let inboxDirectory = noteStore.preferredInboxDirectory
            let recentCount = Self.recentFilesVisibleInLibrary(
                noteStore: noteStore,
                preferredDirectories: preferredDirectories,
                externalDocumentPaths: externalDocumentPaths,
                limit: 80
            ).count
            if let cachedNotes = noteStore.cachedNotes(
                limit: snapshotLimit,
                roots: preferredDirectories
            ) {
                let cachedCountIndex = LibrarySourceCountIndex(
                    notes: cachedNotes,
                    folderPaths: sourceFolderPaths,
                    inboxDirectory: inboxDirectory
                )
                await MainActor.run {
                    guard let self,
                          generation == self.fullLibrarySnapshotReloadGeneration,
                          self.isFullLibrarySnapshotLoading else { return }
                    let mergedCachedNotes = self.includingExternallyOpenedDocuments(in: cachedNotes)
                    self.sourceInboxDirectory = inboxDirectory
                    self.sourceCountSnapshot = mergedCachedNotes
                    self.refreshSourceCounts(
                        using: mergedCachedNotes,
                        countIndex: self.currentSourceFolderPaths() == sourceFolderPaths
                            ? cachedCountIndex
                            : nil,
                        recentCount: recentCount
                    )
                }
            }
            let allNotes = noteStore.listNotesRefreshingIndex(
                limit: snapshotLimit,
                roots: preferredDirectories
            )
            noteStore.cacheLibraryPresentationSnapshot(allNotes)
            let trashedNotes = noteStore.listTrashedNotes(limit: snapshotLimit)
            let countIndex = LibrarySourceCountIndex(
                notes: allNotes,
                folderPaths: sourceFolderPaths,
                inboxDirectory: inboxDirectory
            )
            await MainActor.run {
                guard let self,
                      generation == self.fullLibrarySnapshotReloadGeneration else { return }
                self.fullLibrarySnapshotReloadScheduled = false
                self.isFullLibrarySnapshotLoading = false
                guard self.window?.isVisible == true else { return }
                self.sourceInboxDirectory = inboxDirectory
                self.trashedNotesSnapshot = trashedNotes
                let mergedAllNotes = self.includingExternallyOpenedDocuments(in: allNotes)
                self.applySourceTagsFromValidatedSnapshot(mergedAllNotes)
                let reusableCountIndex = self.currentSourceFolderPaths() == sourceFolderPaths
                    ? countIndex
                    : nil
                let currentQuery = self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !currentQuery.isEmpty {
                    self.sourceCountSnapshot = mergedAllNotes
                    self.refreshSourceCounts(
                        using: mergedAllNotes,
                        countIndex: reusableCountIndex,
                        recentCount: recentCount
                    )
                    self.updateNoteListHeader(query: currentQuery)
                    return
                }
                let shouldLoadFirstAfterSnapshot = self.selectedURL == nil && self.tableView.selectedRow < 0
                self.reloadNotes(
                    selecting: self.selectedURL,
                    loadFirstIfNeeded: shouldLoadFirstAfterSnapshot,
                    allNotesSnapshot: mergedAllNotes,
                    sourceCountIndex: reusableCountIndex,
                    sourceRecentCount: recentCount
                )
            }
        }
    }

    private func forceFullLibrarySnapshotReload() {
        fullLibrarySnapshotReloadGeneration += 1
        fullLibrarySnapshotReloadScheduled = false
        scheduleFullLibrarySnapshotReload()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            return true
        } catch {
            presentErrorAlert(message: "无法关闭资料库", details: error.localizedDescription)
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let librarySplitView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSSplitView.didResizeSubviewsNotification,
                object: librarySplitView
            )
        }
        autosaveTask?.cancel()
        autosaveTask = nil
        editorNoteSuggestionTask?.cancel()
        editorNoteSuggestionTask = nil
        cancelActiveNoteLoad()
        notePrefetchTask?.cancel()
        notePrefetchTask = nil
        thumbnailImageLoadTasks.values.forEach { $0.cancel() }
        thumbnailImageLoadTasks.removeAll()
        pendingThumbnailReloadPaths.removeAll()
        thumbnailReloadScheduled = false
        fileSystemMonitor?.stop()
        fileSystemMonitor = nil
        internallyMutatedPaths.removeAll()
        attachmentQuickLookController.dismiss()
        attachmentManagerWindowController?.close()
        attachmentManagerWindowController = nil
        knowledgeGraphWindowController?.close()
        knowledgeGraphWindowController = nil
        cancelSourceSnapshotValidation()
        sourceCountRefreshTask?.cancel()
        sourceCountRefreshTask = nil
        sourceCountRefreshGeneration += 1
        searchReloadWorkItem?.cancel()
        searchReloadWorkItem = nil
        editorSearchHighlightRefreshTask?.cancel()
        editorSearchHighlightRefreshTask = nil
        knowledgeSynthesisTask?.cancel()
        knowledgeSynthesisTask = nil
        knowledgeSynthesisGeneration += 1
        cancelActiveSearchResultReload()
        hasPendingSearchReload = false
        splitLayoutPersistenceWorkItem?.cancel()
        splitLayoutPersistenceWorkItem = nil
        windowFramePersistenceWorkItem?.cancel()
        windowFramePersistenceWorkItem = nil
        persistLibraryWindowFrameForLibrary()
        persistLibrarySplitLayoutForLibrary()
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        scheduleLibraryWindowFramePersistence()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshToolbarEditorTextButtonFocus(isWindowFocused: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        refreshToolbarEditorTextButtonFocus(isWindowFocused: false)
    }

    func windowDidResize(_ notification: Notification) {
        scheduleLibraryWindowFramePersistence()
        layoutEditorStatusLabel()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        windowFramePersistenceWorkItem?.cancel()
        windowFramePersistenceWorkItem = nil
        persistLibraryWindowFrameForLibrary()
    }

    private func scheduleLibraryWindowFramePersistence() {
        guard !usesCanonicalWindowSize,
              hasRequestedWindowPresentation,
              hasCenteredWindow else {
            return
        }
        windowFramePersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.windowFramePersistenceWorkItem = nil
            self?.persistLibraryWindowFrameForLibrary()
        }
        windowFramePersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: workItem)
    }

    func persistLibraryWindowFrameForLibrary() {
        guard !usesCanonicalWindowSize,
              hasCenteredWindow,
              let frame = window?.frame else {
            return
        }
        noteStore.libraryWindowFrame = StoredWindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    private func startLibraryFileSystemMonitorIfNeeded() {
        guard fileSystemMonitor == nil else { return }
        let monitor = LibraryFileSystemMonitor(roots: noteStore.preferredDirectories) { [weak self] changes in
            Task { @MainActor [weak self] in
                self?.handleLibraryFileSystemChanges(changes)
            }
        }
        guard monitor.start() else { return }
        fileSystemMonitor = monitor
    }

    private func restartLibraryFileSystemMonitorForCurrentRoots() {
        let shouldRestart = fileSystemMonitor != nil || window?.isVisible == true
        fileSystemMonitor?.stop()
        fileSystemMonitor = nil
        if shouldRestart {
            startLibraryFileSystemMonitorIfNeeded()
        }
    }

    private func handleLibraryFileSystemChanges(
        _ changes: Set<LibraryFileSystemChange>,
        requiresVisibleWindow: Bool = true
    ) {
        guard !requiresVisibleWindow || window?.isVisible == true else { return }
        if backgroundAutosaveIsActive {
            deferredFileSystemChangesDuringAutosave.formUnion(changes)
            return
        }
        let externalChanges = changes.filter {
            $0.requiresUnconditionalFullRescan || !isSuppressedInternalChange($0)
        }
        guard !externalChanges.isEmpty else { return }

        let markdownPaths = Set(externalChanges.filter(\.isMarkdownFile).map {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
        })
        let hasFolderStructureChange = externalChanges.contains(where: \.changesDirectoryStructure)
        if externalChanges.contains(where: \.requiresFullRescan) {
            noteStore.invalidateSearchIndexContents()
        } else {
            noteStore.markSearchIndexDirty(at: markdownPaths.map {
                URL(fileURLWithPath: $0)
            })
        }
        knowledgeGraphWindowController?.reload()
        activeSearchSession = nil

        for path in markdownPaths {
            loadedNoteCache.removeEntry(forKey: path as NSString)
        }

        if let selectedURL,
           markdownPaths.contains(selectedURL.standardizedFileURL.path),
           !isDirty,
           FileManager.default.fileExists(atPath: selectedURL.path),
           let selectedNote = notes.first(where: {
               $0.url.standardizedFileURL.path == selectedURL.standardizedFileURL.path
           }) {
            reloadSelectedNoteAfterExternalChange(selectedNote)
        }

        if hasFolderStructureChange {
            sourceFoldersLoaded = false
            scheduleDeferredSourceFolderLoad()
        }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: selectedURL == nil)
            scheduleSourceSnapshotValidation(loadFirstIfNeeded: selectedURL == nil)
        } else {
            performSearchReload()
        }
    }

    private func flushDeferredFileSystemChangesAfterAutosave() {
        guard !backgroundAutosaveIsActive,
              !deferredFileSystemChangesDuringAutosave.isEmpty else {
            return
        }
        let changes = deferredFileSystemChangesDuringAutosave
        deferredFileSystemChangesDuringAutosave.removeAll()
        handleLibraryFileSystemChanges(changes, requiresVisibleWindow: false)
    }

    private func recordInternalFileSystemChanges(
        for urls: [URL],
        includingDescendants: Bool = false
    ) {
        let expiration = Date().addingTimeInterval(2)
        for url in urls {
            let path = url.standardizedFileURL.path
            internallyMutatedPaths[path] = expiration
            if includingDescendants {
                internallyMutatedDirectoryPaths[path] = expiration
            }
        }
    }

    private func isSuppressedInternalChange(_ change: LibraryFileSystemChange) -> Bool {
        let now = Date()
        internallyMutatedPaths = internallyMutatedPaths.filter { $0.value > now }
        internallyMutatedDirectoryPaths = internallyMutatedDirectoryPaths.filter { $0.value > now }
        let path = URL(fileURLWithPath: change.path).standardizedFileURL.path
        if internallyMutatedPaths[path].map({ $0 > now }) ?? false {
            return true
        }
        return internallyMutatedDirectoryPaths.contains { directoryPath, expiration in
            expiration > now && path.hasPrefix(directoryPath + "/")
        }
    }

    func handleLibraryFileSystemChangesForTesting(_ changes: Set<LibraryFileSystemChange>) {
        handleLibraryFileSystemChanges(changes, requiresVisibleWindow: false)
    }

    func waitForExternalLibraryRefreshForTesting() async {
        await sourceSnapshotValidationTask?.value
        await searchResultsTask?.value
        await noteLoadTask?.value
    }

    private func buildUI() {
        let sourceList = buildSourceList()
        let sidebar = buildSidebar()
        let editor = buildEditor()

        let sourceController = NSViewController()
        sourceController.view = sourceList
        let noteListController = NSViewController()
        noteListController.view = sidebar
        let editorController = NSViewController()
        editorController.view = editor

        let sourceItem = NSSplitViewItem(sidebarWithViewController: sourceController)
        sourceItem.minimumThickness = LibraryNotesLayout.sourceColumnMinimumWidth
        sourceItem.maximumThickness = LibraryNotesLayout.sourceColumnMaximumWidth
        sourceItem.canCollapse = true
        sourceItem.allowsFullHeightLayout = true
        sourceItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        sourceItem.isCollapsed = !noteStore.librarySourceListVisible

        let noteListItem = NSSplitViewItem(contentListWithViewController: noteListController)
        noteListItem.minimumThickness = LibraryNotesLayout.noteColumnMinimumWidth
        noteListItem.maximumThickness = LibraryNotesLayout.noteColumnMaximumWidth
        noteListItem.automaticMaximumThickness = LibraryNotesLayout.noteColumnMaximumWidth
        noteListItem.canCollapse = true
        noteListItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView

        let editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = LibraryNotesLayout.editorColumnMinimumWidth

        let splitController = NSSplitViewController()
        splitController.addSplitViewItem(sourceItem)
        splitController.addSplitViewItem(noteListItem)
        splitController.addSplitViewItem(editorItem)
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        splitController.view.wantsLayer = true
        splitController.view.layer?.backgroundColor = LibraryNotesPalette.windowBackground.cgColor

        librarySplitViewController = splitController
        sourceSplitViewItem = sourceItem
        noteListSplitViewItem = noteListItem
        librarySplitView = splitController.splitView
        window?.contentViewController = splitController
        hostEditorSuggestionView(in: splitController.view)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(librarySplitViewDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitController.splitView
        )

        splitController.view.layoutSubtreeIfNeeded()
        applyStoredLibrarySplitLayoutForLibrary()
        applyNoteListViewModeChrome(animated: false)
    }

    private func buildSourceList() -> NSView {
        let sourceList = NSVisualEffectView()
        sourceList.translatesAutoresizingMaskIntoConstraints = false
        sourceList.identifier = NSUserInterfaceItemIdentifier("LibrarySourceSurface")
        sourceList.setAccessibilityLabel("资料库")
        sourceList.material = .sidebar
        sourceList.blendingMode = .withinWindow
        sourceList.state = .active
        sourceList.wantsLayer = true
        sourceList.layer?.backgroundColor = LibraryNotesPalette.sourceBackground
            .withAlphaComponent(0.86)
            .cgColor
        sourceList.layer?.cornerRadius = LibraryNotesLayout.sourceSurfaceCornerRadius
        sourceList.layer?.masksToBounds = true
        sourceListView = sourceList

        let darkeningView = NSView()
        darkeningView.identifier = NSUserInterfaceItemIdentifier("LibrarySourceDarkeningTint")
        darkeningView.wantsLayer = true
        darkeningView.layer?.backgroundColor = NSColor.black.withAlphaComponent(
            LibraryNotesLayout.sourceSurfaceDarkeningAlpha
        ).cgColor
        sourceList.addSubview(darkeningView)
        pin(darkeningView, to: sourceList)
        sourceFolderTreeRows = rootFolderRowsForSourceList()
        sourceFolderRows = sourceFolderTreeRows

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("LibrarySourceColumn"))
        column.resizingMask = .autoresizingMask
        sourceOutlineView.addTableColumn(column)
        sourceOutlineView.outlineTableColumn = column
        sourceOutlineView.identifier = NSUserInterfaceItemIdentifier("LibrarySourceOutline")
        sourceOutlineView.setAccessibilityLabel("资料库")
        sourceOutlineView.headerView = nil
        sourceOutlineView.backgroundColor = .clear
        sourceOutlineView.style = .sourceList
        sourceOutlineView.selectionHighlightStyle = .regular
        sourceOutlineView.allowsEmptySelection = true
        sourceOutlineView.allowsMultipleSelection = false
        sourceOutlineView.indentationPerLevel = LibraryNotesLayout.sourceFolderIndentStep
        sourceOutlineView.rowSizeStyle = .custom
        sourceOutlineView.intercellSpacing = .zero
        sourceOutlineView.delegate = self
        sourceOutlineView.dataSource = self
        sourceOutlineView.registerForDraggedTypes([.fileURL])
        sourceOutlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        sourceOutlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        sourceOutlineView.contextMenuProvider = { [weak self] row in
            self?.sourceContextMenuForLibrary(row: row)
        }
        sourceOutlineView.onPrimaryMouseSelectionCommitted = { [weak self] in
            self?.commitCurrentSourceOutlineSelection()
        }
        sourceOutlineView.onPrimaryMouseSelectionPreviewChanged = { [weak self] in
            guard let self else { return }
            self.refreshVisibleSourceOutlinePresentation()
            self.sourceOutlineView.window?.displayIfNeeded()
        }

        let scrollView = LibrarySourceScrollView()
        scrollView.identifier = NSUserInterfaceItemIdentifier("LibrarySourceScroll")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = sourceOutlineView
        scrollView.contentInsets = NSEdgeInsets(
            top: LibraryNotesLayout.sourceListTopInset,
            left: LibraryNotesLayout.sourceListLeadingInset,
            bottom: LibraryNotesLayout.sourceListBottomInset,
            right: LibraryNotesLayout.sourceListTrailingInset
        )
        scrollView.scrollerInsets = NSEdgeInsets()
        sourceList.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: sourceList.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sourceList.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: sourceList.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sourceList.bottomAnchor)
        ])
        rebuildSourceRows(includeTags: sourceTagsLoaded)

        return sourceList
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = LibraryNotesPalette.noteListBackground.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        configureNoteListHeaderLabels()
        configureSearchScopeControl()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = LibraryNotesLayout.noteTableInitialWidth
        column.minWidth = LibraryNotesLayout.noteTableMinimumWidth
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
        tableView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTable")
        tableView.setAccessibilityLabel("笔记列表")
        tableView.headerView = nil
        tableView.rowHeight = 68
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.floatsGroupRows = false
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
        tableView.onContextMenu = { [weak self] row in
            self?.noteContextMenuForLibrary(row: row)
        }

        let scrollView = LibraryNoteScrollView()
        let clipView = LibraryNoteClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        clipView.drawsBackground = false
        clipView.backgroundColor = .clear
        scrollView.contentView = clipView
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

        let stack = NSStackView(views: [listContainer])
        stack.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListStack")
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(
            top: LibraryNotesLayout.noteListTopInset,
            left: LibraryNotesLayout.noteListLeadingInset,
            bottom: LibraryNotesLayout.noteListBottomInset,
            right: LibraryNotesLayout.noteListTrailingInset
        )
        sidebar.addSubview(stack)
        let titlebarSeparator = makeLibraryTitlebarSeparator(identifier: "LibraryNoteListTitlebarSeparator")
        sidebar.addSubview(titlebarSeparator)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(
                equalTo: sidebar.safeAreaLayoutGuide.topAnchor,
                constant: LibraryNotesLayout.noteListStackTopOffset
            ),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            titlebarSeparator.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            titlebarSeparator.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            titlebarSeparator.bottomAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor),
            titlebarSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
        listContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return sidebar
    }

    private func configureGalleryCollectionView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(
            width: LibraryNotesLayout.galleryItemWidth,
            height: LibraryNotesLayout.galleryItemHeight
        )
        layout.minimumInteritemSpacing = LibraryNotesLayout.galleryInteritemSpacing
        layout.minimumLineSpacing = LibraryNotesLayout.galleryLineSpacing
        layout.sectionInset = NSEdgeInsets(
            top: LibraryNotesLayout.galleryVerticalInset,
            left: LibraryNotesLayout.galleryHorizontalInset,
            bottom: LibraryNotesLayout.galleryVerticalInset,
            right: LibraryNotesLayout.galleryHorizontalInset
        )

        galleryCollectionView.identifier = NSUserInterfaceItemIdentifier("LibraryGalleryCollection")
        galleryCollectionView.setAccessibilityLabel("笔记画廊")
        galleryCollectionView.collectionViewLayout = layout
        galleryCollectionView.backgroundColors = [.clear]
        galleryCollectionView.isSelectable = true
        galleryCollectionView.allowsMultipleSelection = true
        galleryCollectionView.dataSource = self
        galleryCollectionView.delegate = self
        galleryCollectionView.register(
            LibraryGalleryItem.self,
            forItemWithIdentifier: LibraryGalleryItem.identifier
        )
        galleryCollectionView.register(
            LibraryGallerySectionHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: LibraryGallerySectionHeaderView.identifier
        )
        galleryCollectionView.onKeyCommand = { [weak self] command in
            self?.handleGalleryKeyCommand(command) ?? false
        }
        galleryCollectionView.onContextMenu = { [weak self] indexPath in
            self?.galleryContextMenuForLibrary(at: indexPath)
        }
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(galleryDoubleClicked(_:)))
        doubleClick.numberOfClicksRequired = 2
        galleryCollectionView.addGestureRecognizer(doubleClick)
    }

    private func buildEditor() -> NSView {
        let editor = NSView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = LibraryNotesPalette.editorBackground.cgColor

        titleField.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTitleField")
        titleField.setAccessibilityLabel("笔记标题")
        titleField.placeholderString = ""
        titleField.font = .systemFont(ofSize: LibraryNotesLayout.editorTitleFontSize, weight: .bold)
        titleField.textColor = panelPrimaryTextColor()
        titleField.alignment = .left
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.delegate = self
        titleField.isHidden = true
        titleField.setAccessibilityElement(false)

        statusLabel.identifier = NSUserInterfaceItemIdentifier("LibraryEditorStatusLabel")
        statusLabel.setAccessibilityLabel("编辑时间或保存状态")
        statusLabel.font = .systemFont(ofSize: LibraryNotesLayout.editorStatusFontSize, weight: .semibold)
        statusLabel.textColor = panelTertiaryTextColor()
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        wordCountLabel.setAccessibilityLabel("字数")
        wordCountLabel.font = .monospacedDigitSystemFont(
            ofSize: LibraryNotesLayout.editorStatusFontSize,
            weight: .medium
        )
        wordCountLabel.textColor = panelTertiaryTextColor()
        wordCountLabel.alignment = .right

        configureEditorTextView()
        createdDateLabel.identifier = NSUserInterfaceItemIdentifier("LibraryEditorCreatedDateLabel")
        createdDateLabel.setAccessibilityLabel("创建时间")
        createdDateLabel.font = .systemFont(
            ofSize: LibraryNotesLayout.editorStatusFontSize,
            weight: .semibold
        )
        createdDateLabel.textColor = panelTertiaryTextColor()
        createdDateLabel.alignment = .center
        createdDateLabel.lineBreakMode = .byTruncatingTail
        createdDateLabel.translatesAutoresizingMaskIntoConstraints = false
        editorTextView.addSubview(createdDateLabel)
        NSLayoutConstraint.activate([
            createdDateLabel.topAnchor.constraint(equalTo: editorTextView.topAnchor, constant: 4),
            createdDateLabel.centerXAnchor.constraint(
                equalTo: editorTextView.centerXAnchor,
                constant: LibraryNotesLayout.editorStatusHorizontalOffset
            ),
            createdDateLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: editorTextView.leadingAnchor,
                constant: 20
            ),
            createdDateLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: editorTextView.trailingAnchor,
                constant: -20
            ),
            createdDateLabel.heightAnchor.constraint(
                equalToConstant: LibraryNotesLayout.editorDateRowHeight
            )
        ])
        editorTextView.addSubview(statusLabel)
        editorTextView.addSubview(wordCountLabel)
        let scrollView = LibraryEditorScrollView()
        let clipView = EditorClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        clipView.drawsBackground = true
        clipView.backgroundColor = LibraryNotesPalette.editorBackground
        scrollView.contentView = clipView
        scrollView.documentView = editorTextView
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: LibraryNotesLayout.editorHorizontalInset
        )
        scrollView.scrollerInsets = NSEdgeInsets()

        let bodyContainer = NSView()
        bodyContainer.identifier = NSUserInterfaceItemIdentifier("LibraryEditorBodyContainer")
        bodyContainer.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor)
        ])

        noteLinksView.onOpen = { [weak self] url in
            self?.openKnowledgeRelation(at: url)
        }
        noteLinksView.onAcceptSuggestion = { [weak self] item in
            self?.acceptKnowledgeSuggestion(item)
        }
        noteLinksView.onGoBack = { [weak self] in
            self?.goBackInKnowledgeRelations()
        }
        noteLinksView.onGoForward = { [weak self] in
            self?.goForwardInKnowledgeRelations()
        }
        noteLinksView.onGenerateHigherLayer = { [weak self] layer in
            self?.generateHigherLayerDraft(targetLayer: layer)
        }
        noteLinksView.onShowGraph = { [weak self] in
            self?.showKnowledgeGraphForLibrary()
        }

        let stack = NSStackView(views: [bodyContainer, noteLinksView])
        stack.identifier = NSUserInterfaceItemIdentifier("LibraryEditorStack")
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.setCustomSpacing(8, after: bodyContainer)
        stack.edgeInsets = NSEdgeInsets(
            top: 0,
            left: LibraryNotesLayout.editorHorizontalInset,
            bottom: LibraryNotesLayout.editorBottomInset,
            right: LibraryNotesLayout.editorHorizontalInset
        )

        configureGalleryCollectionView()
        let galleryScrollView = NSScrollView()
        galleryScrollView.identifier = NSUserInterfaceItemIdentifier("LibraryGalleryScroll")
        galleryScrollView.drawsBackground = false
        galleryScrollView.borderType = .noBorder
        galleryScrollView.hasVerticalScroller = true
        galleryScrollView.hasHorizontalScroller = false
        galleryScrollView.autohidesScrollers = true
        galleryScrollView.contentView.drawsBackground = false
        galleryScrollView.documentView = galleryCollectionView

        galleryEmptyLabel.identifier = NSUserInterfaceItemIdentifier("LibraryGalleryEmptyLabel")
        galleryEmptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        galleryEmptyLabel.textColor = panelTertiaryTextColor()
        galleryEmptyLabel.alignment = .center
        galleryEmptyLabel.lineBreakMode = .byWordWrapping
        galleryEmptyLabel.maximumNumberOfLines = 2
        galleryEmptyLabel.isHidden = true

        editor.addSubview(stack)
        editor.addSubview(galleryScrollView)
        editor.addSubview(galleryEmptyLabel)
        let titlebarSeparator = makeLibraryTitlebarSeparator(identifier: "LibraryEditorTitlebarSeparator")
        editor.addSubview(titlebarSeparator)
        stack.translatesAutoresizingMaskIntoConstraints = false
        galleryScrollView.translatesAutoresizingMaskIntoConstraints = false
        galleryEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            stack.topAnchor.constraint(equalTo: editor.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            galleryScrollView.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            galleryScrollView.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            galleryScrollView.topAnchor.constraint(equalTo: editor.safeAreaLayoutGuide.topAnchor),
            galleryScrollView.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            galleryEmptyLabel.centerXAnchor.constraint(equalTo: editor.centerXAnchor),
            galleryEmptyLabel.centerYAnchor.constraint(equalTo: editor.centerYAnchor, constant: -20),
            galleryEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: editor.leadingAnchor, constant: 24),
            galleryEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: editor.trailingAnchor, constant: -24),
            titlebarSeparator.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            titlebarSeparator.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            titlebarSeparator.bottomAnchor.constraint(equalTo: editor.safeAreaLayoutGuide.topAnchor),
            titlebarSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
        let editorContentWidthOffset = -(LibraryNotesLayout.editorHorizontalInset * 2)
        NSLayoutConstraint.activate([
            bodyContainer.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -LibraryNotesLayout.editorHorizontalInset
            ),
            noteLinksView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: editorContentWidthOffset)
        ])
        bodyContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        editorStackView = stack
        self.galleryScrollView = galleryScrollView
        stack.isHidden = noteListViewMode == .gallery
        galleryScrollView.isHidden = noteListViewMode != .gallery

        return editor
    }

    private func makeLibraryTitlebarSeparator(identifier: String) -> NSBox {
        let separator = NSBox()
        separator.identifier = NSUserInterfaceItemIdentifier(identifier)
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func configureToolbar() {
        searchField.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarSearchField")
        searchField.placeholderString = LibraryCopy.search
        searchField.toolTip = LibraryCopy.searchNotes
        searchField.setAccessibilityLabel(LibraryCopy.searchNotes)
        searchField.font = .systemFont(ofSize: 14)
        searchField.delegate = self
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .default
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
        applyNoteListViewModeToolbarChrome()
    }

    private func configureSearchScopeControl() {
        searchScopeControl.identifier = NSUserInterfaceItemIdentifier("LibrarySearchScopeControl")
        searchScopeControl.setAccessibilityLabel("搜索范围")
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
            Self.noteListTitleToolbarItemIdentifier,
            Self.noteTrackingSeparatorToolbarItemIdentifier,
            Self.newNoteToolbarItemIdentifier,
            .space,
            Self.editorToolsToolbarItemIdentifier,
            .flexibleSpace,
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
            Self.linkToolbarItemIdentifier,
            Self.sourceModeToolbarItemIdentifier
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
        case Self.noteListTitleToolbarItemIdentifier:
            return toolbarNoteListTitleItem(identifier: itemIdentifier)
        case Self.addFolderToolbarItemIdentifier:
            return toolbarAddFolderItem(
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
                action: #selector(toggleSourceListPressed),
                symbolPointSize: LibraryNotesLayout.toolbarSourceActionSymbolPointSize
            )
        case Self.newNoteToolbarItemIdentifier:
            return toolbarCircularButtonItem(
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
        case Self.revealToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "打开文件位置",
                symbolName: "folder",
                action: #selector(revealSelectedNoteInFinderPressed)
            )
        case Self.linkToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "插入链接",
                symbolName: "link",
                action: #selector(linkPressed)
            )
        case Self.sourceModeToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "显示 Markdown 源码",
                symbolName: "chevron.left.forwardslash.chevron.right",
                action: #selector(toggleEditorSourceModePressed)
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
        case Self.searchToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = LibraryCopy.search
            item.paletteLabel = LibraryCopy.search
            item.toolTip = LibraryCopy.searchNotes
            item.visibilityPriority = .high
            let wrapper = NSView(frame: NSRect(
                x: 0,
                y: 0,
                width: LibraryNotesLayout.toolbarSearchWrapperWidth,
                height: LibraryNotesLayout.toolbarSearchWrapperHeight
            ))
            wrapper.addSubview(searchField)
            NSLayoutConstraint.activate([
                searchField.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
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

    private func toolbarNoteListTitleItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "笔记列表标题"
        item.paletteLabel = "笔记列表标题"
        item.visibilityPriority = .high
        item.isBordered = false

        let titleStack = NSStackView(views: [noteListTitleLabel, noteListCountLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 0
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [titleStack, searchScopeControl])
        headerStack.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarNoteListHeaderStack")
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        searchScopeControl.setContentHuggingPriority(.required, for: .horizontal)
        searchScopeControl.setContentCompressionResistancePriority(.required, for: .horizontal)

        let wrapper = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarNoteListTitleWidth,
            height: LibraryNotesLayout.toolbarNoteListTitleHeight
        ))
        wrapper.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarNoteListTitle")
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        let titleLeadingConstraint = headerStack.leadingAnchor.constraint(
            equalTo: wrapper.leadingAnchor,
            constant: LibraryNotesLayout.toolbarExpandedTitleLeadingOffset
        )
        noteListToolbarTitleLeadingConstraint = titleLeadingConstraint
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarNoteListTitleWidth),
            wrapper.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarNoteListTitleHeight),
            titleLeadingConstraint,
            headerStack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -6),
            headerStack.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])

        item.view = wrapper
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.moreToolbarItemIdentifier:
            return canShowMoreActions
        case Self.openSeparateToolbarItemIdentifier:
            return canUseSingleSelectedNote
        case Self.editorToolsToolbarItemIdentifier:
            return canEditCurrentDocument || canUseSelectedNote
        case Self.formatToolbarItemIdentifier,
             Self.checklistToolbarItemIdentifier,
             Self.linkToolbarItemIdentifier,
             Self.sourceModeToolbarItemIdentifier:
            return canEditCurrentDocument
        case Self.revealToolbarItemIdentifier:
            return canUseSelectedNote
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
        visibilityPriority: NSToolbarItem.VisibilityPriority = .standard,
        symbolPointSize: CGFloat = LibraryNotesLayout.toolbarSymbolPointSize
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = toolbarSymbolImage(
            symbolName: symbolName,
            label: label,
            pointSize: symbolPointSize
        )
        item.target = self
        item.action = action
        item.visibilityPriority = visibilityPriority
        item.isBordered = false
        return item
    }

    private func toolbarAddFolderItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = toolbarButtonItem(
            identifier: identifier,
            label: label,
            symbolName: symbolName,
            action: action,
            symbolPointSize: LibraryNotesLayout.toolbarSourceActionSymbolPointSize
        )
        let button = NSButton(
            image: item.image ?? NSImage(),
            target: self,
            action: action
        )
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
        updateToolbarEditorTextButtonAppearance(button, isEnabled: true, isWindowFocused: true)
        button.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarAddFolderWrapperWidth,
            height: LibraryNotesLayout.toolbarCircularButtonSize
        ))
        wrapper.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarAddFolderWrapper")
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarAddFolderWrapperWidth),
            wrapper.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize),
            button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize),
            button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize)
        ])
        item.view = wrapper
        return item
    }

    private func toolbarEditorToolsItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "编辑工具"
        item.paletteLabel = "编辑工具"
        item.toolTip = "编辑工具"
        item.visibilityPriority = .high
        item.isBordered = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let capsule = toolbarGlassSurface(
            identifier: "LibraryToolbarEditorTools",
            content: stack,
            size: NSSize(
                width: LibraryNotesLayout.toolbarEditorToolsWidth,
                height: LibraryNotesLayout.toolbarEditorToolsHeight
            ),
            cornerRadius: LibraryNotesLayout.toolbarEditorToolsHeight / 2
        )
        let buttons = [
            toolbarEditorFormatButton(
                identifier: Self.formatToolbarItemIdentifier,
                label: "格式",
                action: #selector(formatPressed(_:))
            ),
            toolbarEditorToolButton(
                identifier: Self.checklistToolbarItemIdentifier,
                label: "待办列表",
                symbolName: "checklist",
                action: #selector(checklistPressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.linkToolbarItemIdentifier,
                label: "插入链接",
                symbolName: "link",
                action: #selector(linkPressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.sourceModeToolbarItemIdentifier,
                label: "显示 Markdown 源码",
                symbolName: "chevron.left.forwardslash.chevron.right",
                action: #selector(toggleEditorSourceModePressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.revealToolbarItemIdentifier,
                label: "打开文件位置",
                symbolName: "folder",
                action: #selector(revealSelectedNoteInFinderPressed)
            )
        ]
        buttons.forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolButtonHeight)
        ])

        let slot = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarEditorToolsSlotWidth,
            height: LibraryNotesLayout.toolbarEditorToolsHeight
        ))
        slot.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarEditorToolsSlot")
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(capsule)
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolsSlotWidth),
            slot.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolsHeight),
            capsule.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            capsule.centerYAnchor.constraint(equalTo: slot.centerYAnchor)
        ])

        item.view = slot
        updateEditorToolsToolbarGroupState(in: item)
        return item
    }

    private func toolbarEditorFormatButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: "Aa", target: self, action: action)
        button.font = .systemFont(ofSize: LibraryNotesLayout.toolbarEditorFormatFontSize, weight: .regular)
        return configureToolbarEditorToolButton(button, identifier: identifier, label: label)
    }

    private func toolbarEditorToolButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSButton {
        let image = toolbarEditorToolSymbolImage(symbolName: symbolName, label: label)
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
        return configureToolbarEditorToolButton(button, identifier: identifier, label: label)
    }

    private func configureToolbarEditorToolButton(
        _ button: NSButton,
        identifier: NSToolbarItem.Identifier,
        label: String
    ) -> NSButton {
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.focusRingType = .none
        button.imagePosition = button.image == nil ? .noImage : .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
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

    private func toolbarCircularButtonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = false

        let configuredImage = toolbarCompactGlassSymbolImage(
            symbolName: symbolName,
            label: label,
            pointSize: LibraryNotesLayout.toolbarNewNoteSymbolPointSize
        )
        configuredImage?.isTemplate = true

        let button = NSButton(image: configuredImage ?? NSImage(), target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .glass
        button.isBordered = true
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true

        let wrapper = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarNewNoteWrapperWidth,
            height: LibraryNotesLayout.toolbarCircularButtonSize
        ))
        wrapper.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarNewNoteWrapper")
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarNewNoteWrapperWidth),
            wrapper.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize),
            button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])

        item.image = configuredImage
        item.view = wrapper
        return item
    }

    private func toolbarSymbolImage(
        symbolName: String,
        label: String,
        pointSize: CGFloat = LibraryNotesLayout.toolbarSymbolPointSize
    ) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular
        )) ?? image
    }

    private func toolbarCompactGlassSymbolImage(
        symbolName: String,
        label: String,
        pointSize: CGFloat = LibraryNotesLayout.toolbarCircularButtonSymbolPointSize
    ) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular
        )) ?? image
    }

    private func toolbarEditorToolSymbolImage(symbolName: String, label: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.toolbarEditorToolSymbolPointSize,
            weight: .regular
        )) ?? image
    }

    private func toolbarIconTintColor(isEnabled: Bool) -> NSColor {
        panelPrimaryTextColor().withAlphaComponent(isEnabled
            ? LibraryNotesLayout.toolbarIconEnabledAlpha
            : LibraryNotesLayout.toolbarIconDisabledAlpha
        )
    }

    private func toolbarEditorToolIconTintColor(isEnabled: Bool) -> NSColor {
        panelPrimaryTextColor().withAlphaComponent(isEnabled
            ? LibraryNotesLayout.toolbarIconEnabledAlpha
            : LibraryNotesLayout.toolbarEditorToolIconDisabledAlpha
        )
    }

    private func toolbarGlassSurface(
        identifier: String,
        content: NSView,
        size: NSSize,
        cornerRadius: CGFloat
    ) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.identifier = NSUserInterfaceItemIdentifier(identifier)
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.setContentHuggingPriority(.required, for: .horizontal)
        glass.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            glass.widthAnchor.constraint(equalToConstant: size.width),
            glass.heightAnchor.constraint(equalToConstant: size.height)
        ])
        return glass
    }

    private func makeFormatToolbarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 16))
        image.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        ("Aa" as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "格式"
        return image
    }

    private func configureEditorTextView() {
        editorTextView.setAccessibilityLabel("笔记内容")
        editorTextView.commandDelegate = self
        editorTextView.delegate = self
        editorTextView.markdownPasteTheme = theme
        editorTextView.configureContextMenu = { [weak self] menu, _ in
            self?.configureEditorInsertContextMenu(menu)
        }
        editorTextView.contextMenuOptionsProvider = { [weak self] in
            self?.noteStore.enabledEditorContextMenuOptions ?? Set(EditorContextMenuOption.allCases)
        }
        editorTextView.onImageDisplayWidthChanged = { [weak self] fileURL, width in
            self?.noteStore.setLibraryImageDisplayWidth(width, for: fileURL)
        }
        editorTextView.imageDisplayWidthProvider = { [weak self] fileURL in
            self?.noteStore.libraryImageDisplayWidth(for: fileURL)
        }
        editorTextView.selectionMenuProvider = { [weak self] in
            self?.makeSelectionFormattingMenuForLibrary()
        }
        editorTextView.onTextInputStateChanged = { [weak self] in
            self?.updateEditorSlashSuggestions()
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
        editorTextView.selectedTextAttributes = [
            .backgroundColor: theme.accentColor.withAlphaComponent(0.24)
        ]
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainerInset = NSSize(
            width: LibraryNotesLayout.editorTextContainerHorizontalInset,
            height: LibraryNotesLayout.editorDateRowHeight
                + LibraryNotesLayout.editorDateToTitleSpacing
                + 4
        )
        editorTextView.textContainer?.lineFragmentPadding = 0
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
        editorSuggestionController.view.identifier = NSUserInterfaceItemIdentifier(
            "LibraryEditorSlashSuggestionPopover"
        )
        editorSuggestionController.view.isHidden = true
        editorSuggestionController.view.translatesAutoresizingMaskIntoConstraints = true
        editorSuggestionController.onSelect = { [weak self] index in
            self?.acceptEditorSlashSuggestion(at: index)
        }
    }

    private func hostEditorSuggestionView(in host: NSView) {
        let suggestionView = editorSuggestionController.view
        guard suggestionView.superview !== host else { return }
        suggestionView.removeFromSuperview()
        host.addSubview(suggestionView, positioned: .above, relativeTo: nil)
    }

    private func rebuildSourceRows(includeTags: Bool) {
        let wasSynchronizingSelection = isSynchronizingSourceOutlineSelection
        let wasRestoringExpansion = isRestoringSourceOutlineExpansion
        isSynchronizingSourceOutlineSelection = true
        isRestoringSourceOutlineExpansion = true
        defer {
            isSynchronizingSourceOutlineSelection = wasSynchronizingSelection
            isRestoringSourceOutlineExpansion = wasRestoringExpansion
        }
        if !includeTags {
            sourceTagNames = []
        }

        sourceOutlineItemsByIdentifier.removeAll(keepingCapacity: true)
        sourceOutlineItemsByScopeIdentifier.removeAll(keepingCapacity: true)
        var roots: [LibrarySourceOutlineItem] = []

        let previewFolders = externalPreviewFolderURLs()
        let iCloudGroup = makeSourceOutlineItem(
            identifier: "group:icloud",
            kind: .group(title: "iCloud", section: .folders)
        )
        iCloudGroup.append(makeSourceOutlineScopeItem(.all))
        for folderRoot in makeSourceFolderOutlineRoots() {
            iCloudGroup.append(folderRoot)
        }
        for previewFolder in previewFolders where !sourceFolderTreeRows.contains(where: {
            $0.url.standardizedFileURL.path == previewFolder.standardizedFileURL.path
        }) {
            iCloudGroup.append(makeSourceOutlineScopeItem(.folder(previewFolder)))
        }
        if inlineFolderEditOperation == nil {
            if !sourceFoldersLoaded && sourceFolderTreeRows.isEmpty {
                iCloudGroup.append(makeSourceOutlineItem(
                    identifier: "status:folders:loading",
                    kind: .status(LibraryCopy.loadingFolders)
                ))
            } else if sourceFolderTreeRows.isEmpty {
                iCloudGroup.append(makeSourceOutlineItem(
                    identifier: "status:folders:empty",
                    kind: .status(LibraryCopy.noFolders)
                ))
            }
        }
        iCloudGroup.append(makeSourceOutlineScopeItem(.trash))
        roots.append(iCloudGroup)

        let tagsGroup = makeSourceOutlineItem(
            identifier: "group:tags",
            kind: .group(title: LibraryCopy.tags, section: .tags)
        )
        for tag in sourceTagNames {
            tagsGroup.append(makeSourceOutlineScopeItem(.tag(tag)))
        }
        roots.append(tagsGroup)

        sourceOutlineRootItems = roots
        sourceOutlineView.reloadData()
        restoreSourceOutlineExpansion()
        if hasLoadedSourceCounts {
            refreshSourceCounts(using: sourceCountSnapshot)
        }
        refreshSourceSelection()
        focusInlineFolderEditField()
    }

    private func makeSourceOutlineItem(
        identifier: String,
        kind: LibrarySourceOutlineItem.Kind
    ) -> LibrarySourceOutlineItem {
        let item = LibrarySourceOutlineItem(identifier: identifier, kind: kind)
        sourceOutlineItemsByIdentifier[identifier] = item
        if let scope = item.scope {
            sourceOutlineItemsByScopeIdentifier[sourceOutlineIdentifier(for: scope)] = item
        }
        return item
    }

    private func makeSourceOutlineScopeItem(_ scope: LibraryScope) -> LibrarySourceOutlineItem {
        makeSourceOutlineItem(
            identifier: sourceOutlineIdentifier(for: scope),
            kind: .scope(scope)
        )
    }

    private func sourceOutlineIdentifier(for scope: LibraryScope) -> String {
        switch scope {
        case .all:
            return "scope:all"
        case .recent:
            return "scope:recent"
        case .inbox:
            return "scope:inbox"
        case .folder(let url):
            return "scope:folder:\(url.standardizedFileURL.path)"
        case .tag(let tag):
            return "scope:tag:\(tag.folding(options: [.caseInsensitive], locale: .current))"
        case .trash:
            return "scope:trash"
        }
    }

    private func makeSourceFolderOutlineRoots() -> [LibrarySourceOutlineItem] {
        var roots: [LibrarySourceOutlineItem] = []
        var ancestors: [LibrarySourceOutlineItem] = []

        for folderRow in sourceFolderTreeRows {
            while ancestors.count > folderRow.depth {
                ancestors.removeLast()
            }

            let folderPath = folderRow.url.standardizedFileURL.path
            let item: LibrarySourceOutlineItem
            if case .rename(let folderURL) = inlineFolderEditOperation,
               folderURL.standardizedFileURL.path == folderPath {
                item = makeSourceOutlineItem(
                    identifier: "inline:rename:\(folderPath)",
                    kind: .inlineFolderEdit(.rename(folderURL: folderRow.url))
                )
            } else {
                item = makeSourceOutlineScopeItem(.folder(folderRow.url))
            }

            if let parent = ancestors.last {
                parent.append(item)
            } else {
                roots.append(item)
            }
            ancestors.append(item)
        }

        if case .create(let parentURL) = inlineFolderEditOperation {
            let editItem = makeSourceOutlineItem(
                identifier: "inline:create:\(parentURL.standardizedFileURL.path)",
                kind: .inlineFolderEdit(.create(parentURL: parentURL))
            )
            if let parent = sourceOutlineItemsByScopeIdentifier[sourceOutlineIdentifier(for: .folder(parentURL))] {
                parent.children.insert(editItem, at: 0)
                editItem.parent = parent
            } else {
                roots.insert(editItem, at: 0)
            }
        }

        return roots
    }

    private func externalPreviewFolderURLs() -> [URL] {
        var seenPaths = Set<String>()
        return externallyOpenedDocumentsByPath.values
            .map { $0.url.deletingLastPathComponent().standardizedFileURL }
            .filter { seenPaths.insert($0.path).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func restoreSourceOutlineExpansion() {
        let wasRestoringExpansion = isRestoringSourceOutlineExpansion
        isRestoringSourceOutlineExpansion = true
        defer { isRestoringSourceOutlineExpansion = wasRestoringExpansion }
        if !sourceFoldersSectionCollapsed,
           let iCloudGroup = sourceOutlineItemsByIdentifier["group:icloud"] {
            sourceOutlineView.expandItem(iCloudGroup, expandChildren: false)
        }
        if !sourceTagsSectionCollapsed,
           let tagsGroup = sourceOutlineItemsByIdentifier["group:tags"] {
            sourceOutlineView.expandItem(tagsGroup, expandChildren: false)
        }
        for folderRow in sourceFolderTreeRows where folderRow.hasChildren {
            let path = folderRow.url.standardizedFileURL.path
            guard isSourceFolderExpanded(path: path, depth: folderRow.depth),
                  let item = sourceOutlineItemsByScopeIdentifier[
                    sourceOutlineIdentifier(for: .folder(folderRow.url))
                  ] ?? sourceOutlineItemsByIdentifier["inline:rename:\(path)"] else {
                continue
            }
            sourceOutlineView.expandItem(item, expandChildren: false)
        }
        if let editItem = sourceOutlineItemsByIdentifier.values.first(where: {
            if case .inlineFolderEdit = $0.kind { return true }
            return false
        }) {
            var parent = editItem.parent
            while let current = parent {
                sourceOutlineView.expandItem(current, expandChildren: false)
                parent = current.parent
            }
        }
    }

    private func isSourceSectionCollapsed(_ section: LibrarySourceSection) -> Bool {
        switch section {
        case .folders:
            return sourceFoldersSectionCollapsed
        case .tags:
            return sourceTagsSectionCollapsed
        }
    }

    private func scheduleDeferredSourceFolderLoad() {
        sourceFolderLoadGeneration += 1
        let generation = sourceFolderLoadGeneration
        guard !sourceFoldersSectionCollapsed,
              !sourceFoldersLoaded,
              !sourceFoldersLoading else { return }
        sourceFoldersLoading = true
        let preferredDirectories = noteStore.preferredDirectories
        let folderOrderPaths = noteStore.libraryFolderOrderPaths
        let collapsedPaths = collapsedFolderPaths
        let expandedPaths = expandedFolderPaths
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let treeRows = Self.folderTreeRowsForSourceList(
                from: preferredDirectories,
                orderedPaths: folderOrderPaths
            )
            let rows = Self.visibleFolderRowsForSourceList(
                from: treeRows,
                collapsedFolderPaths: collapsedPaths,
                expandedFolderPaths: expandedPaths
            )
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.sourceFolderLoadGeneration else {
                    self.sourceFoldersLoading = false
                    self.scheduleDeferredSourceFolderLoad()
                    return
                }
                self.sourceFoldersLoaded = true
                self.sourceFoldersLoading = false
                self.sourceFolderTreeRows = treeRows
                self.sourceFolderRows = rows
                self.rebuildSourceRows(includeTags: self.sourceTagsLoaded)
                self.reloadNotesForNavigation(selecting: self.selectedURL, loadFirstIfNeeded: false)
            }
        }
    }

    func loadSourceFoldersForLibrary() {
        reloadSourceFolderRowsForCurrentState()
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    private func scheduleDeferredSourceTagLoad() {
        guard !sourceTagsSectionCollapsed,
              !sourceTagsLoaded,
              !sourceTagsLoading else { return }
        sourceTagsLoading = true
        sourceTagLoadGeneration += 1
        let generation = sourceTagLoadGeneration
        let noteStore = noteStore
        let preferredDirectories = noteStore.preferredDirectories
        DispatchQueue.global(qos: .utility).async { [weak self] in
            noteStore.prewarmSearchIndex(roots: preferredDirectories)
            let tags = noteStore.knownTags(limit: 12, roots: preferredDirectories)
            DispatchQueue.main.async {
                guard let self,
                      generation == self.sourceTagLoadGeneration else { return }
                self.sourceTagsLoading = false
                self.applySourceTagsForLibrary(tags)
            }
        }
    }

    private func applyCachedSourceTags(from notes: [NoteSearchResult]) {
        let tags = Self.mostFrequentTags(in: notes, limit: 12)
        guard !tags.isEmpty else { return }
        sourceTagLoadGeneration += 1
        sourceTagsLoading = false
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
    }

    private func applySourceTagsFromValidatedSnapshot(_ notes: [NoteSearchResult]) {
        let tags = Self.mostFrequentTags(in: notes, limit: 12)
        guard tags != sourceTagNames || !sourceTagsLoaded else { return }
        sourceTagLoadGeneration += 1
        sourceTagsLoading = false
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
    }

    private static func mostFrequentTags(
        in notes: [NoteSearchResult],
        limit: Int
    ) -> [String] {
        var tagCounts: [String: (displayName: String, count: Int)] = [:]
        for tag in notes.flatMap(\.tags) {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive], locale: .current)
            let previous = tagCounts[key]
            tagCounts[key] = (previous?.displayName ?? trimmed, (previous?.count ?? 0) + 1)
        }
        return tagCounts.values
            .sorted {
                $0.count == $1.count
                    ? $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    : $0.count > $1.count
            }
            .prefix(limit)
            .map(\.displayName)
    }

    func loadSourceTagsForLibrary() {
        guard !sourceTagsLoaded, !sourceTagsLoading else { return }
        applySourceTagsForLibrary(noteStore.knownTags(limit: 12, roots: noteStore.preferredDirectories))
    }

    private func applySourceTagsForLibrary(_ tags: [String]) {
        guard !sourceTagsLoaded else { return }
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    private func invalidateSourceTagsForLibrary() {
        sourceTagLoadGeneration += 1
        sourceTagsLoaded = false
        sourceTagsLoading = false
        sourceTagNames = []
    }

    private func reloadSourceFolderRowsForCurrentState() {
        sourceFoldersLoaded = true
        sourceFoldersLoading = false
        applySourceFolderTreeRows(Self.folderTreeRowsForSourceList(
            from: noteStore.preferredDirectories,
            orderedPaths: noteStore.libraryFolderOrderPaths
        ))
    }

    private func applySourceFolderTreeRows(_ treeRows: [LibraryFolderRow]) {
        sourceFolderLoadGeneration += 1
        sourceFoldersLoaded = true
        sourceFoldersLoading = false
        sourceFolderTreeRows = treeRows
        sourceFolderRows = Self.visibleFolderRowsForSourceList(
            from: sourceFolderTreeRows,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
        rebuildSourceRows(includeTags: sourceTagsLoaded)
    }

    private func projectSourceFolderTreeRows(_ treeRows: [LibraryFolderRow]) {
        guard !sourceFoldersLoaded else {
            applySourceFolderTreeRows(treeRows)
            return
        }

        let wasLoading = sourceFoldersLoading
        sourceFolderLoadGeneration += 1
        sourceFolderTreeRows = treeRows
        sourceFolderRows = Self.visibleFolderRowsForSourceList(
            from: sourceFolderTreeRows,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        if !wasLoading {
            sourceFoldersLoading = false
            scheduleDeferredSourceFolderLoad()
        }
    }

    private func rootFolderRowsForSourceList() -> [LibraryFolderRow] {
        Self.rootFolderRowsForSourceList(
            from: noteStore.preferredDirectories,
            orderedPaths: noteStore.libraryFolderOrderPaths
        )
    }

    nonisolated private static func rootFolderRowsForSourceList(
        from directories: [URL],
        orderedPaths: [String] = []
    ) -> [LibraryFolderRow] {
        sortedFolderURLs(rootPreferredDirectories(from: directories), orderedPaths: orderedPaths).map {
            LibraryFolderRow(url: $0, depth: 0, hasChildren: false)
        }
    }

    nonisolated private static func folderTreeRowsForSourceList(
        from directories: [URL],
        orderedPaths: [String] = []
    ) -> [LibraryFolderRow] {
        let preferredRoots = sortedFolderURLs(
            rootPreferredDirectories(from: directories),
            orderedPaths: orderedPaths
        )
        var seenPaths = Set<String>()
        var rows: [LibraryFolderRow] = []

        for root in preferredRoots {
            appendFolderTreeRows(
                root,
                depth: 0,
                maxDepth: 3,
                orderedPaths: orderedPaths,
                seenPaths: &seenPaths,
                rows: &rows
            )
        }

        return rows
    }

    nonisolated private static func visibleFolderRowsForSourceList(
        from treeRows: [LibraryFolderRow],
        collapsedFolderPaths: Set<String>,
        expandedFolderPaths: Set<String>
    ) -> [LibraryFolderRow] {
        var hiddenDescendantDepth: Int?
        var visibleRows: [LibraryFolderRow] = []

        for row in treeRows {
            if let hiddenDepth = hiddenDescendantDepth {
                if row.depth > hiddenDepth {
                    continue
                }
                hiddenDescendantDepth = nil
            }

            visibleRows.append(row)
            if !isSourceFolderExpanded(
                path: row.url.standardizedFileURL.path,
                depth: row.depth,
                collapsedFolderPaths: collapsedFolderPaths,
                expandedFolderPaths: expandedFolderPaths
            ) {
                hiddenDescendantDepth = row.depth
            }
        }

        return visibleRows
    }

    nonisolated private static func rootPreferredDirectories(from directories: [URL]) -> [URL] {
        let standardized = directories.map(\.standardizedFileURL)
        return standardized.filter { candidate in
            !standardized.contains { other in
                other != candidate && candidate.path.hasPrefix(other.path + "/")
            }
        }
    }

    nonisolated private static func appendFolderTreeRows(
        _ folderURL: URL,
        depth: Int,
        maxDepth: Int,
        orderedPaths: [String],
        seenPaths: inout Set<String>,
        rows: inout [LibraryFolderRow]
    ) {
        let standardized = folderURL.standardizedFileURL
        guard seenPaths.insert(standardized.path).inserted else { return }
        let children = sortedFolderURLs(childFolderURLs(of: standardized), orderedPaths: orderedPaths)
        rows.append(LibraryFolderRow(url: standardized, depth: depth, hasChildren: !children.isEmpty))
        guard depth < maxDepth else { return }

        for child in children {
            appendFolderTreeRows(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                orderedPaths: orderedPaths,
                seenPaths: &seenPaths,
                rows: &rows
            )
        }
    }

    nonisolated private static func sortedFolderURLs(_ urls: [URL], orderedPaths: [String]) -> [URL] {
        let ranks = Dictionary(uniqueKeysWithValues: orderedPaths.enumerated().map { ($0.element, $0.offset) })
        return urls.sorted { lhs, rhs in
            let lhsRank = ranks[lhs.standardizedFileURL.path]
            let rhsRank = ranks[rhs.standardizedFileURL.path]
            if let lhsRank, let rhsRank, lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhsRank != nil { return true }
            if rhsRank != nil { return false }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
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
            return values.isDirectory == true
                && values.isHidden != true
                && url.lastPathComponent.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) != .orderedSame
        }
        .sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func sourceTitle(for scope: LibraryScope) -> String {
        switch scope {
        case .folder(let url):
            return folderTitle(for: url)
        default:
            return scope.buttonTitle
        }
    }

    private func noteListTitle(for scope: LibraryScope) -> String {
        switch scope {
        case .tag(let tag):
            return libraryDisplayTag(tag)
        default:
            return sourceTitle(for: scope)
        }
    }

    private func folderTitle(for url: URL) -> String {
        let standardizedURL = url.standardizedFileURL
        return standardizedURL.lastPathComponent.isEmpty ? LibraryCopy.notes : standardizedURL.lastPathComponent
    }

    private func refreshSourceSelection() {
        guard let item = sourceOutlineItemsByScopeIdentifier[sourceOutlineIdentifier(for: selectedScope)] else {
            return
        }
        let row = sourceOutlineView.row(forItem: item)
        guard row >= 0 else { return }
        let wasSynchronizingSelection = isSynchronizingSourceOutlineSelection
        isSynchronizingSourceOutlineSelection = true
        sourceOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isSynchronizingSourceOutlineSelection = wasSynchronizingSelection
        refreshVisibleSourceOutlinePresentation()
    }

    private func refreshVisibleSourceOutlinePresentation() {
        let visibleRows = sourceOutlineView.rows(in: sourceOutlineView.visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
            guard let item = sourceOutlineView.item(atRow: row) as? LibrarySourceOutlineItem,
                  let cell = sourceOutlineView.view(
                    atColumn: 0,
                    row: row,
                    makeIfNecessary: false
                  ) as? LibrarySourceOutlineCellView else {
                continue
            }
            configureSourceOutlineCell(cell, for: item)
        }
    }

    func sourceTitlesForLibrary() -> [String] {
        sourceOutlineItemsByScopeIdentifier.values.compactMap { item in
            item.scope.map(sourceTitle(for:))
        }
    }

    func sourceIconNameForLibrary(titled title: String) -> String? {
        guard let scope = sourceOutlineItemsByScopeIdentifier.values.compactMap(\.scope).first(where: {
            sourceTitle(for: $0).localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else {
            return nil
        }
        return sourceSymbolName(for: scope)
    }

    var selectedSourceTitleForLibrary: String {
        sourceTitle(for: selectedScope)
    }

    func visibleSourceTitlesForLibrary() -> [String] {
        (0..<sourceOutlineView.numberOfRows).compactMap { row in
            guard let item = sourceOutlineView.item(atRow: row) as? LibrarySourceOutlineItem,
                  let scope = item.scope else { return nil }
            return sourceTitle(for: scope)
        }
    }

    func sourceFolderURLsForLibrary() -> [URL] {
        var seenPaths = Set<String>()
        return (sourceFolderTreeRows.map(\.url) + externalPreviewFolderURLs()).filter {
            seenPaths.insert($0.standardizedFileURL.path).inserted
        }
    }

    var editorSlashSuggestionTitlesForLibrary: [String] {
        if let editorNoteSuggestion {
            return editorNoteSuggestion.items.map(\.title)
        }
        return editorSlashSuggestion?.commands.map(\.title) ?? []
    }

    func waitForEditorNoteSuggestionsForTesting() async {
        await editorNoteSuggestionTask?.value
    }

    func acceptEditorSlashSuggestionForLibrary(at index: Int) {
        acceptEditorSlashSuggestion(at: index)
    }

    @discardableResult
    func importExternalLibraryItemForTesting(_ sourceURL: URL, to targetDirectory: URL) throws -> URL {
        try importExternalLibraryItem(sourceURL, to: targetDirectory)
    }

    @discardableResult
    func selectSourceForLibrary(titled title: String) -> Bool {
        guard let item = sourceOutlineItemsByScopeIdentifier.values.first(where: {
            guard let scope = $0.scope else { return false }
            return sourceTitle(for: scope).localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else { return false }
        var parent = item.parent
        while let current = parent {
            sourceOutlineView.expandItem(current, expandChildren: false)
            parent = current.parent
        }
        let row = sourceOutlineView.row(forItem: item)
        guard row >= 0 else { return false }
        let scope = item.scope
        let previousScope = selectedScope
        sourceOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if let scope, selectedScope != scope || selectedScope == previousScope {
            guard activateSourceScope(scope) else { return false }
        }
        sourceOutlineView.scrollRowToVisible(row)
        sourceOutlineView.window?.makeFirstResponder(sourceOutlineView)
        return true
    }

    @discardableResult
    func setSourceFolderExpandedForLibrary(_ folderURL: URL, expanded: Bool) -> Bool {
        guard let item = sourceOutlineItemsByScopeIdentifier[
            sourceOutlineIdentifier(for: .folder(folderURL))
        ], !item.children.isEmpty else { return false }
        if expanded {
            sourceOutlineView.expandItem(item, expandChildren: false)
        } else {
            sourceOutlineView.collapseItem(item, collapseChildren: true)
        }
        return true
    }

    func isSourceFolderExpandedForLibrary(_ folderURL: URL) -> Bool {
        guard let item = sourceOutlineItemsByScopeIdentifier[
            sourceOutlineIdentifier(for: .folder(folderURL))
        ] else { return false }
        return sourceOutlineView.isItemExpanded(item)
    }

    func sourceCountTextForLibrary(titled title: String) -> String? {
        guard let item = sourceOutlineItemsByScopeIdentifier.values.first(where: {
            guard let scope = $0.scope else { return false }
            return sourceTitle(for: scope).localizedCaseInsensitiveCompare(title) == .orderedSame
        }), let scope = item.scope else { return nil }
        return sourceCountText(item.count, for: scope)
    }

    func toggleSourceTagsSectionForLibrary() {
        toggleSourceSection(.tags)
    }

    func toggleSourceFoldersSectionForLibrary() {
        toggleSourceSection(.folders)
    }

    func sourceOutlineLevelForLibrary(titled title: String) -> Int? {
        guard let item = sourceOutlineItemsByScopeIdentifier.values.first(where: {
            guard let scope = $0.scope else { return false }
            return sourceTitle(for: scope).localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else { return nil }
        var level = 0
        var parent = item.parent
        while parent != nil {
            level += 1
            parent = parent?.parent
        }
        return level
    }

    func isSourceGroupExpandedForLibrary(titled title: String) -> Bool? {
        guard let item = sourceOutlineItemsByIdentifier.values.first(where: {
            guard case .group(let groupTitle, _) = $0.kind else { return false }
            return groupTitle.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else { return nil }
        return sourceOutlineView.isItemExpanded(item)
    }

    var sourceOutlineInstantiatedCellCountForLibrary: Int {
        let visibleRows = sourceOutlineView.rows(in: sourceOutlineView.visibleRect)
        guard visibleRows.location != NSNotFound else { return 0 }
        return (visibleRows.location..<(visibleRows.location + visibleRows.length)).reduce(into: 0) {
            count, row in
            if sourceOutlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                is LibrarySourceOutlineCellView {
                count += 1
            }
        }
    }

    private func currentSourceFolderPaths() -> Set<String> {
        Set(
            sourceFolderRows.map { $0.url.standardizedFileURL.path }
                + externalPreviewFolderURLs().map(\.path)
        )
    }

    private func inboxDirectoryForCurrentSourceSnapshot() -> URL {
        if let sourceInboxDirectory {
            return sourceInboxDirectory
        }
        let candidates = noteStore.preferredDirectories + sourceFolderTreeRows.map(\.url)
        if let inbox = candidates.enumerated().min(by: { lhs, rhs in
            let lhsRank = Self.inboxDirectoryRank(lhs.element.lastPathComponent)
            let rhsRank = Self.inboxDirectoryRank(rhs.element.lastPathComponent)
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }), Self.inboxDirectoryRank(inbox.element.lastPathComponent) < Int.max {
            return inbox.element.standardizedFileURL
        }
        return noteStore.notesDirectory
            .appendingPathComponent("Inbox", isDirectory: true)
            .standardizedFileURL
    }

    nonisolated private static func inboxDirectoryRank(_ name: String) -> Int {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "inbox" { return 0 }
        if normalized.hasSuffix("-inbox")
            || normalized.hasSuffix("_inbox")
            || normalized.hasSuffix(" inbox") {
            return 1
        }
        return Int.max
    }

    private func refreshSourceCounts(
        using allNotes: [NoteSearchResult],
        countIndex precomputedCountIndex: LibrarySourceCountIndex? = nil,
        recentCount precomputedRecentCount: Int? = nil
    ) {
        let recentCount = precomputedRecentCount ?? recentFilesVisibleInLibrary(limit: 80).count
        let countIndex = precomputedCountIndex ?? LibrarySourceCountIndex(
            notes: allNotes,
            folderPaths: currentSourceFolderPaths(),
            inboxDirectory: inboxDirectoryForCurrentSourceSnapshot()
        )
        applySourceCounts(
            allNotesCount: allNotes.count,
            recentCount: recentCount,
            trashCount: trashedNotesSnapshot.count,
            countIndex: countIndex
        )
    }

    private func scheduleSourceCountRefresh(using allNotes: [NoteSearchResult]) {
        sourceCountRefreshTask?.cancel()
        sourceCountRefreshGeneration += 1
        let generation = sourceCountRefreshGeneration
        let folderPaths = currentSourceFolderPaths()
        let trashCount = trashedNotesSnapshot.count
        let noteStore = noteStore
        let preferredDirectories = noteStore.preferredDirectories
        let externalDocumentPaths = Set(externallyOpenedDocumentsByPath.keys)
        let willLoad = backgroundSourceCountWillLoad

        sourceCountRefreshTask = Task.detached(priority: .utility) { [weak self] in
            willLoad()
            let inboxDirectory = noteStore.preferredInboxDirectory
            let recentCount = Self.recentFilesVisibleInLibrary(
                noteStore: noteStore,
                preferredDirectories: preferredDirectories,
                externalDocumentPaths: externalDocumentPaths,
                limit: 80
            ).count
            let countIndex = LibrarySourceCountIndex(
                notes: allNotes,
                folderPaths: folderPaths,
                inboxDirectory: inboxDirectory
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      generation == self.sourceCountRefreshGeneration,
                      folderPaths == self.currentSourceFolderPaths() else { return }
                self.sourceCountRefreshTask = nil
                self.sourceInboxDirectory = inboxDirectory
                self.applySourceCounts(
                    allNotesCount: allNotes.count,
                    recentCount: recentCount,
                    trashCount: trashCount,
                    countIndex: countIndex
                )
            }
        }
    }

    private func applySourceCounts(
        allNotesCount: Int,
        recentCount: Int,
        trashCount: Int,
        countIndex: LibrarySourceCountIndex
    ) {
        hasLoadedSourceCounts = true
        for item in sourceOutlineItemsByScopeIdentifier.values {
            guard let scope = item.scope else { continue }
            let count: Int
            switch scope {
            case .all:
                count = allNotesCount
            case .recent:
                count = recentCount
            case .inbox:
                count = countIndex.inboxCount
            case .trash:
                count = trashCount
            case .folder(let url):
                count = countIndex.count(
                    forFolder: url,
                    includingDescendants: noteStore.libraryIncludesSubfolderNotes
                )
            case .tag(let tag):
                count = countIndex.count(forTag: tag)
            }
            item.count = count
        }
        refreshVisibleSourceOutlinePresentation()
    }

    private func sourceCountText(_ count: Int?, for scope: LibraryScope) -> String {
        guard let count else { return "" }
        switch scope {
        case .folder:
            return String(count)
        default:
            return count > 0 ? String(count) : ""
        }
    }

    private func reloadNotes(
        selecting preferredURL: URL? = nil,
        loadFirstIfNeeded: Bool,
        allNotesSnapshot: [NoteSearchResult]? = nil,
        sourceCountIndex: LibrarySourceCountIndex? = nil,
        sourceRecentCount: Int? = nil,
        refreshCounts: Bool = true,
        mutationAnimation: LibraryNoteMutationAnimation? = nil
    ) {
        cancelSourceSnapshotValidation()
        cancelActiveSearchResultReload()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allNotes = allNotesSnapshot ?? sourceCountSnapshot
        searchScopeControl.isHidden = query.isEmpty
        let previousRows = listRows
        notes = query.isEmpty
            ? notesForSelectedScope(limit: 240, allNotes: allNotes)
            : searchResultsForSelectedScope(query: query, limit: 240)
        listRows = buildGroupedRows(for: notes, preservesInputOrder: !query.isEmpty)
        updateNoteListHeader(query: query)

        suppressSelectionChanges = true
        reloadNoteBrowserData(animation: mutationAnimation, previousRows: previousRows)
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
        synchronizeGallerySelectionFromTable()
        stabilizeVisualQASelectionIfNeeded()

        if loadFirstIfNeeded, let noteToLoad {
            load(note: noteToLoad)
        }
        if refreshCounts {
            sourceCountSnapshot = allNotes
            refreshSourceCounts(
                using: allNotes,
                countIndex: sourceCountIndex,
                recentCount: sourceRecentCount
            )
        }
        refreshSourceSelection()
        updateToolbarActionState()
    }

    private func reloadNotesForNavigation(
        selecting preferredURL: URL? = nil,
        loadFirstIfNeeded: Bool
    ) {
        reloadNotes(
            selecting: preferredURL,
            loadFirstIfNeeded: loadFirstIfNeeded,
            refreshCounts: false
        )
    }

    private func scheduleSourceSnapshotValidation(loadFirstIfNeeded: Bool) {
        sourceSnapshotValidationTask?.cancel()
        sourceSnapshotValidationGeneration += 1
        let generation = sourceSnapshotValidationGeneration
        let scope = selectedScope
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteStore = noteStore
        let snapshotLimit = Self.sourceCountSnapshotLimit
        let preferredDirectories = noteStore.preferredDirectories
        let sourceFolderPaths = currentSourceFolderPaths()
        let externalDocumentPaths = Set(externallyOpenedDocumentsByPath.keys)

        sourceSnapshotValidationTask = Task.detached(priority: .userInitiated) { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let inboxDirectory = noteStore.preferredInboxDirectory
            let recentCount = Self.recentFilesVisibleInLibrary(
                noteStore: noteStore,
                preferredDirectories: preferredDirectories,
                externalDocumentPaths: externalDocumentPaths,
                limit: 80
            ).count
            let allNotes = noteStore.listNotesRefreshingIndex(
                limit: snapshotLimit,
                roots: preferredDirectories
            )
            guard !Task.isCancelled else { return }
            let trashedNotes = noteStore.listTrashedNotes(limit: snapshotLimit)
            guard !Task.isCancelled else { return }
            let countIndex = LibrarySourceCountIndex(
                notes: allNotes,
                folderPaths: sourceFolderPaths,
                inboxDirectory: inboxDirectory
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      generation == self.sourceSnapshotValidationGeneration,
                      scope == self.selectedScope,
                      query == self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return
                }

                self.sourceSnapshotValidationTask = nil
                self.sourceInboxDirectory = inboxDirectory
                let mergedAllNotes = self.includingExternallyOpenedDocuments(in: allNotes)
                let reusableCountIndex = self.currentSourceFolderPaths() == sourceFolderPaths
                    ? countIndex
                    : nil
                let trashChanged = trashedNotes != self.trashedNotesSnapshot
                self.trashedNotesSnapshot = trashedNotes
                guard mergedAllNotes != self.sourceCountSnapshot || trashChanged else {
                    self.refreshSourceCounts(
                        using: mergedAllNotes,
                        countIndex: reusableCountIndex,
                        recentCount: recentCount
                    )
                    return
                }

                let selectedURL = self.selectedURL
                let selectedPath = selectedURL?.standardizedFileURL.path
                let nextNotes = self.notesForSelectedScope(limit: 240, allNotes: mergedAllNotes)
                let selectionStillExists = selectedPath.map { path in
                    nextNotes.contains { $0.url.standardizedFileURL.path == path }
                } ?? false
                self.reloadNotes(
                    selecting: selectionStillExists ? selectedURL : nil,
                    loadFirstIfNeeded: loadFirstIfNeeded && !selectionStillExists,
                    allNotesSnapshot: mergedAllNotes,
                    sourceCountIndex: reusableCountIndex,
                    sourceRecentCount: recentCount
                )
            }
        }
    }

    private func cancelSourceSnapshotValidation() {
        sourceSnapshotValidationTask?.cancel()
        sourceSnapshotValidationTask = nil
        sourceSnapshotValidationGeneration += 1
    }

    private func updateNoteListHeader(query: String) {
        let title = query.isEmpty
            ? noteListTitle(for: selectedScope)
            : (searchScopeControl.selectedSegment == 1 ? noteListTitle(for: .all) : noteListTitle(for: selectedScope))
        noteListTitleLabel.stringValue = title
        if query.isEmpty {
            noteListCountLabel.stringValue = notesCountText(notes.count)
        } else if hasPendingSearchReload || isSearchResultReloading {
            noteListCountLabel.stringValue = LibraryCopy.searching
        } else {
            noteListCountLabel.stringValue = resultsCountText(notes.count)
        }
    }

    private func updateNoteListEmptyState(query: String) {
        let isEmpty = listRows.isEmpty
        noteListEmptyLabel.isHidden = !isEmpty
        galleryEmptyLabel.isHidden = !isEmpty || noteListViewMode != .gallery
        guard isEmpty else { return }

        let message: String
        if !query.isEmpty, hasPendingSearchReload || isSearchResultReloading {
            message = LibraryCopy.searching
        } else if !query.isEmpty {
            message = LibraryCopy.noResults
        } else if selectedScope == .trash {
            message = LibraryCopy.recentlyDeletedIsEmpty
        } else {
            message = LibraryCopy.noNotes
        }
        noteListEmptyLabel.stringValue = message
        galleryEmptyLabel.stringValue = message
    }

    private func notesForSelectedScope(limit: Int, allNotes: [NoteSearchResult]) -> [NoteSearchResult] {
        guard noteListSortOrder != .dateEdited else {
            return notesForSelectedScopeByModifiedDate(limit: limit, allNotes: allNotes)
        }

        let candidates: [NoteSearchResult]
        let predicate: (NoteSearchResult) -> Bool
        switch selectedScope {
        case .all:
            candidates = allNotes
            predicate = { _ in true }
        case .recent:
            candidates = recentNoteResults(limit: 80, allNotes: allNotes)
            predicate = { _ in true }
        case .inbox:
            candidates = allNotes
            let inboxDirectory = inboxDirectoryForCurrentSourceSnapshot()
            predicate = { libraryIsInboxNote($0, inboxDirectory: inboxDirectory) }
        case .trash:
            candidates = trashedNotesSnapshot
            predicate = { _ in true }
        case .folder(let url):
            candidates = allNotes
            predicate = { note in
                libraryNote(
                    note,
                    isIn: url,
                    includingDescendants: self.noteStore.libraryIncludesSubfolderNotes
                )
            }
        case .tag(let tag):
            candidates = allNotes
            predicate = { note in
                note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }

        return LibraryNoteListProjection.rankedPrefix(
            candidates,
            limit: limit,
            sortOrder: noteListSortOrder,
            groupsByDate: groupsNoteListByDate,
            includesPinnedGroup: selectedScope != .trash,
            pinnedPaths: Set(noteStore.libraryPinnedNotePaths),
            where: predicate
        )
    }

    private func notesForSelectedScopeByModifiedDate(
        limit: Int,
        allNotes: [NoteSearchResult]
    ) -> [NoteSearchResult] {
        switch selectedScope {
        case .all:
            return Array(allNotes.prefix(limit))
        case .recent:
            return recentNoteResults(limit: min(limit, 80), allNotes: allNotes)
        case .inbox:
            let inboxDirectory = inboxDirectoryForCurrentSourceSnapshot()
            return LibraryNoteListProjection.prefix(allNotes, limit: limit) { note in
                libraryIsInboxNote(note, inboxDirectory: inboxDirectory)
            }
        case .trash:
            return Array(trashedNotesSnapshot.prefix(limit))
        case .folder(let url):
            return LibraryNoteListProjection.prefix(allNotes, limit: limit) { note in
                libraryNote(
                    note,
                    isIn: url,
                    includingDescendants: self.noteStore.libraryIncludesSubfolderNotes
                )
            }
        case .tag(let tag):
            return LibraryNoteListProjection.prefix(allNotes, limit: limit) { note in
                note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }
    }

    private func searchResultsForSelectedScope(query: String, limit: Int) -> [NoteSearchResult] {
        if selectedScope == .trash, searchScopeControl.selectedSegment != 1 {
            return cachedTrashSearchResults(query: query, limit: limit)
        }
        return searchResults(
            for: selectedScope,
            query: query,
            limit: limit,
            searchesAllNotes: searchScopeControl.selectedSegment == 1
        ).filter {
            !pendingDeletionPaths.contains($0.url.standardizedFileURL.path)
        }
    }

    private func cachedTrashSearchResults(query: String, limit: Int) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return Array(trashedNotesSnapshot.prefix(limit)) }
        return Array(trashedNotesSnapshot.lazy.filter { note in
            note.title.localizedCaseInsensitiveContains(trimmedQuery)
                || note.snippet.localizedCaseInsensitiveContains(trimmedQuery)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }.prefix(limit))
    }

    private func cachedSearchResultsForSelectedScope(query: String, limit: Int) -> [NoteSearchResult] {
        if selectedScope == .trash, searchScopeControl.selectedSegment != 1 {
            return cachedTrashSearchResults(query: query, limit: limit)
        }

        let candidates: [NoteSearchResult]
        if searchScopeControl.selectedSegment == 1 {
            candidates = sourceCountSnapshot
        } else {
            switch selectedScope {
            case .all:
                candidates = sourceCountSnapshot
            case .recent:
                candidates = recentNoteResults(limit: 80, allNotes: sourceCountSnapshot)
            case .inbox:
                let inboxDirectory = inboxDirectoryForCurrentSourceSnapshot()
                candidates = sourceCountSnapshot.filter {
                    libraryIsInboxNote($0, inboxDirectory: inboxDirectory)
                }
            case .trash:
                candidates = trashedNotesSnapshot
            case .folder(let folderURL):
                candidates = sourceCountSnapshot.filter { note in
                    libraryNote(
                        note,
                        isIn: folderURL,
                        includingDescendants: self.noteStore.libraryIncludesSubfolderNotes
                    )
                }
            case .tag(let tag):
                candidates = sourceCountSnapshot.filter { note in
                    note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                }
            }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(candidates.lazy.filter { note in
            note.title.localizedCaseInsensitiveContains(trimmedQuery)
                || note.snippet.localizedCaseInsensitiveContains(trimmedQuery)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }.prefix(limit))
    }

    private func searchResults(
        for scope: LibraryScope,
        query: String,
        limit: Int,
        searchesAllNotes: Bool
    ) -> [NoteSearchResult] {
        let searchSession = activeSearchSession
            ?? noteStore.makeSearchSession(roots: noteStore.preferredDirectories)
        activeSearchSession = searchSession
        return librarySearchResults(
            noteStore: noteStore,
            searchSession: searchSession,
            scope: scope,
            query: query,
            limit: limit,
            searchesAllNotes: searchesAllNotes,
            includesSubfolderNotes: noteStore.libraryIncludesSubfolderNotes
        )
    }

    private func allNoteResults(limit: Int) -> [NoteSearchResult] {
        noteStore.listNotes(limit: limit, roots: noteStore.preferredDirectories)
    }

    private func recentShellNoteResults(limit: Int) -> [NoteSearchResult] {
        var results = recentFilesVisibleInLibrary(limit: limit).map { note in
            NoteSearchResult(
                url: note.url,
                title: note.title,
                snippet: "",
                modifiedAt: note.modifiedAt,
                tags: [],
                hasAttachments: false,
                thumbnailURL: nil
            )
        }
        if let cached = noteStore.cachedLibraryLaunchNote(),
           noteStore.preferredDirectories.contains(where: {
               let rootPath = $0.standardizedFileURL.path
               let notePath = cached.url.standardizedFileURL.path
               return notePath.hasPrefix(rootPath + "/")
           }),
           !results.contains(where: {
               $0.url.standardizedFileURL.path == cached.url.standardizedFileURL.path
           }) {
            results.insert(
                NoteSearchResult(
                    url: cached.url,
                    title: cached.document.title,
                    snippet: "",
                    modifiedAt: cached.modifiedAt,
                    tags: cached.document.tags,
                    hasAttachments: MarkdownEditorDocument.containsAttachmentReference(
                        in: cached.document.body
                    ),
                    thumbnailURL: nil
                ),
                at: 0
            )
            if results.count > limit {
                results.removeLast(results.count - limit)
            }
        }
        return results
    }

    private func recentNoteResults(limit: Int, allNotes: [NoteSearchResult]) -> [NoteSearchResult] {
        let resultsByPath = Dictionary(uniqueKeysWithValues: allNotes.map {
            ($0.url.standardizedFileURL.path, $0)
        })
        return recentFilesVisibleInLibrary(limit: limit).map { note in
            resultsByPath[note.url.standardizedFileURL.path] ?? NoteSearchResult(
                url: note.url,
                title: note.title,
                snippet: "",
                modifiedAt: note.modifiedAt,
                tags: [],
                hasAttachments: false,
                thumbnailURL: nil
            )
        }
    }

    private func recentFilesVisibleInLibrary(limit: Int) -> [NoteFile] {
        Self.recentFilesVisibleInLibrary(
            noteStore: noteStore,
            preferredDirectories: noteStore.preferredDirectories,
            externalDocumentPaths: Set(externallyOpenedDocumentsByPath.keys),
            limit: limit
        )
    }

    nonisolated private static func recentFilesVisibleInLibrary(
        noteStore: NoteStore,
        preferredDirectories: [URL],
        externalDocumentPaths: Set<String>,
        limit: Int
    ) -> [NoteFile] {
        Array(noteStore.listRecentFiles(limit: .max).lazy.filter { note in
            let path = note.url.standardizedFileURL.path
            let isInsideLibrary = preferredDirectories.contains { rootURL in
                let rootPath = rootURL.standardizedFileURL.path
                guard path.hasPrefix(rootPath + "/") else { return false }
                let relativePath = String(path.dropFirst(rootPath.count + 1))
                return !relativePath.split(separator: "/").contains {
                    $0.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) == .orderedSame
                }
            }
            return isInsideLibrary || externalDocumentPaths.contains(path)
        }.prefix(limit))
    }

    private func includingExternallyOpenedDocuments(in notes: [NoteSearchResult]) -> [NoteSearchResult] {
        externallyOpenedDocumentsByPath = externallyOpenedDocumentsByPath.filter {
            FileManager.default.fileExists(atPath: $0.key)
        }
        var merged = notes
        for note in externallyOpenedDocumentsByPath.values {
            LibraryNoteListProjection.upsertByModifiedDate(
                note,
                into: &merged,
                replacingPaths: Set([note.url.standardizedFileURL.path]),
                limit: Self.sourceCountSnapshotLimit
            )
        }
        return merged
    }

    private func buildGroupedRows(
        for notes: [NoteSearchResult],
        now: Date = Date(),
        preservesInputOrder: Bool = false
    ) -> [LibraryNoteListRow] {
        LibraryNoteListProjection.rows(
            for: notes,
            sortOrder: noteListSortOrder,
            groupsByDate: groupsNoteListByDate,
            includesPinnedGroup: selectedScope != .trash,
            pinnedPaths: Set(noteStore.libraryPinnedNotePaths),
            now: now,
            preservesInputOrder: preservesInputOrder
        )
    }

    @discardableResult
    func togglePinnedStateForSelectedNotesForLibrary() -> Bool {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard selectedScope != .trash, !urls.isEmpty else { return false }
        let shouldPin = !urls.allSatisfy { noteStore.isLibraryNotePinned(at: $0) }
        urls.forEach { noteStore.setLibraryNotePinned(shouldPin, at: $0) }
        rebuildNoteListRowsForDisplayOptions()
        return shouldPin
    }

    private func rebuildNoteListRowsForDisplayOptions(
        mutationAnimation: LibraryNoteMutationAnimation? = nil,
        refreshedNotePaths: Set<String> = []
    ) {
        let selectedPaths = Set(selectedMarkdownFileURLsForLibrary().map { $0.standardizedFileURL.path })
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousRows = listRows
        if query.isEmpty {
            notes = notesForSelectedScope(limit: 240, allNotes: sourceCountSnapshot)
        }
        listRows = buildGroupedRows(for: notes, preservesInputOrder: !query.isEmpty)

        suppressSelectionChanges = true
        reloadNoteBrowserData(
            animation: mutationAnimation,
            previousRows: previousRows,
            refreshedNotePaths: refreshedNotePaths
        )
        let selectedRows = IndexSet(listRows.indices.filter { row in
            guard let note = listRows[row].note else { return false }
            return selectedPaths.contains(note.url.standardizedFileURL.path)
        })
        tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
        updateNoteListEmptyState(query: query)
        updateToolbarActionState()
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

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard outlineView === sourceOutlineView else { return 0 }
        if let item = item as? LibrarySourceOutlineItem {
            return item.children.count
        }
        return sourceOutlineRootItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? LibrarySourceOutlineItem {
            return item.children[index]
        }
        return sourceOutlineRootItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return false }
        return !item.children.isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return nil }

        switch item.kind {
        case .group(let title, let section):
            let identifier = NSUserInterfaceItemIdentifier(
                section == .tags ? "LibrarySourceGroup-Tags" : "LibrarySourceGroup-iCloud"
            )
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
                ?? NSTableCellView()
            cell.identifier = identifier
            let label = cell.textField ?? NSTextField(labelWithString: "")
            if label.superview == nil {
                cell.textField = label
                cell.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(
                        equalTo: cell.leadingAnchor,
                        constant: LibraryNotesLayout.sourceGroupContentLeadingInset
                            + (section == .tags ? 0 : 4)
                    ),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            label.stringValue = title
            label.identifier = identifier
            label.font = .systemFont(ofSize: LibraryNotesLayout.sourceGroupFontSize, weight: .semibold)
            label.textColor = panelTertiaryTextColor()
            return cell
        case .status(let message):
            let identifier = NSUserInterfaceItemIdentifier("LibrarySourceStatusCell")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
                ?? NSTableCellView()
            cell.identifier = identifier
            let label = cell.textField ?? NSTextField(labelWithString: "")
            if label.superview == nil {
                cell.textField = label
                cell.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            label.identifier = NSUserInterfaceItemIdentifier(
                item.identifier.contains("folders") ? "LibrarySourceFolderStatus" : "LibrarySourceTagStatus"
            )
            label.stringValue = message
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = panelTertiaryTextColor().withAlphaComponent(0.82)
            return cell
        case .inlineFolderEdit(let operation):
            return makeSourceOutlineInlineEditCell(for: operation, item: item)
        case .scope:
            let identifier = NSUserInterfaceItemIdentifier("LibrarySourceOutlineCell")
            let cell: LibrarySourceOutlineCellView
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: nil)
                as? LibrarySourceOutlineCellView {
                cell = reused
            } else {
                cell = LibrarySourceOutlineCellView()
                cell.identifier = identifier
            }
            configureSourceOutlineCell(cell, for: item)
            return cell
        }
    }

    private func configureSourceOutlineCell(
        _ cell: LibrarySourceOutlineCellView,
        for item: LibrarySourceOutlineItem
    ) {
        guard let scope = item.scope else { return }
        let themeColor = selectedThemeColor
        let title = sourceTitle(for: scope)
        let row = sourceOutlineView.row(forItem: item)
        let isSelected = isSourceOutlineItemVisuallySelected(item)
        let legacyTag = sourceLegacyTag(for: scope)
        cell.identifier = NSUserInterfaceItemIdentifier("LibrarySourceRow-\(legacyTag)")
        cell.textField?.identifier = NSUserInterfaceItemIdentifier("LibrarySourceLabel-\(legacyTag)")
        cell.countLabel.identifier = NSUserInterfaceItemIdentifier("LibrarySourceCount-\(legacyTag)")
        cell.textField?.stringValue = title
        cell.textField?.font = .systemFont(
            ofSize: LibraryNotesLayout.sourceButtonFontSize,
            weight: isSelected
                ? LibraryNotesLayout.sourceSelectedButtonFontWeight
                : LibraryNotesLayout.sourceUnselectedButtonFontWeight
        )
        cell.textField?.textColor = isSelected
            ? themeColor.foregroundColor
            : LibrarySourceSelectionPalette.unselectedForegroundColor
        let foregroundColor = isSelected
            ? themeColor.foregroundColor
            : LibrarySourceSelectionPalette.unselectedForegroundColor
        let sourceImageConfiguration = NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.sourceSymbolPointSize,
            weight: LibraryNotesLayout.sourceSymbolWeight
        ).applying(NSImage.SymbolConfiguration(paletteColors: [foregroundColor]))
        let sourceImage = NSImage(
            systemSymbolName: sourceSymbolName(for: scope),
            accessibilityDescription: title
        )?.withSymbolConfiguration(sourceImageConfiguration)
        sourceImage?.isTemplate = false
        cell.imageView?.image = sourceImage
        cell.imageView?.contentTintColor = nil
        cell.imageView?.needsDisplay = true
        cell.needsDisplay = true
        cell.countLabel.stringValue = sourceCountText(item.count, for: scope)
        cell.countLabel.textColor = isSelected
            ? LibrarySourceSelectionPalette.selectedCountColor
            : panelTertiaryTextColor()
        (sourceOutlineView.rowView(
            atRow: row,
            makeIfNecessary: false
        ) as? LibrarySourceOutlineRowView)?.setVisuallySelected(isSelected)
        cell.accessibilityPressHandler = { [weak self] in
            self?.activateSourceScope(scope) ?? false
        }
        cell.setAccessibilityLabel(title)
        cell.setAccessibilityValue(
            item.count.map { "\($0) 条笔记" } ?? "正在载入笔记数量"
        )
    }

    private func isSourceOutlineItemVisuallySelected(_ item: LibrarySourceOutlineItem) -> Bool {
        guard let scope = item.scope else { return false }
        if sourceOutlineView.isDeferringPrimaryMouseSelectionCommit {
            return selectedScope == scope
        }
        let row = sourceOutlineView.row(forItem: item)
        let visualSelectionRow = sourceOutlineView.primaryMouseVisualSelectionRow
            ?? sourceOutlineView.selectedRow
        return row >= 0 ? row == visualSelectionRow : selectedScope == scope
    }

    private var selectedThemeColor: MudsnoteThemeColor {
        MudsnoteThemeColor(identifier: noteStore.themeColorIdentifier)
    }

    private func sourceSymbolName(for scope: LibraryScope) -> String {
        guard case .folder(let folderURL) = scope,
              sourceFolderTreeRows.first(where: {
                  $0.url.standardizedFileURL.path == folderURL.standardizedFileURL.path
              })?.depth == 0 else {
            return scope.symbolName
        }
        return noteStore.libraryFolderIconName(for: folderURL) ?? "folder.fill"
    }

    private func sourceLegacyTag(for scope: LibraryScope) -> Int {
        switch scope {
        case .all:
            return 0
        case .recent:
            return 1
        case .inbox:
            return 2
        case .trash:
            return 3
        case .folder(let folderURL):
            let folderPath = folderURL.standardizedFileURL.path
            return 10 + (sourceFolderTreeRows.firstIndex {
                $0.url.standardizedFileURL.path == folderPath
            } ?? 0)
        case .tag(let tag):
            return 100 + (sourceTagNames.firstIndex {
                $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
            } ?? 0)
        }
    }

    private func makeSourceOutlineInlineEditCell(
        for operation: InlineFolderEditOperation,
        item: LibrarySourceOutlineItem
    ) -> NSView {
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("LibraryInlineFolderEditRow")

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: "文件夹"
        ) ?? NSImage())
        icon.contentTintColor = LibrarySourceSelectionPalette.unselectedForegroundColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.sourceSymbolPointSize,
            weight: LibraryNotesLayout.sourceSymbolWeight
        )
        icon.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField(string: operation.initialName)
        field.identifier = NSUserInterfaceItemIdentifier("LibraryInlineFolderEditField")
        field.delegate = self
        field.font = .systemFont(
            ofSize: LibraryNotesLayout.sourceButtonFontSize,
            weight: LibraryNotesLayout.sourceUnselectedButtonFontWeight
        )
        field.textColor = LibrarySourceSelectionPalette.unselectedForegroundColor
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(
                equalTo: cell.leadingAnchor,
                constant: LibraryNotesLayout.sourceCellContentLeadingInset
            ),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceIconWidth),
            icon.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceIconHeight),
            field.leadingAnchor.constraint(
                equalTo: icon.trailingAnchor,
                constant: LibraryNotesLayout.sourceIconTitleSpacing
            ),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 20)
        ])
        inlineFolderEditField = field
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let item = item as? LibrarySourceOutlineItem else { return false }
        if case .group = item.kind { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return false }
        switch item.kind {
        case .group:
            return false
        case .scope:
            return true
        case .status, .inlineFolderEdit:
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let item = item as? LibrarySourceOutlineItem else {
            return LibraryNotesLayout.sourceRowHeight
        }
        switch item.kind {
        case .group:
            return LibraryNotesLayout.sourceSectionHeaderHeight
        case .status:
            return LibraryNotesLayout.sourceStatusRowHeight
        case .scope, .inlineFolderEdit:
            return LibraryNotesLayout.sourceRowHeight
        }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let item = item as? LibrarySourceOutlineItem else { return nil }
        switch item.kind {
        case .scope:
            let row = LibrarySourceOutlineRowView()
            row.setVisuallySelected(isSourceOutlineItemVisuallySelected(item))
            return row
        case .group, .status, .inlineFolderEdit:
            let row = NSTableRowView()
            row.selectionHighlightStyle = .none
            return row
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSOutlineView === sourceOutlineView,
              !isSynchronizingSourceOutlineSelection else { return }
        if sourceOutlineView.isDeferringPrimaryMouseSelectionCommit {
            refreshVisibleSourceOutlinePresentation()
            sourceOutlineView.window?.displayIfNeeded()
            return
        }
        commitCurrentSourceOutlineSelection()
    }

    private func commitCurrentSourceOutlineSelection() {
        guard sourceOutlineView.selectedRow >= 0,
              let item = sourceOutlineView.item(atRow: sourceOutlineView.selectedRow)
                as? LibrarySourceOutlineItem,
              let scope = item.scope else { return }
        refreshVisibleSourceOutlinePresentation()
        if !activateSourceScope(scope) {
            refreshSourceSelection()
        }
    }

    @discardableResult
    private func activateSourceScope(_ scope: LibraryScope) -> Bool {
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            selectedScope = scope
            reloadNotesForNavigation(loadFirstIfNeeded: true)
            refreshVisibleSourceOutlinePresentation()
            return true
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return false
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        updateSourceFolderExpansion(from: notification, isExpanded: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        updateSourceFolderExpansion(from: notification, isExpanded: false)
    }

    private func updateSourceFolderExpansion(from notification: Notification, isExpanded: Bool) {
        guard !isRestoringSourceOutlineExpansion,
              notification.object as? NSOutlineView === sourceOutlineView,
              let item = notification.userInfo?["NSObject"]
                as? LibrarySourceOutlineItem else { return }

        if case .group(_, let section) = item.kind,
           let section,
           !item.children.isEmpty {
            DispatchQueue.main.async { [weak self, weak item] in
                guard let self,
                      let item,
                      self.sourceOutlineItemsByIdentifier[item.identifier] === item,
                      self.sourceOutlineView.isItemExpanded(item) == isExpanded else { return }
                self.setSourceSection(section, collapsed: !isExpanded)
                if isExpanded {
                    self.refreshSourceSelection()
                }
            }
            return
        }

        let folderURL: URL
        switch item.kind {
        case .scope(.folder(let url)):
            folderURL = url
        case .inlineFolderEdit(.rename(let url)):
            folderURL = url
        default:
            return
        }
        guard let folderRow = sourceFolderTreeRows.first(where: {
            $0.url.standardizedFileURL.path == folderURL.standardizedFileURL.path
        }) else { return }

        let folderPath = folderURL.standardizedFileURL.path
        if folderRow.depth == 0 {
            if isExpanded {
                collapsedFolderPaths.remove(folderPath)
            } else {
                collapsedFolderPaths.insert(folderPath)
            }
        } else if isExpanded {
            expandedFolderPaths.insert(folderPath)
        } else {
            expandedFolderPaths.remove(folderPath)
        }
        if !isExpanded {
            expandedFolderPaths = expandedFolderPaths.filter { !$0.hasPrefix(folderPath + "/") }
            if case .folder(let selectedFolderURL) = selectedScope,
               selectedFolderURL.standardizedFileURL.path.hasPrefix(folderPath + "/") {
                selectedScope = .folder(folderURL)
                refreshSourceSelection()
                reloadNotesForNavigation(loadFirstIfNeeded: true)
            }
        }
        sourceFolderRows = Self.visibleFolderRowsForSourceList(
            from: sourceFolderTreeRows,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
        persistSourceDisclosureState()
        refreshSourceCounts(using: sourceCountSnapshot)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return [] }
        let urls = sourceOutlineDraggedFileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return [] }

        let directories = urls.filter { sourceOutlineURLIsDirectory($0) }
        if directories.isEmpty {
            guard urls.allSatisfy(isMarkdownFileForLibrary),
                  case .folder(let targetDirectory)? = item.scope else { return [] }
            outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return urls.allSatisfy(isInsideConfiguredLibraryRoot)
                ? (canMoveDraggedNotesForLibrary(at: urls, to: targetDirectory) ? .move : [])
                : .copy
        }

        guard directories.count == 1, urls.count == 1 else { return [] }
        let source = directories[0]
        if isManagedLibraryFolder(source) {
            return canMoveOrReorderFolderForLibrary(source, under: item, childIndex: index) ? .move : []
        }
        if case .folder = item.scope {
            outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }
        if case .group(_, .folders) = item.kind {
            return .copy
        }
        return []
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return false }
        let urls = sourceOutlineDraggedFileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }

        do {
            if urls.count == 1, sourceOutlineURLIsDirectory(urls[0]) {
                let source = urls[0]
                if isManagedLibraryFolder(source) {
                    return try moveOrReorderFolderForLibrary(source, under: item, childIndex: index)
                }
                if case .group(_, .folders) = item.kind {
                    try addExistingLibraryFolderForLibrary(at: source)
                    return true
                }
                guard case .folder(let targetDirectory)? = item.scope else { return false }
                _ = try importExternalLibraryItem(source, to: targetDirectory)
                return true
            }

            guard urls.allSatisfy(isMarkdownFileForLibrary),
                  case .folder(let targetDirectory)? = item.scope else { return false }
            if urls.allSatisfy(isInsideConfiguredLibraryRoot) {
                return !(try moveDraggedNotesForLibrary(at: urls, to: targetDirectory)).isEmpty
            }
            for url in urls {
                _ = try importExternalLibraryItem(url, to: targetDirectory)
            }
            return true
        } catch {
            presentErrorAlert(message: "拖拽失败", details: error.localizedDescription)
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem,
              case .folder(let folderURL)? = item.scope else { return nil }
        return folderURL as NSURL
    }

    private func sourceOutlineURLIsDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isMarkdownFileForLibrary(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    private func isManagedLibraryFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return noteStore.preferredDirectories.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private func canMoveOrReorderFolderForLibrary(
        _ sourceURL: URL,
        under item: LibrarySourceOutlineItem,
        childIndex: Int
    ) -> Bool {
        let source = sourceURL.standardizedFileURL
        guard sourceFolderTreeRows.contains(where: { $0.url.standardizedFileURL.path == source.path }) else {
            return false
        }
        if case .group(_, .folders) = item.kind {
            return sourceFolderTreeRows.first(where: { $0.url.standardizedFileURL.path == source.path })?.depth == 0
        }
        guard case .folder(let target)? = item.scope else { return false }
        let targetURL = target.standardizedFileURL
        return source.path != noteStore.notesDirectory.standardizedFileURL.path
            && targetURL.path != source.path
            && !targetURL.path.hasPrefix(source.path + "/")
    }

    @discardableResult
    private func moveOrReorderFolderForLibrary(
        _ sourceURL: URL,
        under item: LibrarySourceOutlineItem,
        childIndex: Int
    ) throws -> Bool {
        let source = sourceURL.standardizedFileURL
        guard canMoveOrReorderFolderForLibrary(source, under: item, childIndex: childIndex) else { return false }

        if case .group(_, .folders) = item.kind {
            persistFolderOrder(moving: source, among: item.children, insertionIndex: childIndex)
            reloadSourceFolderRowsForCurrentState()
            return true
        }

        guard case .folder(let targetParent)? = item.scope else { return false }
        let parent = targetParent.standardizedFileURL
        let destination: URL
        if source.deletingLastPathComponent().standardizedFileURL == parent {
            destination = source
        } else {
            destination = try moveFolderForLibrary(at: source, to: parent)
        }
        persistFolderOrder(moving: destination, among: item.children, insertionIndex: childIndex)
        reloadSourceFolderRowsForCurrentState()
        return true
    }

    @discardableResult
    func moveFolderForLibrary(at sourceURL: URL, to parentDirectory: URL) throws -> URL {
        let source = sourceURL.standardizedFileURL
        let parent = parentDirectory.standardizedFileURL
        try saveCurrentNoteIfNeeded()
        let destination = try noteStore.moveFolder(at: source, to: parent)
        guard destination != source else { return source }

        recordInternalFileSystemChanges(for: [source, destination])
        remapSourceSnapshotFolder(from: source, to: destination)
        setSelectedURLForLibrary(remappedLibraryURL(
            selectedURL,
            from: source,
            to: destination
        ))
        if case .folder(let selectedFolder) = selectedScope,
           let remappedFolder = remappedLibraryURL(selectedFolder, from: source, to: destination) {
            selectedScope = .folder(remappedFolder)
        }
        activeSearchSession = nil
        reloadPersistedSourceDisclosureState()
        reloadSourceFolderRowsForCurrentState()
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
        return destination
    }

    private func remappedLibraryURL(_ url: URL?, from source: URL, to destination: URL) -> URL? {
        guard let url else { return nil }
        let path = url.standardizedFileURL.path
        guard path == source.path || path.hasPrefix(source.path + "/") else { return url }
        return URL(
            fileURLWithPath: destination.path + String(path.dropFirst(source.path.count)),
            isDirectory: path == source.path
        )
    }

    private func persistFolderOrder(
        moving folderURL: URL,
        among children: [LibrarySourceOutlineItem],
        insertionIndex: Int
    ) {
        let folderPath = folderURL.standardizedFileURL.path
        var siblingPaths = children.compactMap { child -> String? in
            guard case .folder(let url)? = child.scope else { return nil }
            let path = url.standardizedFileURL.path
            return path == folderPath ? nil : path
        }
        let targetIndex = insertionIndex == NSOutlineViewDropOnItemIndex
            ? siblingPaths.count
            : min(max(insertionIndex, 0), siblingPaths.count)
        siblingPaths.insert(folderPath, at: targetIndex)
        let siblingSet = Set(siblingPaths)
        noteStore.libraryFolderOrderPaths = noteStore.libraryFolderOrderPaths.filter {
            !siblingSet.contains($0) && $0 != folderPath
        } + siblingPaths
    }

    @discardableResult
    private func importExternalLibraryItem(_ sourceURL: URL, to targetDirectory: URL) throws -> URL {
        let source = sourceURL.standardizedFileURL
        let target = targetDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var destination = target.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: sourceOutlineURLIsDirectory(source)
        )
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            let filename = source.pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(source.pathExtension)"
            destination = target.appendingPathComponent(filename, isDirectory: sourceOutlineURLIsDirectory(source))
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        recordInternalFileSystemChanges(for: [destination])
        activeSearchSession = nil
        reloadSourceFolderRowsForCurrentState()
        forceFullLibrarySnapshotReload()
        selectedScope = sourceOutlineURLIsDirectory(destination) ? .folder(destination) : .folder(target)
        refreshSourceSelection()
        return destination
    }

    private func sourceOutlineDraggedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        var seenPaths = Set<String>()
        return objects.compactMap { object in
            let url = (object as? URL) ?? ((object as? NSURL).map { $0 as URL })
            guard let url else { return nil }
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL,
                  seenPaths.insert(standardized.path).inserted else { return nil }
            return standardized
        }
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
            cell.isFirstGroup = row == 0
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
            noteListDisplayTitle(for: note),
            font: cell.titleLabel.font ?? .systemFont(ofSize: LibraryNotesLayout.noteTitleFontSize, weight: .semibold),
            baseColor: panelPrimaryTextColor(),
            query: query
        )
        cell.snippetLabel.attributedStringValue = highlightedSearchString(
            noteListSnippetText(for: note),
            font: cell.snippetLabel.font ?? .systemFont(ofSize: LibraryNotesLayout.noteSnippetFontSize),
            baseColor: panelSecondaryTextColor(),
            query: query
        )
        let thumbnailImage = thumbnailImage(for: note)
        cell.thumbnailImageView.image = thumbnailImage
        cell.thumbnailImageView.isHidden = thumbnailImage == nil
        cell.attachmentImageView.isHidden = !note.hasAttachments || thumbnailImage != nil
        cell.metaLabel.stringValue = noteListFolderText(for: note)
        return cell
    }

    private func noteListDisplayTitle(for note: NoteSearchResult) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else { return title }
        let fallback = note.url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? LibraryCopy.newNote : fallback
    }

    private func thumbnailImage(for note: NoteSearchResult) -> NSImage? {
        guard let thumbnailURL = note.thumbnailURL else {
            return nil
        }
        let key = thumbnailURL.standardizedFileURL.path
        if let cached = thumbnailImageCache.object(forKey: key as NSString) {
            return cached.image
        }

        guard hasRequestedWindowPresentation else {
            return decodeThumbnailImageSynchronously(at: thumbnailURL, key: key)
        }

        scheduleThumbnailImageLoad(at: thumbnailURL, key: key)
        return nil
    }

    private func decodeThumbnailImageSynchronously(at url: URL, key: String) -> NSImage? {
        thumbnailImageDecodeCountForLibrary += 1
        let image = thumbnailDecoder(url).map {
            NSImage(cgImage: $0, size: NSSize(width: 44, height: 44))
        }
        cacheThumbnailImage(image, key: key)
        return image
    }

    private func scheduleThumbnailImageLoad(at url: URL, key: String) {
        guard thumbnailImageLoadTasks[key] == nil else { return }

        thumbnailImageDecodeCountForLibrary += 1
        let thumbnailDecoder = thumbnailDecoder
        let task = Task.detached(priority: .utility) { [weak self] in
            let decoded = LibraryThumbnailDecodeResult(image: thumbnailDecoder(url))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.thumbnailImageLoadTasks[key] = nil
                guard !Task.isCancelled else { return }

                let image = decoded.image.map {
                    NSImage(cgImage: $0, size: NSSize(width: 44, height: 44))
                }
                self.cacheThumbnailImage(image, key: key)
                guard self.window?.isVisible == true else { return }
                self.scheduleThumbnailReload(for: key)
            }
        }
        thumbnailImageLoadTasks[key] = task
    }

    private func rebuildThumbnailRowIndex() {
        var rowsByPath: [String: IndexSet] = [:]
        for (row, listRow) in listRows.enumerated() {
            guard let path = listRow.note?.thumbnailURL?.standardizedFileURL.path else { continue }
            rowsByPath[path, default: []].insert(row)
        }
        thumbnailRowsByPath = rowsByPath
    }

    private func rebuildThumbnailItemIndex() {
        var itemsByPath: [String: Set<IndexPath>] = [:]
        for (section, gallerySection) in gallerySections.enumerated() {
            for (item, note) in gallerySection.notes.enumerated() {
                guard let path = note.thumbnailURL?.standardizedFileURL.path else { continue }
                itemsByPath[path, default: []].insert(IndexPath(item: item, section: section))
            }
        }
        thumbnailItemsByPath = itemsByPath
    }

    private func scheduleThumbnailReload(for path: String) {
        pendingThumbnailReloadPaths.insert(path)
        guard !thumbnailReloadScheduled else { return }
        thumbnailReloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingThumbnailReloads()
        }
    }

    private func flushPendingThumbnailReloads() {
        guard thumbnailReloadScheduled else { return }
        thumbnailReloadScheduled = false
        let paths = pendingThumbnailReloadPaths
        pendingThumbnailReloadPaths.removeAll()
        guard window?.isVisible == true else { return }

        var matchingRows = IndexSet()
        var matchingItems = Set<IndexPath>()
        for path in paths {
            if let rows = thumbnailRowsByPath[path] {
                matchingRows.formUnion(rows)
            }
            if let items = thumbnailItemsByPath[path] {
                matchingItems.formUnion(items)
            }
        }

        guard !matchingRows.isEmpty || !matchingItems.isEmpty else { return }
        thumbnailReloadBatchCountForLibrary += 1
        if !matchingRows.isEmpty {
            tableView.reloadData(
                forRowIndexes: matchingRows,
                columnIndexes: IndexSet(integer: 0)
            )
        }
        if noteListViewMode == .gallery,
           hasRequestedWindowPresentation,
           !matchingItems.isEmpty {
            galleryCollectionView.reloadItems(at: matchingItems)
        }
    }

    private func cacheThumbnailImage(_ image: NSImage?, key: String) {
        let pixelCost = image == nil ? 1 : 88 * 88 * 4
        thumbnailImageCache.setObject(
            LibraryThumbnailCacheEntry(image: image),
            forKey: key as NSString,
            cost: pixelCost
        )
    }

    nonisolated private static func makeListThumbnailCGImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 88,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func waitForThumbnailLoadsForLibrary() async {
        let tasks = Array(thumbnailImageLoadTasks.values)
        for task in tasks {
            await task.value
        }
        flushPendingThumbnailReloads()
    }

    func highlightedSearchString(
        _ text: String,
        font: NSFont,
        baseColor: NSColor,
        query: String
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraphStyle
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
        guard notification.object as? NSTableView === tableView,
              !suppressSelectionChanges else { return }
        synchronizeGallerySelectionFromTable()
        handleNoteBrowserSelectionChange()
    }

    private func handleNoteBrowserSelectionChange() {
        let previousURL = selectedURL
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            if preservesCurrentLoadedNoteForMultiSelection() {
                updateToolbarActionState()
            } else {
                loadSelectedRow()
            }
        } catch {
            restoreNoteBrowserSelection(to: previousURL)
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    private func restoreNoteBrowserSelection(to url: URL?) {
        suppressSelectionChanges = true
        if let url,
           let row = rowIndex(for: url.standardizedFileURL.path) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        guard collectionView === galleryCollectionView else { return 0 }
        return gallerySections.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard collectionView === galleryCollectionView,
              gallerySections.indices.contains(section) else { return 0 }
        return gallerySections[section].notes.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: LibraryGalleryItem.identifier,
            for: indexPath
        )
        guard let galleryItem = item as? LibraryGalleryItem,
              let note = galleryNote(at: indexPath) else {
            return item
        }
        let rawPreview = note.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        galleryItem.configure(
            title: noteListDisplayTitle(for: note),
            preview: rawPreview.isEmpty ? LibraryCopy.noAdditionalText : rawPreview,
            date: noteListDateText(for: noteListDisplayDateForLibrary(note)),
            metadata: noteListFolderText(for: note),
            thumbnail: thumbnailImage(for: note)
        )
        return galleryItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> NSView {
        guard kind == NSCollectionView.elementKindSectionHeader,
              gallerySections.indices.contains(indexPath.section) else {
            return NSView()
        }
        let view = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: LibraryGallerySectionHeaderView.identifier,
            for: indexPath
        )
        if let header = view as? LibraryGallerySectionHeaderView {
            header.titleLabel.stringValue = gallerySections[indexPath.section].title ?? ""
        }
        return view
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> NSSize {
        guard gallerySections.indices.contains(section), gallerySections[section].title != nil else {
            return .zero
        }
        return NSSize(width: 1, height: LibraryNotesLayout.gallerySectionHeaderHeight)
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        handleGallerySelectionChange()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        handleGallerySelectionChange()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        galleryNote(at: indexPath)?.url as NSURL?
    }

    private func galleryNote(at indexPath: IndexPath) -> NoteSearchResult? {
        guard gallerySections.indices.contains(indexPath.section),
              gallerySections[indexPath.section].notes.indices.contains(indexPath.item) else {
            return nil
        }
        return gallerySections[indexPath.section].notes[indexPath.item]
    }

    private func galleryIndexPath(for standardizedPath: String) -> IndexPath? {
        for section in gallerySections.indices {
            if let item = gallerySections[section].notes.firstIndex(where: {
                $0.url.standardizedFileURL.path == standardizedPath
            }) {
                return IndexPath(item: item, section: section)
            }
        }
        return nil
    }

    private func reloadGalleryData() {
        gallerySections = LibraryGalleryProjection.sections(from: listRows)
        guard noteListViewMode == .gallery, hasRequestedWindowPresentation else { return }
        galleryCollectionView.reloadData()
    }

    private func reloadNoteBrowserData(
        animation: LibraryNoteMutationAnimation? = nil,
        previousRows: [LibraryNoteListRow] = [],
        refreshedNotePaths: Set<String> = []
    ) {
        let canAnimate = animation != nil
            && hasRequestedWindowPresentation
            && window?.isVisible == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let refreshPlan = LibraryNoteListMutationPlan(
            previousRows: previousRows,
            currentRows: listRows,
            refreshingNotePaths: refreshedNotePaths
        ) {
            tableView.beginUpdates()
            if !refreshPlan.removedRows.isEmpty {
                tableView.removeRows(at: refreshPlan.removedRows, withAnimation: [])
            }
            if !refreshPlan.insertedRows.isEmpty {
                tableView.insertRows(at: refreshPlan.insertedRows, withAnimation: [])
            }
            tableView.endUpdates()
        } else if canAnimate,
           let animation,
           let plan = LibraryNoteListMutationPlan(
               previousRows: previousRows,
               currentRows: listRows,
               animation: animation
           ) {
            tableView.beginUpdates()
            if !plan.removedRows.isEmpty {
                tableView.removeRows(at: plan.removedRows, withAnimation: [.effectFade, .slideUp])
            }
            if !plan.insertedRows.isEmpty {
                tableView.insertRows(at: plan.insertedRows, withAnimation: [.effectGap, .slideDown])
            }
            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }

        reloadGalleryData()
        if canAnimate, noteListViewMode == .gallery {
            galleryCollectionView.alphaValue = 0.72
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                galleryCollectionView.animator().alphaValue = 1
            }
        }
    }

    private func synchronizeGallerySelectionFromTable() {
        guard noteListViewMode == .gallery, hasRequestedWindowPresentation else { return }
        let selectedPaths = Set(tableView.selectedRowIndexes.compactMap { row in
            note(at: row)?.url.standardizedFileURL.path
        })
        let indexPaths = Set(selectedPaths.compactMap(galleryIndexPath(for:)))
        suppressGallerySelectionChanges = true
        galleryCollectionView.selectionIndexPaths = indexPaths
        suppressGallerySelectionChanges = false
    }

    private func synchronizeTableSelectionFromGallery() {
        let selectedPaths = Set(galleryCollectionView.selectionIndexPaths.compactMap { indexPath in
            galleryNote(at: indexPath)?.url.standardizedFileURL.path
        })
        let rows = IndexSet(listRows.indices.filter { row in
            guard let note = listRows[row].note else { return false }
            return selectedPaths.contains(note.url.standardizedFileURL.path)
        })
        suppressSelectionChanges = true
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        suppressSelectionChanges = false
    }

    private func handleGallerySelectionChange() {
        guard !suppressGallerySelectionChanges else { return }
        synchronizeTableSelectionFromGallery()
        handleNoteBrowserSelectionChange()
    }

    private func galleryContextMenuForLibrary(at indexPath: IndexPath) -> NSMenu? {
        synchronizeTableSelectionFromGallery()
        guard let row = rowIndex(for: galleryNote(at: indexPath)?.url.standardizedFileURL.path ?? "") else {
            return nil
        }
        return noteContextMenuForLibrary(row: row)
    }

    @objc
    private func galleryDoubleClicked(_ sender: NSClickGestureRecognizer) {
        let location = sender.location(in: galleryCollectionView)
        guard let indexPath = galleryCollectionView.indexPathForItem(at: location) else { return }
        galleryCollectionView.selectionIndexPaths = [indexPath]
        synchronizeTableSelectionFromGallery()
        openSelectedGalleryNoteInList()
    }

    private func handleGalleryKeyCommand(_ command: LibraryNoteKeyCommand) -> Bool {
        switch command {
        case .open:
            guard !galleryCollectionView.selectionIndexPaths.isEmpty else { return false }
            openSelectedGalleryNoteInList()
            return true
        case .delete:
            return handleNoteListKeyCommand(.delete)
        case .moveDown, .moveUp:
            return false
        }
    }

    private func openSelectedGalleryNoteInList() {
        setNoteListViewModeForLibrary(.list)
        loadSelectedRow()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let object = obj.object as AnyObject? else { return }

        if object === inlineFolderEditField {
            return
        }

        if object === searchField {
            scheduleSearchReloadFromTyping()
            return
        }

        if object === titleField {
            replaceUnifiedEditorTitle(titleField.stringValue)
            markDirty()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === inlineFolderEditField {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelInlineFolderEdit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitInlineFolderEdit()
                return true
            }
            return false
        }

        if control === titleField {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            window?.makeFirstResponder(editorTextView)
            editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
            editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
            return true
        }

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

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === editorTextView else { return false }

        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return moveMarkdownTableCellSelectionForLibrary(.next)
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return moveMarkdownTableCellSelectionForLibrary(.previous)
        }

        return false
    }

    func textDidChange(_ notification: Notification) {
        if let object = notification.object as AnyObject?, object === editorTextView {
            normalizeUnifiedTitleLineFormatting()
            let metadata = visibleEditorMetadata()
            titleField.stringValue = metadata.title
            updateWordCount(in: metadata.body)
            layoutEditorStatusLabel()
            libraryUserDidEdit()
        } else {
            markDirty()
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let object = notification.object as AnyObject?, object === editorTextView else { return }
        updateEditorSlashSuggestions()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === inlineFolderEditField,
              inlineFolderEditHasReceivedFocus,
              !isCommittingInlineFolderEdit else {
            return
        }
        commitInlineFolderEdit()
    }

    @objc
    private func searchScopeChanged(_ sender: NSSegmentedControl) {
        cancelPendingSearchReload()
        performSearchReload()
    }

    private func toggleSourceSection(_ section: LibrarySourceSection) {
        let shouldExpand = isSourceSectionCollapsed(section)
        setSourceSection(section, collapsed: !shouldExpand)
        guard let item = sourceOutlineItemsByIdentifier[
            section == .folders ? "group:icloud" : "group:tags"
        ] else { return }
        if shouldExpand {
            sourceOutlineView.expandItem(item, expandChildren: false)
            refreshSourceSelection()
        } else {
            sourceOutlineView.collapseItem(item, collapseChildren: false)
        }
    }

    private func setSourceSection(_ section: LibrarySourceSection, collapsed: Bool) {
        switch section {
        case .folders:
            sourceFoldersSectionCollapsed = collapsed
            noteStore.libraryFoldersSectionCollapsed = collapsed
            if !collapsed {
                scheduleDeferredSourceFolderLoad()
            }
        case .tags:
            sourceTagsSectionCollapsed = collapsed
            noteStore.libraryTagsSectionCollapsed = collapsed
            if !collapsed {
                scheduleDeferredSourceTagLoad()
            }
        }
    }

    private func persistSourceDisclosureState() {
        noteStore.libraryCollapsedFolderPaths = collapsedFolderPaths
        noteStore.libraryExpandedFolderPaths = expandedFolderPaths
    }

    private func reloadPersistedSourceDisclosureState() {
        collapsedFolderPaths = noteStore.libraryCollapsedFolderPaths
        expandedFolderPaths = noteStore.libraryExpandedFolderPaths
        sourceFoldersSectionCollapsed = noteStore.libraryFoldersSectionCollapsed
        sourceTagsSectionCollapsed = noteStore.libraryTagsSectionCollapsed
    }

    @objc
    private func addFolderPressed() {
        beginInlineFolderCreationForLibrary()
    }

    @objc
    private func addExistingLibraryFolderMenuItemPressed() {
        presentAddExistingLibraryFolderPanelForLibrary()
    }

    @objc
    private func removeLibraryFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL,
              confirmDestructiveAction(
                title: "从资料库移除？",
                message: "只会从列表移除该文件夹，不会删除其中的文件。"
              ) else { return }

        do {
            try removeRegisteredLibraryFolderForLibrary(at: directory)
        } catch {
            presentErrorAlert(message: "无法移除文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func revealLibraryFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory.standardizedFileURL])
    }

    @objc
    private func toggleSourceListPressed() {
        setSourceListVisibleForLibrary(
            !isSourceListVisibleForLibrary,
            animated: window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    @objc
    private func newNotePressed() {
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            if noteListViewMode == .gallery {
                noteListViewMode = .list
                noteStore.libraryNoteViewModeRawValue = LibraryNoteViewMode.list.rawValue
                applyNoteListViewModeChrome(animated: window?.isVisible == true)
            }
            if selectedScope == .trash {
                selectedScope = .folder(noteStore.notesDirectory)
            }
            cancelActiveNoteLoad()
            isLoadingInitialNote = false
            isCreatingNewNote = true
            setSelectedURLForLibrary(nil)
            selectedSourceContents = nil
            noteLinksView.update(.empty)
            selectedTags = []
            suppressSelectionChanges = true
            tableView.deselectAll(nil)
            suppressSelectionChanges = false
            setEditorEditable(true)
            applyDocument(title: "", body: "", tags: [])
            isDirty = true
            updateEditorCreatedDate(Date())
            if backgroundAutosaveIsActive {
                autosaveCurrentNote()
            } else {
                _ = try saveCurrentNote(force: true)
            }
            updateEditorStatus(editorEditedDateText(for: Date()))
            refreshSourceSelection()
            updateToolbarActionState()
            window?.makeFirstResponder(editorTextView)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCreatingNewNote else { return }
                self.window?.makeFirstResponder(self.editorTextView)
            }
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    func createNewNoteForLibrary() {
        newNotePressed()
    }

    func createNewFolderForLibrary() {
        addFolderPressed()
    }

    func presentAddExistingLibraryFolderPanelForLibrary() {
        let panel = NSOpenPanel()
        panel.title = "将文件夹添加到资料库"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = noteStore.notesDirectory.deletingLastPathComponent()

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            try addExistingLibraryFolderForLibrary(at: directory)
        } catch {
            presentErrorAlert(message: "无法添加文件夹", details: error.localizedDescription)
        }
    }

    func focusSearchForLibrary() {
        window?.makeFirstResponder(searchField)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.searchField)
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
                try deleteSelectedNotesInBackgroundForLibrary()
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
        activeSearchSession = nil
        cancelPendingSearchReload()
        performSearchReload()
        removeEditorSearchHighlights()
        return true
    }

    private func scheduleSearchReloadFromTyping() {
        searchReloadWorkItem?.cancel()

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            activeSearchSession = nil
            hasPendingSearchReload = false
            performSearchReload(synchronously: true)
            removeEditorSearchHighlights()
            return
        }

        hasPendingSearchReload = true
        searchScopeControl.isHidden = false
        updateNoteListHeader(query: query)
        updateNoteListEmptyState(query: query)
        applyEditorSearchHighlightsForCurrentQuery()

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
        isSearchResultReloading = false
        searchResultsGeneration += 1
    }

    private func performSearchReload(synchronously: Bool = false) {
        cancelPendingSearchReload()
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            activeSearchSession = nil
            reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
            applyEditorSearchHighlightsForCurrentQuery()
        } else if synchronously {
            if activeSearchSession == nil || (selectedScope == .trash && searchScopeControl.selectedSegment != 1) {
                let provisionalResults = cachedSearchResultsForSelectedScope(query: query, limit: 240)
                applySearchResults(provisionalResults, query: query, selecting: selectedURL)
                scheduleSearchResultReload(query: query, selecting: selectedURL)
            } else {
                reloadNotes(selecting: selectedURL, loadFirstIfNeeded: false, refreshCounts: false)
            }
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
        let existingSearchSession = activeSearchSession
        let preferredDirectories = noteStore.preferredDirectories
        let includesSubfolderNotes = noteStore.libraryIncludesSubfolderNotes
        isSearchResultReloading = true
        searchScopeControl.isHidden = false
        updateNoteListHeader(query: query)
        updateNoteListEmptyState(query: query)

        let task = Task.detached(priority: .userInitiated) { [noteStore, existingSearchSession, preferredDirectories, scope, query, searchesAllNotes, includesSubfolderNotes, generation, preferredURL] in
            guard !Task.isCancelled else { return }
            let searchSession: NoteSearchSession
            if let existingSearchSession {
                searchSession = existingSearchSession
            } else {
                guard let builtSession = noteStore.makeSearchSession(
                    roots: preferredDirectories,
                    cancellationCheck: { Task.isCancelled }
                ) else {
                    return
                }
                searchSession = builtSession
            }
            let results = librarySearchResults(
                noteStore: noteStore,
                searchSession: searchSession,
                scope: scope,
                query: query,
                limit: 240,
                searchesAllNotes: searchesAllNotes,
                includesSubfolderNotes: includesSubfolderNotes
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
                self.activeSearchSession = searchSession
                self.applySearchResults(results, query: query, selecting: preferredURL)
            }
        }
        searchResultsTask = task
    }

    private func applySearchResults(_ results: [NoteSearchResult], query: String, selecting preferredURL: URL?) {
        isSearchResultReloading = false
        notes = results.filter {
            !pendingDeletionPaths.contains($0.url.standardizedFileURL.path)
        }
        listRows = buildGroupedRows(for: notes, preservesInputOrder: true)
        updateNoteListHeader(query: query)

        suppressSelectionChanges = true
        reloadNoteBrowserData()
        updateNoteListEmptyState(query: query)

        if let preferredPath = preferredURL?.standardizedFileURL.path,
           let row = rowIndex(for: preferredPath) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()

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
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
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
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        let menu = makeFormatMenuForLibrary()
        guard !menu.items.isEmpty else { return }
        popToolbarMenu(menu, from: sender)
    }

    @objc
    private func formatMenuItemPressed(_ sender: NSMenuItem) {
        guard let command = LibraryFormatCommand(rawValue: sender.tag) else { return }
        applyFormatCommand(command)
    }

    @objc
    private func checklistPressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        focusEditorForLibraryAction()
        let undoSnapshot = libraryFormattingUndoSnapshot()
        toggleParagraphKind(.checklist(checked: false))
        registerLibraryFormattingUndoIfNeeded(before: undoSnapshot, actionName: "待办列表")
    }

    @objc
    private func tablePressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        insertTableForLibrary()
    }

    @objc
    func linkPressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        if let link = editorTextView.linkReference(for: editorTextView.selectedRange()) {
            presentLinkEditorForLibrary(
                title: "编辑链接",
                destination: link.url,
                name: link.label
            ) { [weak self] destination, name in
                self?.updateLinkForLibrary(
                    link,
                    label: name.isEmpty ? destination : name,
                    url: destination
                )
            }
            return
        }

        let defaultLabel = selectedTextForLinkDefault()
        presentLinkEditorForLibrary(
            title: "添加链接",
            destination: "",
            name: defaultLabel
        ) { [weak self] destination, name in
            self?.insertLinkForLibrary(
                label: name.isEmpty ? destination : name,
                url: destination
            )
        }
    }

    @objc
    private func attachmentPressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
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
    private func toggleEditorSourceModePressed() {
        guard canEditCurrentDocument, let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        suppressEditorChanges = true
        if isEditorShowingMarkdownSource {
            let markdown = storage.string
            editorTextView.isRichText = true
            editorTextView.markdownPasteTheme = theme
            storage.setAttributedString(
                MarkdownRichTextCodec.render(
                    markdown: markdown,
                    theme: theme,
                    baseURL: selectedURL,
                    imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
                )
            )
            editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
            isEditorShowingMarkdownSource = false
        } else {
            let markdown = MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
            removeEditorSearchHighlights()
            editorTextView.isRichText = false
            editorTextView.markdownPasteTheme = nil
            let sourceAttributes: [NSAttributedString.Key: Any] = [
                .font: theme.codeFont,
                .foregroundColor: theme.textColor,
                .paragraphStyle: theme.paragraphStyle(for: .paragraph)
            ]
            storage.setAttributedString(NSAttributedString(string: markdown, attributes: sourceAttributes))
            editorTextView.typingAttributes = sourceAttributes
            isEditorShowingMarkdownSource = true
        }
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        editorTextView.window?.makeFirstResponder(editorTextView)
        updateToolbarActionState()
    }

    @objc
    private func moveSelectedNotePressed(_ sender: Any?) {
        guard canMoveSelectedNote else { return }
        let menu = makeMoveNoteMenu()
        guard !menu.items.isEmpty else { return }
        popToolbarMenu(menu, from: sender)
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
            try deleteSelectedNotesInBackgroundForLibrary()
        } catch {
            presentErrorAlert(message: "删除失败", details: error.localizedDescription)
        }
    }

    @objc
    private func togglePinnedNotesPressed() {
        _ = togglePinnedStateForSelectedNotesForLibrary()
    }

    @objc
    private func renameFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }
        beginInlineFolderRenameForLibrary(at: directory)
    }

    @objc
    func deleteFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }

        do {
            selectedScope = .folder(directory)
            try deleteSelectedFolderForLibrary()
        } catch {
            presentErrorAlert(message: "无法删除文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func moveFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? LibraryFolderMoveRequest else { return }
        do {
            _ = try moveFolderForLibrary(at: request.source, to: request.destinationParent)
        } catch {
            presentErrorAlert(message: "无法移动文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func changeFolderIconMenuItemPressed(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? LibraryFolderIconRequest else { return }
        noteStore.setLibraryFolderIconName(request.symbolName, for: request.folderURL)
        refreshVisibleSourceOutlinePresentation()
        sourceOutlineView.window?.displayIfNeeded()
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
            return
        }
        load(note: note)
    }

    private func load(note: NoteSearchResult) {
        isLoadingInitialNote = false
        persistedLaunchFallbackURL = nil
        isCreatingNewNote = false
        cancelActiveNoteLoad(preservingFallback: true)
        notePrefetchTask?.cancel()
        notePrefetchTask = nil
        if let cached = cachedLoadedNote(for: note) {
            noteLoadFallbackURL = nil
            applyLoadedNote(cached, for: note)
            scheduleCachedNoteValidation(cached, for: note)
            releaseDeferredLaunchWorkIfReady()
            return
        }

        guard window?.isVisible == true,
              visualQASelectedURL == nil else {
            loadNoteSynchronously(note)
            return
        }

        beginNoteSwitchLoading(note)
        let generation = noteLoadGeneration
        let editorRevision = editorContentRevision
        let noteLoader = noteLoader
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result<LoadedLibraryNote, Error> {
                try noteLoader(note.url)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      generation == self.noteLoadGeneration,
                      editorRevision == self.editorContentRevision,
                      self.selectedNoteStillMatchesInitialLoad(note) else {
                    return
                }
                self.noteLoadTask = nil
                self.applyLoadedNoteResult(result, for: note)
            }
        }
        noteLoadTask = task
    }

    private func reloadSelectedNoteAfterExternalChange(_ note: NoteSearchResult) {
        cancelActiveNoteLoad()
        let generation = noteLoadGeneration
        let editorRevision = editorContentRevision
        let noteLoader = noteLoader
        let fileModificationDateLoader = fileModificationDateLoader
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result<LoadedLibraryNote, Error> {
                try noteLoader(note.url)
            }
            let fileModifiedAt = fileModificationDateLoader(note.url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      generation == self.noteLoadGeneration,
                      editorRevision == self.editorContentRevision,
                      !self.isDirty,
                      self.selectedNoteStillMatchesInitialLoad(note) else { return }
                self.noteLoadTask = nil
                switch result {
                case .success(let loaded):
                    let cached = self.cacheLoadedNote(
                        loaded,
                        for: note,
                        fileModifiedAt: fileModifiedAt
                    )
                    self.applyLoadedNote(cached, for: note, preservingEditorSelection: true)
                case .failure(let error):
                    self.presentErrorAlert(message: "无法刷新笔记", details: error.localizedDescription)
                }
            }
        }
        noteLoadTask = task
    }

    private func loadNoteSynchronously(_ note: NoteSearchResult) {
        do {
            let loaded = try noteLoader(note.url)
            applyLoadedNoteResult(.success(loaded), for: note)
        } catch {
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    private func cancelActiveNoteLoad(preservingFallback: Bool = false) {
        noteLoadTask?.cancel()
        noteLoadTask = nil
        noteLoadGeneration += 1
        if !preservingFallback {
            noteLoadFallbackURL = nil
        }
    }

    private func beginNoteSwitchLoading(_ note: NoteSearchResult) {
        if noteLoadFallbackURL == nil {
            noteLoadFallbackURL = selectedURL
        }
        isLoadingInitialNote = true
        setSelectedURLForLibrary(note.url)
        setEditorEditable(false)
        updateEditorStatus("正在载入…")
        updateToolbarActionState()
    }

    private func applyLoadedNoteResult(
        _ result: Result<LoadedLibraryNote, Error>,
        for note: NoteSearchResult,
        fileModifiedAt: Date? = nil
    ) {
        isLoadingInitialNote = false
        defer { releaseDeferredLaunchWorkIfReady() }
        switch result {
        case .success(let loaded):
            noteLoadFallbackURL = nil
            let cached = cacheLoadedNote(loaded, for: note, fileModifiedAt: fileModifiedAt)
            applyLoadedNote(cached, for: note)
        case .failure(let error):
            let fallbackURL = noteLoadFallbackURL
            noteLoadFallbackURL = nil
            setSelectedURLForLibrary(fallbackURL)
            setEditorEditable(selectedScope != .trash)
            restoreNoteBrowserSelection(to: fallbackURL)
            updateToolbarActionState()
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    private func applyLoadedNote(_ cached: LoadedLibraryNoteCacheEntry, for note: NoteSearchResult) {
        applyLoadedNote(cached, for: note, preservingEditorSelection: false)
    }

    private func applyLoadedNote(
        _ cached: LoadedLibraryNoteCacheEntry,
        for note: NoteSearchResult,
        preservingEditorSelection: Bool
    ) {
        setSelectedURLForLibrary(note.url)
        selectedSourceContents = cached.loaded.sourceContents
        setEditorEditable(selectedScope != .trash)

        let preservedSelection = preservingEditorSelection ? editorTextView.selectedRange() : nil
        if preservingEditorSelection,
           titleField.stringValue == cached.loaded.title,
           selectedTags == cached.loaded.tags,
           normalizedEditorMarkdownBody() == normalizedMarkdownBody(cached.loaded.body) {
            isDirty = false
            updateEditorCreatedDate(note.createdAt)
            updateEditorStatus(editorEditedDateText(for: note.modifiedAt))
            updateToolbarActionState()
            refreshNoteLinks(for: note.url, body: cached.loaded.body)
            return
        }

        let renderedBody: NSAttributedString
        if let rendered = cached.renderedBody {
            renderedBody = rendered
        } else {
            let rendered = MarkdownRichTextCodec.render(
                markdown: MarkdownEditorDocument.composeEditorText(
                    title: cached.loaded.title,
                    body: cached.loaded.body,
                    hasMetadataTags: !cached.loaded.tags.isEmpty
                ),
                theme: theme,
                baseURL: note.url,
                imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
            )
            renderedBody = rendered
            if !MarkdownEditorDocument.containsAttachmentReference(in: cached.loaded.body) {
                cached.renderedBody = rendered.copy() as? NSAttributedString
            }
        }

        applyDocument(
            title: cached.loaded.title,
            body: cached.loaded.body,
            tags: cached.loaded.tags,
            renderedBody: renderedBody,
            preservedSelection: preservedSelection
        )
        isDirty = false
        updateEditorCreatedDate(note.createdAt)
        updateEditorStatus(editorEditedDateText(for: note.modifiedAt))
        applyEditorSearchHighlightsForCurrentQuery()
        updateToolbarActionState()
        refreshNoteLinks(for: note.url, body: cached.loaded.body)
        prefetchAdjacentNotes(around: note)
    }

    private func refreshNoteLinks(for noteURL: URL, body: String) {
        noteLinksRefreshTask?.cancel()
        noteLinksRefreshGeneration += 1
        let generation = noteLinksRefreshGeneration
        let noteStore = noteStore
        let roots = noteStore.preferredDirectories + [noteURL.deletingLastPathComponent()]
        let task = Task.detached(priority: .utility) { [weak self] in
            let relations = noteStore.knowledgeRelations(
                for: noteURL,
                currentBody: body,
                roots: roots,
                suggestionLimit: 3,
                cancellationCheck: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      generation == self.noteLinksRefreshGeneration,
                      self.selectedURL?.standardizedFileURL == noteURL.standardizedFileURL else {
                    return
                }
                self.noteLinksRefreshTask = nil
                self.noteLinksView.update(relations)
                self.updateKnowledgeNavigationControls()
            }
        }
        noteLinksRefreshTask = task
    }

    private func refreshNoteLinksAfterSave(
        for noteURL: URL,
        replacing previousURL: URL?,
        body: String
    ) {
        refreshNoteLinks(for: noteURL, body: body)
        knowledgeGraphWindowController?.reload()
    }

    private func acceptKnowledgeSuggestion(_ item: KnowledgeRelationItem) {
        guard selectedScope != .trash, let sourceURL = selectedURL else { return }
        let link = noteStore.markdownKnowledgeLink(
            from: sourceURL,
            to: item.url,
            title: item.title
        )
        let insertionLocation = editorTextView.string.utf16.count
        editorTextView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
        let prefix = insertionLocation == 0 ? "" : "\n\n"
        replaceSelectionWithRenderedMarkdown(
            "\(prefix)- 关联：\(link)",
            renderingBaseURL: sourceURL
        )
        refreshNoteLinks(for: sourceURL, body: normalizedEditorMarkdownBody())
        NSAccessibility.post(
            element: noteLinksView,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "已将 \(item.title) 加入明确关联",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func openKnowledgeRelation(at url: URL) {
        guard let currentURL = selectedURL?.standardizedFileURL,
              currentURL != url.standardizedFileURL else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        do {
            try openMarkdownDocumentForLibrary(at: url)
            knowledgeBackStack.append(currentURL)
            knowledgeForwardStack.removeAll()
            updateKnowledgeNavigationControls()
            announceKnowledgeNavigation(title: url.deletingPathExtension().lastPathComponent)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
        }
    }

    var canShowKnowledgeGraphForLibrary: Bool {
        selectedURL != nil
    }

    func showKnowledgeGraphForLibrary() {
        guard let selectedURL else { return }
        let controller: KnowledgeGraphWindowController
        if let existing = knowledgeGraphWindowController {
            controller = existing
        } else {
            let noteStore = noteStore
            let created = KnowledgeGraphWindowController(
                noteStore: noteStore,
                rootsProvider: {
                    noteStore.preferredDirectories
                }
            )
            created.onOpenNode = { [weak self] url in
                self?.openKnowledgeRelation(at: url)
            }
            created.onClose = { [weak self, weak created] in
                guard self?.knowledgeGraphWindowController === created else { return }
                self?.knowledgeGraphWindowController = nil
            }
            knowledgeGraphWindowController = created
            controller = created
        }
        controller.show(rootURL: selectedURL)
    }

    private func goBackInKnowledgeRelations() {
        guard let targetURL = knowledgeBackStack.last,
              let currentURL = selectedURL?.standardizedFileURL else {
            return
        }
        do {
            try openMarkdownDocumentForLibrary(at: targetURL)
            knowledgeBackStack.removeLast()
            knowledgeForwardStack.append(currentURL)
            updateKnowledgeNavigationControls()
            announceKnowledgeNavigation(title: targetURL.deletingPathExtension().lastPathComponent)
        } catch {
            presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
        }
    }

    private func goForwardInKnowledgeRelations() {
        guard let targetURL = knowledgeForwardStack.last,
              let currentURL = selectedURL?.standardizedFileURL else {
            return
        }
        do {
            try openMarkdownDocumentForLibrary(at: targetURL)
            knowledgeForwardStack.removeLast()
            knowledgeBackStack.append(currentURL)
            updateKnowledgeNavigationControls()
            announceKnowledgeNavigation(title: targetURL.deletingPathExtension().lastPathComponent)
        } catch {
            presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
        }
    }

    private func updateKnowledgeNavigationControls() {
        noteLinksView.updateNavigation(
            canGoBack: !knowledgeBackStack.isEmpty,
            canGoForward: !knowledgeForwardStack.isEmpty
        )
    }

    private func announceKnowledgeNavigation(title: String) {
        NSAccessibility.post(
            element: noteLinksView,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "已打开 \(title)",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func cancelKnowledgeSynthesisForSelectionChange(to nextURL: URL?) {
        let currentPath = selectedURL?.standardizedFileURL.path
        let nextPath = nextURL?.standardizedFileURL.path
        guard currentPath != nextPath, knowledgeSynthesisTask != nil else { return }
        knowledgeSynthesisTask?.cancel()
        knowledgeSynthesisTask = nil
        knowledgeSynthesisGeneration += 1
        noteLinksView.setSynthesisInProgress(false)
    }

    private func setSelectedURLForLibrary(_ nextURL: URL?) {
        cancelKnowledgeSynthesisForSelectionChange(to: nextURL)
        selectedURL = nextURL
        knowledgeGraphWindowController?.setRoot(nextURL, reload: true)
    }

    private func generateHigherLayerDraft(targetLayer: KnowledgeLayer) {
        guard selectedScope != .trash,
              targetLayer == .line || targetLayer == .plane else {
            return
        }
        guard noteStore.aiEnabled else {
            presentErrorAlert(message: "AI 功能未启用", details: AIError.disabled.localizedDescription)
            return
        }
        guard let executableURL = CodexRuntimeLocator.resolve(
            configuredPath: noteStore.aiCodexExecutablePath
        ) else {
            presentErrorAlert(
                message: "未找到本机 Codex",
                details: AIError.providerNotConfigured.localizedDescription
            )
            return
        }

        do {
            try saveCurrentNoteIfNeeded()
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return
        }
        guard let currentURL = selectedURL?.standardizedFileURL else { return }

        let currentBody: String
        do {
            currentBody = try noteStore.loadNote(at: currentURL).body
        } catch {
            presentErrorAlert(message: "无法读取当前笔记", details: error.localizedDescription)
            return
        }
        let roots = noteStore.preferredDirectories + [currentURL.deletingLastPathComponent()]
        let relations = noteStore.knowledgeRelations(
            for: currentURL,
            currentBody: currentBody,
            roots: roots,
            suggestionLimit: 0
        )
        let relationItems = relations.related
            + relations.children
        var sourceURLs = [currentURL]
        var seenPaths = Set([currentURL.path])
        for item in relationItems where seenPaths.insert(item.url.standardizedFileURL.path).inserted {
            sourceURLs.append(item.url.standardizedFileURL)
            if sourceURLs.count == 6 { break }
        }
        let synthesisSourceURLs = sourceURLs
        let sourceNames = synthesisSourceURLs.map {
            $0.deletingPathExtension().lastPathComponent
        }.joined(separator: "、")
        let confirmation = NSAlert()
        confirmation.messageText = "将 \(synthesisSourceURLs.count) 篇笔记交给 Codex 生成草案？"
        confirmation.informativeText = "发送范围：\(sourceNames)。只包含当前笔记和已明确关联的下层/同层笔记；Codex 进程会被系统限制在临时目录，不能读取知识库中的其他文件。"
        confirmation.addButton(withTitle: "开始生成")
        confirmation.addButton(withTitle: "取消")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        let noteStore = noteStore
        let provider = CodexAIProvider(executableURL: executableURL)
        knowledgeSynthesisTask?.cancel()
        knowledgeSynthesisGeneration += 1
        let generation = knowledgeSynthesisGeneration
        let previousStatus = statusLabel.stringValue
        noteLinksView.setSynthesisInProgress(true)
        updateEditorStatus("正在生成\(targetLayer.displayName)层草案…")
        knowledgeSynthesisTask = Task { [weak self] in
            do {
                let sources = try await Task.detached(priority: .userInitiated) {
                    try synthesisSourceURLs.map { url -> KnowledgeSynthesisSource in
                        let note = try noteStore.loadNote(at: url)
                        return KnowledgeSynthesisSource(
                            title: note.title.isEmpty
                                ? url.deletingPathExtension().lastPathComponent
                                : note.title,
                            markdown: note.body
                        )
                    }
                }.value
                try Task.checkCancellation()
                let output = try await provider.generate(request: KnowledgeSynthesisRequest(
                    targetLayer: targetLayer,
                    sources: sources
                ))
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          generation == self.knowledgeSynthesisGeneration,
                          self.selectedURL?.standardizedFileURL == currentURL else {
                        return
                    }
                    self.knowledgeSynthesisTask = nil
                    self.noteLinksView.setSynthesisInProgress(false)
                    self.updateEditorStatus(previousStatus)
                    self.presentKnowledgeSynthesis(
                        output,
                        targetLayer: targetLayer,
                        sourceURLs: synthesisSourceURLs
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self,
                          generation == self.knowledgeSynthesisGeneration else {
                        return
                    }
                    self.knowledgeSynthesisTask = nil
                    self.noteLinksView.setSynthesisInProgress(false)
                    self.updateEditorStatus(previousStatus)
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          generation == self.knowledgeSynthesisGeneration,
                          self.selectedURL?.standardizedFileURL == currentURL else {
                        return
                    }
                    self.knowledgeSynthesisTask = nil
                    self.noteLinksView.setSynthesisInProgress(false)
                    self.updateEditorStatus("草案生成失败", kind: .failure)
                    self.presentErrorAlert(message: "无法生成上层草案", details: error.localizedDescription)
                }
            }
        }
    }

    private func presentKnowledgeSynthesis(
        _ output: String,
        targetLayer: KnowledgeLayer,
        sourceURLs: [URL]
    ) {
        let document = MarkdownEditorDocument.parse(editorText: output)
        guard !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentErrorAlert(message: "无法创建草案", details: AIError.invalidResponse.localizedDescription)
            return
        }

        let alert = NSAlert()
        alert.messageText = "生成\(targetLayer.displayName)层草案"
        alert.informativeText = "AI 基于 \(sourceURLs.count) 篇笔记生成。只有点击“创建草案”后才会写入，原笔记不会被改动。"
        alert.alertStyle = .informational
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 280))
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = output
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "创建草案")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            window?.makeFirstResponder(editorTextView)
            return
        }

        let referenceSourceURL = noteStore.notesDirectory
            .appendingPathComponent("Knowledge-Synthesis.md")
        let sourceLinks = sourceURLs.enumerated().map { index, url in
            let title = (try? noteStore.loadNote(at: url).title)
                .flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                }
                ?? url.deletingPathExtension().lastPathComponent
            let link = noteStore.markdownKnowledgeLink(
                from: referenceSourceURL,
                to: url,
                title: title
            )
            return "- S\(index + 1): \(link)"
        }.joined(separator: "\n")
        let body = """
        \(document.body)

        ## 来源笔记

        \(sourceLinks)
        """
        do {
            let savedURL = try noteStore.saveNewNote(
                title: document.title,
                body: body,
                tags: ["层级/\(targetLayer.displayName)", "AI草案", "待审核"],
                in: noteStore.notesDirectory
            )
            recordInternalFileSystemChanges(for: [savedURL])
            onSave(savedURL)
            try openMarkdownDocumentForLibrary(at: savedURL)
            announceKnowledgeNavigation(title: document.title)
        } catch {
            presentErrorAlert(message: "无法创建草案", details: error.localizedDescription)
        }
    }

    private func applyDocument(
        title: String,
        body: String,
        tags: [String],
        renderedBody: NSAttributedString? = nil,
        preservedSelection: NSRange? = nil
    ) {
        editorSearchHighlightRefreshTask?.cancel()
        editorSearchHighlightRefreshTask = nil
        suppressEditorChanges = true
        isEditorShowingMarkdownSource = false
        editorTextView.isRichText = true
        editorTextView.markdownPasteTheme = theme
        titleField.stringValue = title
        selectedTags = tags
        let unifiedMarkdown = MarkdownEditorDocument.composeEditorText(
            title: title,
            body: body,
            hasMetadataTags: !tags.isEmpty
        )
        editorTextView.replaceAllContent(with:
            renderedBody ?? MarkdownRichTextCodec.render(
                markdown: unifiedMarkdown,
                theme: theme,
                baseURL: selectedURL,
                imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
            )
        )
        editorTextView.setMetadataTags(tags) { [weak self] tag in
            self?.removeSelectedMetadataTag(tag)
        }
        editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
        let requestedSelection = preservedSelection ?? NSRange(location: 0, length: 0)
        let contentLength = editorTextView.textStorage?.length ?? 0
        let location = min(requestedSelection.location, contentLength)
        let length = min(requestedSelection.length, max(contentLength - location, 0))
        editorTextView.setSelectedRange(NSRange(location: location, length: length))
        suppressEditorChanges = false
        updateWordCount()
        layoutEditorStatusLabel()
    }

    private func updateWordCount() {
        updateWordCount(in: visibleEditorMetadata().body)
    }

    private func updateWordCount(in body: String) {
        let count = MarkdownEditorDocument.wordCount(in: body)
        wordCountLabel.stringValue = "\(count) 字"
        wordCountLabel.setAccessibilityValue(wordCountLabel.stringValue)
    }

    private func visibleEditorMetadata() -> (title: String, body: String) {
        let visibleText = editorTextView.string
        if isEditorShowingMarkdownSource {
            let document = MarkdownEditorDocument.parse(
                editorText: visibleText,
                tags: selectedTags
            )
            return (document.title, document.body)
        }

        let text = visibleText as NSString
        guard text.length > 0 else { return ("", "") }
        let titleParagraph = text.paragraphRange(for: NSRange(location: 0, length: 0))
        let title = text.substring(with: titleParagraph)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyStart = NSMaxRange(titleParagraph)
        let body = bodyStart < text.length ? text.substring(from: bodyStart) : ""
        return (title, body)
    }

    private func normalizedEditorMarkdownBody() -> String {
        normalizedMarkdownBody(currentEditorMarkdownBody())
    }

    private func replaceUnifiedEditorTitle(_ title: String) {
        let document = currentEditorDocument()
        let markdown = MarkdownEditorDocument.composeEditorText(
            title: title,
            body: document.body,
            hasMetadataTags: !selectedTags.isEmpty
        )
        let selection = editorTextView.selectedRange()
        suppressEditorChanges = true
        editorTextView.replaceAllContent(with:
            MarkdownRichTextCodec.render(
                markdown: markdown,
                theme: theme,
                baseURL: selectedURL,
                imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
            )
        )
        editorTextView.setMetadataTags(selectedTags) { [weak self] tag in
            self?.removeSelectedMetadataTag(tag)
        }
        suppressEditorChanges = false
        let contentLength = editorTextView.textStorage?.length ?? 0
        editorTextView.setSelectedRange(NSRange(location: min(selection.location, contentLength), length: 0))
    }

    private func normalizeUnifiedTitleLineFormatting() {
        guard !suppressEditorChanges,
              !isEditorShowingMarkdownSource,
              let storage = editorTextView.textStorage else {
            return
        }
        guard storage.length > 0 else {
            editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
            return
        }

        let firstParagraph = (storage.string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        let hasTrailingNewline = (storage.string as NSString)
            .substring(with: firstParagraph)
            .hasSuffix("\n")
        let titleRange = NSRange(
            location: 0,
            length: max(firstParagraph.length - (hasTrailingNewline ? 1 : 0), 0)
        )
        guard titleRange.length > 0 else { return }

        let headingAttributes = theme.baseAttributes(for: .heading(level: 1))
        suppressEditorChanges = true
        storage.addAttributes(headingAttributes, range: titleRange)
        suppressEditorChanges = false
    }

    private func normalizedMarkdownBody(_ body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cachedLoadedNote(for note: NoteSearchResult) -> LoadedLibraryNoteCacheEntry? {
        loadedNoteCache.entry(forKey: loadedNoteCacheKey(for: note.url))
    }

    @discardableResult
    private func cacheLoadedNote(
        _ loaded: LoadedLibraryNote,
        for note: NoteSearchResult,
        fileModifiedAt: Date? = nil
    ) -> LoadedLibraryNoteCacheEntry {
        let modifiedAt = fileModifiedAt ?? note.modifiedAt
        let cached = LoadedLibraryNoteCacheEntry(
            loaded: loaded,
            fileModifiedAt: modifiedAt
        )
        loadedNoteCache.insert(cached, forKey: loadedNoteCacheKey(for: note.url))
        let noteStore = noteStore
        let noteURL = note.url
        let createdAt = note.createdAt
        launchNoteCacheQueue.async {
            noteStore.cacheLibraryLaunchNote(
                loaded,
                at: noteURL,
                modifiedAt: modifiedAt,
                createdAt: createdAt
            )
        }
        return cached
    }

    private func scheduleCachedNoteValidation(
        _ cached: LoadedLibraryNoteCacheEntry,
        for note: NoteSearchResult
    ) {
        let generation = noteLoadGeneration
        let editorRevision = editorContentRevision
        let fileModificationDateLoader = fileModificationDateLoader
        let noteLoader = noteLoader
        let cachedModifiedAt = cached.fileModifiedAt
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let currentModifiedAt = fileModificationDateLoader(note.url),
                  !Task.isCancelled else {
                await MainActor.run {
                    guard let self, generation == self.noteLoadGeneration else { return }
                    self.noteLoadTask = nil
                }
                return
            }

            guard abs(currentModifiedAt.timeIntervalSince(cachedModifiedAt)) >= 0.001 else {
                await MainActor.run {
                    guard let self, generation == self.noteLoadGeneration else { return }
                    self.noteLoadTask = nil
                }
                return
            }

            let result = Result<LoadedLibraryNote, Error> {
                try noteLoader(note.url)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      generation == self.noteLoadGeneration,
                      editorRevision == self.editorContentRevision,
                      self.selectedNoteStillMatchesInitialLoad(note) else {
                    return
                }
                self.noteLoadTask = nil
                self.loadedNoteCache.removeEntry(forKey: self.loadedNoteCacheKey(for: note.url))
                guard !self.isDirty else { return }
                switch result {
                case .success(let loaded):
                    let refreshed = self.cacheLoadedNote(
                        loaded,
                        for: note,
                        fileModifiedAt: currentModifiedAt
                    )
                    self.applyLoadedNote(refreshed, for: note, preservingEditorSelection: true)
                case .failure(let error):
                    self.presentErrorAlert(message: "无法刷新笔记", details: error.localizedDescription)
                }
            }
        }
        noteLoadTask = task
    }

    private func prefetchAdjacentNotes(around note: NoteSearchResult) {
        guard let index = notes.firstIndex(where: {
            $0.url.standardizedFileURL.path == note.url.standardizedFileURL.path
        }) else { return }

        let lowerBound = max(0, index - 2)
        let upperBound = min(notes.count, index + 3)
        let candidates = notes[lowerBound..<upperBound].filter {
            $0.url.standardizedFileURL.path != note.url.standardizedFileURL.path
                && loadedNoteCache.entry(forKey: loadedNoteCacheKey(for: $0.url)) == nil
        }
        guard !candidates.isEmpty else { return }

        let noteStore = noteStore
        let cache = loadedNoteCache
        notePrefetchTask?.cancel()
        let task = Task.detached(priority: .utility) {
            for candidate in candidates {
                guard !Task.isCancelled else { return }
                let key = candidate.url.standardizedFileURL.path as NSString
                guard cache.entry(forKey: key) == nil,
                      let loaded = try? noteStore.loadNoteDocument(at: candidate.url) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                let modifiedAt = Self.fileModificationDate(at: candidate.url) ?? candidate.modifiedAt
                cache.insert(
                    LoadedLibraryNoteCacheEntry(loaded: loaded, fileModifiedAt: modifiedAt),
                    forKey: key
                )
            }
        }
        notePrefetchTask = task
    }

    private func loadedNoteCacheKey(for url: URL) -> NSString {
        url.path as NSString
    }

    nonisolated private static func fileModificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func fileModificationDate(at url: URL) -> Date? {
        Self.fileModificationDate(at: url)
    }

    func hasCachedLoadedNoteForLibrary(at url: URL) -> Bool {
        loadedNoteCache.entry(forKey: loadedNoteCacheKey(for: url)) != nil
    }

    func waitForActiveNoteLoadForLibrary() async {
        let task = noteLoadTask
        await task?.value
    }

    var hasReleasedDeferredLaunchWorkForLibrary: Bool {
        hasReleasedDeferredLaunchWork
    }

    func waitForNoteLinksRefreshForLibrary() async {
        let task = noteLinksRefreshTask
        await task?.value
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
        var foundMatch = false
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
            foundMatch = true

            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        hasEditorSearchHighlights = foundMatch
    }

    func removeEditorSearchHighlights() {
        guard hasEditorSearchHighlights else { return }
        guard let storage = editorTextView.textStorage, storage.length > 0 else {
            hasEditorSearchHighlights = false
            return
        }
        editorSearchHighlightRemovalScanCount += 1
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
            storage.removeAttribute(.qmSearchHighlight, range: range)
            var location = range.location
            while location < NSMaxRange(range) {
                var effectiveRange = NSRange(location: 0, length: 0)
                let isDocumentHighlight = (storage.attribute(
                    .qmHighlight,
                    at: location,
                    effectiveRange: &effectiveRange
                ) as? Bool) == true
                let clippedRange = NSIntersectionRange(range, effectiveRange)
                if isDocumentHighlight {
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor.systemYellow.withAlphaComponent(0.38),
                        range: clippedRange
                    )
                } else {
                    storage.removeAttribute(.backgroundColor, range: clippedRange)
                }
                location = NSMaxRange(clippedRange)
            }
        }
        hasEditorSearchHighlights = false
    }

    var editorSearchHighlightRemovalScanCountForLibrary: Int {
        editorSearchHighlightRemovalScanCount
    }

    private func markDirty() {
        guard !suppressEditorChanges, selectedScope != .trash else { return }
        editorContentRevision &+= 1
        let becameDirty = !isDirty
        isDirty = true
        if becameDirty {
            updateToolbarActionState()
        }
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

        enqueueBackgroundAutosave()
    }

    private func enqueueBackgroundAutosave() {
        if backgroundAutosaveIsActive {
            backgroundAutosaveNeedsLatest = true
            return
        }
        let editorSnapshot: LibraryBackgroundEditorSnapshot
        if isEditorShowingMarkdownSource {
            editorSnapshot = LibraryBackgroundEditorSnapshot(
                sourceMarkdown: editorTextView.string,
                theme: theme
            )
        } else {
            editorSnapshot = LibraryBackgroundEditorSnapshot(
                attributedMarkdown: editorTextView.attributedString(),
                theme: theme
            )
        }

        backgroundAutosaveGeneration &+= 1
        backgroundAutosaveIsActive = true
        let generation = backgroundAutosaveGeneration
        let editorRevision = editorContentRevision
        let previousURL = selectedURL
        let tags = selectedTags
        let targetDirectory = previousURL?.deletingLastPathComponent() ?? targetDirectoryForNewNote()
        let updatesInPlace = previousURL.map {
            externallyOpenedDocumentsByPath[$0.path] != nil
        } ?? false
        let expectedContents = selectedSourceContents
        backgroundAutosaveActiveEditorRevision = editorRevision
        backgroundAutosaveActivePreviousURL = previousURL
        cancelSourceSnapshotValidation()
        let noteStore = noteStore
        let resultStore = backgroundAutosaveResultStore
        let willPersist = backgroundAutosaveWillPersist
        autosavePersistenceQueue.async { [weak self] in
            willPersist()
            let result = Result {
                let document = MarkdownEditorDocument.parse(
                    editorText: editorSnapshot.markdown(),
                    tags: tags
                )
                let title = document.title
                let snapshot = LibraryBackgroundSaveSnapshot(
                    generation: generation,
                    editorRevision: editorRevision,
                    previousURL: previousURL,
                    title: title,
                    body: document.body,
                    tags: tags,
                    targetDirectory: targetDirectory,
                    updatesInPlace: updatesInPlace,
                    expectedContents: expectedContents
                )
                return try Self.performBackgroundSave(snapshot, noteStore: noteStore)
            }
            resultStore.insert(LibraryBackgroundSaveResultBox(result), for: generation)
            DispatchQueue.main.async { [weak self] in
                self?.finishBackgroundAutosave(generation: generation)
            }
        }
    }

    private nonisolated static func performBackgroundSave(
        _ snapshot: LibraryBackgroundSaveSnapshot,
        noteStore: NoteStore
    ) throws -> LibraryBackgroundSaveSuccess {
        let savedURL: URL
        let sourceContents: String
        let conflictedOriginalURL: URL?
        if let previousURL = snapshot.previousURL {
            guard let expectedContents = snapshot.expectedContents else {
                throw CocoaError(.fileReadUnknown)
            }
            let result = try noteStore.updateNote(
                at: previousURL.standardizedFileURL,
                title: snapshot.title,
                body: snapshot.body,
                tags: snapshot.tags,
                expectedContents: expectedContents,
                updatesInPlace: snapshot.updatesInPlace
            )
            savedURL = result.url
            sourceContents = result.sourceContents
            conflictedOriginalURL = result.conflictedOriginalURL
        } else {
            savedURL = try noteStore.saveNewNote(
                title: snapshot.title,
                body: snapshot.body,
                tags: snapshot.tags,
                in: snapshot.targetDirectory
            )
            sourceContents = try String(contentsOf: savedURL, encoding: .utf8)
            conflictedOriginalURL = nil
        }

        let savedResourceValues = try? savedURL.resourceValues(forKeys: [.contentModificationDateKey])
        let savedAt = savedResourceValues?.contentModificationDate ?? Date()
        return LibraryBackgroundSaveSuccess(
            snapshot: snapshot,
            savedURL: savedURL,
            savedAt: savedAt,
            snippet: libraryFirstMeaningfulLine(from: snapshot.body) ?? "",
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: snapshot.body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(
                in: snapshot.body,
                relativeTo: savedURL
            ),
            sourceContents: sourceContents,
            conflictedOriginalURL: conflictedOriginalURL
        )
    }

    private func finishBackgroundAutosave(generation: Int) {
        let boxedResult = backgroundAutosaveResultStore.remove(generation: generation)
        guard let boxedResult else { return }
        backgroundAutosaveIsActive = false
        backgroundAutosaveActiveEditorRevision = nil
        backgroundAutosaveActivePreviousURL = nil

        switch boxedResult.result {
        case .success(let success):
            applyBackgroundSaveSuccess(success)
            if backgroundAutosaveNeedsLatest, isDirty {
                backgroundAutosaveNeedsLatest = false
                enqueueBackgroundAutosave()
            } else {
                backgroundAutosaveNeedsLatest = false
            }
        case .failure:
            backgroundAutosaveNeedsLatest = false
            updateEditorStatus(
                "自动保存失败，编辑仍保留",
                kind: .failure,
                toolTip: "按 Command-S 重试保存",
                announcesChange: true
            )
            NSSound.beep()
        }
        flushDeferredFileSystemChangesAfterAutosave()
    }

    private func applyBackgroundSaveSuccess(_ success: LibraryBackgroundSaveSuccess) {
        let snapshot = success.snapshot
        let changedURLs = [snapshot.previousURL, success.savedURL].compactMap { $0 }
        recordInternalFileSystemChanges(for: changedURLs)
        if let previousURL = snapshot.previousURL {
            loadedNoteCache.removeEntry(forKey: loadedNoteCacheKey(for: previousURL))
        }
        loadedNoteCache.removeEntry(forKey: loadedNoteCacheKey(for: success.savedURL))
        let sourceCountsChanged = updateSourceCountSnapshotAfterSave(
            previousURL: success.conflictedOriginalURL == nil ? snapshot.previousURL : nil,
            savedURL: success.savedURL,
            title: snapshot.title,
            tags: snapshot.tags,
            modifiedAt: success.savedAt,
            snippet: success.snippet,
            hasAttachments: success.hasAttachments,
            thumbnailURL: success.thumbnailURL
        )
        if let conflictedOriginalURL = success.conflictedOriginalURL,
           externallyOpenedDocumentsByPath[conflictedOriginalURL.standardizedFileURL.path] != nil,
           let recoveryNote = sourceCountSnapshot.first(where: {
               $0.url.standardizedFileURL == success.savedURL.standardizedFileURL
           }) {
            externallyOpenedDocumentsByPath[success.savedURL.standardizedFileURL.path] = recoveryNote
        }
        let isCurrentDocument = selectedScope != .trash
            && selectedURL?.path == snapshot.previousURL?.path
        guard isCurrentDocument else {
            onSave(success.savedURL)
            return
        }

        setSelectedURLForLibrary(success.savedURL)
        selectedSourceContents = success.sourceContents
        activeSearchSession = nil
        isCreatingNewNote = false
        isDirty = editorContentRevision != snapshot.editorRevision
        refreshVisibleNoteListAfterSave(
            selecting: success.savedURL,
            replacing: snapshot.previousURL,
            isNewNote: snapshot.previousURL == nil,
            refreshesSourceCounts: sourceCountsChanged
        )
        if success.conflictedOriginalURL != nil {
            updateEditorStatus(
                "检测到外部修改，本地编辑已保存为冲突副本",
                kind: .failure,
                toolTip: "原文件保持不变；当前编辑已切换到冲突副本",
                announcesChange: true
            )
        } else if !isDirty {
            updateEditorStatus(editorEditedDateText(for: success.savedAt))
        }
        refreshNoteLinksAfterSave(
            for: success.savedURL,
            replacing: success.conflictedOriginalURL == nil ? snapshot.previousURL : nil,
            body: snapshot.body
        )
        onSave(success.savedURL)
        updateToolbarActionState()
    }

    private func drainBackgroundAutosaves() {
        while backgroundAutosaveIsActive {
            autosavePersistenceQueue.sync {}
            for generation in backgroundAutosaveResultStore.pendingGenerations() {
                finishBackgroundAutosave(generation: generation)
            }
        }
    }

    private func saveCurrentNoteIfNeeded(allowBackgroundHandoff: Bool = false) throws {
        guard isDirty else { return }
        if allowBackgroundHandoff, handOffCurrentEditorToBackgroundAutosave() {
            return
        }
        _ = try saveCurrentNote(force: false)
    }

    private func handOffCurrentEditorToBackgroundAutosave() -> Bool {
        if !backgroundAutosaveIsActive {
            autosaveCurrentNote()
        }
        return backgroundAutosaveIsActive
            && backgroundAutosaveActiveEditorRevision == editorContentRevision
            && backgroundAutosaveActivePreviousURL?.path == selectedURL?.path
    }

    private func serializedEditorMarkdown() -> String {
        if isEditorShowingMarkdownSource {
            return editorTextView.string
        }
        return MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
    }

    private func currentEditorDocument() -> MarkdownEditorDocument {
        MarkdownEditorDocument.parse(
            editorText: serializedEditorMarkdown(),
            tags: selectedTags
        )
    }

    private func currentEditorMarkdownBody() -> String {
        currentEditorDocument().body
    }

    private func updateEditorStatus(
        _ text: String,
        kind: EditorStatusKind = .normal,
        toolTip: String? = nil,
        announcesChange: Bool = false
    ) {
        statusLabel.stringValue = text
        statusLabel.toolTip = toolTip
        statusLabel.setAccessibilityValue(text)
        switch kind {
        case .normal:
            statusLabel.textColor = panelTertiaryTextColor()
        case .failure:
            statusLabel.textColor = .systemRed
        }
        if announcesChange {
            NSAccessibility.post(element: statusLabel, notification: .valueChanged)
        }
        layoutEditorStatusLabel()
    }

    private func layoutEditorStatusLabel() {
        guard let layoutManager = editorTextView.layoutManager,
              let textContainer = editorTextView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let horizontalInset: CGFloat = 20
        let contentBottom = editorTextView.textContainerInset.height + usedRect.maxY
        let viewportHeight = editorTextView.enclosingScrollView?.contentView.bounds.height ?? 0
        let rowHeight = LibraryNotesLayout.editorDateRowHeight
        let topGap = LibraryNotesLayout.editorBottomInset
        let bottomGap = LibraryNotesLayout.editorStatusBottomGap
        // Pin the label to the bottom of the visible editor area when the
        // content is short; otherwise let the label flow after the content.
        let pinToBottom = viewportHeight > 0 && contentBottom + topGap + rowHeight + bottomGap < viewportHeight
        let statusTop: CGFloat
        let documentHeight: CGFloat
        if pinToBottom {
            statusTop = viewportHeight - rowHeight - bottomGap
            documentHeight = viewportHeight
        } else {
            statusTop = contentBottom + topGap
            documentHeight = statusTop + rowHeight + bottomGap
        }
        editorTextView.minimumScrollableContentHeight = documentHeight
        editorTextView.minSize = NSSize(width: 0, height: documentHeight)
        if abs(editorTextView.frame.height - documentHeight) > 0.5 {
            var frame = editorTextView.frame
            frame.size.height = documentHeight
            editorTextView.frame = frame
        }
        statusLabel.frame = NSRect(
            x: horizontalInset + LibraryNotesLayout.editorStatusHorizontalOffset,
            y: statusTop,
            width: max(0, editorTextView.bounds.width - (horizontalInset * 2)),
            height: rowHeight
        )
        wordCountLabel.frame = NSRect(
            x: max(horizontalInset, editorTextView.bounds.width - 112),
            y: statusTop,
            width: 88,
            height: rowHeight
        )
    }

    @discardableResult
    private func saveCurrentNote(force: Bool) throws -> URL? {
        drainBackgroundAutosaves()
        guard force || isDirty else { return selectedURL }
        guard selectedScope != .trash else { return selectedURL }
        autosaveTask?.cancel()
        autosaveTask = nil
        cancelSourceSnapshotValidation()

        let document = currentEditorDocument()
        let body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = document.title
        guard selectedURL != nil || isCreatingNewNote || !title.isEmpty || !body.isEmpty else { return nil }

        let previousURL = selectedURL
        let savedURL: URL
        let sourceContents: String
        let conflictedOriginalURL: URL?
        if let previousURL {
            loadedNoteCache.removeEntry(forKey: loadedNoteCacheKey(for: previousURL))
            guard let expectedContents = selectedSourceContents else {
                throw CocoaError(.fileReadUnknown)
            }
            let result = try noteStore.updateNote(
                at: previousURL,
                title: title,
                body: body,
                tags: selectedTags,
                expectedContents: expectedContents,
                updatesInPlace: externallyOpenedDocumentsByPath[
                    previousURL.standardizedFileURL.path
                ] != nil
            )
            savedURL = result.url
            sourceContents = result.sourceContents
            conflictedOriginalURL = result.conflictedOriginalURL
        } else {
            savedURL = try noteStore.saveNewNote(
                title: title,
                body: body,
                tags: selectedTags,
                in: targetDirectoryForNewNote()
            )
            sourceContents = try String(contentsOf: savedURL, encoding: .utf8)
            conflictedOriginalURL = nil
        }

        let changedURLs = [previousURL, savedURL].compactMap { $0 }
        recordInternalFileSystemChanges(for: changedURLs)
        setSelectedURLForLibrary(savedURL)
        selectedSourceContents = sourceContents
        activeSearchSession = nil
        isCreatingNewNote = false
        isDirty = false
        let savedAt = (try? FileManager.default.attributesOfItem(atPath: savedURL.path)[.modificationDate])
            as? Date ?? Date()
        let sourceCountsChanged = updateSourceCountSnapshotAfterSave(
            previousURL: conflictedOriginalURL == nil ? previousURL : nil,
            savedURL: savedURL,
            title: title,
            tags: selectedTags,
            modifiedAt: savedAt,
            snippet: libraryFirstMeaningfulLine(from: body) ?? "",
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: body, relativeTo: savedURL)
        )
        if let conflictedOriginalURL,
           externallyOpenedDocumentsByPath[conflictedOriginalURL.standardizedFileURL.path] != nil,
           let recoveryNote = sourceCountSnapshot.first(where: {
               $0.url.standardizedFileURL == savedURL.standardizedFileURL
           }) {
            externallyOpenedDocumentsByPath[savedURL.standardizedFileURL.path] = recoveryNote
        }
        refreshVisibleNoteListAfterSave(
            selecting: savedURL,
            replacing: conflictedOriginalURL == nil ? previousURL : nil,
            isNewNote: previousURL == nil,
            refreshesSourceCounts: sourceCountsChanged
        )
        if conflictedOriginalURL != nil {
            updateEditorStatus(
                "检测到外部修改，本地编辑已保存为冲突副本",
                kind: .failure,
                toolTip: "原文件保持不变；当前编辑已切换到冲突副本",
                announcesChange: true
            )
        } else {
            updateEditorStatus(editorEditedDateText(for: savedAt))
        }
        refreshNoteLinksAfterSave(
            for: savedURL,
            replacing: conflictedOriginalURL == nil ? previousURL : nil,
            body: body
        )
        onSave(savedURL)
        updateToolbarActionState()
        return savedURL
    }

    @discardableResult
    private func updateSourceCountSnapshotAfterSave(
        previousURL: URL?,
        savedURL: URL,
        title: String,
        tags: [String],
        modifiedAt: Date,
        snippet: String,
        hasAttachments: Bool,
        thumbnailURL: URL?
    ) -> Bool {
        let previousPath = previousURL?.path
        let savedPath = savedURL.path
        let previousNote = sourceCountSnapshot.first {
            $0.url.path == previousPath || $0.url.path == savedPath
        }
        let previousTagKeys = Set(previousNote?.tags.map {
            $0.folding(options: [.caseInsensitive], locale: .current)
        } ?? [])
        let savedTagKeys = Set(tags.map {
            $0.folding(options: [.caseInsensitive], locale: .current)
        })
        let sourceCountsChanged = previousNote == nil
            || previousPath != savedPath
            || previousTagKeys != savedTagKeys
        let updatedNote = NoteSearchResult(
            url: savedURL,
            title: title,
            snippet: snippet,
            modifiedAt: modifiedAt,
            createdAt: previousNote?.createdAt ?? modifiedAt,
            tags: tags,
            hasAttachments: hasAttachments,
            thumbnailURL: thumbnailURL
        )
        if let previousPath,
           externallyOpenedDocumentsByPath.removeValue(forKey: previousPath) != nil {
            externallyOpenedDocumentsByPath[savedPath] = updatedNote
        }
        LibraryNoteListProjection.upsertByModifiedDate(
            updatedNote,
            into: &sourceCountSnapshot,
            replacingPaths: Set([
                previousURL?.path,
                previousPath,
                savedURL.path,
                savedPath
            ].compactMap { $0 }),
            limit: Self.sourceCountSnapshotLimit
        )
        persistCurrentLibraryPresentationCache()
        return sourceCountsChanged
    }

    private func refreshVisibleNoteListAfterSave(
        selecting savedURL: URL,
        replacing previousURL: URL?,
        isNewNote: Bool,
        refreshesSourceCounts: Bool
    ) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            scheduleSearchResultReload(query: query, selecting: savedURL)
            return
        }

        notes = notesForSelectedScope(limit: 240, allNotes: sourceCountSnapshot)
        let refreshedPaths = isNewNote
            ? Set<String>()
            : Set([previousURL, savedURL].compactMap { $0?.path })
        rebuildNoteListRowsForDisplayOptions(
            mutationAnimation: isNewNote ? .insertion : nil,
            refreshedNotePaths: refreshedPaths
        )
        if isNewNote,
           let row = rowIndex(for: savedURL.path) {
            suppressSelectionChanges = true
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            suppressSelectionChanges = false
            synchronizeGallerySelectionFromTable()
        }
        updateNoteListHeader(query: "")
        if refreshesSourceCounts {
            scheduleSourceCountRefresh(using: sourceCountSnapshot)
        }
    }

    func waitForSourceCountRefreshForLibrary() async {
        await sourceCountRefreshTask?.value
    }

    private func removeNotesFromSourceSnapshot(at urls: [URL]) {
        let removedPaths = Set(urls.map { $0.standardizedFileURL.path })
        sourceCountSnapshot.removeAll { removedPaths.contains($0.url.standardizedFileURL.path) }
        persistCurrentLibraryPresentationCache()
    }

    private func remapSourceSnapshotNotes(from sourceURLs: [URL], to destinationURLs: [URL]) {
        let destinationBySourcePath = Dictionary(uniqueKeysWithValues: zip(sourceURLs, destinationURLs).map {
            ($0.standardizedFileURL.path, $1.standardizedFileURL)
        })
        for (sourcePath, destinationURL) in destinationBySourcePath {
            guard let externalNote = externallyOpenedDocumentsByPath.removeValue(forKey: sourcePath),
                  !isInsideConfiguredLibraryRoot(destinationURL) else { continue }
            externallyOpenedDocumentsByPath[destinationURL.path] = externalNote.replacingURL(destinationURL)
        }
        sourceCountSnapshot = sourceCountSnapshot.map { note in
            guard let destinationURL = destinationBySourcePath[note.url.standardizedFileURL.path] else { return note }
            return note.replacingURL(destinationURL)
        }
        persistCurrentLibraryPresentationCache()
    }

    private func remapSourceSnapshotFolder(from sourceURL: URL, to destinationURL: URL) {
        let sourcePath = sourceURL.standardizedFileURL.path
        let destination = destinationURL.standardizedFileURL
        sourceCountSnapshot = sourceCountSnapshot.map { note in
            let notePath = note.url.standardizedFileURL.path
            guard notePath.hasPrefix(sourcePath + "/") else { return note }
            let relativePath = String(notePath.dropFirst(sourcePath.count + 1))
            return note.replacingURL(destination.appendingPathComponent(relativePath))
        }
        persistCurrentLibraryPresentationCache()
    }

    private func removeSourceSnapshotNotes(in folderURL: URL) {
        let folderPath = folderURL.standardizedFileURL.path
        sourceCountSnapshot.removeAll {
            $0.url.standardizedFileURL.path.hasPrefix(folderPath + "/")
        }
        persistCurrentLibraryPresentationCache()
    }

    private func persistCurrentLibraryPresentationCache() {
        let snapshot = sourceCountSnapshot
        let noteStore = noteStore
        launchNoteCacheQueue.async {
            noteStore.cacheLibraryPresentationSnapshot(snapshot)
        }
    }

    @discardableResult
    func saveCurrentNoteForLibrary() throws -> URL? {
        let savedURL = try saveCurrentNote(force: true)
        if let savedURL {
            reloadNotes(selecting: savedURL, loadFirstIfNeeded: false)
        }
        return savedURL
    }

    @discardableResult
    func flushPendingAutosaveForTesting() throws -> URL? {
        try saveCurrentNote(force: false)
    }

    func flushBackgroundAutosaveForTesting() {
        autosaveTask?.cancel()
        autosaveTask = nil
        autosaveCurrentNote()
        drainBackgroundAutosaves()
    }

    func triggerBackgroundAutosaveForTesting() {
        autosaveTask?.cancel()
        autosaveTask = nil
        autosaveCurrentNote()
    }

    func waitForBackgroundAutosaveForTesting() async {
        while backgroundAutosaveIsActive {
            await withCheckedContinuation { continuation in
                autosavePersistenceQueue.async {
                    continuation.resume()
                }
            }
            drainBackgroundAutosaves()
        }
    }

    func deleteSelectedNoteForLibrary() throws {
        try deleteSelectedNotesForLibrary()
    }

    var canDeleteSelectedNotesFromMenuForLibrary: Bool {
        selectedScope != .trash && canUseSelectedNote
    }

    var canRestoreSelectedNotesFromMenuForLibrary: Bool {
        canRestoreSelectedNote
    }

    var canMoveSelectedNotesFromMenuForLibrary: Bool {
        canMoveSelectedNote
    }

    func makeMoveNoteMenuForLibrary() -> NSMenu {
        makeMoveNoteMenu()
    }

    func deleteSelectedNotesForLibrary() throws {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard !urls.isEmpty else { return }
        if selectedScope == .trash {
            for url in urls {
                try noteStore.permanentlyDeleteTrashedNote(at: url)
            }
            removeNotesFromTrashSnapshot(at: urls)
        } else {
            try saveCurrentNoteIfNeeded()
            let selectedNotesByPath = Dictionary(uniqueKeysWithValues: urls.compactMap { url in
                let path = url.standardizedFileURL.path
                return sourceCountSnapshot.first { $0.url.standardizedFileURL.path == path }.map { (path, $0) }
            })
            for url in urls {
                let trashedURL = try noteStore.trashNote(at: url)
                if let note = selectedNotesByPath[url.standardizedFileURL.path] {
                    trashedNotesSnapshot.append(note.replacingURL(trashedURL, modifiedAt: Date()))
                }
            }
            sortAndTrimTrashSnapshot()
        }
        recordInternalFileSystemChanges(for: urls)
        if selectedScope != .trash {
            removeNotesFromSourceSnapshot(at: urls)
        }
        activeSearchSession = nil
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(loadFirstIfNeeded: true, mutationAnimation: .deletion)
    }

    func deleteSelectedNotesInBackgroundForLibrary() throws {
        let urls = selectedMarkdownFileURLsForLibrary().filter {
            !pendingDeletionPaths.contains($0.standardizedFileURL.path)
        }
        guard !urls.isEmpty else { return }

        // A dirty editor must be durably saved before its source can leave the
        // library. Clean-note deletion can publish its UI transition immediately.
        try saveCurrentNoteIfNeeded()

        let deletesFromTrash = selectedScope == .trash
        let snapshot = deletesFromTrash ? trashedNotesSnapshot : sourceCountSnapshot
        let notesByPath = Dictionary(uniqueKeysWithValues: urls.compactMap { url in
            let path = url.standardizedFileURL.path
            return snapshot.first {
                $0.url.standardizedFileURL.path == path
            }.map { (path, $0) }
        })
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        pendingDeletionPaths.formUnion(paths)
        pendingDeletionBatchCount += 1

        if deletesFromTrash {
            removeNotesFromTrashSnapshot(at: urls)
        } else {
            removeNotesFromSourceSnapshot(at: urls)
        }
        clearCurrentDocumentAfterRemoval()
        reloadNotes(
            loadFirstIfNeeded: true,
            refreshCounts: false,
            mutationAnimation: .deletion
        )
        scheduleSourceCountRefresh(using: sourceCountSnapshot)

        let noteStore = noteStore
        let willPersist = backgroundDeletionWillPersist
        libraryMutationQueue.async { [weak self] in
            willPersist()
            var deletedNotes: [LibraryDeletedNote] = []
            var failures: [LibraryDeletionFailure] = []
            for sourceURL in urls {
                do {
                    if deletesFromTrash {
                        try noteStore.permanentlyDeleteTrashedNote(at: sourceURL)
                        deletedNotes.append(LibraryDeletedNote(
                            sourceURL: sourceURL,
                            trashedURL: nil
                        ))
                    } else {
                        let trashedURL = try noteStore.trashNote(at: sourceURL)
                        deletedNotes.append(LibraryDeletedNote(
                            sourceURL: sourceURL,
                            trashedURL: trashedURL
                        ))
                    }
                } catch {
                    failures.append(LibraryDeletionFailure(
                        sourceURL: sourceURL,
                        message: error.localizedDescription
                    ))
                }
            }
            let result = LibraryDeletionPersistenceResult(
                deletedNotes: deletedNotes,
                failures: failures
            )
            DispatchQueue.main.async {
                self?.finishBackgroundDeletion(
                    result,
                    notesByPath: notesByPath,
                    deletesFromTrash: deletesFromTrash
                )
            }
        }
    }

    private func finishBackgroundDeletion(
        _ result: LibraryDeletionPersistenceResult,
        notesByPath: [String: NoteSearchResult],
        deletesFromTrash: Bool
    ) {
        let completedPaths = Set(
            result.deletedNotes.map { $0.sourceURL.standardizedFileURL.path }
                + result.failures.map { $0.sourceURL.standardizedFileURL.path }
        )
        pendingDeletionPaths.subtract(completedPaths)

        var changedURLs: [URL] = []
        for deletedNote in result.deletedNotes {
            changedURLs.append(deletedNote.sourceURL)
            if let trashedURL = deletedNote.trashedURL {
                changedURLs.append(trashedURL)
                if let note = notesByPath[deletedNote.sourceURL.standardizedFileURL.path] {
                    trashedNotesSnapshot.append(
                        note.replacingURL(trashedURL, modifiedAt: Date())
                    )
                }
            }
        }
        if !changedURLs.isEmpty {
            recordInternalFileSystemChanges(for: changedURLs)
        }
        sortAndTrimTrashSnapshot()

        if !result.failures.isEmpty {
            for failure in result.failures {
                guard let note = notesByPath[failure.sourceURL.standardizedFileURL.path] else {
                    continue
                }
                if deletesFromTrash {
                    trashedNotesSnapshot.append(note)
                } else {
                    LibraryNoteListProjection.upsertByModifiedDate(
                        note,
                        into: &sourceCountSnapshot,
                        replacingPaths: Set([failure.sourceURL.standardizedFileURL.path]),
                        limit: Self.sourceCountSnapshotLimit
                    )
                }
            }
            if deletesFromTrash {
                sortAndTrimTrashSnapshot()
            }
            reloadNotes(
                loadFirstIfNeeded: selectedURL == nil,
                refreshCounts: false,
                mutationAnimation: .insertion
            )
            let details = result.failures.map(\.message).joined(separator: "\n")
            presentErrorAlert(
                message: deletesFromTrash ? "永久删除失败" : "删除失败，笔记已恢复",
                details: details
            )
        }

        activeSearchSession = nil
        scheduleSourceCountRefresh(using: sourceCountSnapshot)
        updateToolbarActionState()
        pendingDeletionBatchCount = max(0, pendingDeletionBatchCount - 1)
        if pendingDeletionBatchCount == 0 {
            let waiters = pendingDeletionWaiters
            pendingDeletionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitForBackgroundDeletionsForLibrary() async {
        guard pendingDeletionBatchCount > 0 else { return }
        await withCheckedContinuation { continuation in
            pendingDeletionWaiters.append(continuation)
        }
    }

    @discardableResult
    func restoreSelectedNoteForLibrary() throws -> URL? {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard selectedScope == .trash, !urls.isEmpty else { return nil }
        let restoredURLs = try urls.map { try noteStore.restoreTrashedNote(at: $0) }
        let restoredURL = restoredURLs.first
        recordInternalFileSystemChanges(for: urls + restoredURLs)
        removeNotesFromTrashSnapshot(at: urls)
        for url in restoredURLs {
            let document = try noteStore.loadNote(at: url)
            let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate])
                as? Date ?? Date()
            updateSourceCountSnapshotAfterSave(
                previousURL: nil,
                savedURL: url,
                title: document.title,
                tags: document.tags,
                modifiedAt: modifiedAt,
                snippet: libraryFirstMeaningfulLine(from: document.body) ?? "",
                hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: document.body),
                thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(
                    in: document.body,
                    relativeTo: url
                )
            )
        }
        activeSearchSession = nil
        selectedScope = restoredURL.map { .folder($0.deletingLastPathComponent()) }
            ?? .folder(noteStore.notesDirectory)
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(selecting: restoredURL, loadFirstIfNeeded: true)
        return restoredURL
    }

    private func removeNotesFromTrashSnapshot(at urls: [URL]) {
        let removedPaths = Set(urls.map { $0.standardizedFileURL.path })
        trashedNotesSnapshot.removeAll { removedPaths.contains($0.url.standardizedFileURL.path) }
    }

    private func sortAndTrimTrashSnapshot() {
        trashedNotesSnapshot.sort { $0.modifiedAt > $1.modifiedAt }
        if trashedNotesSnapshot.count > Self.sourceCountSnapshotLimit {
            trashedNotesSnapshot.removeLast(trashedNotesSnapshot.count - Self.sourceCountSnapshotLimit)
        }
    }

    func selectedMarkdownFileURLForLibrary() -> URL? {
        selectedMarkdownFileURLsForLibrary().first
    }

    var currentNoteHasUnsavedChangesForLibrary: Bool {
        isDirty
    }

    func openMarkdownDocumentForLibrary(at url: URL) throws {
        try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
        cancelActiveNoteLoad()
        isLoadingInitialNote = false
        isCreatingNewNote = false
        let standardizedURL = url.standardizedFileURL
        let loaded = try noteLoader(standardizedURL)
        let modifiedAt = fileModificationDateLoader(standardizedURL) ?? Date()
        let note = NoteSearchResult(
            url: standardizedURL,
            title: loaded.title,
            snippet: libraryFirstMeaningfulLine(from: loaded.body) ?? "",
            modifiedAt: modifiedAt,
            tags: loaded.tags,
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: loaded.body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: loaded.body, relativeTo: standardizedURL)
        )

        externallyOpenedDocumentsByPath[standardizedURL.path] = note
        sourceCountSnapshot = includingExternallyOpenedDocuments(in: sourceCountSnapshot)
        selectedScope = .folder(standardizedURL.deletingLastPathComponent())
        searchField.stringValue = ""
        activeSearchSession = nil
        let cached = cacheLoadedNote(loaded, for: note, fileModifiedAt: modifiedAt)
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(
            selecting: standardizedURL,
            loadFirstIfNeeded: false,
            allNotesSnapshot: sourceCountSnapshot
        )
        applyLoadedNote(cached, for: note)
        releaseDeferredLaunchWorkIfReady()
        if let row = rowIndex(for: standardizedURL.path) {
            tableView.scrollRowToVisible(row)
        }
        window?.makeFirstResponder(editorTextView)
    }

    func showAttachmentManagerForLibrary() {
        let controller: LibraryAttachmentManagerWindowController
        if let existing = attachmentManagerWindowController {
            controller = existing
        } else {
            controller = LibraryAttachmentManagerWindowController(
                rootsProvider: { [weak self] in
                    self?.noteStore.preferredDirectories ?? []
                },
                onOpenNote: { [weak self] url in
                    do {
                        try self?.openMarkdownDocumentForLibrary(at: url)
                    } catch {
                        self?.presentErrorAlert(
                            message: "无法打开引用笔记",
                            details: error.localizedDescription
                        )
                    }
                }
            )
            attachmentManagerWindowController = controller
        }
        controller.showAndRefresh()
    }

    @objc
    private func manageAttachmentsPressed() {
        showAttachmentManagerForLibrary()
    }

    func selectNoteForVisualQA(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        visualQASelectedURL = standardizedURL
        reloadNotes(
            selecting: standardizedURL,
            loadFirstIfNeeded: true,
            refreshCounts: false
        )
        window?.makeFirstResponder(tableView)
    }

    private func stabilizeVisualQASelectionIfNeeded() {
        guard let visualQASelectedURL,
              let row = rowIndex(for: visualQASelectedURL.path) else {
            return
        }
        suppressSelectionChanges = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressSelectionChanges = false
        tableView.scrollRowToVisible(row)
        if row <= 1, let scrollView = tableView.enclosingScrollView {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
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
        let snippet = noteListSnippetText(for: firstNote)
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

    func selectRecentScopeForLibrary() {
        selectedScope = .recent
        reloadNotesForNavigation(loadFirstIfNeeded: true)
    }

    func refreshSelectedScopeFromCachedSnapshotForLibrary() {
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
        scheduleSourceSnapshotValidation(loadFirstIfNeeded: false)
    }

    func waitForSourceSnapshotValidationForLibrary() async {
        let task = sourceSnapshotValidationTask
        await task?.value
    }

    func refreshFolderNoteVisibilityForLibrary() {
        activeSearchSession = nil
        let previousURL = selectedURL
        reloadNotesForNavigation(selecting: previousURL, loadFirstIfNeeded: true)
        if notes.isEmpty {
            clearCurrentDocumentAfterRemoval()
        }
    }

    func refreshThemeColorForLibrary() {
        LibraryNoteRowView.selectionFillColor = selectedThemeColor.noteSelectionColor
        refreshVisibleSourceOutlinePresentation()
        tableView.reloadData()
        window?.displayIfNeeded()
    }

    func noteListSearchResultsForLibrary() -> [NoteSearchResult] {
        notes
    }

    func activeSearchSessionForLibrary() -> NoteSearchSession? {
        activeSearchSession
    }

    var isSourceListVisibleForLibrary: Bool {
        if let sourceSplitViewItem {
            return !sourceSplitViewItem.isCollapsed
        }
        return sourceListView?.isHidden == false
    }

    private var storedSourceColumnWidthForLibrary: CGFloat {
        LibraryNotesLayout.clampedSourceColumnWidth(
            CGFloat(noteStore.librarySourceColumnWidth ?? Double(LibraryNotesLayout.sourceColumnWidth))
        )
    }

    private var storedNoteColumnWidthForLibrary: CGFloat {
        LibraryNotesLayout.clampedNoteColumnWidth(
            CGFloat(noteStore.libraryNoteColumnWidth ?? Double(LibraryNotesLayout.noteColumnWidth))
        )
    }

    func applyStoredLibrarySplitLayoutForLibrary() {
        guard let splitView = librarySplitView,
              splitView.arrangedSubviews.count == 3,
              splitView.bounds.width > 0 else {
            return
        }

        isApplyingStoredSplitLayout = true
        defer { isApplyingStoredSplitLayout = false }

        let sourceList = splitView.arrangedSubviews[0]
        let noteList = splitView.arrangedSubviews[1]
        sourceSplitViewItem?.isCollapsed = !noteStore.librarySourceListVisible
        noteListSplitViewItem?.isCollapsed = noteListViewMode == .gallery
        splitView.adjustSubviews()

        if !sourceList.isHidden {
            splitView.setPosition(storedSourceColumnWidthForLibrary, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
        }
        if noteListViewMode == .list {
            let noteDividerPosition = noteList.frame.minX + storedNoteColumnWidthForLibrary
            splitView.setPosition(noteDividerPosition, ofDividerAt: 1)
            splitView.layoutSubtreeIfNeeded()
        }
    }

    func persistLibrarySplitLayoutForLibrary() {
        guard !isApplyingStoredSplitLayout,
              let splitView = librarySplitView,
              splitView.arrangedSubviews.count == 3 else {
            return
        }

        let sourceList = splitView.arrangedSubviews[0]
        let noteList = splitView.arrangedSubviews[1]
        if !sourceList.isHidden, sourceList.frame.width > 0 {
            noteStore.librarySourceColumnWidth = Double(
                LibraryNotesLayout.clampedSourceColumnWidth(sourceList.frame.width)
            )
        }
        if noteListViewMode == .list, noteList.frame.width > 0 {
            noteStore.libraryNoteColumnWidth = Double(
                LibraryNotesLayout.clampedNoteColumnWidth(noteList.frame.width)
            )
        }
    }

    @objc
    private func librarySplitViewDidResize(_ notification: Notification) {
        guard let resizedSplitView = notification.object as? NSSplitView,
              resizedSplitView === librarySplitView,
              !isApplyingStoredSplitLayout,
              window?.isVisible == true else {
            return
        }
        splitLayoutPersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.splitLayoutPersistenceWorkItem = nil
            self?.persistLibrarySplitLayoutForLibrary()
        }
        splitLayoutPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(160), execute: workItem)
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view === splitView.arrangedSubviews.last
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0:
            return LibraryNotesLayout.sourceColumnMinimumWidth
        case 1:
            let noteList = splitView.arrangedSubviews[1]
            return noteList.frame.minX + LibraryNotesLayout.noteColumnMinimumWidth
        default:
            return proposedMinimumPosition
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let editorLimit = splitView.bounds.width
            - LibraryNotesLayout.editorColumnMinimumWidth
            - splitView.dividerThickness
        switch dividerIndex {
        case 0:
            let remainingColumnsLimit = splitView.bounds.width
                - LibraryNotesLayout.noteColumnMinimumWidth
                - LibraryNotesLayout.editorColumnMinimumWidth
                - (splitView.dividerThickness * 2)
            return min(LibraryNotesLayout.sourceColumnMaximumWidth, remainingColumnsLimit)
        case 1:
            let noteList = splitView.arrangedSubviews[1]
            return min(
                noteList.frame.minX + LibraryNotesLayout.noteColumnMaximumWidth,
                editorLimit
            )
        default:
            return proposedMaximumPosition
        }
    }

    @discardableResult
    func toggleSourceListForLibrary() -> Bool {
        setSourceListVisibleForLibrary(!isSourceListVisibleForLibrary)
    }

    @discardableResult
    func setSourceListVisibleForLibrary(_ isVisible: Bool) -> Bool {
        setSourceListVisibleForLibrary(isVisible, animated: false)
    }

    @discardableResult
    private func setSourceListVisibleForLibrary(_ isVisible: Bool, animated: Bool) -> Bool {
        guard let sourceListView else { return false }
        noteStore.librarySourceListVisible = isVisible
        applySourceVisibilityChrome(isVisible)
        if let sourceSplitViewItem {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = LibraryNotesLayout.sourceCollapseAnimationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    sourceSplitViewItem.animator().isCollapsed = !isVisible
                    if let titleView = noteListToolbarTitleLeadingConstraint?.firstItem as? NSView {
                        titleView.superview?.animator().layoutSubtreeIfNeeded()
                    }
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.restoreStoredPaneWidthsAfterSourceVisibilityChange()
                        self?.updateToolbarActionState()
                    }
                }
            } else {
                sourceSplitViewItem.isCollapsed = !isVisible
                restoreStoredPaneWidthsAfterSourceVisibilityChange()
            }
        } else {
            sourceListView.isHidden = !isVisible
        }
        updateToolbarActionState()
        return isSourceListVisibleForLibrary
    }

    private func applySourceVisibilityChrome(_ isVisible: Bool) {
        noteListToolbarTitleLeadingConstraint?.constant = isVisible
            ? LibraryNotesLayout.toolbarExpandedTitleLeadingOffset
            : LibraryNotesLayout.toolbarCollapsedTitleLeadingOffset
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.addFolderToolbarItemIdentifier,
                 Self.sourceTrackingSeparatorToolbarItemIdentifier:
                item.isHidden = !isVisible
            case Self.toggleSidebarToolbarItemIdentifier:
                let label = isVisible ? "隐藏资料库" : "显示资料库"
                updateToolbarItemPresentation(
                    item,
                    label: label,
                    symbolName: "sidebar.left",
                    symbolPointSize: isVisible
                        ? LibraryNotesLayout.toolbarSourceActionSymbolPointSize
                        : LibraryNotesLayout.toolbarCircularButtonSymbolPointSize
                )
                configureToggleSidebarToolbarItem(item, label: label, usesCompactGlass: !isVisible)
            default:
                break
            }
        }
    }

    private func restoreStoredPaneWidthsAfterSourceVisibilityChange() {
        guard let splitView = librarySplitView,
              splitView.arrangedSubviews.count == 3 else { return }
        isApplyingStoredSplitLayout = true
        defer { isApplyingStoredSplitLayout = false }
        splitView.adjustSubviews()
        if !splitView.arrangedSubviews[0].isHidden {
            splitView.setPosition(storedSourceColumnWidthForLibrary, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
        }
        if noteListViewMode == .list {
            let noteList = splitView.arrangedSubviews[1]
            splitView.setPosition(noteList.frame.minX + storedNoteColumnWidthForLibrary, ofDividerAt: 1)
            splitView.layoutSubtreeIfNeeded()
        }
    }

    func setNoteListViewModeForLibrary(_ mode: LibraryNoteViewMode) {
        guard noteListViewMode != mode else {
            if mode == .gallery {
                window?.makeFirstResponder(galleryCollectionView)
            }
            return
        }

        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return
        }

        noteListViewMode = mode
        noteStore.libraryNoteViewModeRawValue = mode.rawValue
        applyNoteListViewModeChrome(animated: window?.isVisible == true)
    }

    private func applyNoteListViewModeChrome(animated: Bool) {
        guard let noteListSplitViewItem, let editorStackView, let galleryScrollView else { return }
        let showsGallery = noteListViewMode == .gallery

        if showsGallery {
            reloadGalleryData()
            synchronizeGallerySelectionFromTable()
            galleryScrollView.isHidden = false
            galleryScrollView.alphaValue = 1
            editorStackView.isHidden = true
        } else {
            editorStackView.isHidden = false
            editorStackView.alphaValue = 1
            galleryScrollView.isHidden = true
        }
        updateNoteListEmptyState(query: searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))

        if animated {
            isApplyingStoredSplitLayout = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = LibraryNotesLayout.sourceCollapseAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                noteListSplitViewItem.animator().isCollapsed = showsGallery
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.isApplyingStoredSplitLayout = false
                    self?.completeNoteListViewModeTransition(showingGallery: showsGallery)
                }
            }
        } else {
            isApplyingStoredSplitLayout = true
            noteListSplitViewItem.isCollapsed = showsGallery
            librarySplitView?.adjustSubviews()
            isApplyingStoredSplitLayout = false
            completeNoteListViewModeTransition(showingGallery: showsGallery)
        }
        applyNoteListViewModeToolbarChrome()
    }

    private func completeNoteListViewModeTransition(showingGallery: Bool) {
        if !showingGallery {
            applyStoredLibrarySplitLayoutForLibrary()
        }
        applyNoteListViewModeToolbarChrome()
        if showingGallery {
            window?.makeFirstResponder(galleryCollectionView)
        } else if selectedURL == nil {
            window?.makeFirstResponder(tableView)
        } else {
            window?.makeFirstResponder(editorTextView)
        }
    }

    private func applyNoteListViewModeToolbarChrome() {
        let showsGallery = noteListViewMode == .gallery
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.noteListTitleToolbarItemIdentifier,
                 Self.noteTrackingSeparatorToolbarItemIdentifier,
                 Self.editorToolsToolbarItemIdentifier:
                item.isHidden = showsGallery
            default:
                break
            }
        }
        window?.toolbar?.validateVisibleItems()
    }

    private static func externalScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0
        }
    }

    @discardableResult
    func createLibraryFolder(named name: String) throws -> URL {
        try createLibraryFolder(named: name, in: targetDirectoryForNewFolder())
    }

    func addExistingLibraryFolderForLibrary(at directory: URL) throws {
        let candidate = directory.standardizedFileURL
        let roots = Self.rootPreferredDirectories(from: noteStore.preferredDirectories)
        if roots.contains(where: { $0.path == candidate.path }) {
            throw LibraryActionError.libraryFolderAlreadyRegistered
        }
        if roots.contains(where: {
            candidate.path.hasPrefix($0.path + "/") || $0.path.hasPrefix(candidate.path + "/")
        }) {
            throw LibraryActionError.libraryFolderOverlapsRegisteredFolder
        }

        noteStore.addPreferredDirectory(candidate)
        activeSearchSession = nil
        invalidateSourceTagsForLibrary()
        reloadPersistedSourceDisclosureState()
        restartLibraryFileSystemMonitorForCurrentRoots()
        reloadSourceFolderRowsForCurrentState()
        forceFullLibrarySnapshotReload()
        selectedScope = .folder(candidate)
        refreshSourceSelection()
        scheduleDeferredSourceTagLoad()
    }

    func removeRegisteredLibraryFolderForLibrary(at directory: URL) throws {
        let candidate = directory.standardizedFileURL
        if candidate.path == noteStore.notesDirectory.standardizedFileURL.path {
            throw LibraryActionError.cannotRemoveDefaultLibraryFolder
        }
        let roots = Self.rootPreferredDirectories(from: noteStore.preferredDirectories)
        guard roots.contains(where: { $0.path == candidate.path }) else {
            throw LibraryActionError.noFolderSelected
        }

        noteStore.removePreferredDirectory(candidate)
        noteStore.removeLibraryFolderDisclosurePaths(in: candidate)
        noteStore.removeLibraryPinnedNotePaths(in: candidate)
        externallyOpenedDocumentsByPath = externallyOpenedDocumentsByPath.filter {
            !$0.key.hasPrefix(candidate.path + "/")
        }
        if case .folder(let selectedFolder) = selectedScope,
           (selectedFolder.standardizedFileURL.path == candidate.path
            || selectedFolder.standardizedFileURL.path.hasPrefix(candidate.path + "/")) {
            selectedScope = .folder(noteStore.notesDirectory)
        }
        if let selectedURL, selectedURL.standardizedFileURL.path.hasPrefix(candidate.path + "/") {
            clearCurrentDocumentAfterRemoval()
        }
        activeSearchSession = nil
        invalidateSourceTagsForLibrary()
        reloadPersistedSourceDisclosureState()
        restartLibraryFileSystemMonitorForCurrentRoots()
        reloadSourceFolderRowsForCurrentState()
        forceFullLibrarySnapshotReload()
        scheduleDeferredSourceTagLoad()
    }

    @discardableResult
    private func createLibraryFolder(named name: String, in parentURL: URL) throws -> URL {
        let folderURL = try noteStore.createFolder(named: name, in: parentURL)
        recordInternalFileSystemChanges(for: [folderURL])
        activeSearchSession = nil
        selectedScope = .folder(folderURL)
        projectSourceFolderTreeRows(LibraryFolderTreeProjection.inserting(
            folderURL,
            under: parentURL,
            into: sourceFolderTreeRows
        ))
        reloadNotes(loadFirstIfNeeded: true)
        return folderURL
    }

    func beginInlineFolderCreationForLibrary() {
        if inlineFolderEditField != nil {
            focusInlineFolderEditField()
            return
        }

        if !isSourceListVisibleForLibrary {
            _ = setSourceListVisibleForLibrary(true)
        }
        if sourceFoldersSectionCollapsed {
            sourceFoldersSectionCollapsed = false
            noteStore.libraryFoldersSectionCollapsed = false
        }
        if !sourceFoldersLoaded {
            scheduleDeferredSourceFolderLoad()
        }

        inlineFolderEditOperation = .create(parentURL: targetDirectoryForNewFolder().standardizedFileURL)
        inlineFolderEditHasReceivedFocus = false
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        focusInlineFolderEditField()
    }

    func beginInlineFolderRenameForLibrary(at folderURL: URL) {
        if inlineFolderEditField != nil {
            focusInlineFolderEditField()
            return
        }

        if !isSourceListVisibleForLibrary {
            _ = setSourceListVisibleForLibrary(true)
        }
        if sourceFoldersSectionCollapsed {
            sourceFoldersSectionCollapsed = false
            noteStore.libraryFoldersSectionCollapsed = false
        }
        if !sourceFoldersLoaded {
            scheduleDeferredSourceFolderLoad()
        }

        let standardizedURL = folderURL.standardizedFileURL
        guard sourceFolderTreeRows.contains(where: {
            $0.url.standardizedFileURL.path == standardizedURL.path
        }) else { return }
        inlineFolderEditOperation = .rename(folderURL: standardizedURL)
        inlineFolderEditHasReceivedFocus = false
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        focusInlineFolderEditField()
    }

    private func focusInlineFolderEditField(remainingAttempts: Int = 4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let field = self.inlineFolderEditField else { return }
            guard let window = field.window ?? self.window else { return }

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.contentView?.layoutSubtreeIfNeeded()
            if let fieldEditor = field.currentEditor() as? NSTextView,
               window.firstResponder === fieldEditor {
                fieldEditor.setSelectedRange(NSRange(location: 0, length: field.stringValue.utf16.count))
                self.inlineFolderEditHasReceivedFocus = true
                return
            }
            if window.makeFirstResponder(field),
               let fieldEditor = field.currentEditor() as? NSTextView {
                fieldEditor.setSelectedRange(NSRange(location: 0, length: field.stringValue.utf16.count))
                self.inlineFolderEditHasReceivedFocus = true
                return
            }

            guard remainingAttempts > 0 else { return }
            self.focusInlineFolderEditField(remainingAttempts: remainingAttempts - 1)
        }
    }

    private func commitInlineFolderEdit() {
        guard !isCommittingInlineFolderEdit,
              let field = inlineFolderEditField,
              let operation = inlineFolderEditOperation else {
            return
        }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            cancelInlineFolderEdit()
            return
        }

        isCommittingInlineFolderEdit = true
        clearInlineFolderEditState()
        do {
            switch operation {
            case .create(let parentURL):
                _ = try createLibraryFolder(named: name, in: parentURL)
            case .rename(let folderURL):
                _ = try renameLibraryFolder(at: folderURL, to: name)
            }
            isCommittingInlineFolderEdit = false
        } catch {
            isCommittingInlineFolderEdit = false
            inlineFolderEditOperation = operation
            rebuildSourceRows(includeTags: sourceTagsLoaded)
            inlineFolderEditField?.stringValue = name
            focusInlineFolderEditField()
            let message: String
            switch operation {
            case .create:
                message = "无法新建文件夹"
            case .rename:
                message = "无法重命名文件夹"
            }
            presentErrorAlert(message: message, details: error.localizedDescription)
        }
    }

    private func cancelInlineFolderEdit() {
        guard inlineFolderEditOperation != nil else { return }
        clearInlineFolderEditState()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
    }

    private func clearInlineFolderEditState() {
        inlineFolderEditField = nil
        inlineFolderEditOperation = nil
        inlineFolderEditHasReceivedFocus = false
    }

    @discardableResult
    func renameSelectedFolderForLibrary(to name: String) throws -> URL {
        guard case .folder(let folderURL) = selectedScope else {
            throw LibraryActionError.noFolderSelected
        }

        return try renameLibraryFolder(at: folderURL, to: name)
    }

    @discardableResult
    private func renameLibraryFolder(at folderURL: URL, to name: String) throws -> URL {
        let renamedURL = try noteStore.renamePreferredDirectory(folderURL, to: name)
        recordInternalFileSystemChanges(for: [folderURL, renamedURL])
        remapSourceSnapshotFolder(from: folderURL, to: renamedURL)
        activeSearchSession = nil
        reloadPersistedSourceDisclosureState()
        selectedScope = .folder(renamedURL)
        projectSourceFolderTreeRows(LibraryFolderTreeProjection.renaming(
            folderURL,
            to: renamedURL,
            in: sourceFolderTreeRows
        ))
        reloadNotes(loadFirstIfNeeded: true)
        return renamedURL
    }

    func deleteSelectedFolderForLibrary() throws {
        guard case .folder(let folderURL) = selectedScope else {
            throw LibraryActionError.noFolderSelected
        }

        let folderPath = folderURL.standardizedFileURL.path
        let notesInFolderByPath = Dictionary(uniqueKeysWithValues: sourceCountSnapshot.compactMap { note -> (String, NoteSearchResult)? in
            let notePath = note.url.standardizedFileURL.path
            guard notePath.hasPrefix(folderPath + "/") else { return nil }
            return (notePath, note)
        })
        recordInternalFileSystemChanges(for: [folderURL], includingDescendants: true)
        let trashResult = try noteStore.trashFolderWithNoteURLs(
            at: folderURL,
            knownNoteURLs: notesInFolderByPath.values.map(\.url)
        )
        let trashedFolderURL = trashResult.directory
        let deletedAt = Date()
        trashedNotesSnapshot.append(contentsOf: trashResult.noteURLs.map { trashedURL in
            let trashedFolderPath = trashedFolderURL.standardizedFileURL.path
            let relativePath = String(trashedURL.standardizedFileURL.path.dropFirst(trashedFolderPath.count + 1))
            let originalPath = folderURL.appendingPathComponent(relativePath).standardizedFileURL.path
            if let note = notesInFolderByPath[originalPath] {
                return note.replacingURL(trashedURL, modifiedAt: deletedAt)
            }
            return NoteSearchResult(
                url: trashedURL,
                title: trashedURL.deletingPathExtension().lastPathComponent,
                snippet: "",
                modifiedAt: deletedAt
            )
        })
        sortAndTrimTrashSnapshot()
        recordInternalFileSystemChanges(for: [folderURL, trashedFolderURL])
        removeSourceSnapshotNotes(in: folderURL)
        activeSearchSession = nil
        reloadPersistedSourceDisclosureState()
        selectedScope = .folder(noteStore.notesDirectory)
        clearCurrentDocumentAfterRemoval()
        projectSourceFolderTreeRows(LibraryFolderTreeProjection.removing(
            folderURL,
            from: sourceFolderTreeRows
        ))
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
        recordInternalFileSystemChanges(for: sourceURLs + movedURLs)
        remapSourceSnapshotNotes(from: sourceURLs, to: movedURLs)
        activeSearchSession = nil
        setSelectedURLForLibrary(movedURLs.first)
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

        return isInsideConfiguredLibraryRoot(sourceURL)
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

        let sourcePaths = Set(sourceURLs.map(\.path))
        let scopeBeforeMove = selectedScope
        let visibleNotesBeforeMove = notes
        let noteListScrollOrigin = tableView.enclosingScrollView?.contentView.bounds.origin
        let galleryScrollOrigin = galleryScrollView?.contentView.bounds.origin
        let movedURLs = try sourceURLs.map { sourceURL in
            try noteStore.moveNote(at: sourceURL, to: targetDirectory)
        }
        recordInternalFileSystemChanges(for: sourceURLs + movedURLs)
        remapSourceSnapshotNotes(from: sourceURLs, to: movedURLs)
        activeSearchSession = nil
        selectedScope = scopeBeforeMove

        let movedURLBySourcePath = Dictionary(uniqueKeysWithValues: zip(sourceURLs, movedURLs).map {
            ($0.path, $1)
        })
        let currentSelectionAfterMove = selectedPath.flatMap {
            movedURLBySourcePath[$0] ?? selectedURL
        }
        let visibleNotesAfterMove = notesForSelectedScope(
            limit: 240,
            allNotes: sourceCountSnapshot
        )
        let visiblePathsAfterMove = Set(visibleNotesAfterMove.map { $0.url.standardizedFileURL.path })
        let selectionAnchorIndex = visibleNotesBeforeMove.firstIndex {
            $0.url.standardizedFileURL.path == selectedPath
        } ?? visibleNotesBeforeMove.firstIndex {
            sourcePaths.contains($0.url.standardizedFileURL.path)
        } ?? 0
        let nearestRemainingURL = visibleNotesBeforeMove.enumerated()
            .filter {
                !sourcePaths.contains($0.element.url.standardizedFileURL.path)
                    && visiblePathsAfterMove.contains($0.element.url.standardizedFileURL.path)
            }
            .min {
                abs($0.offset - selectionAnchorIndex) < abs($1.offset - selectionAnchorIndex)
            }?
            .element.url
        let preferredURL = [currentSelectionAfterMove, nearestRemainingURL]
            .compactMap { $0 }
            .first { visiblePathsAfterMove.contains($0.standardizedFileURL.path) }

        selectedURL = preferredURL
        if preferredURL == nil {
            clearCurrentDocumentAfterRemoval()
        }
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(selecting: preferredURL, loadFirstIfNeeded: preferredURL != nil)
        restoreNoteBrowserScrollPosition(
            noteListOrigin: noteListScrollOrigin,
            galleryOrigin: galleryScrollOrigin
        )
        return movedURLs
    }

    private func restoreNoteBrowserScrollPosition(
        noteListOrigin: NSPoint?,
        galleryOrigin: NSPoint?
    ) {
        if let noteListOrigin,
           let scrollView = tableView.enclosingScrollView {
            scrollView.contentView.scroll(to: noteListOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        if let galleryOrigin,
           let galleryScrollView {
            galleryScrollView.contentView.scroll(to: galleryOrigin)
            galleryScrollView.reflectScrolledClipView(galleryScrollView.contentView)
        }
    }

    private func uniqueStandardizedFileURLs(from urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }

    private func isInsideConfiguredLibraryRoot(_ noteURL: URL) -> Bool {
        let notePath = noteURL.standardizedFileURL.path
        return noteStore.preferredDirectories.contains { rootURL in
            let rootPath = rootURL.standardizedFileURL.path
            guard notePath.hasPrefix(rootPath + "/") else { return false }
            let relativePath = String(notePath.dropFirst(rootPath.count + 1))
            return !relativePath.split(separator: "/").contains {
                $0.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) == .orderedSame
            }
        }
    }

    private func clearCurrentDocumentAfterRemoval() {
        cancelActiveNoteLoad()
        isLoadingInitialNote = false
        isCreatingNewNote = false
        setSelectedURLForLibrary(nil)
        selectedTags = []
        isDirty = false
        updateEditorCreatedDate(nil)
        updateEditorStatus("")
        setEditorEditable(selectedScope != .trash)
        applyDocument(title: "", body: "", tags: [])
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

    private func noteListSnippetText(for note: NoteSearchResult) -> String {
        let snippet = note.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = snippet.isEmpty ? LibraryCopy.noAdditionalText : snippet
        let dateText = noteListDateText(for: noteListDisplayDateForLibrary(note))
        let cleanedPreview = noteListPreviewText(preview, removingDuplicateDateText: dateText)
        guard !cleanedPreview.isEmpty else { return dateText }
        return "\(dateText)  \(cleanedPreview)"
    }

    func noteListDisplayDateForLibrary(_ note: NoteSearchResult) -> Date {
        noteListSortOrder == .dateCreated ? note.createdAt : note.modifiedAt
    }

    private func noteListPreviewText(_ preview: String, removingDuplicateDateText dateText: String) -> String {
        guard !preview.isEmpty,
              !dateText.isEmpty else {
            return preview
        }

        if preview.localizedCaseInsensitiveCompare(dateText) == .orderedSame {
            return ""
        }

        let prefix = "\(dateText) "
        if preview.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
            let index = preview.index(preview.startIndex, offsetBy: dateText.count)
            return String(preview[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return preview
    }

    private func noteListFolderText(for note: NoteSearchResult) -> String {
        let folder = isTrashURL(note.url)
            ? LibraryCopy.recentlyDeleted
            : folderTitle(for: note.url.deletingLastPathComponent())
        let tags = note.tags.prefix(3).map(libraryDisplayTag).joined(separator: " ")
        if tags.isEmpty {
            return folder
        }
        return "\(folder) · \(tags)"
    }

    private func noteListDateText(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return noteListTimeFormatter.string(from: date)
        }

        if calendar.isDateInYesterday(date) {
            return LibraryCopy.yesterday
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if (2...7).contains(daysAgo) {
            return noteListWeekdayFormatter.string(from: date)
        }

        return noteListShortDateFormatter.string(from: date)
    }

    private func editorEditedDateText(for date: Date) -> String {
        "编辑于 \(dateFormatter.string(from: date))"
    }

    private func updateEditorCreatedDate(_ date: Date?) {
        let text = date.map { "创建于 \(dateFormatter.string(from: $0))" } ?? ""
        createdDateLabel.stringValue = text
        createdDateLabel.setAccessibilityValue(text)
    }

    private func notesCountText(_ count: Int) -> String {
        LibraryCopy.noteCount(count)
    }

    private func resultsCountText(_ count: Int) -> String {
        LibraryCopy.resultCount(count)
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
            || isCreatingNewNote
            || isDirty
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
        applySourceVisibilityChrome(isSourceListVisibleForLibrary)
        applyNoteListViewModeToolbarChrome()
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.deleteToolbarItemIdentifier:
                let label = isTrashScope
                    ? noteActionTitle(single: "永久删除", multiple: "永久删除 %d 条笔记", count: selectionCount)
                    : noteActionTitle(single: "删除", multiple: "删除 %d 条笔记", count: selectionCount)
                updateToolbarItemPresentation(
                    item,
                    label: label,
                    symbolName: isTrashScope ? "trash.slash" : "trash"
                )
            case Self.restoreToolbarItemIdentifier:
                let label = noteActionTitle(single: "恢复", multiple: "恢复 %d 条笔记", count: selectionCount)
                updateToolbarItemPresentation(item, label: label, symbolName: "arrow.uturn.backward")
            case Self.editorToolsToolbarItemIdentifier:
                updateEditorToolsToolbarGroupState(in: item)
                updateSourceModeToolbarButton(in: item)
            default:
                continue
            }
        }
        window?.toolbar?.validateVisibleItems()
        updateVisibleEditorToolsToolbarGroupEnabled()
    }

    private func updateToolbarItemPresentation(
        _ item: NSToolbarItem,
        label: String,
        symbolName: String,
        symbolPointSize: CGFloat = LibraryNotesLayout.toolbarSymbolPointSize
    ) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        let image = toolbarSymbolImage(
            symbolName: symbolName,
            label: label,
            pointSize: symbolPointSize
        )
        image?.isTemplate = true
        item.image = image
        guard let button = item.view as? NSButton else { return }
        button.image = image
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func configureToggleSidebarToolbarItem(
        _ item: NSToolbarItem,
        label: String,
        usesCompactGlass: Bool
    ) {
        item.isBordered = false
        let image = usesCompactGlass
            ? toolbarCompactGlassSymbolImage(symbolName: "sidebar.left", label: label)
            : toolbarSymbolImage(
                symbolName: "sidebar.left",
                label: label,
                pointSize: LibraryNotesLayout.toolbarSourceActionSymbolPointSize
            )
        image?.isTemplate = true
        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(toggleSourceListPressed))
        button.identifier = NSUserInterfaceItemIdentifier(Self.toggleSidebarToolbarItemIdentifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = usesCompactGlass ? .glass : .toolbar
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = !usesCompactGlass
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = usesCompactGlass ? .scaleNone : .scaleProportionallyDown
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true
        guard usesCompactGlass else {
            item.view = button
            return
        }

        let wrapper = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarCollapsedSidebarWrapperWidth,
            height: LibraryNotesLayout.toolbarCircularButtonSize
        ))
        wrapper.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarCollapsedSidebarWrapper")
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCollapsedSidebarWrapperWidth),
            wrapper.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize),
            button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])
        item.view = wrapper
    }

    private func popToolbarMenu(_ menu: NSMenu, from sender: Any?) {
        menu.autoenablesItems = false
        if let view = (sender as? NSView) ?? (sender as? NSToolbarItem)?.view {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: view.bounds.midX, y: view.bounds.minY - 4),
                in: view
            )
        } else if let contentView = window?.contentView {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 44),
                in: contentView
            )
        }
    }

    private func updateVisibleEditorToolsToolbarGroupEnabled() {
        for item in window?.toolbar?.items ?? [] where item.itemIdentifier == Self.editorToolsToolbarItemIdentifier {
            updateEditorToolsToolbarGroupState(in: item)
        }
    }

    private func updateEditorToolsToolbarGroupState(in item: NSToolbarItem) {
        let hasEnabledAction = canEditCurrentDocument || canUseSelectedNote
        item.isEnabled = hasEnabledAction
        guard let view = item.view else { return }
        view.alphaValue = hasEnabledAction
            ? LibraryNotesLayout.toolbarEditorToolsEnabledAlpha
            : LibraryNotesLayout.toolbarEditorToolsDisabledAlpha
        for button in editorToolButtons(in: view) {
            let identifier = button.identifier?.rawValue
            let isEnabled: Bool
            if identifier == Self.revealToolbarItemIdentifier.rawValue {
                isEnabled = canUseSelectedNote
            } else if identifier == Self.sourceModeToolbarItemIdentifier.rawValue {
                isEnabled = canEditCurrentDocument
            } else {
                isEnabled = canEditCurrentDocument && !isEditorShowingMarkdownSource
            }
            button.isEnabled = isEnabled
            button.alphaValue = 1
            button.contentTintColor = toolbarEditorToolIconTintColor(isEnabled: isEnabled)
            updateToolbarEditorTextButtonAppearance(
                button,
                isEnabled: isEnabled,
                isWindowFocused: window?.isKeyWindow == true
            )
        }
    }

    private func updateSourceModeToolbarButton(in item: NSToolbarItem) {
        guard let view = item.view,
              let button = editorToolButtons(in: view).first(where: {
                  $0.identifier?.rawValue == Self.sourceModeToolbarItemIdentifier.rawValue
              }) else { return }
        let label = isEditorShowingMarkdownSource ? "显示渲染模式" : "显示 Markdown 源码"
        let symbol = isEditorShowingMarkdownSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right"
        button.image = toolbarEditorToolSymbolImage(symbolName: symbol, label: label)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func editorToolButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        for subview in view.subviews {
            buttons.append(contentsOf: editorToolButtons(in: subview))
        }
        return buttons
    }

    private func updateToolbarEditorTextButtonAppearance(
        _ button: NSButton,
        isEnabled: Bool,
        isWindowFocused: Bool
    ) {
        guard button.identifier?.rawValue == Self.formatToolbarItemIdentifier.rawValue else { return }
        let titleAlpha = isEnabled && isWindowFocused
            ? LibraryNotesLayout.toolbarIconEnabledAlpha
            : LibraryNotesLayout.toolbarIconDisabledAlpha
        button.attributedTitle = NSAttributedString(string: "Aa", attributes: [
            .font: NSFont.systemFont(
                ofSize: LibraryNotesLayout.toolbarEditorFormatFontSize,
                weight: .regular
            ),
            .foregroundColor: panelPrimaryTextColor().withAlphaComponent(titleAlpha)
        ])
    }

    private func refreshToolbarEditorTextButtonFocus(isWindowFocused: Bool) {
        for item in window?.toolbar?.items ?? [] where item.itemIdentifier == Self.editorToolsToolbarItemIdentifier {
            guard let view = item.view else { continue }
            for button in editorToolButtons(in: view) {
                updateToolbarEditorTextButtonAppearance(
                    button,
                    isEnabled: button.isEnabled,
                    isWindowFocused: isWindowFocused
                )
            }
        }
    }

    func sourceContextMenuForLibrary(row: Int) -> NSMenu? {
        guard let item = sourceOutlineView.item(atRow: row) as? LibrarySourceOutlineItem else { return nil }
        if case .group(title: _, section: .folders) = item.kind {
            let menu = NSMenu()
            let addItem = NSMenuItem(
                title: "将文件夹添加到资料库…",
                action: #selector(addExistingLibraryFolderMenuItemPressed),
                keyEquivalent: ""
            )
            addItem.target = self
            menu.addItem(addItem)
            return menu
        }
        if case .tag(let tag)? = item.scope {
            let menu = NSMenu()
            let deleteItem = NSMenuItem(
                title: "删除标签",
                action: #selector(deleteLibraryTagMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = tag
            menu.addItem(deleteItem)
            return menu
        }
        guard case .folder(let folderURL)? = item.scope else { return nil }
        return makeFolderContextMenu(for: folderURL)
    }

    @objc
    private func deleteLibraryTagMenuItemPressed(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除 \(libraryDisplayTag(tag))？"
        alert.informativeText = "该标签会从所有笔记中移除，此操作无法撤销。"
        alert.addButton(withTitle: "删除标签")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let noteStore = self.noteStore
        Task { [weak self] in
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try noteStore.deleteTag(tag)
                }.value
                guard let self else { return }
                if case .tag(let selectedTag) = selectedScope,
                   selectedTag.localizedCaseInsensitiveCompare(tag) == .orderedSame {
                    selectedScope = .all
                }
                invalidateSourceTagsForLibrary()
                forceFullLibrarySnapshotReload()
                scheduleDeferredSourceTagLoad()
            } catch {
                self?.presentErrorAlert(
                    message: "无法删除标签",
                    details: error.localizedDescription
                )
            }
        }
    }

    private func makeFolderContextMenu(for folderURL: URL) -> NSMenu {
        let menu = NSMenu()

        let standardizedFolder = folderURL.standardizedFileURL
        let rootPaths = Set(Self.rootPreferredDirectories(from: noteStore.preferredDirectories).map(\.path))
        let isRoot = rootPaths.contains(standardizedFolder.path)
        let isDefaultRoot = standardizedFolder.path == noteStore.notesDirectory.standardizedFileURL.path
        let isExternalPreviewFolder = externalPreviewFolderURLs().contains {
            $0.standardizedFileURL.path == standardizedFolder.path
        }

        let revealItem = NSMenuItem(
            title: "在 Finder 中显示",
            action: #selector(revealLibraryFolderMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        revealItem.target = self
        revealItem.representedObject = standardizedFolder
        menu.addItem(revealItem)

        if isRoot {
            menu.addItem(.separator())
            let iconItem = NSMenuItem(title: "更改图标", action: nil, keyEquivalent: "")
            iconItem.submenu = makeFolderIconMenu(for: standardizedFolder)
            menu.addItem(iconItem)

            if !isDefaultRoot {
                menu.addItem(.separator())
                let removeItem = NSMenuItem(
                    title: "从资料库移除",
                    action: #selector(removeLibraryFolderMenuItemPressed(_:)),
                    keyEquivalent: ""
                )
                removeItem.target = self
                removeItem.representedObject = standardizedFolder
                menu.addItem(removeItem)
            }
            return menu
        }

        if isExternalPreviewFolder {
            return menu
        }

        menu.addItem(.separator())

        let renameItem = NSMenuItem(title: "重命名文件夹", action: #selector(renameFolderMenuItemPressed(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = folderURL
        menu.addItem(renameItem)

        let moveItem = NSMenuItem(title: "移动到文件夹", action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveFolderMenu(for: standardizedFolder)
        moveItem.isEnabled = moveItem.submenu?.items.contains(where: \.isEnabled) == true
        menu.addItem(moveItem)

        let deleteItem = NSMenuItem(title: "删除文件夹", action: #selector(deleteFolderMenuItemPressed(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = folderURL
        menu.addItem(deleteItem)

        return menu
    }

    private func makeFolderIconMenu(for folderURL: URL) -> NSMenu {
        let menu = NSMenu()
        let currentSymbolName = noteStore.libraryFolderIconName(for: folderURL)
        let defaultItem = NSMenuItem(
            title: "默认",
            action: #selector(changeFolderIconMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "默认图标")
        defaultItem.state = currentSymbolName == nil ? .on : .off
        defaultItem.representedObject = LibraryFolderIconRequest(folderURL: folderURL, symbolName: nil)
        menu.addItem(defaultItem)
        menu.addItem(.separator())

        for choice in LibraryFolderIconChoice.all {
            let item = NSMenuItem(
                title: choice.title,
                action: #selector(changeFolderIconMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(systemSymbolName: choice.symbolName, accessibilityDescription: choice.title)
            item.state = currentSymbolName == choice.symbolName ? .on : .off
            item.representedObject = LibraryFolderIconRequest(
                folderURL: folderURL,
                symbolName: choice.symbolName
            )
            menu.addItem(item)
        }
        return menu
    }

    func makeMoveFolderMenuForLibrary(at folderURL: URL) -> NSMenu {
        makeMoveFolderMenu(for: folderURL.standardizedFileURL)
    }

    private func makeMoveFolderMenu(for sourceFolder: URL) -> NSMenu {
        let menu = NSMenu()
        let source = sourceFolder.standardizedFileURL
        let currentParentPath = source.deletingLastPathComponent().standardizedFileURL.path

        for folderRow in sourceFolderTreeRows {
            let destination = folderRow.url.standardizedFileURL
            guard destination.path != source.path,
                  !destination.path.hasPrefix(source.path + "/") else {
                continue
            }
            let title = String(repeating: "  ", count: folderRow.depth) + folderTitle(for: destination)
            let item = NSMenuItem(
                title: title,
                action: #selector(moveFolderMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = LibraryFolderMoveRequest(
                source: source,
                destinationParent: destination
            )
            item.isEnabled = destination.path != currentParentPath
            menu.addItem(item)
        }
        return menu
    }

    func noteContextMenuForLibrary(row: Int) -> NSMenu? {
        guard let clickedNote = note(at: row) else { return nil }

        if !tableView.selectedRowIndexes.contains(row) {
            do {
                try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
                suppressSelectionChanges = true
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                suppressSelectionChanges = false
                load(note: clickedNote)
            } catch {
                suppressSelectionChanges = false
                presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
                return nil
            }
        }

        return makeNoteContextMenu()
    }

    private func makeNoteContextMenu() -> NSMenu {
        let menu = NSMenu()
        let isTrashScope = selectedScope == .trash
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        if isTrashScope {
            addTrashNoteLifecycleItems(to: menu, selectionCount: selectionCount)
            menu.addItem(.separator())

            let revealItem = NSMenuItem(title: noteActionTitle(single: "在 Finder 中显示", multiple: "在 Finder 中显示 %d 个文件", count: selectionCount), action: #selector(revealSelectedNoteInFinderPressed), keyEquivalent: "")
            revealItem.target = self
            revealItem.isEnabled = canUseSelectedNote
            menu.addItem(revealItem)

            let copyPathItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 路径", multiple: "复制 %d 个 Markdown 路径", count: selectionCount), action: #selector(copySelectedMarkdownPathPressed), keyEquivalent: "")
            copyPathItem.target = self
            copyPathItem.isEnabled = canUseSelectedNote
            menu.addItem(copyPathItem)

            return menu
        }

        addPinNoteItem(to: menu, selectionCount: selectionCount)
        menu.addItem(.separator())

        let moveItem = NSMenuItem(title: noteActionTitle(single: "移到文件夹", multiple: "移动 %d 条笔记到文件夹", count: selectionCount), action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveNoteMenu()
        moveItem.isEnabled = canMoveSelectedNote
        menu.addItem(moveItem)
        menu.addItem(.separator())

        let revealItem = NSMenuItem(title: noteActionTitle(single: "在 Finder 中显示", multiple: "在 Finder 中显示 %d 个文件", count: selectionCount), action: #selector(revealSelectedNoteInFinderPressed), keyEquivalent: "")
        revealItem.target = self
        revealItem.isEnabled = canUseSelectedNote
        menu.addItem(revealItem)

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

    private func addTrashNoteLifecycleItems(to menu: NSMenu, selectionCount: Int) {
        let restoreItem = NSMenuItem(title: noteActionTitle(single: "恢复", multiple: "恢复 %d 条笔记", count: selectionCount), action: #selector(restoreSelectedNotePressed), keyEquivalent: "")
        restoreItem.target = self
        restoreItem.isEnabled = canRestoreSelectedNote
        menu.addItem(restoreItem)

        let permanentlyDeleteItem = NSMenuItem(title: noteActionTitle(single: "永久删除", multiple: "永久删除 %d 条笔记", count: selectionCount), action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
        permanentlyDeleteItem.target = self
        permanentlyDeleteItem.isEnabled = canUseSelectedNote
        menu.addItem(permanentlyDeleteItem)
    }

    private func addPinNoteItem(to menu: NSMenu, selectionCount: Int) {
        let urls = selectedMarkdownFileURLsForLibrary()
        let allPinned = !urls.isEmpty && urls.allSatisfy { noteStore.isLibraryNotePinned(at: $0) }
        let title = allPinned
            ? noteActionTitle(single: "取消置顶", multiple: "取消置顶 %d 条笔记", count: selectionCount)
            : noteActionTitle(single: "置顶笔记", multiple: "置顶 %d 条笔记", count: selectionCount)
        let item = NSMenuItem(title: title, action: #selector(togglePinnedNotesPressed), keyEquivalent: "")
        item.target = self
        item.isEnabled = canUseSelectedNote && selectedScope != .trash
        menu.addItem(item)
    }

    func makeExportMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

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

    func makeNoteListActionsMenuForLibrary() -> NSMenu {
        let menu = NSMenu()

        let sortItem = NSMenuItem(title: "排序方式", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for (title, order) in [
            ("编辑日期", LibraryNoteSortOrder.dateEdited),
            ("创建日期", .dateCreated),
            ("标题", .title)
        ] {
            let item = NSMenuItem(
                title: title,
                action: #selector(noteListSortMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = order.rawValue
            item.state = noteListSortOrder == order ? .on : .off
            sortMenu.addItem(item)
        }
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)

        let groupingItem = NSMenuItem(
            title: "按日期分组",
            action: #selector(noteListGroupingMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        groupingItem.target = self
        groupingItem.state = groupsNoteListByDate ? .on : .off
        menu.addItem(groupingItem)

        return menu
    }

    @objc
    private func noteListGroupingMenuItemPressed(_ sender: NSMenuItem) {
        setNoteListGroupingForLibrary(!groupsNoteListByDate)
    }

    func setNoteListGroupingForLibrary(_ groupsByDate: Bool) {
        guard groupsNoteListByDate != groupsByDate else { return }
        groupsNoteListByDate = groupsByDate
        noteStore.libraryGroupsNotesByDate = groupsNoteListByDate
        rebuildNoteListRowsForDisplayOptions()
    }

    @objc
    private func noteListSortMenuItemPressed(_ sender: NSMenuItem) {
        guard let order = LibraryNoteSortOrder(rawValue: sender.tag) else { return }
        setNoteListSortOrderForLibrary(order)
    }

    func setNoteListSortOrderForLibrary(_ order: LibraryNoteSortOrder) {
        guard order != noteListSortOrder else { return }
        noteListSortOrder = order
        noteStore.libraryNoteSortOrderRawValue = order.rawValue
        rebuildNoteListRowsForDisplayOptions()
    }

    func makeMoreActionsMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let isTrashScope = selectedScope == .trash
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        let openItem = NSMenuItem(title: "独立窗口打开", action: #selector(openSelectedInSeparateWindow), keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = canUseSingleSelectedNote
        menu.addItem(openItem)

        if !isTrashScope {
            addPinNoteItem(to: menu, selectionCount: selectionCount)
        }

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

        let manageAttachmentsItem = NSMenuItem(
            title: "管理附件…",
            action: #selector(manageAttachmentsPressed),
            keyEquivalent: ""
        )
        manageAttachmentsItem.target = self
        menu.addItem(manageAttachmentsItem)

        menu.addItem(.separator())

        if isTrashScope {
            addTrashNoteLifecycleItems(to: menu, selectionCount: selectionCount)
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

    func makeFormatMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let groups: [[(String, LibraryFormatCommand, String, NSEvent.ModifierFlags)]] = [
            [
                ("标题", .heading1, "1", [.command, .option]),
                ("副标题", .heading2, "2", [.command, .option]),
                ("小标题", .heading3, "3", [.command, .option]),
                ("正文", .paragraph, "0", [.command, .option])
            ],
            [
                ("加粗", .bold, "b", [.command]),
                ("斜体", .italic, "i", [.command]),
                ("下划线", .underline, "u", [.command]),
                ("删除线", .strikethrough, "x", [.command, .shift])
            ],
            [
                ("待办列表", .checklist, "9", [.command, .shift]),
                ("项目符号列表", .bullet, "8", [.command, .shift]),
                ("编号列表", .ordered, "7", [.command, .shift])
            ]
        ]

        for (groupIndex, items) in groups.enumerated() {
            if groupIndex > 0 {
                menu.addItem(.separator())
            }
            for (title, command, keyEquivalent, modifiers) in items {
                let item = NSMenuItem(title: title, action: #selector(formatMenuItemPressed(_:)), keyEquivalent: keyEquivalent)
                item.target = self
                item.tag = command.rawValue
                item.keyEquivalentModifierMask = modifiers
                item.state = isFormatCommandActive(command) ? .on : .off
                menu.addItem(item)
            }
        }

        return menu
    }

    func makeSelectionFormattingMenuForLibrary() -> NSMenu? {
        guard canEditCurrentDocument,
              !isEditorShowingMarkdownSource,
              editorTextView.selectedRange().length > 0 else { return nil }

        let menu = NSMenu(title: "快捷格式")
        let enabled = noteStore.enabledSelectionToolbarOptions
        let inlineCommands: [(SelectionToolbarOption, String, String, LibraryFormatCommand)] = [
            (.bold, "加粗", "bold", .bold),
            (.italic, "斜体", "italic", .italic)
        ]
        for (option, title, symbolName, command) in inlineCommands where enabled.contains(option) {
            let item = NSMenuItem(title: title, action: #selector(formatMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.tag = command.rawValue
            item.state = isFormatCommandActive(command) ? .on : .off
            item.image = selectionMenuImage(symbolName: symbolName, title: title)
            menu.addItem(item)
        }

        if enabled.contains(.highlight) {
            let isHighlighted = isFormatCommandActive(.highlight)
            let highlightItem = NSMenuItem(title: "高亮", action: #selector(formatMenuItemPressed(_:)), keyEquivalent: "")
            highlightItem.target = self
            highlightItem.tag = (isHighlighted ? LibraryFormatCommand.removeHighlight : .highlight).rawValue
            highlightItem.state = isHighlighted ? .on : .off
            highlightItem.image = selectionMenuImage(symbolName: "highlighter", title: "高亮")
            menu.addItem(highlightItem)
        }

        if enabled.contains(.link) {
            let linkItem = NSMenuItem(title: "添加链接", action: #selector(linkPressed), keyEquivalent: "")
            linkItem.target = self
            linkItem.image = selectionMenuImage(symbolName: "link", title: "添加链接")
            menu.addItem(linkItem)
        }

        let conversionOptions: Set<SelectionToolbarOption> = [.conversion, .checklist, .bulletList, .orderedList]
        if !enabled.isDisjoint(with: conversionOptions) {
            let conversionItem = NSMenuItem(title: "转换为", action: nil, keyEquivalent: "")
            conversionItem.image = selectionMenuTextImage("Aa", title: "转换为")
            let conversionMenu = NSMenu(title: "转换为")
            let conversionCommands: [(SelectionToolbarOption, String, String, LibraryFormatCommand)] = [
                (.conversion, "正文", "textformat", .paragraph),
                (.conversion, "标题", "textformat.size.larger", .heading1),
                (.conversion, "副标题", "textformat.size", .heading2),
                (.conversion, "小标题", "textformat.size.smaller", .heading3),
                (.bulletList, "项目符号列表", "list.bullet", .bullet),
                (.orderedList, "编号列表", "list.number", .ordered),
                (.checklist, "待办列表", "checkmark.square", .checklist)
            ]
            for (option, title, symbolName, command) in conversionCommands where enabled.contains(option) {
                let item = NSMenuItem(title: title, action: #selector(formatMenuItemPressed(_:)), keyEquivalent: "")
                item.target = self
                item.tag = command.rawValue
                item.state = isFormatCommandActive(command) ? .on : .off
                item.image = selectionMenuImage(symbolName: symbolName, title: title)
                conversionMenu.addItem(item)
            }
            conversionItem.submenu = conversionMenu
            menu.insertItem(conversionItem, at: 0)
        }
        return menu
    }

    private func configureEditorInsertContextMenu(_ menu: NSMenu) {
        let enabled = noteStore.enabledEditorContextMenuOptions
        let commands: [(EditorContextMenuOption, String, String, Selector)] = [
            (.insertTable, "表格", "tablecells", #selector(tablePressed)),
            (.insertLink, "链接…", "link", #selector(linkPressed)),
            (.insertAttachment, "附件…", "paperclip", #selector(attachmentPressed))
        ]
        let visibleCommands = commands.filter { enabled.contains($0.0) }
        guard !visibleCommands.isEmpty else { return }
        let insertItem = NSMenuItem(title: "插入", action: nil, keyEquivalent: "")
        insertItem.image = selectionMenuImage(symbolName: "plus", title: "插入")
        insertItem.isEnabled = canEditCurrentDocument && !isEditorShowingMarkdownSource
        let insertMenu = NSMenu(title: "插入")
        for (_, title, symbolName, action) in visibleCommands {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = selectionMenuImage(symbolName: symbolName, title: title)
            item.isEnabled = insertItem.isEnabled
            insertMenu.addItem(item)
        }
        insertItem.submenu = insertMenu
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        menu.insertItem(insertItem, at: 0)
    }

    private func selectionMenuImage(symbolName: String, title: String) -> NSImage? {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
    }

    private func selectionMenuTextImage(_ text: String, title: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16))
        image.lockFocus()
        (text as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = title
        return image
    }

    private func isFormatCommandActive(_ command: LibraryFormatCommand) -> Bool {
        if let targetKind = command.paragraphKind,
           let storage = editorTextView.textStorage {
            let kinds = selectedLineRanges().map {
                MarkdownRichTextCodec.paragraphKind(at: $0, in: storage)
            }
            return !kinds.isEmpty && kinds.allSatisfy { sameParagraphCategory($0, targetKind) }
        }

        let attributes: [NSAttributedString.Key: Any]
        if let storage = editorTextView.textStorage, storage.length > 0 {
            let location = min(editorTextView.selectedRange().location, storage.length - 1)
            attributes = storage.attributes(at: location, effectiveRange: nil)
        } else {
            attributes = editorTextView.typingAttributes
        }
        switch command {
        case .bold:
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        case .italic:
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            return isItalicActive(font: font, obliqueness: attributes[.obliqueness])
        case .underline:
            return (attributes[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        case .strikethrough:
            return (attributes[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue
        case .highlight:
            return (attributes[.qmHighlight] as? Bool) == true
        case .removeHighlight:
            return (attributes[.qmHighlight] as? Bool) != true
        default:
            return false
        }
    }

    private func makeMoveNoteMenu() -> NSMenu {
        let menu = NSMenu()
        for folderRow in sourceFolderRows {
            let folderURL = folderRow.url
            let title = String(repeating: "  ", count: folderRow.depth) + folderTitle(for: folderURL)
            let item = NSMenuItem(title: title, action: #selector(moveNoteMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = folderURL
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    @discardableResult
    func configureLinkContextMenuForLibrary(_ menu: NSMenu, for link: MarkdownLinkReference) -> Bool {
        let openItem = NSMenuItem(title: "打开链接", action: #selector(openLinkMenuItemPressed(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = link
        openItem.isEnabled = markdownLinkDestination(link.url, relativeTo: selectedURL) != nil

        let editItem = NSMenuItem(title: "编辑链接...", action: #selector(editLinkMenuItemPressed(_:)), keyEquivalent: "")
        editItem.target = self
        editItem.representedObject = link
        editItem.isEnabled = canEditCurrentDocument

        let copyItem = NSMenuItem(title: "复制链接", action: #selector(copyLinkMenuItemPressed(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = link

        let removeItem = NSMenuItem(title: "移除链接", action: #selector(removeLinkMenuItemPressed(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = link
        removeItem.isEnabled = canEditCurrentDocument

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [openItem, editItem, copyItem, removeItem].reversed() {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    private func openLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        _ = openMarkdownLinkForLibrary(link)
    }

    @objc
    private func editLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        presentLinkEditorForLibrary(
            title: "编辑链接",
            destination: link.url,
            name: link.label
        ) { [weak self] destination, name in
            self?.updateLinkForLibrary(
                link,
                label: name.isEmpty ? destination : name,
                url: destination
            )
        }
    }

    @objc
    private func copyLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url, forType: .string)
    }

    @objc
    private func removeLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        updateLinkForLibrary(link, url: nil)
    }

    @discardableResult
    private func openMarkdownLinkForLibrary(_ link: MarkdownLinkReference) -> Bool {
        guard let destination = markdownLinkDestination(link.url, relativeTo: selectedURL) else {
            return false
        }
        switch destination {
        case .localMarkdown(let url):
            do {
                try openMarkdownDocumentForLibrary(at: url)
            } catch {
                presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
                return false
            }
        case .external(let url):
            NSWorkspace.shared.open(url)
        }
        return true
    }

    func updateLinkForLibrary(_ link: MarkdownLinkReference, label: String? = nil, url: String?) {
        guard canEditCurrentDocument,
              let storage = editorTextView.textStorage,
              link.range.location >= 0,
              NSMaxRange(link.range) <= storage.length,
              storage.attribute(.qmLinkURL, at: link.range.location, effectiveRange: nil) != nil else {
            return
        }

        suppressEditorChanges = true
        storage.beginEditing()
        if let url {
            if let label {
                storage.replaceCharacters(in: link.range, with: label)
            }
            let updatedRange = NSRange(location: link.range.location, length: (label ?? link.label).utf16.count)
            storage.removeAttribute(.qmAutomaticLink, range: updatedRange)
            storage.addAttribute(.qmLinkURL, value: url, range: updatedRange)
            storage.addAttribute(.foregroundColor, value: theme.accentColor, range: updatedRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: updatedRange)
        } else {
            storage.removeAttribute(.qmAutomaticLink, range: link.range)
            storage.removeAttribute(.qmLinkURL, range: link.range)
            storage.removeAttribute(.underlineStyle, range: link.range)
            storage.addAttribute(.foregroundColor, value: theme.textColor, range: link.range)
        }
        storage.endEditing()
        suppressEditorChanges = false

        let selectedLength = url == nil ? link.range.length : (label ?? link.label).utf16.count
        editorTextView.setSelectedRange(NSRange(location: link.range.location, length: selectedLength))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    private func presentLinkEditorForLibrary(
        title: String,
        destination: String,
        name: String,
        onSubmit: @escaping (String, String) -> Void
    ) {
        guard linkEditorSheetController == nil, let window else { return }
        editorTextView.dismissSelectionFormattingPanel()
        let controller = LinkEditorSheetController(
            title: title,
            destination: destination,
            name: name,
            onSubmit: onSubmit,
            onDismiss: { [weak self] in
                self?.linkEditorSheetController = nil
                self?.focusEditorForLibraryAction()
            }
        )
        linkEditorSheetController = controller
        controller.beginSheet(for: window)
    }

    @discardableResult
    func configureMarkdownTableContextMenuForLibrary(_ menu: NSMenu, atCharacterIndex characterIndex: Int) -> Bool {
        guard canEditCurrentDocument else {
            return false
        }

        guard let string = editorTextView.textStorage?.mutableString else {
            return false
        }
        let richLocation = richMarkdownTableLocation(atCharacterIndex: characterIndex)
        let plainLocation = markdownTableLocation(atCharacterIndex: characterIndex, in: string)
        guard richLocation != nil || plainLocation != nil else {
            return false
        }
        let columnCount = richLocation?.snapshot.columnCount ?? plainLocation?.columnCount ?? 0
        let isDataRow = richLocation.map { $0.row > 0 } ?? isMarkdownTableDataRow(atCharacterIndex: characterIndex)

        let insertRowItem = NSMenuItem(title: "插入表格行", action: #selector(insertMarkdownTableRowMenuItemPressed(_:)), keyEquivalent: "")
        insertRowItem.target = self
        insertRowItem.representedObject = characterIndex

        let insertColumnItem = NSMenuItem(title: "插入右侧列", action: #selector(insertMarkdownTableColumnMenuItemPressed(_:)), keyEquivalent: "")
        insertColumnItem.target = self
        insertColumnItem.representedObject = characterIndex

        let deleteRowItem = NSMenuItem(title: "删除表格行", action: #selector(deleteMarkdownTableRowMenuItemPressed(_:)), keyEquivalent: "")
        deleteRowItem.target = self
        deleteRowItem.representedObject = characterIndex
        deleteRowItem.keyEquivalent = "\u{7F}"
        deleteRowItem.keyEquivalentModifierMask = [.command]
        deleteRowItem.isEnabled = isDataRow

        let deleteColumnItem = NSMenuItem(title: "删除表格列", action: #selector(deleteMarkdownTableColumnMenuItemPressed(_:)), keyEquivalent: "")
        deleteColumnItem.target = self
        deleteColumnItem.representedObject = characterIndex
        deleteColumnItem.isEnabled = columnCount > 2

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [insertRowItem, insertColumnItem, deleteRowItem, deleteColumnItem].reversed() {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    private func insertMarkdownTableRowMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        moveEditorSelection(to: characterIndex)
        insertTableForLibrary()
    }

    @objc
    private func deleteMarkdownTableRowMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        moveEditorSelection(to: characterIndex)
        deleteCurrentMarkdownTableRowForLibrary()
    }

    @objc
    private func insertMarkdownTableColumnMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        insertMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex)
    }

    @objc
    private func deleteMarkdownTableColumnMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        deleteMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex)
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
        if isEditorShowingMarkdownSource {
            editorSearchHighlightRefreshTask?.cancel()
            markDirty()
            return
        }
        let activeSearchQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRefreshSearchHighlights = !activeSearchQuery.isEmpty
        if !shouldRefreshSearchHighlights {
            removeEditorSearchHighlights()
        }
        if !normalizeCurrentLineAfterListPrefixEdit() {
            interpretTypedMarkdownIfNeeded()
        }
        updateTypingAttributesFromInsertionPoint()
        markDirty()
        if shouldRefreshSearchHighlights {
            scheduleEditorSearchHighlightRefresh(query: activeSearchQuery)
        }
    }

    private func scheduleEditorSearchHighlightRefresh(query: String) {
        editorSearchHighlightRefreshTask?.cancel()
        editorSearchHighlightRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self, !self.isEditorShowingMarkdownSource else { return }
            self.refreshEditorSearchHighlightsAtomically(query: query)
            self.editorSearchHighlightRefreshTask = nil
        }
    }

    private func refreshEditorSearchHighlightsAtomically(query: String) {
        guard let storage = editorTextView.textStorage else { return }
        let wasSuppressingEditorChanges = suppressEditorChanges
        suppressEditorChanges = true
        storage.beginEditing()
        applyEditorSearchHighlights(query: query)
        storage.endEditing()
        suppressEditorChanges = wasSuppressingEditorChanges
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

        if storage.length == 0 {
            editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
            return
        }

        if location == 0 {
            if storage.length > 0,
               storage.attribute(.qmTableID, at: 0, effectiveRange: nil) != nil {
                var attributes = storage.attributes(at: 0, effectiveRange: nil)
                attributes.removeValue(forKey: .qmTablePlaceholder)
                editorTextView.typingAttributes = attributes
                return
            }
            editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
            return
        }

        let tableProbeLocation = min(location, storage.length - 1)
        if storage.attribute(.qmTableID, at: tableProbeLocation, effectiveRange: nil) != nil {
            var attributes = storage.attributes(at: tableProbeLocation, effectiveRange: nil)
            attributes.removeValue(forKey: .qmTablePlaceholder)
            editorTextView.typingAttributes = attributes
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
        applyParagraphKind(target, togglesOffWhenMatching: true)
    }

    private func setParagraphKind(_ target: MarkdownParagraphKind) {
        applyParagraphKind(target, togglesOffWhenMatching: false)
    }

    private func applyParagraphKind(_ target: MarkdownParagraphKind, togglesOffWhenMatching: Bool) {
        guard selectedScope != .trash, let storage = editorTextView.textStorage else { return }
        let ranges = selectedLineRanges()
        let currentKinds = ranges.map { MarkdownRichTextCodec.paragraphKind(at: $0, in: storage) }
        let allMatchTarget = currentKinds.allSatisfy { sameParagraphCategory($0, target) }
        if allMatchTarget, !togglesOffWhenMatching {
            return
        }
        let shouldResetToParagraph = togglesOffWhenMatching && allMatchTarget
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
        guard !isEditorShowingMarkdownSource else { return }
        focusEditorForLibraryAction()
        let undoSnapshot = libraryFormattingUndoSnapshot()
        if let paragraphKind = command.paragraphKind {
            setParagraphKind(paragraphKind)
            registerLibraryFormattingUndoIfNeeded(before: undoSnapshot, actionName: command.undoActionName)
            return
        }
        switch command {
        case .bold:
            toggleInlineFontTrait(.boldFontMask)
        case .italic:
            toggleInlineFontTrait(.italicFontMask)
        case .underline:
            toggleIntAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue, actionName: "下划线")
        case .strikethrough:
            toggleIntAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue, actionName: "删除线")
        case .highlight:
            setHighlightForLibrary(enabled: true)
        case .removeHighlight:
            setHighlightForLibrary(enabled: false)
        case .heading1, .heading2, .heading3, .paragraph, .checklist, .bullet, .ordered:
            break
        }
        registerLibraryFormattingUndoIfNeeded(before: undoSnapshot, actionName: command.undoActionName)
    }

    private func libraryFormattingUndoSnapshot() -> LibraryFormattingUndoSnapshot? {
        guard let storage = editorTextView.textStorage else { return nil }
        return LibraryFormattingUndoSnapshot(
            content: NSAttributedString(attributedString: storage),
            selection: editorTextView.selectedRange()
        )
    }

    private func registerLibraryFormattingUndoIfNeeded(
        before: LibraryFormattingUndoSnapshot?,
        actionName: String
    ) {
        guard let before,
              let after = libraryFormattingUndoSnapshot(),
              !before.content.isEqual(to: after.content),
              let undoManager = editorTextView.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreLibraryFormattingSnapshot(before, inverse: after, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func restoreLibraryFormattingSnapshot(
        _ snapshot: LibraryFormattingUndoSnapshot,
        inverse: LibraryFormattingUndoSnapshot,
        actionName: String
    ) {
        editorTextView.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreLibraryFormattingSnapshot(inverse, inverse: snapshot, actionName: actionName)
        }
        editorTextView.undoManager?.setActionName(actionName)
        guard let storage = editorTextView.textStorage else { return }
        suppressEditorChanges = true
        storage.setAttributedString(snapshot.content)
        suppressEditorChanges = false
        let location = min(snapshot.selection.location, storage.length)
        let length = min(snapshot.selection.length, max(storage.length - location, 0))
        editorTextView.setSelectedRange(NSRange(location: location, length: length))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    private func setHighlightForLibrary(enabled: Bool) {
        guard selectedScope != .trash,
              let storage = editorTextView.textStorage,
              editorTextView.selectedRange().length > 0 else { return }
        let selection = editorTextView.selectedRange()
        suppressEditorChanges = true
        storage.beginEditing()
        if enabled {
            storage.addAttributes([
                .qmHighlight: true,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.38)
            ], range: selection)
        } else {
            storage.removeAttribute(.qmHighlight, range: selection)
            var location = selection.location
            while location < NSMaxRange(selection) {
                var effectiveRange = NSRange(location: 0, length: 0)
                let isSearchHighlight = storage.attribute(
                    .qmSearchHighlight,
                    at: location,
                    effectiveRange: &effectiveRange
                ) != nil
                let clippedRange = NSIntersectionRange(selection, effectiveRange)
                if isSearchHighlight {
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor.systemYellow.withAlphaComponent(0.30),
                        range: clippedRange
                    )
                } else {
                    storage.removeAttribute(.backgroundColor, range: clippedRange)
                }
                location = NSMaxRange(clippedRange)
            }
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        markDirty()
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
        let removesTrait = selectionEntirelyHasFontTrait(
            trait,
            selection: selection,
            storage: storage
        )
        suppressEditorChanges = true
        storage.beginEditing()
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let font = (storage.attribute(.font, at: location, effectiveRange: &effectiveRange) as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            let updatedFont = removesTrait
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: updatedFont, range: clippedRange)
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
        let removesItalic = selectionEntirelyUsesItalic(
            selection: selection,
            storage: storage
        )
        suppressEditorChanges = true
        storage.beginEditing()
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = storage.attributes(at: location, effectiveRange: &effectiveRange)
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            if removesItalic {
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

    private func selectionEntirelyHasFontTrait(
        _ trait: NSFontTraitMask,
        selection: NSRange,
        storage: NSTextStorage
    ) -> Bool {
        var allMatch = true
        storage.enumerateAttribute(.font, in: selection) { value, _, stop in
            let font = (value as? NSFont) ?? theme.bodyFont
            guard NSFontManager.shared.traits(of: font).contains(trait) else {
                allMatch = false
                stop.pointee = true
                return
            }
        }
        return allMatch
    }

    private func selectionEntirelyUsesItalic(
        selection: NSRange,
        storage: NSTextStorage
    ) -> Bool {
        var allMatch = true
        storage.enumerateAttributes(in: selection) { attributes, _, stop in
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            guard isItalicActive(font: font, obliqueness: attributes[.obliqueness]) else {
                allMatch = false
                stop.pointee = true
                return
            }
        }
        return allMatch
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
        var enabled = true
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            guard (storage.attribute(key, at: location, effectiveRange: &effectiveRange) as? Int) == enabledValue else {
                enabled = false
                break
            }
            location = max(location + 1, NSMaxRange(effectiveRange))
        }

        suppressEditorChanges = true
        storage.beginEditing()
        if enabled {
            storage.removeAttribute(key, range: selection)
            if key == .underlineStyle {
                storage.removeAttribute(.underlineColor, range: selection)
            } else if key == .strikethroughStyle {
                storage.removeAttribute(.strikethroughColor, range: selection)
            }
        } else {
            storage.addAttribute(key, value: enabledValue, range: selection)
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        updateTypingAttributesFromInsertionPoint()
        editorTextView.layoutManager?.invalidateDisplay(forCharacterRange: selection)
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
        if insertTableRowInCurrentMarkdownTableForLibrary() {
            return
        }

        let markdown = """
        | Column 1 | Column 2 |
        | --- | --- |
        |  |  |
        """
        insertMarkdownBlockForLibrary(markdown)
    }

    private enum MarkdownTableCellDirection {
        case next
        case previous
    }

    private struct MarkdownTableLocation {
        let lineRange: NSRange
        let columnIndex: Int
        let columnCount: Int
    }

    private struct RichMarkdownTableSnapshot {
        let tableRange: NSRange
        let rows: [[String]]
        let cellRanges: [[NSRange]]
        let columnCount: Int
    }

    private struct RichMarkdownTableLocation {
        let snapshot: RichMarkdownTableSnapshot
        let row: Int
        let column: Int
    }

    private func moveMarkdownTableCellSelectionForLibrary(_ direction: MarkdownTableCellDirection) -> Bool {
        guard selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: editorTextView.selectedRange().location) {
            let flatIndex = location.row * location.snapshot.columnCount + location.column
            switch direction {
            case .next:
                let cellCount = location.snapshot.rows.count * location.snapshot.columnCount
                if flatIndex + 1 < cellCount {
                    let nextIndex = flatIndex + 1
                    moveEditorSelection(to: location.snapshot.cellRanges[nextIndex / location.snapshot.columnCount][nextIndex % location.snapshot.columnCount].location)
                    return true
                }

                var rows = location.snapshot.rows
                rows.append(Array(repeating: "", count: location.snapshot.columnCount))
                replaceRichMarkdownTable(
                    location.snapshot,
                    rows: rows,
                    selectedRow: rows.count - 1,
                    selectedColumn: 0
                )
                return true

            case .previous:
                let previousIndex = max(flatIndex - 1, 0)
                moveEditorSelection(to: location.snapshot.cellRanges[previousIndex / location.snapshot.columnCount][previousIndex % location.snapshot.columnCount].location)
                return true
            }
        }

        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }

        let currentLineRange = visibleLineRangeForSelection()
        let currentLine = string.substring(with: currentLineRange)
        guard markdownTableColumnCount(in: currentLine) != nil,
              !isMarkdownTableSeparatorLine(currentLine),
              let currentCell = markdownTableCellIndex(at: editorTextView.selectedRange().location, lineRange: currentLineRange, in: string),
              let currentCellStarts = markdownTableCellStartLocations(in: currentLine, lineStartLocation: currentLineRange.location) else {
            return false
        }

        switch direction {
        case .next:
            if currentCell + 1 < currentCellStarts.count {
                moveEditorSelection(to: currentCellStarts[currentCell + 1])
                return true
            }

            if let nextRow = adjacentMarkdownTableDataRow(after: currentLineRange, in: string),
               let nextStarts = markdownTableCellStartLocations(
                    in: string.substring(with: nextRow),
                    lineStartLocation: nextRow.location
               ),
               let firstStart = nextStarts.first {
                moveEditorSelection(to: firstStart)
                return true
            }

            let columnCount = currentCellStarts.count
            let insertedRowStart = insertEmptyMarkdownTableRow(after: currentLineRange, columnCount: columnCount, in: storage)
            moveEditorSelection(to: insertedRowStart)
            return true

        case .previous:
            if currentCell > 0 {
                moveEditorSelection(to: currentCellStarts[currentCell - 1])
                return true
            }

            if let previousRow = adjacentMarkdownTableDataRow(before: currentLineRange, in: string),
               let previousStarts = markdownTableCellStartLocations(
                    in: string.substring(with: previousRow),
                    lineStartLocation: previousRow.location
               ),
               let lastStart = previousStarts.last {
                moveEditorSelection(to: lastStart)
                return true
            }

            if let firstStart = currentCellStarts.first {
                moveEditorSelection(to: firstStart)
                return true
            }
            return false
        }
    }

    @discardableResult
    private func insertTableRowInCurrentMarkdownTableForLibrary() -> Bool {
        guard selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: editorTextView.selectedRange().location) {
            var rows = location.snapshot.rows
            let insertionRow = min(location.row + 1, rows.count)
            rows.insert(Array(repeating: "", count: location.snapshot.columnCount), at: insertionRow)
            replaceRichMarkdownTable(
                location.snapshot,
                rows: rows,
                selectedRow: insertionRow,
                selectedColumn: min(location.column, location.snapshot.columnCount - 1)
            )
            return true
        }

        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }

        let currentLineRange = visibleLineRangeForSelection()
        let currentLine = string.substring(with: currentLineRange)
        guard markdownTableColumnCount(in: currentLine) != nil else { return false }

        var targetLineRange = currentLineRange
        var columnCount = markdownTableColumnCount(in: currentLine) ?? 2
        if !isMarkdownTableSeparatorLine(currentLine),
           let nextLineRange = lineRange(after: currentLineRange, in: string) {
            let nextLine = string.substring(with: nextLineRange)
            if isMarkdownTableSeparatorLine(nextLine),
               let nextColumnCount = markdownTableColumnCount(in: nextLine) {
                targetLineRange = nextLineRange
                columnCount = nextColumnCount
            }
        }

        moveEditorSelection(to: insertEmptyMarkdownTableRow(after: targetLineRange, columnCount: columnCount, in: storage))
        return true
    }

    private func insertEmptyMarkdownTableRow(after targetLineRange: NSRange, columnCount: Int, in storage: NSTextStorage) -> Int {
        let insertionLocation = NSMaxRange(targetLineRange)
        let rowMarkdown = "\n" + emptyMarkdownTableRow(columnCount: columnCount)
        let rendered = MarkdownRichTextCodec.render(
            markdown: rowMarkdown,
            theme: theme,
            baseURL: selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: NSRange(location: insertionLocation, length: 0), with: rendered)
        suppressEditorChanges = false

        markDirty()
        return min(insertionLocation + 3, storage.length)
    }

    @discardableResult
    private func deleteCurrentMarkdownTableRowForLibrary() -> Bool {
        guard selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: editorTextView.selectedRange().location) {
            guard location.row > 0 else { return false }
            var rows = location.snapshot.rows
            rows.remove(at: location.row)
            replaceRichMarkdownTable(
                location.snapshot,
                rows: rows,
                selectedRow: min(location.row, rows.count - 1),
                selectedColumn: min(location.column, location.snapshot.columnCount - 1)
            )
            return true
        }

        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }

        let currentLineRange = visibleLineRangeForSelection()
        let currentLine = string.substring(with: currentLineRange)
        guard markdownTableColumnCount(in: currentLine) != nil,
              !isMarkdownTableSeparatorLine(currentLine),
              isMarkdownTableDataRow(currentLineRange, in: string) else {
            return false
        }

        let deletionRange = fullLineDeletionRange(for: currentLineRange, in: string)
        let nextSelectionLocation = deletionRange.location

        suppressEditorChanges = true
        storage.replaceCharacters(in: deletionRange, with: NSAttributedString(string: ""))
        suppressEditorChanges = false

        markDirty()
        moveEditorSelection(to: nextSelectionLocation)
        return true
    }

    @discardableResult
    private func insertMarkdownTableColumnForLibrary(atCharacterIndex characterIndex: Int) -> Bool {
        editMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex, operation: .insertAfter)
    }

    @discardableResult
    private func deleteMarkdownTableColumnForLibrary(atCharacterIndex characterIndex: Int) -> Bool {
        editMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex, operation: .delete)
    }

    private enum MarkdownTableColumnOperation {
        case insertAfter
        case delete
    }

    @discardableResult
    private func editMarkdownTableColumnForLibrary(
        atCharacterIndex characterIndex: Int,
        operation: MarkdownTableColumnOperation
    ) -> Bool {
        guard selectedScope != .trash,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: characterIndex) {
            guard operation != .delete || location.snapshot.columnCount > 2 else { return false }
            var rows = location.snapshot.rows
            let selectedColumn: Int
            switch operation {
            case .insertAfter:
                selectedColumn = location.column + 1
                for rowIndex in rows.indices {
                    rows[rowIndex].insert("", at: selectedColumn)
                }
            case .delete:
                selectedColumn = min(location.column, location.snapshot.columnCount - 2)
                for rowIndex in rows.indices {
                    rows[rowIndex].remove(at: location.column)
                }
            }
            replaceRichMarkdownTable(
                location.snapshot,
                rows: rows,
                selectedRow: location.row,
                selectedColumn: selectedColumn
            )
            return true
        }

        let string = editorTextView.string as NSString
        guard let location = markdownTableLocation(atCharacterIndex: characterIndex, in: string),
              let lineRanges = markdownTableLineRanges(containing: location.lineRange, in: string),
              location.columnCount > 1 else {
            return false
        }

        if operation == .delete, location.columnCount <= 2 {
            return false
        }

        var replacementLines: [String] = []
        for lineRange in lineRanges {
            let line = string.substring(with: lineRange)
            guard var cells = markdownTableCells(in: line) else { return false }
            switch operation {
            case .insertAfter:
                cells.insert(isMarkdownTableSeparatorLine(line) ? "---" : "", at: min(location.columnIndex + 1, cells.count))
            case .delete:
                guard cells.indices.contains(location.columnIndex) else { return false }
                cells.remove(at: location.columnIndex)
            }
            replacementLines.append(markdownTableLine(cells: cells))
        }

        guard let firstRange = lineRanges.first,
              let lastRange = lineRanges.last else {
            return false
        }

        let tableRange = NSRange(location: firstRange.location, length: NSMaxRange(lastRange) - firstRange.location)
        let currentRowIndex = lineRanges.firstIndex { $0.location == location.lineRange.location } ?? 0
        let targetColumnIndex: Int
        switch operation {
        case .insertAfter:
            targetColumnIndex = location.columnIndex + 1
        case .delete:
            targetColumnIndex = min(location.columnIndex, max(location.columnCount - 2, 0))
        }

        let rendered = MarkdownRichTextCodec.render(
            markdown: replacementLines.joined(separator: "\n"),
            theme: theme,
            baseURL: selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: tableRange, with: rendered)
        suppressEditorChanges = false

        markDirty()
        let targetLineStart = firstRange.location + replacementLines.prefix(currentRowIndex).reduce(0) { partial, line in
            partial + (line as NSString).length + 1
        }
        if let targetStarts = markdownTableCellStartLocations(
            in: replacementLines[currentRowIndex],
            lineStartLocation: targetLineStart
        ), targetStarts.indices.contains(targetColumnIndex) {
            moveEditorSelection(to: targetStarts[targetColumnIndex])
        } else {
            moveEditorSelection(to: firstRange.location)
        }
        return true
    }

    private func richMarkdownTableLocation(atCharacterIndex characterIndex: Int) -> RichMarkdownTableLocation? {
        guard let storage = editorTextView.textStorage,
              storage.length > 0 else {
            return nil
        }

        let probeLocation = max(0, min(characterIndex, storage.length - 1))
        guard tableAttributeString(.qmTableID, at: probeLocation, in: storage) != nil,
              let row = tableAttributeInteger(.qmTableRow, at: probeLocation, in: storage),
              let column = tableAttributeInteger(.qmTableColumn, at: probeLocation, in: storage),
              let snapshot = richMarkdownTableSnapshot(atCharacterIndex: probeLocation, in: storage),
              snapshot.rows.indices.contains(row),
              snapshot.cellRanges[row].indices.contains(column) else {
            return nil
        }
        return RichMarkdownTableLocation(snapshot: snapshot, row: row, column: column)
    }

    private func richMarkdownTableSnapshot(
        atCharacterIndex characterIndex: Int,
        in storage: NSTextStorage
    ) -> RichMarkdownTableSnapshot? {
        guard storage.length > 0 else { return nil }
        let probeLocation = max(0, min(characterIndex, storage.length - 1))
        var tableRange = NSRange(location: 0, length: 0)
        guard let tableID = storage.attribute(
            .qmTableID,
            at: probeLocation,
            longestEffectiveRange: &tableRange,
            in: NSRange(location: 0, length: storage.length)
        ) as? String else {
            return nil
        }

        let string = storage.string as NSString
        var markdownByRow: [Int: [Int: String]] = [:]
        var rangesByRow: [Int: [Int: NSRange]] = [:]
        var columnCount = 0
        var cursor = tableRange.location
        while cursor < NSMaxRange(tableRange) {
            let paragraphRange = string.paragraphRange(for: NSRange(location: cursor, length: 0))
            let clippedParagraphRange = NSIntersectionRange(paragraphRange, tableRange)
            let hasTrailingNewline = clippedParagraphRange.length > 0
                && string.substring(with: clippedParagraphRange).hasSuffix("\n")
            let cellRange = NSRange(
                location: clippedParagraphRange.location,
                length: max(clippedParagraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
            )
            let metadataLocation = cellRange.length > 0 ? cellRange.location : clippedParagraphRange.location
            guard metadataLocation < storage.length,
                  tableAttributeString(.qmTableID, at: metadataLocation, in: storage) == tableID,
                  let row = tableAttributeInteger(.qmTableRow, at: metadataLocation, in: storage),
                  let column = tableAttributeInteger(.qmTableColumn, at: metadataLocation, in: storage) else {
                break
            }

            columnCount = max(
                columnCount,
                tableAttributeInteger(.qmTableColumnCount, at: metadataLocation, in: storage) ?? 0
            )
            let cellMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
                range: cellRange,
                in: storage,
                paragraphKind: .paragraph,
                theme: theme
            )
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "|", with: "\\|")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            markdownByRow[row, default: [:]][column] = cellMarkdown
            rangesByRow[row, default: [:]][column] = cellRange
            cursor = NSMaxRange(clippedParagraphRange)
        }

        guard columnCount >= 2,
              let maximumRow = markdownByRow.keys.max(),
              maximumRow >= 0 else {
            return nil
        }

        var rows: [[String]] = []
        var cellRanges: [[NSRange]] = []
        for row in 0...maximumRow {
            guard let rowMarkdown = markdownByRow[row],
                  let rowRanges = rangesByRow[row],
                  rowMarkdown.count == columnCount,
                  rowRanges.count == columnCount else {
                return nil
            }
            rows.append((0..<columnCount).map { rowMarkdown[$0] ?? "" })
            cellRanges.append((0..<columnCount).compactMap { rowRanges[$0] })
        }

        return RichMarkdownTableSnapshot(
            tableRange: tableRange,
            rows: rows,
            cellRanges: cellRanges,
            columnCount: columnCount
        )
    }

    private func replaceRichMarkdownTable(
        _ snapshot: RichMarkdownTableSnapshot,
        rows: [[String]],
        selectedRow: Int,
        selectedColumn: Int
    ) {
        guard let storage = editorTextView.textStorage,
              !rows.isEmpty,
              rows.allSatisfy({ $0.count == rows[0].count }),
              rows[0].count >= 2 else {
            return
        }

        let lines = rows.enumerated().flatMap { rowIndex, row -> [String] in
            let rowLine = markdownTableLine(cells: row)
            guard rowIndex == 0 else { return [rowLine] }
            return [rowLine, markdownTableLine(cells: Array(repeating: "---", count: row.count))]
        }
        let source = lines.joined(separator: "\n")
        let rendered = MarkdownRichTextCodec.render(
            markdown: source,
            theme: theme,
            baseURL: selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: snapshot.tableRange, with: rendered)
        suppressEditorChanges = false
        markDirty()

        if let replacement = richMarkdownTableSnapshot(atCharacterIndex: snapshot.tableRange.location, in: storage),
           replacement.cellRanges.indices.contains(selectedRow),
           replacement.cellRanges[selectedRow].indices.contains(selectedColumn) {
            moveEditorSelection(to: replacement.cellRanges[selectedRow][selectedColumn].location)
        } else {
            moveEditorSelection(to: snapshot.tableRange.location)
        }
    }

    private func tableAttributeString(
        _ key: NSAttributedString.Key,
        at location: Int,
        in attributedString: NSAttributedString
    ) -> String? {
        attributedString.attribute(key, at: location, effectiveRange: nil) as? String
    }

    private func tableAttributeInteger(
        _ key: NSAttributedString.Key,
        at location: Int,
        in attributedString: NSAttributedString
    ) -> Int? {
        if let value = attributedString.attribute(key, at: location, effectiveRange: nil) as? Int {
            return value
        }
        return (attributedString.attribute(key, at: location, effectiveRange: nil) as? NSNumber)?.intValue
    }

    private func moveEditorSelection(to location: Int) {
        guard let storage = editorTextView.textStorage else { return }
        editorTextView.setSelectedRange(NSRange(location: max(0, min(location, storage.length)), length: 0))
        updateTypingAttributesFromInsertionPoint()
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
    }

    private func lineRange(after range: NSRange, in string: NSString) -> NSRange? {
        let nextLocation = NSMaxRange(string.lineRange(for: range))
        guard nextLocation < string.length else { return nil }
        let paragraphRange = string.paragraphRange(for: NSRange(location: nextLocation, length: 0))
        let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
        return NSRange(
            location: paragraphRange.location,
            length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
        )
    }

    private func lineRange(before range: NSRange, in string: NSString) -> NSRange? {
        guard range.location > 0 else { return nil }
        let previousProbeLocation = max(range.location - 1, 0)
        let paragraphRange = string.paragraphRange(for: NSRange(location: previousProbeLocation, length: 0))
        let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
        return NSRange(
            location: paragraphRange.location,
            length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
        )
    }

    private func adjacentMarkdownTableDataRow(after range: NSRange, in string: NSString) -> NSRange? {
        var candidate = lineRange(after: range, in: string)
        while let candidateRange = candidate {
            let line = string.substring(with: candidateRange)
            guard markdownTableColumnCount(in: line) != nil else { return nil }
            if !isMarkdownTableSeparatorLine(line) {
                return candidateRange
            }
            candidate = lineRange(after: candidateRange, in: string)
        }
        return nil
    }

    private func adjacentMarkdownTableDataRow(before range: NSRange, in string: NSString) -> NSRange? {
        var candidate = lineRange(before: range, in: string)
        while let candidateRange = candidate {
            let line = string.substring(with: candidateRange)
            guard markdownTableColumnCount(in: line) != nil else { return nil }
            if !isMarkdownTableSeparatorLine(line) {
                return candidateRange
            }
            candidate = lineRange(before: candidateRange, in: string)
        }
        return nil
    }

    private func markdownTableLocation(atCharacterIndex characterIndex: Int, in string: NSString) -> MarkdownTableLocation? {
        guard string.length > 0 else { return nil }
        let safeLocation = max(0, min(characterIndex, string.length))
        let lineRange = visibleLineRange(atCharacterIndex: safeLocation, in: string)
        let line = string.substring(with: lineRange)
        guard let columnCount = markdownTableColumnCount(in: line),
              let columnIndex = markdownTableCellIndex(at: safeLocation, lineRange: lineRange, in: string) else {
            return nil
        }
        return MarkdownTableLocation(lineRange: lineRange, columnIndex: min(columnIndex, columnCount - 1), columnCount: columnCount)
    }

    private func markdownTableLineRanges(containing range: NSRange, in string: NSString) -> [NSRange]? {
        guard markdownTableColumnCount(in: string.substring(with: range)) != nil else { return nil }

        var firstRange = range
        while let previousRange = lineRange(before: firstRange, in: string),
              markdownTableColumnCount(in: string.substring(with: previousRange)) != nil {
            firstRange = previousRange
        }

        var ranges = [firstRange]
        var currentRange = firstRange
        while let nextRange = lineRange(after: currentRange, in: string),
              markdownTableColumnCount(in: string.substring(with: nextRange)) != nil {
            ranges.append(nextRange)
            currentRange = nextRange
        }

        return ranges
    }

    private func markdownTableColumnCount(atCharacterIndex characterIndex: Int) -> Int? {
        let string = editorTextView.string as NSString
        guard string.length > 0 else { return nil }
        return markdownTableLocation(atCharacterIndex: characterIndex, in: string)?.columnCount
    }

    private func isMarkdownTableDataRow(atCharacterIndex characterIndex: Int) -> Bool {
        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }
        guard let tableLocation = markdownTableLocation(atCharacterIndex: characterIndex, in: string) else { return false }
        let visibleLineRange = tableLocation.lineRange
        let line = string.substring(with: visibleLineRange)
        return markdownTableColumnCount(in: line) != nil
            && !isMarkdownTableSeparatorLine(line)
            && isMarkdownTableDataRow(visibleLineRange, in: string)
    }

    private func visibleLineRange(atCharacterIndex characterIndex: Int, in string: NSString) -> NSRange {
        let lineRange = string.paragraphRange(for: NSRange(location: max(0, min(characterIndex, string.length)), length: 0))
        let hasTrailingNewline = string.substring(with: lineRange).hasSuffix("\n")
        return NSRange(
            location: lineRange.location,
            length: max(lineRange.length - (hasTrailingNewline ? 1 : 0), 0)
        )
    }

    private func isMarkdownTableDataRow(_ range: NSRange, in string: NSString) -> Bool {
        if let nextLineRange = lineRange(after: range, in: string) {
            let nextLine = string.substring(with: nextLineRange)
            if isMarkdownTableSeparatorLine(nextLine) {
                return false
            }
            if markdownTableColumnCount(in: nextLine) != nil {
                return true
            }
        }

        if let previousLineRange = lineRange(before: range, in: string) {
            let previousLine = string.substring(with: previousLineRange)
            if isMarkdownTableSeparatorLine(previousLine) {
                return true
            }
            return markdownTableColumnCount(in: previousLine) != nil
        }

        return false
    }

    private func fullLineDeletionRange(for range: NSRange, in string: NSString) -> NSRange {
        let fullLineRange = string.lineRange(for: range)
        if NSMaxRange(fullLineRange) > NSMaxRange(range) {
            return fullLineRange
        }

        if range.location > 0,
           string.substring(with: NSRange(location: range.location - 1, length: 1)) == "\n" {
            return NSRange(location: range.location - 1, length: range.length + 1)
        }

        return fullLineRange
    }

    private func markdownTableColumnCount(in line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }

        let columns = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
        let count = columns.count
        return count >= 2 ? count : nil
    }

    private func isMarkdownTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard markdownTableColumnCount(in: trimmed) != nil else { return false }

        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    private func emptyMarkdownTableRow(columnCount: Int) -> String {
        "| " + Array(repeating: " ", count: max(columnCount, 2)).joined(separator: " | ") + " |"
    }

    private func markdownTableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard markdownTableColumnCount(in: trimmed) != nil else { return nil }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func markdownTableLine(cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    private func markdownTableCellStartLocations(in line: String, lineStartLocation: Int) -> [Int]? {
        let lineString = line as NSString
        let pipeIndexes = markdownTablePipeIndexes(in: lineString)
        guard pipeIndexes.count >= 3 else { return nil }

        return (0..<(pipeIndexes.count - 1)).map { index in
            var start = pipeIndexes[index] + 1
            while start < pipeIndexes[index + 1],
                  lineString.substring(with: NSRange(location: start, length: 1)) == " " {
                start += 1
            }
            return lineStartLocation + min(start, pipeIndexes[index + 1])
        }
    }

    private func markdownTableCellIndex(at location: Int, lineRange: NSRange, in string: NSString) -> Int? {
        let lineString = string.substring(with: lineRange) as NSString
        let pipeIndexes = markdownTablePipeIndexes(in: lineString)
        guard pipeIndexes.count >= 3 else { return nil }

        let localLocation = max(0, min(location - lineRange.location, lineString.length))
        for index in 0..<(pipeIndexes.count - 1) {
            if localLocation <= pipeIndexes[index + 1] {
                return index
            }
        }
        return pipeIndexes.count - 2
    }

    private func markdownTablePipeIndexes(in line: NSString) -> [Int] {
        var indexes: [Int] = []
        for index in 0..<line.length where line.substring(with: NSRange(location: index, length: 1)) == "|" {
            indexes.append(index)
        }
        return indexes
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
        let copiedURL = try MarkdownAttachmentStorage.storeFile(fileURL, in: noteDirectory)
        insertStoredAttachmentForLibrary(copiedURL, relativeTo: noteDirectory)
        return copiedURL
    }

    func markdownTextView(_ textView: MarkdownTextView, pasteAttachmentsFrom pasteboard: NSPasteboard) -> Bool {
        guard textView === editorTextView,
              canEditCurrentDocument,
              let payload = MarkdownAttachmentStorage.pastePayload(from: pasteboard) else {
            return false
        }

        let noteDirectory = targetDirectoryForAttachment()
        do {
            switch payload {
            case .files(let fileURLs):
                for fileURL in fileURLs {
                    let storedURL = try MarkdownAttachmentStorage.storeFile(fileURL, in: noteDirectory)
                    insertStoredAttachmentForLibrary(storedURL, relativeTo: noteDirectory)
                }
            case .imagePNG(let data):
                let storedURL = try MarkdownAttachmentStorage.storePastedPNG(data, in: noteDirectory)
                insertStoredAttachmentForLibrary(storedURL, relativeTo: noteDirectory)
            }
        } catch {
            presentErrorAlert(message: "粘贴附件失败", details: error.localizedDescription)
        }
        return true
    }

    private func insertStoredAttachmentForLibrary(_ fileURL: URL, relativeTo noteDirectory: URL) {
        let markdown = MarkdownAttachmentStorage.markdownReference(for: fileURL, relativeTo: noteDirectory)
        let renderingBaseURL = selectedURL
            ?? noteDirectory.appendingPathComponent(".mudsnote-unsaved.md")
        insertMarkdownBlockForLibrary(markdown, renderingBaseURL: renderingBaseURL)
    }

    private func selectedTextForLinkDefault() -> String {
        let selection = editorTextView.selectedRange()
        guard selection.length > 0, NSMaxRange(selection) <= (editorTextView.string as NSString).length else {
            return ""
        }
        return (editorTextView.string as NSString).substring(with: selection)
    }

    private func insertMarkdownBlockForLibrary(_ markdown: String, renderingBaseURL: URL? = nil) {
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

        replaceSelectionWithRenderedMarkdown(block, renderingBaseURL: renderingBaseURL)
    }

    private func replaceSelectionWithRenderedMarkdown(_ markdown: String, renderingBaseURL: URL? = nil) {
        guard selectedScope != .trash, let storage = editorTextView.textStorage else { return }
        focusEditorForLibraryAction()
        let selection = editorTextView.selectedRange()
        let rendered = MarkdownRichTextCodec.render(
            markdown: markdown,
            theme: theme,
            baseURL: renderingBaseURL ?? selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

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
        if commitSelectedMetadataTagIfNeeded(insertingTrailingText: "\n") { return }
        guard handleStructuredNewline() else {
            textView.insertNewlineIgnoringFieldEditor(self)
            updateTypingAttributesFromInsertionPoint()
            return
        }
    }

    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool {
        guard text == " " || text == "\t" else { return false }
        return commitSelectedMetadataTagIfNeeded(insertingTrailingText: text)
    }

    private func commitSelectedMetadataTagIfNeeded(
        insertingTrailingText trailingText: String
    ) -> Bool {
        let selection = editorTextView.selectedRange()
        guard selection.length == 0 else { return false }
        let source = editorTextView.string as NSString
        let caret = min(selection.location, source.length)
        let paragraph = source.paragraphRange(
            for: NSRange(location: caret, length: 0)
        )
        let prefix = source.substring(with: NSRange(
            location: paragraph.location,
            length: max(0, caret - paragraph.location)
        ))
        guard let match = prefix.range(
            of: #"(^|\s)#([^\s#]+)$"#,
            options: .regularExpression
        ) else { return false }
        let token = String(prefix[match]).trimmingCharacters(in: .whitespaces)
        let tag = String(token.dropFirst())
        guard !tag.isEmpty, !tag.contains("/") else { return false }
        let leadingWhitespace = String(prefix[match]).hasPrefix(" ") ? 1 : 0
        let range = NSRange(
            location: paragraph.location
                + prefix.distance(from: prefix.startIndex, to: match.lowerBound)
                + leadingWhitespace,
            length: token.utf16.count
        )
        editorTextView.textStorage?.replaceCharacters(in: range, with: trailingText)
        editorTextView.setSelectedRange(NSRange(
            location: range.location + trailingText.utf16.count,
            length: 0
        ))
        selectedTags = MarkdownEditorDocument.normalizedTags(selectedTags + [tag])
        editorTextView.setMetadataTags(selectedTags) { [weak self] removed in
            self?.removeSelectedMetadataTag(removed)
        }
        markDirty()
        return true
    }

    private func removeSelectedMetadataTag(_ tag: String) {
        selectedTags.removeAll {
            $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
        }
        editorTextView.setMetadataTags(selectedTags) { [weak self] removed in
            self?.removeSelectedMetadataTag(removed)
        }
        markDirty()
    }

    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool {
        guard textView === editorTextView else { return false }
        if !editorSuggestionController.view.isHidden {
            switch event.keyCode {
            case UInt16(kVK_DownArrow):
                editorSuggestionController.moveSelection(delta: 1)
                return true
            case UInt16(kVK_UpArrow):
                editorSuggestionController.moveSelection(delta: -1)
                return true
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                editorSuggestionController.acceptSelection()
                return true
            case UInt16(kVK_Escape):
                dismissEditorSlashSuggestions()
                return true
            default:
                break
            }
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Space),
           modifiers.isEmpty,
           let attachment = textView.fileAttachmentReferenceNearSelection() {
            return previewAttachmentForLibrary(atPath: attachment.path)
        }

        guard event.keyCode == UInt16(kVK_Delete),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] else {
            return false
        }
        return deleteCurrentMarkdownTableRowForLibrary()
    }

    private func updateEditorSlashSuggestions() {
        if editorTextView.hasMarkedText() {
            return
        }
        guard !isEditorShowingMarkdownSource,
              selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let host = window?.contentView else {
            editorSlashSuggestionLastInput = nil
            dismissEditorSlashSuggestions()
            return
        }
        guard let string = editorTextView.textStorage?.mutableString else {
            dismissEditorSlashSuggestions()
            return
        }
        let caret = min(editorTextView.selectedRange().location, string.length)
        let maximumLookback = 128
        let lowerBound = max(caret - maximumLookback, 0)
        let newlineRange = string.rangeOfCharacter(
            from: .newlines,
            options: .backwards,
            range: NSRange(location: lowerBound, length: caret - lowerBound)
        )
        let prefixStart = newlineRange.location == NSNotFound
            ? lowerBound
            : NSMaxRange(newlineRange)
        let startsAtParagraphBoundary = prefixStart == 0 || newlineRange.location != NSNotFound
        let prefixRange = NSRange(location: prefixStart, length: caret - prefixStart)
        let prefix = string.substring(with: prefixRange)
        editorSlashSuggestionInspectionLengthForLibrary = prefixRange.length

        let mentionPattern = startsAtParagraphBoundary
            ? #"(^|\s)@([^@\n]*)$"#
            : #"\s@([^@\n]*)$"#
        if let match = prefix.range(of: mentionPattern, options: .regularExpression) {
            let matchedText = String(prefix[match])
            if let atIndex = matchedText.firstIndex(of: "@") {
                let token = String(matchedText[atIndex...])
                let query = String(token.dropFirst())
                let matchRange = NSRange(match, in: prefix)
                let tokenOffset = matchedText[..<atIndex].utf16.count
                let replacementRange = NSRange(
                    location: prefixStart + matchRange.location + tokenOffset,
                    length: token.utf16.count
                )
                if editorNoteSuggestionQuery != query {
                    scheduleEditorNoteSuggestions(query: query)
                    dismissEditorSlashSuggestions()
                    return
                }
                guard !editorNoteSuggestions.isEmpty else {
                    dismissEditorSlashSuggestions()
                    return
                }
                editorSlashSuggestion = nil
                editorNoteSuggestion = (
                    replacementRange,
                    editorNoteSuggestions
                )
                hostEditorSuggestionView(in: host)
                editorSuggestionController.updateItems(editorNoteSuggestions.map {
                    SuggestionItem(
                        title: $0.title,
                        subtitle: $0.url.deletingLastPathComponent().lastPathComponent,
                        symbolName: "note.text"
                    )
                })
                let size = editorSuggestionController.preferredContentSize
                let tokenRect = editorTextView.convert(
                    caretRectInWindow(for: editorTextView, at: replacementRange.location),
                    to: host
                )
                var origin = NSPoint(x: tokenRect.minX, y: tokenRect.minY - size.height - 6)
                origin.x = min(max(origin.x, 4), max(host.bounds.width - size.width - 4, 4))
                origin.y = min(max(origin.y, 4), max(host.bounds.height - size.height - 4, 4))
                editorSuggestionController.view.frame = NSRect(origin: origin, size: size)
                editorSuggestionController.view.isHidden = false
                slashCommandInputSourceSession.end()
                return
            }
        }

        if let previousInput = editorSlashSuggestionLastInput,
           previousInput.caret == caret,
           previousInput.prefixStart == prefixStart,
           previousInput.prefix == prefix {
            return
        }
        editorSlashSuggestionLastInput = (caret, prefixStart, prefix)

        let pattern = startsAtParagraphBoundary
            ? #"(^|\s)/([^\s/]*)$"#
            : #"\s/([^\s/]*)$"#
        guard let match = prefix.range(of: pattern, options: .regularExpression) else {
            dismissEditorSlashSuggestions()
            return
        }
        let matchedText = String(prefix[match])
        guard let slashIndex = matchedText.firstIndex(of: "/") else {
            dismissEditorSlashSuggestions()
            return
        }
        let token = String(matchedText[slashIndex...])
        let query = String(token.dropFirst()).lowercased()
        let commands = SlashCommand.matching(query, includesAI: false)
        hostEditorSuggestionView(in: host)
        let matchRange = NSRange(match, in: prefix)
        let tokenOffset = matchedText[..<slashIndex].utf16.count
        let replacementRange = NSRange(
            location: prefixStart + matchRange.location + tokenOffset,
            length: token.utf16.count
        )
        editorSlashSuggestion = (replacementRange, commands)
        editorNoteSuggestion = nil
        let items = commands.isEmpty
            ? [SuggestionItem(title: "无匹配命令", subtitle: nil, symbolName: nil)]
            : commands.map { SuggestionItem(title: $0.title, subtitle: nil, symbolName: nil) }
        editorSuggestionController.updateItems(items)
        let size = editorSuggestionController.preferredContentSize
        let tokenRect = editorTextView.convert(
            caretRectInWindow(for: editorTextView, at: replacementRange.location),
            to: host
        )
        var origin = NSPoint(x: tokenRect.minX, y: tokenRect.minY - size.height - 6)
        origin.x = min(max(origin.x, 4), max(host.bounds.width - size.width - 4, 4))
        origin.y = min(max(origin.y, 4), max(host.bounds.height - size.height - 4, 4))
        editorSuggestionController.view.frame = NSRect(origin: origin, size: size)
        editorSuggestionController.view.isHidden = false
        scheduleEditorSlashInputSourceSwitch()
    }

    private func scheduleEditorSlashInputSourceSwitch() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !editorSuggestionController.view.isHidden,
                  editorSlashSuggestion != nil else { return }
            slashCommandInputSourceSession.beginIfAllowed(
                hasMarkedText: editorTextView.hasMarkedText(),
                editorIsFirstResponder: window?.firstResponder === editorTextView
            )
        }
    }

    private func dismissEditorSlashSuggestions() {
        editorSlashSuggestion = nil
        editorNoteSuggestion = nil
        editorSuggestionController.view.isHidden = true
        slashCommandInputSourceSession.end()
    }

    private func acceptEditorSlashSuggestion(at index: Int) {
        if let suggestion = editorNoteSuggestion,
           suggestion.items.indices.contains(index) {
            let item = suggestion.items[index]
            let sourceURL = selectedURL
                ?? targetDirectoryForNewNote().appendingPathComponent("Untitled.md")
            let markdown = noteStore.markdownKnowledgeLink(
                from: sourceURL,
                to: item.url,
                title: item.title
            )
            editorTextView.setSelectedRange(suggestion.replacementRange)
            dismissEditorSlashSuggestions()
            replaceSelectionWithRenderedMarkdown(markdown, renderingBaseURL: sourceURL)
            return
        }
        guard let suggestion = editorSlashSuggestion,
              suggestion.commands.indices.contains(index),
              let storage = editorTextView.textStorage else { return }
        let command = suggestion.commands[index]
        suppressEditorChanges = true
        storage.replaceCharacters(in: suggestion.replacementRange, with: "")
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: suggestion.replacementRange.location, length: 0))
        dismissEditorSlashSuggestions()
        switch command {
        case .heading1: applyFormatCommand(.heading1)
        case .heading2: applyFormatCommand(.heading2)
        case .heading3: applyFormatCommand(.heading3)
        case .checklist: applyFormatCommand(.checklist)
        case .bulletList: applyFormatCommand(.bullet)
        case .orderedList: applyFormatCommand(.ordered)
        case .divider:
            editorTextView.insertText("---", replacementRange: editorTextView.selectedRange())
            libraryUserDidEdit()
        case .aiSummarize, .aiFix, .aiTodos:
            break
        }
    }

    private func scheduleEditorNoteSuggestions(query: String) {
        editorNoteSuggestionTask?.cancel()
        editorNoteSuggestionQuery = query
        editorNoteSuggestions = []
        let noteStore = self.noteStore
        let sourceURL = selectedURL
            ?? targetDirectoryForNewNote().appendingPathComponent("Untitled.md")
        let currentBody = normalizedEditorMarkdownBody()
        editorNoteSuggestionTask = Task { [weak self] in
            let suggestions = await Task.detached(priority: .userInitiated) {
                noteStore.noteMentionSuggestions(
                    query: query,
                    sourceURL: sourceURL,
                    currentBody: currentBody
                )
            }.value
            guard !Task.isCancelled,
                  let self,
                  editorNoteSuggestionQuery == query else { return }
            editorNoteSuggestions = suggestions
            editorNoteSuggestionTask = nil
            editorSlashSuggestionLastInput = nil
            updateEditorSlashSuggestions()
        }
    }

    func markdownTextViewToggleBold(_ textView: MarkdownTextView) { applyFormatCommand(.bold) }
    func markdownTextViewToggleItalic(_ textView: MarkdownTextView) { applyFormatCommand(.italic) }
    func markdownTextViewToggleUnderline(_ textView: MarkdownTextView) { applyFormatCommand(.underline) }
    func markdownTextViewToggleStrikethrough(_ textView: MarkdownTextView) { applyFormatCommand(.strikethrough) }
    func markdownTextViewToggleHeading(_ textView: MarkdownTextView) { applyFormatCommand(.heading1) }
    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView) { applyFormatCommand(.bullet) }
    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView) { applyFormatCommand(.ordered) }
    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView) { applyFormatCommand(.checklist) }

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

    func markdownTextView(_ textView: MarkdownTextView, didCommandClickLinkAt index: Int) -> Bool {
        guard let link = textView.linkReference(atCharacterIndex: index) else { return false }
        return openMarkdownLinkForLibrary(link)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachment attachment: MarkdownAttachmentReference) -> Bool {
        configureAttachmentContextMenu(menu, forAttachmentPath: attachment.path, markdown: attachment.markdown)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachmentPath path: String, markdown: String? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }

        let previewItem = NSMenuItem(title: "快速查看", action: #selector(previewAttachmentMenuItemPressed(_:)), keyEquivalent: " ")
        previewItem.keyEquivalentModifierMask = []
        previewItem.target = self
        previewItem.representedObject = path

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
        for item in [copyPathItem, copyMarkdownItem, revealItem, openItem, previewItem] {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    private func previewAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        attachmentQuickLookController.preview(url)
    }

    @discardableResult
    func previewAttachmentForLibrary(atPath path: String) -> Bool {
        attachmentQuickLookController.preview(URL(fileURLWithPath: path))
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
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    private let noteListTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let noteListWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private let noteListShortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()
}
