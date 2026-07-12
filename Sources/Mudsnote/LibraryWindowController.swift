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
            return "All iCloud"
        case .recent:
            return "最近"
        case .inbox:
            return "Inbox"
        case .folder(let url):
            return url.lastPathComponent.isEmpty ? "Notes" : url.lastPathComponent
        case .tag(let tag):
            return libraryBareTag(tag)
        case .trash:
            return "Recently Deleted"
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

private func librarySearchResults(
    noteStore: NoteStore,
    searchSession: NoteSearchSession,
    scope: LibraryScope,
    query: String,
    limit: Int,
    searchesAllNotes: Bool
) -> [NoteSearchResult] {
    if searchesAllNotes {
        return searchSession.searchNotes(query: query, limit: limit)
    }

    switch scope {
    case .all:
        return searchSession.searchNotes(query: query, limit: limit)
    case .recent:
        return searchSession.searchRecentNotes(query: query, limit: limit)
    case .inbox:
        return searchSession.searchInboxNotes(query: query, limit: limit)
    case .trash:
        return libraryFilteredTrashedNotes(noteStore: noteStore, query: query, limit: limit)
    case .folder(let url):
        return searchSession.searchNotes(query: query, limit: limit, in: url)
    case .tag(let tag):
        return searchSession.searchNotes(query: query, limit: limit, tagged: tag)
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
            snippet: matchingLine.flatMap(MarkdownEditorDocument.previewText(fromMarkdownLine:))
                ?? libraryFirstMeaningfulLine(from: loaded.body)
                ?? "",
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
    MarkdownEditorDocument.firstPreviewLine(in: body)
}

private struct LibraryFolderRow: Equatable, Sendable {
    let url: URL
    let depth: Int
    let hasChildren: Bool
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

struct LibrarySourceCountIndex: Sendable {
    let inboxCount: Int
    private let folderCounts: [String: Int]
    private let tagCounts: [String: Int]

    init(notes: [NoteSearchResult], folderPaths: Set<String>) {
        var inboxCount = 0
        var folderCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]

        for note in notes {
            if libraryIsInboxNote(note) {
                inboxCount += 1
            }

            var directory = note.url.deletingLastPathComponent().standardizedFileURL
            while true {
                let path = directory.path
                if folderPaths.contains(path) {
                    folderCounts[path, default: 0] += 1
                }
                let parent = directory.deletingLastPathComponent().standardizedFileURL
                guard parent.path != path else { break }
                directory = parent
            }

            let noteTagKeys = Set(note.tags.map(Self.tagKey))
            for key in noteTagKeys {
                tagCounts[key, default: 0] += 1
            }
        }

        self.inboxCount = inboxCount
        self.folderCounts = folderCounts
        self.tagCounts = tagCounts
    }

    func count(forFolder url: URL) -> Int {
        folderCounts[url.standardizedFileURL.path, default: 0]
    }

    func count(forTag tag: String) -> Int {
        tagCounts[Self.tagKey(tag), default: 0]
    }

    private static func tagKey(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive], locale: .current)
    }
}

private typealias LoadedLibraryNote = (title: String, body: String, tags: [String])

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
    func replacingURL(_ url: URL) -> NoteSearchResult {
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
            modifiedAt: modifiedAt,
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
            return "Folders"
        case .tags:
            return "Tags"
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
    static let storedLayoutScaleVersion = 4
    static let initialWindowSize = NSSize(width: 1080, height: 680)
    static let presentedWindowSize = NSSize(width: 1080, height: 720)
    static let minimumWindowSize = NSSize(width: 1040, height: 620)
    static let sourceColumnWidth: CGFloat = 220
    static let noteColumnWidth: CGFloat = 200
    static let sourceColumnMinimumWidth: CGFloat = 220
    static let sourceColumnMaximumWidth: CGFloat = 320
    static let noteColumnMinimumWidth: CGFloat = 200
    static let noteColumnMaximumWidth: CGFloat = 320
    static let editorColumnMinimumWidth: CGFloat = 480
    static let noteTableInitialWidth: CGFloat = 174
    static let noteTableMinimumWidth: CGFloat = 174
    static let sourceRowWidth: CGFloat = 192
    static let toolbarSearchWidth: CGFloat = 210
    static let toolbarSearchHeight: CGFloat = 32
    static let toolbarSearchWrapperWidth: CGFloat = 230
    static let toolbarSearchWrapperHeight: CGFloat = 36
    static let toolbarEditorToolsWidth: CGFloat = 184
    static let toolbarEditorToolsHeight: CGFloat = 32
    static let toolbarEditorToolButtonWidth: CGFloat = 35
    static let toolbarEditorToolButtonHeight: CGFloat = 26
    static let toolbarCircularButtonSize: CGFloat = 30
    static let toolbarCircularButtonSymbolPointSize: CGFloat = 16
    static let toolbarIconEnabledAlpha: CGFloat = 0.76
    static let toolbarIconDisabledAlpha: CGFloat = 0.42
    static let toolbarEditorToolIconDisabledAlpha: CGFloat = 1.0
    static let toolbarMoreSymbolName = "ellipsis"
    static let toolbarNoteListTitleWidth: CGFloat = 160
    static let toolbarNoteListTitleHeight: CGFloat = 46
    static let toolbarEditorToolsEnabledAlpha: CGFloat = 1.0
    static let toolbarEditorToolsDisabledAlpha: CGFloat = 0.42
    static let toolbarSymbolPointSize: CGFloat = 19
    static let sourceSymbolPointSize: CGFloat = 16
    static let sourceDisclosureSymbolPointSize: CGFloat = 10
    static let windowScreenMargin: CGFloat = 72
    static let sourceRowHeight: CGFloat = 36
    static let sourceSectionHeaderHeight: CGFloat = 22
    static let sourceStatusRowHeight: CGFloat = 22
    static let sourceListTopInset: CGFloat = 12
    static let sourceListLeadingInset: CGFloat = 14
    static let sourceListBottomInset: CGFloat = 14
    static let sourceListTrailingInset: CGFloat = 14
    static let sourceSurfaceCornerRadius: CGFloat = 24
    static let sourceSurfaceBorderAlpha: CGFloat = 0.20
    static let sourceSurfaceDarkeningAlpha: CGFloat = 0.30
    static let sourceCollapseAnimationDuration: TimeInterval = 0.22
    static let sourceInnerRowSpacing: CGFloat = 1
    static let sourceSectionSpacing: CGFloat = 6
    static let sourceRowCornerRadius: CGFloat = 8
    static let sourceFolderIndentStep: CGFloat = 14
    static let sourceDisclosureButtonWidth: CGFloat = 14
    static let sourceDisclosureButtonHeight: CGFloat = 18
    static let sourceDisclosureToButtonSpacing: CGFloat = 1
    static let sourceCountTrailingInset: CGFloat = 6
    static let sourceCountWidth: CGFloat = 32
    static let noteGroupRowHeight: CGFloat = 54
    static let noteRowHeight: CGFloat = 76
    static let sourceGroupFontSize: CGFloat = 13.5
    static let sourceButtonFontSize: CGFloat = 15
    static let sourceSelectedButtonFontWeight: NSFont.Weight = .semibold
    static let sourceUnselectedButtonFontWeight: NSFont.Weight = .medium
    static let sourceButtonFontWeight: NSFont.Weight = sourceSelectedButtonFontWeight
    static let sourceCountFontSize: CGFloat = 13
    static let sourceSymbolWeight: NSFont.Weight = .medium
    static let noteGroupFontSize: CGFloat = 16
    static let noteGroupFontWeight: NSFont.Weight = .bold
    static let noteTitleFontSize: CGFloat = 14
    static let noteTitleFontWeight: NSFont.Weight = .bold
    static let noteSnippetFontSize: CGFloat = 12
    static let noteSnippetFontWeight: NSFont.Weight = .regular
    static let noteMetaFontSize: CGFloat = 11
    static let noteMetaFontWeight: NSFont.Weight = .medium
    static let noteListHeaderTitleFontSize: CGFloat = 18
    static let noteListHeaderCountFontSize: CGFloat = 12
    static let noteListLeadingInset: CGFloat = 14
    static let noteListTrailingInset: CGFloat = 12
    static let noteListTopInset: CGFloat = 4
    static let noteListBottomInset: CGFloat = 14
    static let editorTopInset: CGFloat = 18
    static let editorHorizontalInset: CGFloat = 24
    static let editorBottomInset: CGFloat = 20
    static let editorDateRowHeight: CGFloat = 20
    static let editorDateToTitleSpacing: CGFloat = 34
    static let editorTitleToBodySpacing: CGFloat = 8
    static let editorStatusFontSize: CGFloat = 13
    static let editorTitleFontSize: CGFloat = 24
    static let editorBodyFontSize: CGFloat = 15
    static let editorCodeFontSize: CGFloat = 14
    static let editorLineSpacing: CGFloat = 2.5
    static let editorParagraphSpacing: CGFloat = 6

    static func presentedWindowSize(in visibleFrame: NSRect) -> NSSize {
        let availableWidth = max(minimumWindowSize.width, visibleFrame.width - windowScreenMargin)
        let availableHeight = max(minimumWindowSize.height, visibleFrame.height - windowScreenMargin)
        return NSSize(
            width: min(presentedWindowSize.width, availableWidth),
            height: min(presentedWindowSize.height, availableHeight)
        )
    }

    static func presentedWindowSize(in visibleFrame: NSRect, usesCanonicalSize: Bool) -> NSSize {
        usesCanonicalSize ? presentedWindowSize : presentedWindowSize(in: visibleFrame)
    }

    static func clampedSourceColumnWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sourceColumnMinimumWidth), sourceColumnMaximumWidth)
    }

    static func clampedNoteColumnWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, noteColumnMinimumWidth), noteColumnMaximumWidth)
    }
}

