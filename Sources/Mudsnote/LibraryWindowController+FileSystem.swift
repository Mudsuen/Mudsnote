import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func startLibraryFileSystemMonitorIfNeeded() {
        guard fileSystemMonitor == nil else { return }
        let monitor = LibraryFileSystemMonitor(roots: noteStore.preferredDirectories) { [weak self] changes in
            Task { @MainActor [weak self] in
                self?.handleLibraryFileSystemChanges(changes)
            }
        }
        guard monitor.start() else { return }
        fileSystemMonitor = monitor
    }

    func restartLibraryFileSystemMonitorForCurrentRoots() {
        let shouldRestart = fileSystemMonitor != nil || window?.isVisible == true
        fileSystemMonitor?.stop()
        fileSystemMonitor = nil
        if shouldRestart {
            startLibraryFileSystemMonitorIfNeeded()
        }
    }

    func handleLibraryFileSystemChanges(
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

        let invalidatesAllThumbnails = externalChanges.contains(where: \.changesDirectoryStructure)
        let imagePaths = Set(externalChanges.filter(\.isImageFile).map {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
        })
        if invalidatesAllThumbnails || !imagePaths.isEmpty,
           let storage = editorTextView.textStorage {
            // Refresh attachment cells in place so unsaved text, selection,
            // scroll position, and undo history are not replaced by a reload.
            storage.enumerateAttribute(.qmImageFilePath, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard let path = value as? String,
                      invalidatesAllThumbnails || imagePaths.contains(URL(fileURLWithPath: path).standardizedFileURL.path),
                      let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                      let cell = attachment.attachmentCell as? AsyncImageAttachmentCell else { return }
                cell.reloadImage(in: editorTextView)
            }
        }
        if invalidatesAllThumbnails {
            thumbnailImageLoadTasks.values.forEach { $0.cancel() }
            thumbnailImageLoadTasks.removeAll()
            thumbnailImageCache.removeAllObjects()
        } else {
            for path in imagePaths {
                thumbnailImageLoadTasks.removeValue(forKey: path)?.cancel()
                thumbnailImageCache.removeObject(forKey: path as NSString)
                scheduleThumbnailReload(for: path)
            }
        }
        // Attachment-only changes do not change note metadata or search results.
        guard invalidatesAllThumbnails || externalChanges.contains(where: \.isMarkdownFile) else { return }

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

    func flushDeferredFileSystemChangesAfterAutosave() {
        guard !backgroundAutosaveIsActive,
              !deferredFileSystemChangesDuringAutosave.isEmpty else {
            return
        }
        let changes = deferredFileSystemChangesDuringAutosave
        deferredFileSystemChangesDuringAutosave.removeAll()
        handleLibraryFileSystemChanges(changes, requiresVisibleWindow: false)
    }

    func recordInternalFileSystemChanges(
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

    func isSuppressedInternalChange(_ change: LibraryFileSystemChange) -> Bool {
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
}
