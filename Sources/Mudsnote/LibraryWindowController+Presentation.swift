import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func setEditorEditable(_ isEditable: Bool) {
        titleField.isEditable = isEditable
        editorTextView.isEditable = isEditable
    }

    func targetDirectoryForNewNote() -> URL {
        if case .folder(let folderURL) = selectedScope {
            return folderURL
        }
        return noteStore.notesDirectory
    }

    func targetDirectoryForNewFolder() -> URL {
        if case .folder(let folderURL) = selectedScope {
            return folderURL
        }
        return noteStore.notesDirectory
    }

    func noteListSnippetText(for note: NoteSearchResult) -> String {
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

    func noteListPreviewText(_ preview: String, removingDuplicateDateText dateText: String) -> String {
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

    func noteListFolderText(for note: NoteSearchResult) -> String {
        let folder = isTrashURL(note.url)
            ? LibraryCopy.recentlyDeleted
            : folderTitle(for: note.url.deletingLastPathComponent())
        let tags = note.tags.prefix(3).map(libraryDisplayTag).joined(separator: " ")
        if tags.isEmpty {
            return folder
        }
        return "\(folder) · \(tags)"
    }

    func noteListDateText(for date: Date, now: Date = Date()) -> String {
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

    func editorEditedDateText(for date: Date) -> String {
        "编辑于 \(dateFormatter.string(from: date))"
    }

    func updateEditorCreatedDate(_ date: Date?) {
        let text = date.map { "创建于 \(dateFormatter.string(from: $0))" } ?? ""
        createdDateLabel.stringValue = text
        createdDateLabel.setAccessibilityValue(text)
    }

    func notesCountText(_ count: Int) -> String {
        LibraryCopy.noteCount(count)
    }

    func resultsCountText(_ count: Int) -> String {
        LibraryCopy.resultCount(count)
    }

    func isTrashURL(_ url: URL) -> Bool {
        let trashPath = noteStore.trashDirectory().standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    var canUseSelectedNote: Bool {
        !selectedMarkdownFileURLsForLibrary().isEmpty
    }

    var canUseSingleSelectedNote: Bool {
        selectedMarkdownFileURLsForLibrary().count == 1
    }

    var canEditCurrentDocument: Bool {
        guard selectedScope != .trash else { return false }
        guard !isLoadingInitialNote else { return false }
        return selectedURL != nil
            || isCreatingNewNote
            || isDirty
            || !titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !editorTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canMoveSelectedNote: Bool {
        canUseSelectedNote && selectedScope != .trash && !sourceFolderRows.isEmpty
    }

    var canExportSelectedNote: Bool {
        canUseSelectedNote && selectedScope != .trash
    }

    var canRestoreSelectedNote: Bool {
        selectedScope == .trash && canUseSelectedNote
    }

    var canShowMoreActions: Bool {
        canUseSelectedNote || canEditCurrentDocument
    }
}