private enum LibraryNotesPalette {
    static let windowBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let sourceBackground = NSColor(calibratedWhite: 0.045, alpha: 1)
    static let noteListBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let editorBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
}

enum LibrarySourceSelectionPalette {
    static let backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.86)
    static let foregroundColor = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.16, alpha: 1)
    static let selectedCountColor = NSColor.labelColor.withAlphaComponent(0.42)
    static let unselectedForegroundColor = NSColor.labelColor.withAlphaComponent(0.92)
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

    var paragraphKind: MarkdownParagraphKind? {
        switch self {
        case .heading1: return .heading(level: 1)
        case .heading2: return .heading(level: 2)
        case .heading3: return .heading(level: 3)
        case .paragraph: return .paragraph
        case .checklist: return .checklist(checked: false)
        case .bullet: return .bullet
        case .ordered: return .ordered(index: 1)
        case .bold, .italic, .underline, .strikethrough: return nil
        }
    }
}

@MainActor
final class LibraryGroupHeaderCellView: NSTableCellView {
    static let titleLeadingInset: CGFloat = 10
    static let titleTrailingInset: CGFloat = 10
    static let titleBottomInset: CGFloat = 12

    let titleLabel = NSTextField(labelWithString: "")

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
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.titleLeadingInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.titleTrailingInset),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.titleBottomInset)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class LibraryNoteCellView: NSTableCellView {
    static let contentTopInset: CGFloat = 6
    static let contentLeadingInset: CGFloat = 36
    static let contentBottomInset: CGFloat = 6
    static let contentTrailingInset: CGFloat = 14
    static let textRowSpacing: CGFloat = 1

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
    static let selectionTrailingInset: CGFloat = 24
    static let selectionVerticalInset: CGFloat = 4
    static let selectionCornerRadius: CGFloat = 8
    static let selectionFillColor = NSColor(calibratedRed: 0.492, green: 0.377, blue: 0.09, alpha: 0.96)
    static let hoverLeadingInset: CGFloat = 10
    static let hoverTrailingInset: CGFloat = 24
    static let hoverVerticalInset: CGFloat = 3
    static let hoverCornerRadius: CGFloat = 8
    static let hoverFillColor = NSColor(calibratedWhite: 0.22, alpha: 0.24)
    static let separatorLeadingInset: CGFloat = 36
    static let separatorTrailingInset: CGFloat = 24
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

        let hoverRect = insetRect(
            leading: Self.hoverLeadingInset,
            trailing: Self.hoverTrailingInset,
            vertical: Self.hoverVerticalInset
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
            vertical: Self.selectionVerticalInset
        )
        let path = NSBezierPath(
            roundedRect: selectionRect,
            xRadius: Self.selectionCornerRadius,
            yRadius: Self.selectionCornerRadius
        )
        Self.selectionFillColor.setFill()
        path.fill()
    }

    private func insetRect(leading: CGFloat, trailing: CGFloat, vertical: CGFloat) -> NSRect {
        NSRect(
            x: bounds.minX + leading,
            y: bounds.minY + vertical,
            width: max(0, bounds.width - leading - trailing),
            height: max(0, bounds.height - vertical * 2)
        )
    }
}

@MainActor
final class LibrarySourceRowView: NSView {
    static let hoverHorizontalInset: CGFloat = 0
    static let hoverVerticalInset: CGFloat = 1
    static let hoverCornerRadius: CGFloat = LibraryNotesLayout.sourceRowCornerRadius
    static let hoverColor = NSColor(calibratedWhite: 0.20, alpha: 0.42)
    static let dropHighlightColor = NSColor(calibratedWhite: 0.24, alpha: 0.80)
    static let dropRejectedColor = NSColor(calibratedWhite: 0.36, alpha: 0.34)

