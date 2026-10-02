import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

enum LibraryScope: Equatable, Sendable {
    case all
    case recent
    case favorites
    case inbox
    case folder(URL)
    case tag(String)
    case trash

    var buttonTitle: String {
        switch self {
        case .all:
            return LibraryCopy.allNotes
        case .recent:
            return "最近编辑"
        case .favorites:
            return "收藏"
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
        case .favorites:
            return "star"
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

enum LibrarySidebarPresentation: Int {
    case tree
    case list
}

func librarySearchResults(
    noteStore: NoteStore,
    searchSession: NoteSearchSession,
    scope: LibraryScope,
    query: String,
    limit: Int,
    searchesAllNotes: Bool,
    includesSubfolderNotes: Bool,
    recentlyEditedPaths: Set<String>
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
        // This category contains the 80 most recently edited library notes,
        // including imported files that have never entered the open history.
        return searchSession.searchNotes(
            query: query,
            limit: limit,
            restrictedTo: recentlyEditedPaths,
            cancellationCheck: cancellationCheck
        )
    case .favorites:
        let pinnedPaths = Set(noteStore.libraryPinnedNotePaths)
        return searchSession.searchNotes(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        ).filter { pinnedPaths.contains($0.url.standardizedFileURL.path) }
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

func libraryNote(
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

func libraryFirstMeaningfulLine(from body: String) -> String? {
    MarkdownEditorDocument.firstPreviewLine(in: body)
}

enum InlineFolderEditOperation: Equatable {
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

typealias LoadedLibraryNote = LoadedNoteDocument

extension NoteSearchResult {
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

enum LibrarySourceSection: Int {
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

enum LibraryNotesPalette {
    static let windowBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let editorBackground = NSColor(calibratedWhite: 0.075, alpha: 1)
    static let sidebarMaterialTint = NSColor.black.withAlphaComponent(0.10)
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

struct LibraryFolderIconChoice {
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

func libraryDisplayTag(_ tag: String) -> String {
    let trimmed = libraryBareTag(tag)
    guard !trimmed.isEmpty else { return "#" }
    return "#\(trimmed)"
}

func libraryBareTag(_ tag: String) -> String {
    var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasPrefix("#") {
        trimmed.removeFirst()
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
}

enum LibraryActionError: LocalizedError {
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

final class LibraryFolderMoveRequest: NSObject {
    let source: URL
    let destinationParent: URL

    init(source: URL, destinationParent: URL) {
        self.source = source.standardizedFileURL
        self.destinationParent = destinationParent.standardizedFileURL
    }
}

final class LibraryFolderIconRequest: NSObject {
    let folderURL: URL
    let symbolName: String?

    init(folderURL: URL, symbolName: String?) {
        self.folderURL = folderURL.standardizedFileURL
        self.symbolName = symbolName
    }
}

enum LibraryFormatCommand: Int {
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

struct LibraryFormattingUndoSnapshot {
    let content: NSAttributedString
    let selection: NSRange
}
