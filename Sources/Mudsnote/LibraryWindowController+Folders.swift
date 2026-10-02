import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
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
    func createLibraryFolder(named name: String, in parentURL: URL) throws -> URL {
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

    func focusInlineFolderEditField(remainingAttempts: Int = 4) {
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

    func commitInlineFolderEdit() {
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

    func cancelInlineFolderEdit() {
        guard inlineFolderEditOperation != nil else { return }
        clearInlineFolderEditState()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
    }

    func clearInlineFolderEditState() {
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
    func renameLibraryFolder(at folderURL: URL, to name: String) throws -> URL {
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
            at: folderURL
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

    func canMoveDraggedNoteForLibrary(sourceURL: URL, to directory: URL) -> Bool {
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
            limit: Self.noteListResultLimit,
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

    func restoreNoteBrowserScrollPosition(
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

    func uniqueStandardizedFileURLs(from urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }

    func isInsideConfiguredLibraryRoot(_ noteURL: URL) -> Bool {
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

    func clearCurrentDocumentAfterRemoval() {
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
}