    var targetDirectory: URL?
    var canDropNotes: (([URL], URL) -> Bool)?
    var onDropNotes: (([URL], URL) -> Bool)?
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isPointerHovered = false
    private(set) var isDropTargeted = false
    private(set) var isDropRejected = false

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
        setDropRejected(false)
        let noteURLs = draggedFileURLs(from: sender.draggingPasteboard)
        guard let targetDirectory,
              !noteURLs.isEmpty else {
            return false
        }
        return onDropNotes?(noteURLs, targetDirectory) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
        setDropRejected(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isPointerHovered, !isDropTargeted, !isDropRejected {
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

        if isDropRejected {
            let rejectedRect = bounds.insetBy(dx: 1, dy: 2)
            let rejectedPath = NSBezierPath(
                roundedRect: rejectedRect,
                xRadius: LibraryNotesLayout.sourceRowCornerRadius,
                yRadius: LibraryNotesLayout.sourceRowCornerRadius
            )
            rejectedPath.lineWidth = 1.5
            Self.dropRejectedColor.setStroke()
            rejectedPath.stroke()
        }

        guard isDropTargeted else { return }

        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: LibraryNotesLayout.sourceRowCornerRadius,
            yRadius: LibraryNotesLayout.sourceRowCornerRadius
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
        if targeted {
            isDropRejected = false
        }
        needsDisplay = true
    }

    func setDropRejected(_ rejected: Bool) {
        guard isDropRejected != rejected else { return }
        isDropRejected = rejected
        if rejected {
            isDropTargeted = false
        }
        needsDisplay = true
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let noteURLs = draggedFileURLs(from: sender.draggingPasteboard)
        guard targetDirectory != nil,
              !noteURLs.isEmpty,
              let targetDirectory else {
            setDropTargeted(false)
            setDropRejected(false)
            return []
        }
        guard canDropNotes?(noteURLs, targetDirectory) == true else {
            setDropRejected(true)
            return []
        }
        setDropRejected(false)
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

@MainActor
final class LibrarySourceButtonCell: NSButtonCell {
    static let contentLeadingInset: CGFloat = 18

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        drawingRect.origin.x += Self.contentLeadingInset
        drawingRect.size.width = max(0, drawingRect.width - Self.contentLeadingInset)
        return drawingRect
    }
}

fileprivate enum LibrarySourceKeyCommand {
    case next
    case previous
    case enterHierarchy
    case leaveHierarchy
}

@MainActor
final class LibrarySourceButton: NSButton {
    fileprivate var onKeyCommand: ((LibrarySourceKeyCommand) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func moveDown(_ sender: Any?) {
        guard onKeyCommand?(.next) != true else { return }
        super.moveDown(sender)
    }

    override func moveUp(_ sender: Any?) {
        guard onKeyCommand?(.previous) != true else { return }
        super.moveUp(sender)
    }

    override func moveRight(_ sender: Any?) {
        guard onKeyCommand?(.enterHierarchy) != true else { return }
        super.moveRight(sender)
    }

    override func moveLeft(_ sender: Any?) {
        guard onKeyCommand?(.leaveHierarchy) != true else { return }
        super.moveLeft(sender)
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
            super.keyDown(with: event)
            return
        }

        let command: LibrarySourceKeyCommand?
        switch event.keyCode {
        case 123:
            command = .leaveHierarchy
        case 124:
            command = .enterHierarchy
        case 125:
            command = .next
        case 126:
            command = .previous
        default:
            command = nil
        }

        if let command, onKeyCommand?(command) == true {
            return
        }
        super.keyDown(with: event)
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
    fileprivate var onContextMenu: ((Int) -> NSMenu?)?

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
final class LibraryToolbarMenuButton: NSButton {
    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, isEnabled else {
            super.mouseDown(with: event)
            return
        }

        highlight(true)
        defer { highlight(false) }
        _ = sendAction(action, to: target)
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
    NSSplitViewDelegate,
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
    let attachmentQuickLookController = AttachmentQuickLookController()
    let statusLabel = NSTextField(labelWithString: "")

    private static let toolbarIdentifier = NSToolbar.Identifier("mudsnote.library.toolbar")
    private static let addFolderToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.add-folder")
    private static let toggleSidebarToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.toggle-sidebar")
    private static let sourceTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.source-separator")
    private static let noteTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-separator")
    private static let noteListTitleToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-list-title")
    private static let noteListActionsToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-list-actions")
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
    private let noteLoader: @Sendable (URL) throws -> LoadedLibraryNote
    private let thumbnailDecoder: @Sendable (URL) -> CGImage?
    private let usesCanonicalWindowSize: Bool
    private let prefersExternalScreen: Bool
    private var notes: [NoteSearchResult] = []
    private var listRows: [LibraryNoteListRow] = []
    private var visualQASelectedURL: URL?
    private(set) var noteListSortOrder: LibraryNoteSortOrder = .dateEdited
    private(set) var groupsNoteListByDate = true
    private var sourceCountSnapshot: [NoteSearchResult] = []
    private var selectedURL: URL?
    private var selectedTags: [String] = []
    private var isDirty = false
    private var autosaveTask: Task<Void, Never>?
    private var noteLoadTask: Task<Void, Never>?
    private var noteLoadGeneration = 0
    private var notePrefetchTask: Task<Void, Never>?
    private var searchReloadWorkItem: DispatchWorkItem?
    private var searchResultsTask: Task<Void, Never>?
    private var searchResultsGeneration = 0
    private var activeSearchSession: NoteSearchSession?
    private var sourceSnapshotValidationTask: Task<Void, Never>?
    private var sourceSnapshotValidationGeneration = 0
    private var noteListToolbarTitleLeadingConstraint: NSLayoutConstraint?
    private var hasPendingSearchReload = false
    private var isSearchResultReloading = false
    private var isLoadingInitialNote = false
    private var suppressEditorChanges = false
    private var suppressSelectionChanges = false
    private var isCreatingNewNote = false
    private var hasCenteredWindow = false
    private var hasRequestedWindowPresentation = false
    private var hasHydratedInitialNoteList = false
    private var selectedScope: LibraryScope = .all
    private var sourceButtons: [NSButton] = []
    private var sourceCountLabels: [Int: NSTextField] = [:]
    private var sourceFolderRows: [LibraryFolderRow] = []
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
    private(set) var thumbnailImageDecodeCountForLibrary = 0
    private var sourceFoldersLoaded = false
    private var sourceFoldersLoading = false
    private var sourceTagsLoaded = false
    private var sourceTagsLoading = false
    private var fullLibrarySnapshotReloadScheduled = false
    private var isFullLibrarySnapshotLoading = false
    private var fileSystemMonitor: LibraryFileSystemMonitor?
    private var internallyMutatedPaths: [String: Date] = [:]
    private var sourceFoldersSectionCollapsed = false
    private var sourceTagsSectionCollapsed = false
    private var inlineFolderEditOperation: InlineFolderEditOperation?
    private var inlineFolderEditField: NSTextField?
    private var inlineFolderEditRow: NSView?
    private var isCommittingInlineFolderEdit = false
    private var inlineFolderEditHasReceivedFocus = false
    private var linkEditorSheetController: LinkEditorSheetController?
    private var isApplyingStoredSplitLayout = false
    private var splitLayoutPersistenceWorkItem: DispatchWorkItem?
    private var windowFramePersistenceWorkItem: DispatchWorkItem?
    private weak var librarySplitView: NSSplitView?
    private var librarySplitViewController: NSSplitViewController?
    private weak var sourceSplitViewItem: NSSplitViewItem?
    private weak var sourceListView: NSView?
    private let sourcePrimaryStack = NSStackView()
    private let sourceFolderStack = NSStackView()
    private let sourceTrashStack = NSStackView()
    private let sourceTagStack = NSStackView()
    private let sourceFolderStatusLabel = NSTextField(labelWithString: "")
    private let sourceTagStatusLabel = NSTextField(labelWithString: "")
    private weak var sourceTagHeaderButton: NSButton?
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
        thumbnailDecoder: (@Sendable (URL) -> CGImage?)? = nil,
        onOpenInSeparateWindow: @escaping (URL) -> Void,
        onSave: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        noteStore.migrateLibraryLayoutScaleIfNeeded(
            to: LibraryNotesLayout.storedLayoutScaleVersion,
            replacingDefaultPaneWidths: (source: 220, note: 220)
        )
        self.noteLoader = noteLoader ?? { try noteStore.loadNote(at: $0) }
        self.thumbnailDecoder = thumbnailDecoder ?? Self.makeListThumbnailCGImage(at:)
        self.usesCanonicalWindowSize = usesCanonicalWindowSize
        self.prefersExternalScreen = prefersExternalScreen
        self.onOpenInSeparateWindow = onOpenInSeparateWindow
        self.onSave = onSave
        self.onClose = onClose
        self.noteListSortOrder = LibraryNoteSortOrder(rawValue: noteStore.libraryNoteSortOrderRawValue) ?? .dateEdited
        self.groupsNoteListByDate = noteStore.libraryGroupsNotesByDate
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
        window.delegate = self
        buildUI()
        configureToolbar()
        if defersInitialNoteHydration {
            reloadNotes(
                loadFirstIfNeeded: false,
                allNotesSnapshot: recentShellNoteResults(limit: 240),
                refreshCounts: true
            )
        } else {
            hasHydratedInitialNoteList = true
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
        startLibraryFileSystemMonitorIfNeeded()
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
        isCreatingNewNote = false
        selectedURL = note.url
        setEditorEditable(false)
        applyDocument(title: note.title, body: "", tags: note.tags)
        isDirty = false
        statusLabel.stringValue = editorDateText(for: note.modifiedAt)
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
        if case .failure(let error) = result,
           isMissingInitialNoteError(error) {
            noteStore.removeRecentFileReference(at: note.url)
            guard selectedNoteStillMatchesInitialLoad(note) else { return }
            recoverFromMissingInitialNote(note)
            return
        }
        guard selectedNoteStillMatchesInitialLoad(note) else { return }
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
        tableView.reloadData()
        tableView.deselectAll(nil)
        suppressSelectionChanges = false
        clearCurrentDocumentAfterRemoval()
        statusLabel.stringValue = ""
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
        showInitialNoteLoadingShell(for: nextNote)
        loadInitialNoteAfterLaunch(nextNote)
    }

    private func scheduleFullLibrarySnapshotReload() {
        guard !fullLibrarySnapshotReloadScheduled else { return }
        fullLibrarySnapshotReloadScheduled = true
        isFullLibrarySnapshotLoading = true
        updateNoteListHeader(query: searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let noteStore = noteStore
        let snapshotLimit = Self.sourceCountSnapshotLimit
        let sourceFolderPaths = currentSourceFolderPaths()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let allNotes = noteStore.listNotes(limit: snapshotLimit)
            let countIndex = LibrarySourceCountIndex(notes: allNotes, folderPaths: sourceFolderPaths)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFullLibrarySnapshotLoading = false
                guard self.window?.isVisible == true else { return }
                let reusableCountIndex = self.currentSourceFolderPaths() == sourceFolderPaths
                    ? countIndex
                    : nil
                let currentQuery = self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !currentQuery.isEmpty {
                    self.sourceCountSnapshot = allNotes
                    self.refreshSourceCounts(using: allNotes, countIndex: reusableCountIndex)
                    self.updateNoteListHeader(query: currentQuery)
                    return
                }
                let shouldLoadFirstAfterSnapshot = self.selectedURL == nil && self.tableView.selectedRow < 0
                self.reloadNotes(
                    selecting: self.selectedURL,
                    loadFirstIfNeeded: shouldLoadFirstAfterSnapshot,
                    allNotesSnapshot: allNotes,
                    sourceCountIndex: reusableCountIndex
                )
            }
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
        cancelActiveNoteLoad()
        notePrefetchTask?.cancel()
        notePrefetchTask = nil
        thumbnailImageLoadTasks.values.forEach { $0.cancel() }
        thumbnailImageLoadTasks.removeAll()
        fileSystemMonitor?.stop()
        fileSystemMonitor = nil
        internallyMutatedPaths.removeAll()
        attachmentQuickLookController.dismiss()
        cancelSourceSnapshotValidation()
        searchReloadWorkItem?.cancel()
        searchReloadWorkItem = nil
        cancelActiveSearchResultReload()
        hasPendingSearchReload = false
        splitLayoutPersistenceWorkItem?.cancel()
        splitLayoutPersistenceWorkItem = nil
        windowFramePersistenceWorkItem?.cancel()
        windowFramePersistenceWorkItem = nil
        persistLibraryWindowFrameForLibrary()
        persistLibrarySplitLayoutForLibrary()
        try? saveCurrentNoteIfNeeded()
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        scheduleLibraryWindowFramePersistence()
    }

    func windowDidResize(_ notification: Notification) {
        scheduleLibraryWindowFramePersistence()
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

    private func handleLibraryFileSystemChanges(
        _ changes: Set<LibraryFileSystemChange>,
        requiresVisibleWindow: Bool = true
    ) {
        guard !requiresVisibleWindow || window?.isVisible == true else { return }
        let externalChanges = changes.filter { !isSuppressedInternalChange($0) }
        guard !externalChanges.isEmpty else { return }

        let markdownPaths = Set(externalChanges.filter(\.isMarkdownFile).map {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
        })
        let hasFolderStructureChange = externalChanges.contains(where: \.changesDirectoryStructure)
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
            load(note: selectedNote)
        }

        if hasFolderStructureChange {
            sourceFoldersLoaded = false
            scheduleDeferredSourceFolderLoad()
        }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: selectedURL == nil)
        } else {
            performSearchReload()
        }
    }

    private func recordInternalFileSystemChanges(for urls: [URL]) {
        let expiration = Date().addingTimeInterval(2)
        for url in urls {
            internallyMutatedPaths[url.standardizedFileURL.path] = expiration
        }
    }

    private func isSuppressedInternalChange(_ change: LibraryFileSystemChange) -> Bool {
        let now = Date()
        internallyMutatedPaths = internallyMutatedPaths.filter { $0.value > now }
        let path = URL(fileURLWithPath: change.path).standardizedFileURL.path
        return internallyMutatedPaths[path].map { $0 > now } ?? false
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
        librarySplitView = splitController.splitView
        window?.contentViewController = splitController
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(librarySplitViewDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitController.splitView
        )

        splitController.view.layoutSubtreeIfNeeded()
        applyStoredLibrarySplitLayoutForLibrary()
    }

    private func buildSourceList() -> NSView {
        let sourceList = NSVisualEffectView()
        sourceList.translatesAutoresizingMaskIntoConstraints = false
        sourceList.identifier = NSUserInterfaceItemIdentifier("LibrarySourceSurface")
        sourceList.material = .sidebar
        sourceList.blendingMode = .withinWindow
        sourceList.state = .active
        sourceList.wantsLayer = true
        sourceList.layer?.backgroundColor = LibraryNotesPalette.sourceBackground
            .withAlphaComponent(0.86)
            .cgColor
        sourceList.layer?.cornerRadius = LibraryNotesLayout.sourceSurfaceCornerRadius
        sourceList.layer?.masksToBounds = true
        sourceList.layer?.borderWidth = 1
        sourceList.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(
            LibraryNotesLayout.sourceSurfaceBorderAlpha
        ).cgColor
        sourceListView = sourceList

        let darkeningView = NSView()
        darkeningView.identifier = NSUserInterfaceItemIdentifier("LibrarySourceDarkeningTint")
        darkeningView.wantsLayer = true
        darkeningView.layer?.backgroundColor = NSColor.black.withAlphaComponent(
            LibraryNotesLayout.sourceSurfaceDarkeningAlpha
        ).cgColor
        sourceList.addSubview(darkeningView)
        pin(darkeningView, to: sourceList)

        configureSourceStack(sourcePrimaryStack)
        configureSourceStack(sourceFolderStack)
        configureSourceStack(sourceTrashStack)
        configureSourceStack(sourceTagStack)
        sourcePrimaryStack.identifier = NSUserInterfaceItemIdentifier("LibrarySourcePrimaryStack")
        sourceFolderStack.identifier = NSUserInterfaceItemIdentifier("LibrarySourceFolderStack")
        sourceTrashStack.identifier = NSUserInterfaceItemIdentifier("LibrarySourceTrashStack")
        sourceTagStack.identifier = NSUserInterfaceItemIdentifier("LibrarySourceTagStack")
        configureSourceStatusLabel(
            sourceFolderStatusLabel,
            identifier: "LibrarySourceFolderStatus"
        )
        configureSourceStatusLabel(
            sourceTagStatusLabel,
            identifier: "LibrarySourceTagStatus"
        )

        let libraryHeader = makeSourceGroupLabel("iCloud", identifier: "LibrarySourceGroup-iCloud")
        let tagHeader = makeSourceSectionHeader(.tags)
        sourceTagHeaderButton = tagHeader

        sourceFolderRows = rootFolderRowsForSourceList()
        rebuildSourceRows(includeTags: sourceTagsLoaded)

        let stack = NSStackView(views: [
            libraryHeader,
            sourcePrimaryStack,
            sourceFolderStack,
            sourceTrashStack,
            tagHeader,
            sourceTagStack,
            NSView()
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = LibraryNotesLayout.sourceSectionSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: LibraryNotesLayout.sourceListTopInset,
            left: LibraryNotesLayout.sourceListLeadingInset,
            bottom: LibraryNotesLayout.sourceListBottomInset,
            right: LibraryNotesLayout.sourceListTrailingInset
        )
        sourceList.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sourceList.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sourceList.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sourceList.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: sourceList.bottomAnchor)
        ])
        refreshSourceSelection()

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
            stack.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            titlebarSeparator.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            titlebarSeparator.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            titlebarSeparator.bottomAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor),
            titlebarSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
        listContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return sidebar
    }

    private func buildEditor() -> NSView {
        let editor = NSView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = LibraryNotesPalette.editorBackground.cgColor

        titleField.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTitleField")
        titleField.placeholderString = ""
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
        stack.alignment = .leading
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
        let titlebarSeparator = makeLibraryTitlebarSeparator(identifier: "LibraryEditorTitlebarSeparator")
        editor.addSubview(titlebarSeparator)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            stack.topAnchor.constraint(equalTo: editor.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            titlebarSeparator.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            titlebarSeparator.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            titlebarSeparator.bottomAnchor.constraint(equalTo: editor.safeAreaLayoutGuide.topAnchor),
            titlebarSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
        let editorContentWidthOffset = -(LibraryNotesLayout.editorHorizontalInset * 2)
        NSLayoutConstraint.activate([
            dateRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: editorContentWidthOffset),
            titleField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: editorContentWidthOffset),
            bodyContainer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: editorContentWidthOffset)
        ])
        bodyContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

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
        searchField.placeholderString = "Search"
        searchField.toolTip = "Search Notes"
        searchField.setAccessibilityLabel("Search Notes")
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
            Self.noteListTitleToolbarItemIdentifier,
            Self.noteListActionsToolbarItemIdentifier,
            Self.noteTrackingSeparatorToolbarItemIdentifier,
            Self.newNoteToolbarItemIdentifier,
            .flexibleSpace,
            Self.editorToolsToolbarItemIdentifier,
            .space,
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
        case Self.noteListTitleToolbarItemIdentifier:
            return toolbarNoteListTitleItem(identifier: itemIdentifier)
        case Self.noteListActionsToolbarItemIdentifier:
            return toolbarCircularButtonItem(
                identifier: itemIdentifier,
                label: "列表显示选项",
                symbolName: LibraryNotesLayout.toolbarMoreSymbolName,
                action: #selector(noteListActionsToolbarMenuPressed(_:))
            )
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
            item.label = "Search"
            item.paletteLabel = "Search"
            item.toolTip = "Search Notes"
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
        let titleLeadingConstraint = headerStack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor)
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
        item.isBordered = false
        return item
    }

    private func toolbarEditorToolsItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "编辑工具"
        item.paletteLabel = "编辑工具"
        item.toolTip = "编辑工具"
        item.visibilityPriority = .high

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

        NSLayoutConstraint.activate([
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
        let button: NSButton
        if identifier == Self.formatToolbarItemIdentifier {
            button = LibraryToolbarMenuButton(image: image ?? NSImage(), target: self, action: action)
        } else {
            button = NSButton(image: image ?? NSImage(), target: self, action: action)
        }
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
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

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        let configuredImage = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.toolbarCircularButtonSymbolPointSize,
            weight: .regular
        )) ?? image
        configuredImage?.isTemplate = true

        let button: NSButton
        if identifier == Self.noteListActionsToolbarItemIdentifier {
            button = LibraryToolbarMenuButton(image: configuredImage ?? NSImage(), target: self, action: action)
        } else {
            button = NSButton(image: configuredImage ?? NSImage(), target: self, action: action)
        }
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true

        let glass = toolbarGlassSurface(
            identifier: "\(identifier.rawValue).glass",
            content: button,
            size: NSSize(
                width: LibraryNotesLayout.toolbarCircularButtonSize,
                height: LibraryNotesLayout.toolbarCircularButtonSize
            ),
            cornerRadius: LibraryNotesLayout.toolbarCircularButtonSize / 2
        )
        item.image = configuredImage
        item.view = glass
        return item
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

    private func toolbarSymbolImage(symbolName: String, label: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.toolbarSymbolPointSize,
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
        editorTextView.commandDelegate = self
        editorTextView.delegate = self
        editorTextView.markdownPasteTheme = theme
        editorTextView.configureContextMenu = { [weak self] menu, event in
            if let attachment = self?.editorTextView.fileAttachmentReference(at: event) {
                self?.configureAttachmentContextMenu(menu, forAttachment: attachment)
            }
            if let link = self?.editorTextView.linkReference(at: event) {
                self?.configureLinkContextMenuForLibrary(menu, for: link)
            }
            if let characterIndex = self?.editorTextView.characterIndex(at: event) {
                self?.configureMarkdownTableContextMenuForLibrary(menu, atCharacterIndex: characterIndex)
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
        stack.spacing = LibraryNotesLayout.sourceInnerRowSpacing
    }

    private func configureSourceStatusLabel(_ label: NSTextField, identifier: String) {
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = panelTertiaryTextColor().withAlphaComponent(0.82)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceStatusRowHeight).isActive = true
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
        let button = NSButton(
            title: section.title,
            image: sourceSectionDisclosureImage(for: section) ?? NSImage(),
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
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceSectionHeaderHeight).isActive = true
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceRowWidth).isActive = true
        return button
    }

    private func sourceSectionDisclosureImage(for section: LibrarySourceSection) -> NSImage? {
        let symbolName = isSourceSectionCollapsed(section) ? "chevron.right" : "chevron.down"
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: section.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: LibraryNotesLayout.sourceDisclosureSymbolPointSize,
                weight: .semibold
            ))
    }

    private func rebuildSourceRows(includeTags: Bool) {
        sourceButtons.removeAll()
        sourceCountLabels.removeAll()
        removeArrangedSubviews(from: sourcePrimaryStack)
        removeArrangedSubviews(from: sourceFolderStack)
        removeArrangedSubviews(from: sourceTrashStack)
        removeArrangedSubviews(from: sourceTagStack)

        sourcePrimaryStack.addArrangedSubview(makeScopeRow(.all, tag: 0))

        updateSourceFolderStatus()
        if !sourceFoldersSectionCollapsed {
            for (index, folderRow) in sourceFolderRows.enumerated() {
                if case .rename(let folderURL) = inlineFolderEditOperation,
                   folderURL.standardizedFileURL.path == folderRow.url.standardizedFileURL.path {
                    continue
                }
                sourceFolderStack.addArrangedSubview(makeScopeRow(
                    .folder(folderRow.url),
                    tag: 10 + index,
                    folderRow: folderRow
                ))
            }
            insertInlineFolderEditRowIfNeeded()
            if inlineFolderEditOperation == nil, !sourceFolderStatusLabel.stringValue.isEmpty {
                sourceFolderStack.addArrangedSubview(sourceFolderStatusLabel)
            }
        }
        sourceTrashStack.addArrangedSubview(makeScopeRow(.trash, tag: 3))

        if !includeTags {
            sourceTagNames = []
        }
        updateSourceTagStatus()
        updateSourceTagHeaderPresentation()
        if !sourceTagsSectionCollapsed {
            for (index, tag) in sourceTagNames.enumerated() {
                sourceTagStack.addArrangedSubview(makeScopeRow(.tag(tag), tag: 100 + index))
            }
            if !sourceTagStatusLabel.stringValue.isEmpty {
                sourceTagStack.addArrangedSubview(sourceTagStatusLabel)
            }
        }
        refreshSourceCounts(using: sourceCountSnapshot)
        refreshSourceSelection()
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
            sourceFolderStatusLabel.stringValue = "Loading Folders..."
        } else if sourceFolderRows.isEmpty {
            sourceFolderStatusLabel.stringValue = "No Folders"
        } else {
            sourceFolderStatusLabel.stringValue = ""
        }
    }

    private func updateSourceTagStatus() {
        sourceTagStatusLabel.stringValue = ""
    }

    private func updateSourceTagHeaderPresentation() {
        guard let button = sourceTagHeaderButton else { return }
        if sourceTagsLoaded && sourceTagNames.isEmpty {
            button.image = nil
            button.imagePosition = .noImage
        } else {
            button.image = sourceSectionDisclosureImage(for: .tags)
            button.imagePosition = .imageLeading
        }
        button.imageHugsTitle = true
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
                self.reloadNotesForNavigation(selecting: self.selectedURL, loadFirstIfNeeded: false)
            }
        }
    }

    func loadSourceFoldersForLibrary() {
        reloadSourceFolderRowsForCurrentState()
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    private func scheduleDeferredSourceTagLoad() {
        guard !sourceTagsLoaded, !sourceTagsLoading else { return }
        sourceTagsLoading = true
        let noteStore = noteStore
        DispatchQueue.global(qos: .utility).async { [weak self] in
            noteStore.prewarmSearchIndex()
            let tags = noteStore.knownTags(limit: 12)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sourceTagsLoading = false
                self.applySourceTagsForLibrary(tags)
            }
        }
    }

    func loadSourceTagsForLibrary() {
        guard !sourceTagsLoaded, !sourceTagsLoading else { return }
        applySourceTagsForLibrary(noteStore.knownTags(limit: 12))
    }

    private func applySourceTagsForLibrary(_ tags: [String]) {
        guard !sourceTagsLoaded else { return }
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
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
            return values.isDirectory == true
                && values.isHidden != true
                && url.lastPathComponent.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) != .orderedSame
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
        overlay.identifier = NSUserInterfaceItemIdentifier("LibrarySourceCountOverlay-\(tag)")
        let countLabel = NSTextField(labelWithString: "")
        countLabel.identifier = NSUserInterfaceItemIdentifier("LibrarySourceCount-\(tag)")
        countLabel.font = .systemFont(ofSize: LibraryNotesLayout.sourceCountFontSize, weight: .medium)
        countLabel.textColor = panelTertiaryTextColor()
        countLabel.alignment = .right
        let depth = folderRow?.depth ?? 0
        let leadingInset = CGFloat(depth) * LibraryNotesLayout.sourceFolderIndentStep

        row.addSubview(button)
        row.addSubview(overlay, positioned: .above, relativeTo: button)
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
            countLabel.trailingAnchor.constraint(
                equalTo: overlay.trailingAnchor,
                constant: -LibraryNotesLayout.sourceCountTrailingInset
            ),
            countLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceCountWidth)
        ]
        if let chevronButton {
            constraints.append(contentsOf: [
                chevronButton.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: leadingInset),
                chevronButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevronButton.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceDisclosureButtonWidth),
                chevronButton.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceDisclosureButtonHeight),
                button.leadingAnchor.constraint(
                    equalTo: chevronButton.trailingAnchor,
                    constant: LibraryNotesLayout.sourceDisclosureToButtonSpacing
                )
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
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "展开或折叠文件夹")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: LibraryNotesLayout.sourceDisclosureSymbolPointSize,
                weight: .semibold
            ))
        let button = NSButton(
            image: image ?? NSImage(),
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
        let title = sourceTitle(for: scope)
        let button = LibrarySourceButton(title: title, target: self, action: #selector(scopeButtonPressed(_:)))
        button.cell = LibrarySourceButtonCell(textCell: title)
        button.target = self
        button.action = #selector(scopeButtonPressed(_:))
        button.identifier = NSUserInterfaceItemIdentifier("LibrarySourceButton-\(tag)")
        button.tag = tag
        button.image = NSImage(systemSymbolName: scope.symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: LibraryNotesLayout.sourceSymbolPointSize,
                weight: LibraryNotesLayout.sourceSymbolWeight
            ))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.focusRingType = .none
        button.font = .systemFont(
            ofSize: LibraryNotesLayout.sourceButtonFontSize,
            weight: LibraryNotesLayout.sourceUnselectedButtonFontWeight
        )
        button.contentTintColor = LibrarySourceSelectionPalette.unselectedForegroundColor
        button.wantsLayer = true
        button.layer?.cornerRadius = LibraryNotesLayout.sourceRowCornerRadius
        button.layer?.cornerCurve = .continuous
        button.onKeyCommand = { [weak self, weak button] command in
            guard let self, let button else { return false }
            return self.handleSourceKeyCommand(command, from: button)
        }
        return button
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
        let notesDirectory = noteStore.notesDirectory.standardizedFileURL
        if standardizedURL.path == notesDirectory.path {
            return "Notes"
        }
        return standardizedURL.lastPathComponent.isEmpty ? "Notes" : standardizedURL.lastPathComponent
    }

    private func refreshSourceSelection() {
        for button in sourceButtons {
            let isSelected = scope(for: button) == selectedScope
            button.layer?.backgroundColor = isSelected
                ? LibrarySourceSelectionPalette.backgroundColor.cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected
                ? LibrarySourceSelectionPalette.foregroundColor
                : LibrarySourceSelectionPalette.unselectedForegroundColor
            button.font = .systemFont(
                ofSize: LibraryNotesLayout.sourceButtonFontSize,
                weight: isSelected
                    ? LibraryNotesLayout.sourceSelectedButtonFontWeight
                    : LibraryNotesLayout.sourceUnselectedButtonFontWeight
            )
            sourceCountLabels[button.tag]?.textColor = isSelected
                ? LibrarySourceSelectionPalette.selectedCountColor
                : panelTertiaryTextColor()
        }
    }

    private func handleSourceKeyCommand(_ command: LibrarySourceKeyCommand, from button: NSButton) -> Bool {
        guard let currentIndex = sourceButtons.firstIndex(where: { $0 === button }) else {
            return false
        }

        switch command {
        case .next:
            return activateSourceButton(at: currentIndex + 1)
        case .previous:
            return activateSourceButton(at: currentIndex - 1)
        case .enterHierarchy:
            return enterSourceFolderHierarchy(from: button)
        case .leaveHierarchy:
            return leaveSourceFolderHierarchy(from: button)
        }
    }

    private func activateSourceButton(at index: Int) -> Bool {
        guard sourceButtons.indices.contains(index) else { return true }

        let target = sourceButtons[index]
        target.performClick(nil)
        target.window?.makeFirstResponder(target)
        return true
    }

    private func enterSourceFolderHierarchy(from button: NSButton) -> Bool {
        guard case .folder(let folderURL) = scope(for: button),
              let folderIndex = sourceFolderRows.firstIndex(where: {
                  $0.url.standardizedFileURL.path == folderURL.standardizedFileURL.path
              }) else {
            return true
        }
        let folderRow = sourceFolderRows[folderIndex]
        guard folderRow.hasChildren else { return true }

        if !isSourceFolderExpanded(path: folderURL.standardizedFileURL.path, depth: folderRow.depth) {
            toggleSourceFolderDisclosure(at: folderIndex)
            focusSourceButton(for: .folder(folderURL))
            return true
        }

        let childIndex = folderIndex + 1
        guard sourceFolderRows.indices.contains(childIndex),
              sourceFolderRows[childIndex].depth == folderRow.depth + 1 else {
            return true
        }
        focusAndActivateSourceButton(for: .folder(sourceFolderRows[childIndex].url))
        return true
    }

    private func leaveSourceFolderHierarchy(from button: NSButton) -> Bool {
        guard case .folder(let folderURL) = scope(for: button),
              let folderIndex = sourceFolderRows.firstIndex(where: {
                  $0.url.standardizedFileURL.path == folderURL.standardizedFileURL.path
              }) else {
            return true
        }
        let folderRow = sourceFolderRows[folderIndex]
        if folderRow.hasChildren,
           isSourceFolderExpanded(path: folderURL.standardizedFileURL.path, depth: folderRow.depth) {
            toggleSourceFolderDisclosure(at: folderIndex)
            focusSourceButton(for: .folder(folderURL))
            return true
        }

        guard folderRow.depth > 0,
              let parentIndex = stride(from: folderIndex - 1, through: 0, by: -1).first(where: {
                  sourceFolderRows[$0].depth == folderRow.depth - 1
              }) else {
            return true
        }
        focusAndActivateSourceButton(for: .folder(sourceFolderRows[parentIndex].url))
        return true
    }

    private func focusAndActivateSourceButton(for targetScope: LibraryScope) {
        guard let button = sourceButtons.first(where: { scope(for: $0) == targetScope }) else { return }
        button.performClick(nil)
        button.window?.makeFirstResponder(button)
    }

    private func focusSourceButton(for targetScope: LibraryScope) {
        guard let button = sourceButtons.first(where: { scope(for: $0) == targetScope }) else { return }
        button.window?.makeFirstResponder(button)
    }

    private func currentSourceFolderPaths() -> Set<String> {
        Set(sourceFolderRows.map { $0.url.standardizedFileURL.path })
    }

    private func refreshSourceCounts(
        using allNotes: [NoteSearchResult],
        countIndex precomputedCountIndex: LibrarySourceCountIndex? = nil
    ) {
        let recentCount = noteStore.listRecentFiles(limit: 80).count
        let countIndex = precomputedCountIndex ?? LibrarySourceCountIndex(
            notes: allNotes,
            folderPaths: currentSourceFolderPaths()
        )
        let trashCount = noteStore.trashedNoteCount()

        for button in sourceButtons {
            let count: Int
            switch scope(for: button) {
            case .all:
                count = allNotes.count
            case .recent:
                count = recentCount
            case .inbox:
                count = countIndex.inboxCount
            case .trash:
                count = trashCount
            case .folder(let url):
                count = countIndex.count(forFolder: url)
            case .tag(let tag):
                count = countIndex.count(forTag: tag)
            }
            sourceCountLabels[button.tag]?.stringValue = sourceCountText(count, for: scope(for: button))
        }
    }

    private func sourceCountText(_ count: Int, for scope: LibraryScope) -> String {
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
        refreshCounts: Bool = true
    ) {
        cancelSourceSnapshotValidation()
        cancelActiveSearchResultReload()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allNotes = allNotesSnapshot ?? sourceCountSnapshot
        searchScopeControl.isHidden = query.isEmpty
        notes = query.isEmpty
            ? notesForSelectedScope(limit: 240, allNotes: allNotes)
            : searchResultsForSelectedScope(query: query, limit: 240)
        listRows = buildGroupedRows(for: notes, preservesInputOrder: !query.isEmpty)
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
        stabilizeVisualQASelectionIfNeeded()

        if loadFirstIfNeeded, let noteToLoad {
            load(note: noteToLoad)
        }
        if refreshCounts {
            sourceCountSnapshot = allNotes
            refreshSourceCounts(using: allNotes, countIndex: sourceCountIndex)
        }
        refreshSourceSelection()
        updateToolbarActionState()
        if allNotesSnapshot == nil, query.isEmpty {
            scheduleSourceSnapshotValidation(loadFirstIfNeeded: loadFirstIfNeeded)
        }
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
        let sourceFolderPaths = currentSourceFolderPaths()

        sourceSnapshotValidationTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let allNotes = noteStore.listNotes(limit: snapshotLimit)
            guard !Task.isCancelled else { return }
            let countIndex = LibrarySourceCountIndex(notes: allNotes, folderPaths: sourceFolderPaths)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      generation == self.sourceSnapshotValidationGeneration,
                      scope == self.selectedScope,
                      query == self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return
                }

                self.sourceSnapshotValidationTask = nil
                let reusableCountIndex = self.currentSourceFolderPaths() == sourceFolderPaths
                    ? countIndex
                    : nil
                guard allNotes != self.sourceCountSnapshot else {
                    self.refreshSourceCounts(using: allNotes, countIndex: reusableCountIndex)
                    return
                }

                let selectedURL = self.selectedURL
                let selectedPath = selectedURL?.standardizedFileURL.path
                let nextNotes = self.notesForSelectedScope(limit: 240, allNotes: allNotes)
                let selectionStillExists = selectedPath.map { path in
                    nextNotes.contains { $0.url.standardizedFileURL.path == path }
                } ?? false
                self.reloadNotes(
                    selecting: selectionStillExists ? selectedURL : nil,
                    loadFirstIfNeeded: loadFirstIfNeeded && !selectionStillExists,
                    allNotesSnapshot: allNotes,
                    sourceCountIndex: reusableCountIndex
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
            noteListCountLabel.stringValue = "Searching..."
        } else {
            noteListCountLabel.stringValue = resultsCountText(notes.count)
        }
    }

    private func updateNoteListEmptyState(query: String) {
        let isEmpty = listRows.isEmpty
        noteListEmptyLabel.isHidden = !isEmpty
        guard isEmpty else { return }

        if !query.isEmpty, hasPendingSearchReload || isSearchResultReloading {
            noteListEmptyLabel.stringValue = "Searching..."
        } else if !query.isEmpty {
            noteListEmptyLabel.stringValue = "No Results"
        } else if selectedScope == .trash {
            noteListEmptyLabel.stringValue = "Recently Deleted is empty"
        } else {
            noteListEmptyLabel.stringValue = "No Notes"
        }
    }

    private func notesForSelectedScope(limit: Int, allNotes: [NoteSearchResult]) -> [NoteSearchResult] {
        switch selectedScope {
        case .all:
            return Array(allNotes.prefix(limit))
        case .recent:
            return recentNoteResults(limit: min(limit, 80), allNotes: allNotes)
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
        let searchSession = activeSearchSession ?? noteStore.makeSearchSession()
        activeSearchSession = searchSession
        return librarySearchResults(
            noteStore: noteStore,
            searchSession: searchSession,
            scope: scope,
            query: query,
            limit: limit,
            searchesAllNotes: searchesAllNotes
        )
    }

    private func allNoteResults(limit: Int) -> [NoteSearchResult] {
        noteStore.listNotes(limit: limit)
    }

    private func recentShellNoteResults(limit: Int) -> [NoteSearchResult] {
        noteStore.listRecentFiles(limit: limit).map { note in
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
    }

    private func recentNoteResults(limit: Int, allNotes: [NoteSearchResult]) -> [NoteSearchResult] {
        let resultsByPath = Dictionary(uniqueKeysWithValues: allNotes.map {
            ($0.url.standardizedFileURL.path, $0)
        })
        return noteStore.listRecentFiles(limit: limit).map { note in
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

    private func rebuildNoteListRowsForDisplayOptions() {
        let selectedPaths = Set(selectedMarkdownFileURLsForLibrary().map { $0.standardizedFileURL.path })
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        listRows = buildGroupedRows(for: notes, preservesInputOrder: !query.isEmpty)

        suppressSelectionChanges = true
        tableView.reloadData()
        let selectedRows = IndexSet(listRows.indices.filter { row in
            guard let note = listRows[row].note else { return false }
            return selectedPaths.contains(note.url.standardizedFileURL.path)
        })
        tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
        suppressSelectionChanges = false
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
        return fallback.isEmpty ? "New Note" : fallback
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

                let matchingRows = IndexSet(self.listRows.indices.filter { row in
                    self.listRows[row].note?.thumbnailURL?.standardizedFileURL.path == key
                })
                guard !matchingRows.isEmpty else { return }
                self.tableView.reloadData(
                    forRowIndexes: matchingRows,
                    columnIndexes: IndexSet(integer: 0)
                )
            }
        }
        thumbnailImageLoadTasks[key] = task
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

        if object === inlineFolderEditField {
            return
        }

        if object === searchField {
            scheduleSearchReloadFromTyping()
            return
        }

        if object === titleField {
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
            libraryUserDidEdit()
        } else {
            markDirty()
        }
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

    @objc
    private func scopeButtonPressed(_ sender: NSButton) {
        do {
            try saveCurrentNoteIfNeeded()
            selectedScope = scope(for: sender)
            reloadNotesForNavigation(loadFirstIfNeeded: true)
            sender.window?.makeFirstResponder(sender)
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    @objc
    private func folderDisclosurePressed(_ sender: NSButton) {
        let index = sender.tag - 10
        guard sourceFolderRows.indices.contains(index) else { return }
        toggleSourceFolderDisclosure(at: index)
    }

    private func toggleSourceFolderDisclosure(at index: Int) {
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

        persistSourceDisclosureState()
        reloadSourceFolderRowsForCurrentState()
        reloadNotesForNavigation(loadFirstIfNeeded: true)
    }

    @objc
    private func sourceSectionDisclosurePressed(_ sender: NSButton) {
        guard let section = LibrarySourceSection(rawValue: sender.tag) else { return }

        switch section {
        case .folders:
            sourceFoldersSectionCollapsed.toggle()
            noteStore.libraryFoldersSectionCollapsed = sourceFoldersSectionCollapsed
            if !sourceFoldersSectionCollapsed {
                scheduleDeferredSourceFolderLoad()
            }
        case .tags:
            sourceTagsSectionCollapsed.toggle()
            noteStore.libraryTagsSectionCollapsed = sourceTagsSectionCollapsed
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
        beginInlineFolderCreationForLibrary()
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
            try saveCurrentNoteIfNeeded()
            if selectedScope == .trash {
                selectedScope = .all
            }
            cancelActiveNoteLoad()
            isLoadingInitialNote = false
            isCreatingNewNote = true
            selectedURL = nil
            selectedTags = []
            suppressSelectionChanges = true
            tableView.deselectAll(nil)
            suppressSelectionChanges = false
            setEditorEditable(true)
            applyDocument(title: "", body: "", tags: [])
            isDirty = false
            statusLabel.stringValue = editorDateText(for: Date())
            refreshSourceSelection()
            updateToolbarActionState()
            window?.makeFirstResponder(titleField)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCreatingNewNote else { return }
                self.window?.makeFirstResponder(self.titleField)
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
        let existingSearchSession = activeSearchSession
        isSearchResultReloading = true
        searchScopeControl.isHidden = false
        updateNoteListHeader(query: query)
        updateNoteListEmptyState(query: query)

        let task = Task.detached(priority: .userInitiated) { [noteStore, existingSearchSession, scope, query, searchesAllNotes, generation, preferredURL] in
            guard !Task.isCancelled else { return }
            let searchSession = existingSearchSession ?? noteStore.makeSearchSession()
            let results = librarySearchResults(
                noteStore: noteStore,
                searchSession: searchSession,
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
                self.activeSearchSession = searchSession
                self.applySearchResults(results, query: query, selecting: preferredURL)
            }
        }
        searchResultsTask = task
    }

    private func applySearchResults(_ results: [NoteSearchResult], query: String, selecting preferredURL: URL?) {
        isSearchResultReloading = false
        notes = results
        listRows = buildGroupedRows(for: notes, preservesInputOrder: true)
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
            try deleteSelectedNotesForLibrary()
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
        isCreatingNewNote = false
        cancelActiveNoteLoad()
        notePrefetchTask?.cancel()
        notePrefetchTask = nil
        if let cached = cachedLoadedNote(for: note) {
            applyLoadedNote(cached, for: note)
            return
        }

        guard window?.isVisible == true,
              visualQASelectedURL == nil else {
            loadNoteSynchronously(note)
            return
        }

        showInitialNoteLoadingShell(for: note)
        let generation = noteLoadGeneration
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
                      self.selectedNoteStillMatchesInitialLoad(note) else {
                    return
                }
                self.noteLoadTask = nil
                self.applyLoadedNoteResult(result, for: note)
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

    private func cancelActiveNoteLoad() {
        noteLoadTask?.cancel()
        noteLoadTask = nil
        noteLoadGeneration += 1
    }

    private func applyLoadedNoteResult(_ result: Result<LoadedLibraryNote, Error>, for note: NoteSearchResult) {
        isLoadingInitialNote = false
        switch result {
        case .success(let loaded):
            let cached = cacheLoadedNote(loaded, for: note)
            applyLoadedNote(cached, for: note)
        case .failure(let error):
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    private func applyLoadedNote(_ cached: LoadedLibraryNoteCacheEntry, for note: NoteSearchResult) {
        selectedURL = note.url
        setEditorEditable(selectedScope != .trash)

        let renderedBody: NSAttributedString
        if let rendered = cached.renderedBody {
            renderedBody = rendered
        } else {
            let rendered = MarkdownRichTextCodec.render(
                markdown: cached.loaded.body,
                theme: theme,
                baseURL: note.url
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
            renderedBody: renderedBody
        )
        isDirty = false
        statusLabel.stringValue = editorDateText(for: note.modifiedAt)
        applyEditorSearchHighlightsForCurrentQuery()
        updateToolbarActionState()
        prefetchAdjacentNotes(around: note)
    }

    private func applyDocument(
        title: String,
        body: String,
        tags: [String],
        renderedBody: NSAttributedString? = nil
    ) {
        suppressEditorChanges = true
        titleField.stringValue = title
        selectedTags = tags
        editorTextView.textStorage?.setAttributedString(
            renderedBody ?? MarkdownRichTextCodec.render(markdown: body, theme: theme, baseURL: selectedURL)
        )
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
        editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        suppressEditorChanges = false
    }

    private func cachedLoadedNote(for note: NoteSearchResult) -> LoadedLibraryNoteCacheEntry? {
        let key = loadedNoteCacheKey(for: note.url)
        guard let cached = loadedNoteCache.entry(forKey: key),
              let currentModifiedAt = fileModificationDate(at: note.url),
              abs(currentModifiedAt.timeIntervalSince(cached.fileModifiedAt)) < 0.001 else {
            loadedNoteCache.removeEntry(forKey: key)
            return nil
        }
        return cached
    }

    @discardableResult
    private func cacheLoadedNote(
        _ loaded: LoadedLibraryNote,
        for note: NoteSearchResult
    ) -> LoadedLibraryNoteCacheEntry {
        let cached = LoadedLibraryNoteCacheEntry(
            loaded: loaded,
            fileModifiedAt: fileModificationDate(at: note.url) ?? note.modifiedAt
        )
        loadedNoteCache.insert(cached, forKey: loadedNoteCacheKey(for: note.url))
        return cached
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
                      let loaded = try? noteStore.loadNote(at: candidate.url) else {
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
        url.standardizedFileURL.path as NSString
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
        cancelSourceSnapshotValidation()

        let rawTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "无标题" : rawTitle
        guard selectedURL != nil || !title.isEmpty || !body.isEmpty else { return nil }

        let previousURL = selectedURL
        let savedURL: URL
        if let previousURL {
            loadedNoteCache.removeEntry(forKey: loadedNoteCacheKey(for: previousURL))
            savedURL = try noteStore.updateNote(at: previousURL, title: title, body: body, tags: selectedTags)
        } else {
            savedURL = try noteStore.saveNewNote(
                title: title,
                body: body,
                tags: selectedTags,
                in: targetDirectoryForNewNote()
            )
        }

        recordInternalFileSystemChanges(for: [previousURL, savedURL].compactMap { $0 })
        selectedURL = savedURL
        activeSearchSession = nil
        isCreatingNewNote = false
        isDirty = false
        let savedAt = (try? FileManager.default.attributesOfItem(atPath: savedURL.path)[.modificationDate])
            as? Date ?? Date()
        updateSourceCountSnapshotAfterSave(
            previousURL: previousURL,
            savedURL: savedURL,
            title: title,
            body: body,
            tags: selectedTags,
            modifiedAt: savedAt
        )
        statusLabel.stringValue = editorDateText(for: savedAt)
        onSave(savedURL)
        updateToolbarActionState()
        return savedURL
    }

    private func updateSourceCountSnapshotAfterSave(
        previousURL: URL?,
        savedURL: URL,
        title: String,
        body: String,
        tags: [String],
        modifiedAt: Date
    ) {
        let previousPath = previousURL?.standardizedFileURL.path
        let savedPath = savedURL.standardizedFileURL.path
        sourceCountSnapshot.removeAll { note in
            let notePath = note.url.standardizedFileURL.path
            return notePath == previousPath || notePath == savedPath
        }
        sourceCountSnapshot.append(NoteSearchResult(
            url: savedURL,
            title: title,
            snippet: libraryFirstMeaningfulLine(from: body) ?? "",
            modifiedAt: modifiedAt,
            tags: tags,
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: body, relativeTo: savedURL)
        ))
        sourceCountSnapshot.sort { $0.modifiedAt > $1.modifiedAt }
        if sourceCountSnapshot.count > Self.sourceCountSnapshotLimit {
            sourceCountSnapshot.removeLast(sourceCountSnapshot.count - Self.sourceCountSnapshotLimit)
        }
    }

    private func removeNotesFromSourceSnapshot(at urls: [URL]) {
        let removedPaths = Set(urls.map { $0.standardizedFileURL.path })
        sourceCountSnapshot.removeAll { removedPaths.contains($0.url.standardizedFileURL.path) }
    }

    private func remapSourceSnapshotNotes(from sourceURLs: [URL], to destinationURLs: [URL]) {
        let destinationBySourcePath = Dictionary(uniqueKeysWithValues: zip(sourceURLs, destinationURLs).map {
            ($0.standardizedFileURL.path, $1.standardizedFileURL)
        })
        sourceCountSnapshot = sourceCountSnapshot.map { note in
            guard let destinationURL = destinationBySourcePath[note.url.standardizedFileURL.path] else { return note }
            return note.replacingURL(destinationURL)
        }
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
    }

    private func removeSourceSnapshotNotes(in folderURL: URL) {
        let folderPath = folderURL.standardizedFileURL.path
        sourceCountSnapshot.removeAll {
            $0.url.standardizedFileURL.path.hasPrefix(folderPath + "/")
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
        recordInternalFileSystemChanges(for: urls)
        if selectedScope != .trash {
            removeNotesFromSourceSnapshot(at: urls)
        }
        activeSearchSession = nil
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
        recordInternalFileSystemChanges(for: urls + restoredURLs)
        for url in restoredURLs {
            let document = try noteStore.loadNote(at: url)
            let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate])
                as? Date ?? Date()
            updateSourceCountSnapshotAfterSave(
                previousURL: nil,
                savedURL: url,
                title: document.title,
                body: document.body,
                tags: document.tags,
                modifiedAt: modifiedAt
            )
        }
        activeSearchSession = nil
        selectedScope = .all
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(selecting: restoredURL, loadFirstIfNeeded: true)
        return restoredURL
    }

    func selectedMarkdownFileURLForLibrary() -> URL? {
        selectedMarkdownFileURLsForLibrary().first
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
    }

    func waitForSourceSnapshotValidationForLibrary() async {
        let task = sourceSnapshotValidationTask
        await task?.value
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
        splitView.adjustSubviews()

        if !sourceList.isHidden {
            splitView.setPosition(storedSourceColumnWidthForLibrary, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
        }
        let noteDividerPosition = noteList.frame.minX + storedNoteColumnWidthForLibrary
        splitView.setPosition(noteDividerPosition, ofDividerAt: 1)
        splitView.layoutSubtreeIfNeeded()
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
        if noteList.frame.width > 0 {
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
        if let sourceSplitViewItem {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = LibraryNotesLayout.sourceCollapseAnimationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    sourceSplitViewItem.animator().isCollapsed = !isVisible
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.restoreStoredPaneWidthsAfterSourceVisibilityChange()
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
        let noteList = splitView.arrangedSubviews[1]
        splitView.setPosition(noteList.frame.minX + storedNoteColumnWidthForLibrary, ofDividerAt: 1)
        splitView.layoutSubtreeIfNeeded()
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

    @discardableResult
    private func createLibraryFolder(named name: String, in parentURL: URL) throws -> URL {
        let folderURL = try noteStore.createFolder(named: name, in: parentURL)
        recordInternalFileSystemChanges(for: [folderURL])
        activeSearchSession = nil
        selectedScope = .folder(folderURL)
        reloadSourceFolderRowsForCurrentState()
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
            reloadSourceFolderRowsForCurrentState()
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
            reloadSourceFolderRowsForCurrentState()
        }

        let standardizedURL = folderURL.standardizedFileURL
        guard sourceFolderRows.contains(where: {
            $0.url.standardizedFileURL.path == standardizedURL.path
        }) else { return }
        inlineFolderEditOperation = .rename(folderURL: standardizedURL)
        inlineFolderEditHasReceivedFocus = false
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        focusInlineFolderEditField()
    }

    private func insertInlineFolderEditRowIfNeeded() {
        guard let operation = inlineFolderEditOperation else { return }

        let insertionIndex: Int
        let depth: Int
        switch operation {
        case .create(let parentURL):
            let parentPath = parentURL.standardizedFileURL.path
            let parentIndex = sourceFolderRows.firstIndex {
                $0.url.standardizedFileURL.path == parentPath
            }
            depth = parentIndex.map { sourceFolderRows[$0].depth + 1 } ?? 0
            insertionIndex = min((parentIndex ?? -1) + 1, sourceFolderStack.arrangedSubviews.count)
        case .rename(let folderURL):
            guard let folderIndex = sourceFolderRows.firstIndex(where: {
                $0.url.standardizedFileURL.path == folderURL.standardizedFileURL.path
            }) else { return }
            depth = sourceFolderRows[folderIndex].depth
            insertionIndex = min(folderIndex, sourceFolderStack.arrangedSubviews.count)
        }

        let row = makeInlineFolderEditRow(depth: depth, name: operation.initialName)
        sourceFolderStack.insertArrangedSubview(row, at: insertionIndex)
        inlineFolderEditRow = row
        inlineFolderEditHasReceivedFocus = false
    }

    private func makeInlineFolderEditRow(depth: Int, name: String) -> NSView {
        let row = LibrarySourceRowView()
        row.identifier = NSUserInterfaceItemIdentifier("LibraryInlineFolderEditRow")
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceRowHeight).isActive = true
        row.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceRowWidth).isActive = true

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

        let field = NSTextField(string: name)
        field.identifier = NSUserInterfaceItemIdentifier("LibraryInlineFolderEditField")
        field.delegate = self
        field.font = .systemFont(
            ofSize: LibraryNotesLayout.sourceButtonFontSize,
            weight: LibraryNotesLayout.sourceUnselectedButtonFontWeight
        )
        field.textColor = LibrarySourceSelectionPalette.unselectedForegroundColor
        field.backgroundColor = NSColor.controlBackgroundColor
        field.drawsBackground = true
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        field.layer?.borderWidth = 1
        field.layer?.borderColor = panelAccentColor().withAlphaComponent(0.8).cgColor
        field.translatesAutoresizingMaskIntoConstraints = false

        let leadingInset = LibrarySourceButtonCell.contentLeadingInset
            + CGFloat(depth) * LibraryNotesLayout.sourceFolderIndentStep
        row.addSubview(icon)
        row.addSubview(field)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: leadingInset),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 24)
        ])
        inlineFolderEditField = field
        return row
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
        if let row = inlineFolderEditRow {
            sourceFolderStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        inlineFolderEditRow = nil
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
        reloadSourceFolderRowsForCurrentState()
        reloadNotes(loadFirstIfNeeded: true)
        return renamedURL
    }

    func deleteSelectedFolderForLibrary() throws {
        guard case .folder(let folderURL) = selectedScope else {
            throw LibraryActionError.noFolderSelected
        }

        _ = try noteStore.trashFolder(at: folderURL)
        recordInternalFileSystemChanges(for: [folderURL])
        removeSourceSnapshotNotes(in: folderURL)
        activeSearchSession = nil
        reloadPersistedSourceDisclosureState()
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
        recordInternalFileSystemChanges(for: sourceURLs + movedURLs)
        remapSourceSnapshotNotes(from: sourceURLs, to: movedURLs)
        activeSearchSession = nil
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

        let movedURLs = try sourceURLs.map { sourceURL in
            try noteStore.moveNote(at: sourceURL, to: targetDirectory)
        }
        recordInternalFileSystemChanges(for: sourceURLs + movedURLs)
        remapSourceSnapshotNotes(from: sourceURLs, to: movedURLs)
        activeSearchSession = nil
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
        selectedURL = nil
        selectedTags = []
        isDirty = false
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
        let preview = snippet.isEmpty ? "No additional text" : snippet
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
            ? "Recently Deleted"
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
            return "Yesterday"
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if (2...7).contains(daysAgo) {
            return noteListWeekdayFormatter.string(from: date)
        }

        return noteListShortDateFormatter.string(from: date)
    }

    private func editorDateText(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func notesCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "note" : "notes")"
    }

    private func resultsCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "result" : "results")"
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
        noteListToolbarTitleLeadingConstraint?.constant = isSourceListVisibleForLibrary ? 0 : -24
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.addFolderToolbarItemIdentifier:
                item.isHidden = !isSourceListVisibleForLibrary
            case Self.sourceTrackingSeparatorToolbarItemIdentifier:
                item.isHidden = !isSourceListVisibleForLibrary
            case Self.toggleSidebarToolbarItemIdentifier:
                let label = isSourceListVisibleForLibrary ? "隐藏资料库" : "显示资料库"
                updateToolbarItemPresentation(item, label: label, symbolName: "sidebar.left")
                configureToggleSidebarToolbarItem(
                    item,
                    label: label,
                    usesCompactGlass: !isSourceListVisibleForLibrary
                )
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
                setEditorToolsToolbarGroupEnabled(canEditCurrentDocument, in: item)
            default:
                continue
            }
        }
        window?.toolbar?.validateVisibleItems()
        updateVisibleEditorToolsToolbarGroupEnabled()
    }

    private func updateToolbarItemPresentation(_ item: NSToolbarItem, label: String, symbolName: String) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        let image = toolbarSymbolImage(symbolName: symbolName, label: label)
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
        let image = toolbarSymbolImage(symbolName: "sidebar.left", label: label)
        image?.isTemplate = true
        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(toggleSourceListPressed))
        button.identifier = NSUserInterfaceItemIdentifier(Self.toggleSidebarToolbarItemIdentifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true
        guard usesCompactGlass else {
            item.view = button
            return
        }

        item.view = toolbarGlassSurface(
            identifier: "\(Self.toggleSidebarToolbarItemIdentifier.rawValue).glass",
            content: button,
            size: NSSize(
                width: LibraryNotesLayout.toolbarCircularButtonSize,
                height: LibraryNotesLayout.toolbarCircularButtonSize
            ),
            cornerRadius: LibraryNotesLayout.toolbarCircularButtonSize / 2
        )
    }

    @objc
    private func noteListActionsToolbarMenuPressed(_ sender: Any?) {
        popToolbarMenu(makeNoteListActionsMenuForLibrary(), from: sender)
    }

    private func popToolbarMenu(_ menu: NSMenu, from sender: Any?) {
        menu.autoenablesItems = false
        if let view = (sender as? NSView) ?? (sender as? NSToolbarItem)?.view {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: view.bounds.minX, y: view.bounds.minY - 6),
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
            setEditorToolsToolbarGroupEnabled(canEditCurrentDocument, in: item)
        }
    }

    private func setEditorToolsToolbarGroupEnabled(_ isEnabled: Bool, in item: NSToolbarItem) {
        item.isEnabled = isEnabled
        guard let view = item.view else { return }
        view.alphaValue = isEnabled
            ? LibraryNotesLayout.toolbarEditorToolsEnabledAlpha
            : LibraryNotesLayout.toolbarEditorToolsDisabledAlpha
        setEditorToolControls(in: view, enabled: isEnabled)
    }

    private func setEditorToolControls(in view: NSView, enabled isEnabled: Bool) {
        if let control = view as? NSControl {
            control.isEnabled = isEnabled
        }
        if let button = view as? NSButton {
            button.alphaValue = 1
            button.contentTintColor = toolbarEditorToolIconTintColor(isEnabled: isEnabled)
        }
        view.subviews.forEach { setEditorToolControls(in: $0, enabled: isEnabled) }
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

    func noteContextMenuForLibrary(row: Int) -> NSMenu? {
        guard let clickedNote = note(at: row) else { return nil }

        if !tableView.selectedRowIndexes.contains(row) {
            do {
                try saveCurrentNoteIfNeeded()
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
        groupsNoteListByDate.toggle()
        noteStore.libraryGroupsNotesByDate = groupsNoteListByDate
        rebuildNoteListRowsForDisplayOptions()
    }

    @objc
    private func noteListSortMenuItemPressed(_ sender: NSMenuItem) {
        guard let order = LibraryNoteSortOrder(rawValue: sender.tag), order != noteListSortOrder else {
            return
        }
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
        openItem.isEnabled = openableMarkdownLinkURL(link.url) != nil

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
        guard let url = openableMarkdownLinkURL(link.url) else { return false }
        NSWorkspace.shared.open(url)
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
            storage.addAttribute(.qmLinkURL, value: url, range: updatedRange)
            storage.addAttribute(.foregroundColor, value: theme.accentColor, range: updatedRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: updatedRange)
        } else {
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

        let string = editorTextView.string as NSString
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
            if storage.length > 0,
               storage.attribute(.qmTableID, at: 0, effectiveRange: nil) != nil {
                var attributes = storage.attributes(at: 0, effectiveRange: nil)
                attributes.removeValue(forKey: .qmTablePlaceholder)
                editorTextView.typingAttributes = attributes
                return
            }
            editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
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
        focusEditorForLibraryAction()
        if let paragraphKind = command.paragraphKind {
            setParagraphKind(paragraphKind)
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
        case .heading1, .heading2, .heading3, .paragraph, .checklist, .bullet, .ordered:
            break
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
        let rendered = MarkdownRichTextCodec.render(markdown: rowMarkdown, theme: theme, baseURL: selectedURL)

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
            baseURL: selectedURL
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
        let rendered = MarkdownRichTextCodec.render(markdown: source, theme: theme, baseURL: selectedURL)

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
            baseURL: renderingBaseURL ?? selectedURL
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
        guard handleStructuredNewline() else {
            textView.insertNewlineIgnoringFieldEditor(self)
            updateTypingAttributesFromInsertionPoint()
            return
        }
    }

    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool {
        false
    }

    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool {
        guard textView === editorTextView else { return false }
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
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy 'at' HH:mm"
        return formatter
    }()

    private let noteListTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let noteListWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private let noteListShortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d/yy"
        return formatter
    }()
}
