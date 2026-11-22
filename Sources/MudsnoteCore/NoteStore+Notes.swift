import Foundation

private struct TrashedNoteMetadata: Codable {
    let originalPath: String
    let deletedAt: Date
}

private struct NoteAttachmentRelocation {
    let markdown: String
    let copiedURLs: [URL]
    var destinationURLs: [URL] = []
    var cleanupRoot: URL? = nil
}

extension NoteStore {
    public var preferredInboxDirectory: URL {
        let candidates = preferredDirectories.flatMap { root -> [URL] in
            let children = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return [root] + children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
        }

        if let inbox = candidates.enumerated().min(by: { lhs, rhs in
            let lhsRank = Self.inboxDirectoryRank(lhs.element.lastPathComponent)
            let rhsRank = Self.inboxDirectoryRank(rhs.element.lastPathComponent)
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }), Self.inboxDirectoryRank(inbox.element.lastPathComponent) < Int.max {
            return inbox.element.standardizedFileURL
        }

        return notesDirectory.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL
    }

    private static func inboxDirectoryRank(_ name: String) -> Int {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "inbox" { return 0 }
        if normalized.hasSuffix("-inbox") || normalized.hasSuffix("_inbox") || normalized.hasSuffix(" inbox") {
            return 1
        }
        return Int.max
    }

    public func isInboxNote(at url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        return standardizedURL.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
            || standardizedURL.deletingLastPathComponent() == preferredInboxDirectory
    }

    public func listRecentFiles(limit: Int = 8) -> [NoteFile] {
        let recentPaths = (defaults.array(forKey: NoteStoreDefaultsKey.recentFiles) as? [String]) ?? []
        let recentMetadata = storedRecentMetadata()

        return recentPaths.prefix(limit).map { path in
            let url = URL(fileURLWithPath: path)
            return NoteFile(
                url: url,
                title: recentTitle(for: url),
                modifiedAt: recentModifiedDate(for: url, metadata: recentMetadata)
            )
        }
    }

    public func removeRecentFileReference(at url: URL) {
        forgetRecentFile(url.standardizedFileURL)
    }

    private static let leadingDatePrefixRegex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}-"#)
    private static let consecutiveHyphensRegex = try! NSRegularExpression(pattern: #"-+"#)

    private func recentTitle(for url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        let range = NSRange(location: 0, length: (stem as NSString).length)
        stem = Self.leadingDatePrefixRegex.stringByReplacingMatches(in: stem, range: range, withTemplate: "")
        let title = stem
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
    }

    public func loadNoteDocument(at url: URL) throws -> LoadedNoteDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        let loaded = loadedNote(from: text, at: url)
        return LoadedNoteDocument(
            title: loaded.title,
            body: loaded.body,
            tags: loaded.tags,
            sourceContents: text
        )
    }

    public func loadNote(at url: URL) throws -> (title: String, body: String, tags: [String]) {
        let document = try loadNoteDocument(at: url)
        return (document.title, document.body, document.tags)
    }

    func loadedNote(from text: String, at url: URL) -> (title: String, body: String, tags: [String]) {
        let parsed = parseStoredDocument(text)
        let trimmedBody = parsed.body.trimmingCharacters(in: .newlines)
        let lines = parsed.body.components(separatedBy: .newlines)

        if let firstLine = lines.first, firstLine.hasPrefix("# ") {
            let title = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            var bodyLines = Array(lines.dropFirst())
            if bodyLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                bodyLines.removeFirst()
            }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            return (title, body, parsed.tags)
        }

        guard !trimmedBody.isEmpty else {
            return ("", "", parsed.tags)
        }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        return (fallbackTitle, trimmedBody, parsed.tags)
    }

    func displayTitle(for url: URL, loadedTitle: String) -> String {
        let trimmedTitle = loadedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty else { return trimmedTitle }
        return recentTitle(for: url)
    }

    public func saveNewNote(title: String, body: String, tags: [String] = [], in directory: URL? = nil) throws -> URL {
        let targetDirectory = directory ?? notesDirectory
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let content = Data(storedNoteContent(title: title, body: body, tags: tags).utf8)
        while true {
            let fileURL = uniqueFileURL(for: title, in: targetDirectory)
            do {
                // Existence checks only suggest a name; creation must reject collisions.
                try content.write(to: fileURL, options: .withoutOverwriting)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
            rememberRecentFile(fileURL)
            markSearchIndexDirty(at: [fileURL])
            return fileURL
        }
    }

    public func updateNote(at url: URL, title: String, body: String, tags: [String] = [], in directory: URL? = nil) throws -> URL {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        return try updateManagedNote(at: url, title: title, body: body, tags: tags, in: directory, sourceIsCoordinated: false)
    }

    private func updateManagedNote(at url: URL, title: String, body: String, tags: [String], in directory: URL?, sourceIsCoordinated: Bool) throws -> URL {
        let sourceURL = url.standardizedFileURL
        let currentDirectory = sourceURL.deletingLastPathComponent()
        let targetDirectory = (directory ?? currentDirectory).standardizedFileURL
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let existingText = try String(contentsOf: sourceURL, encoding: .utf8)
        let previousTitle = loadedNote(from: existingText, at: sourceURL).title
        let sameTitle = previousTitle == title.trimmingCharacters(in: .whitespacesAndNewlines)
            || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !parseStoredDocument(existingText).body.hasPrefix("# "))
        let desiredURL = sameTitle && targetDirectory == currentDirectory
            ? sourceURL : uniqueUpdatedFileURL(for: title, currentURL: sourceURL, in: targetDirectory)
        let relocation = try relocatingAttachmentsIfNeeded(
            in: body,
            from: currentDirectory,
            to: targetDirectory
        )
        var didCommitRelocation = false
        defer {
            if !didCommitRelocation {
                removeRelocatedAttachments(relocation.copiedURLs, inside: relocation.cleanupRoot)
            }
        }
        if desiredURL == sourceURL {
            try writeNote(
                to: sourceURL,
                title: title,
                body: relocation.markdown,
                tags: tags,
                preservingFrontMatterFrom: existingText
            )
        } else {
            let content = storedNoteContent(
                    title: title,
                    body: relocation.markdown,
                    tags: tags,
                    preservingFrontMatterFrom: existingText
            )
            try withRelocatedNoteLinks(
                from: sourceURL, to: desiredURL,
                sourceContents: content, expectedSourceContents: existingText,
                copiedAttachmentURLs: relocation.destinationURLs
            ) { rewritten in
                try commitUpdatedNote(from: sourceURL, to: desiredURL, content: rewritten ?? content,
                                      expectedContents: existingText, sourceIsCoordinated: sourceIsCoordinated)
            }
        }
        didCommitRelocation = true

        rememberRecentFile(desiredURL, replacing: desiredURL == sourceURL ? nil : sourceURL)
        if desiredURL != sourceURL {
            replacePrimaryFloatingNotePath(sourceURL, with: desiredURL)
            replaceLibraryPinnedNotePath(sourceURL, with: desiredURL)
        }
        markSearchIndexDirty(at: [sourceURL, desiredURL])
        return desiredURL
    }

    public func updateNoteInPlace(at url: URL, title: String, body: String, tags: [String] = []) throws -> URL {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        let standardizedURL = url.standardizedFileURL
        let existingText = try String(contentsOf: standardizedURL, encoding: .utf8)
        try writeNote(
            to: standardizedURL,
            title: title,
            body: body,
            tags: tags,
            preservingFrontMatterFrom: existingText
        )
        rememberRecentFile(standardizedURL)
        markSearchIndexDirty(at: [standardizedURL])
        return standardizedURL
    }

    public func updateNote(
        at url: URL,
        title: String,
        body: String,
        tags: [String] = [],
        expectedContents: String,
        updatesInPlace: Bool,
        in directory: URL? = nil
    ) throws -> NoteUpdateResult {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        let standardizedURL = url.standardizedFileURL
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationResult: Result<NoteUpdateResult, Error>?

        coordinator.coordinate(
            writingItemAt: standardizedURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            operationResult = Result {
                let currentContents = try String(contentsOf: coordinatedURL, encoding: .utf8)
                guard currentContents == expectedContents else {
                    return try preserveConflictingUpdate(
                        originalURL: standardizedURL,
                        title: title,
                        body: body,
                        tags: tags,
                        expectedContents: expectedContents
                    )
                }

                let savedURL: URL
                if updatesInPlace {
                    savedURL = try updateNoteInPlace(
                        at: coordinatedURL,
                        title: title,
                        body: body,
                        tags: tags
                    )
                } else {
                    savedURL = try updateManagedNote(
                        at: coordinatedURL,
                        title: title,
                        body: body,
                        tags: tags,
                        in: directory,
                        sourceIsCoordinated: true
                    )
                }
                return NoteUpdateResult(
                    url: savedURL,
                    sourceContents: try String(contentsOf: savedURL, encoding: .utf8)
                )
            }
        }

        if let coordinationError { throw coordinationError }
        guard let operationResult else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try operationResult.get()
    }

    public func createFolder(named name: String, in parentDirectory: URL? = nil) throws -> URL {
        let parent = (parentDirectory ?? notesDirectory).standardizedFileURL
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let folderName = sanitizedFolderName(from: name)
        let folderURL = uniqueFolderURL(directory: parent, folderName: folderName)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        addPreferredDirectory(folderURL)
        return folderURL
    }

    public func renamePreferredDirectory(_ directory: URL, to name: String) throws -> URL {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        let oldDirectory = directory.standardizedFileURL
        let folderName = sanitizedFolderName(from: name)
        let newDirectory = uniqueFolderURL(
            directory: oldDirectory.deletingLastPathComponent(),
            folderName: folderName,
            excluding: oldDirectory
        )
        if oldDirectory != newDirectory {
            try withRelocatedNoteLinks(from: oldDirectory, to: newDirectory, isDirectory: true) { _ in
                try fileManager.moveItem(at: oldDirectory, to: newDirectory)
            }
            replaceRecentPathPrefix(oldDirectory, with: newDirectory)
            replacePrimaryFloatingNotePath(oldDirectory, with: newDirectory)
            replaceLibraryPinnedNotePathPrefix(oldDirectory, with: newDirectory)
            replaceLibraryFolderDisclosurePathPrefix(oldDirectory, with: newDirectory)
            invalidateSearchIndexContents()
        }
        replacePreferredDirectory(oldDirectory, with: newDirectory)
        return newDirectory
    }

    public func moveNote(at url: URL, to directory: URL) throws -> URL {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        let sourceURL = url.standardizedFileURL
        let targetDirectory = directory.standardizedFileURL
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        if sourceURL.deletingLastPathComponent().standardizedFileURL == targetDirectory {
            rememberRecentFile(sourceURL)
            return sourceURL
        }
        let movedURL = uniqueURLPreservingExtension(
            directory: targetDirectory,
            filenameStem: sourceURL.deletingPathExtension().lastPathComponent,
            pathExtension: sourceURL.pathExtension.isEmpty ? "md" : sourceURL.pathExtension
        )
        let existingText = try String(contentsOf: sourceURL, encoding: .utf8)
        let relocation = try relocatingAttachmentsIfNeeded(
            in: existingText,
            from: sourceURL.deletingLastPathComponent(),
            to: targetDirectory
        )
        var didCommitRelocation = false
        defer {
            if !didCommitRelocation {
                removeRelocatedAttachments(relocation.copiedURLs, inside: relocation.cleanupRoot)
            }
        }
        try withRelocatedNoteLinks(
            from: sourceURL, to: movedURL,
            sourceContents: relocation.markdown, expectedSourceContents: existingText,
            copiedAttachmentURLs: relocation.destinationURLs
        ) { rewritten in
            try commitUpdatedNote(from: sourceURL, to: movedURL, content: rewritten ?? relocation.markdown, expectedContents: existingText)
        }
        didCommitRelocation = true
        rememberRecentFile(movedURL, replacing: sourceURL)
        replacePrimaryFloatingNotePath(sourceURL, with: movedURL)
        replaceLibraryPinnedNotePath(sourceURL, with: movedURL)
        markSearchIndexDirty(at: [sourceURL, movedURL])
        return movedURL
    }

    public func moveFolder(at url: URL, to parentDirectory: URL) throws -> URL {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        let sourceURL = url.standardizedFileURL
        let targetParent = parentDirectory.standardizedFileURL
        let resolvedSource = sourceURL.resolvingSymlinksInPath()
        let resolvedTarget = targetParent.resolvingSymlinksInPath()
        guard sourceURL != notesDirectory.standardizedFileURL,
              sourceURL.deletingLastPathComponent() != targetParent,
              resolvedTarget != resolvedSource,
              !resolvedTarget.path.hasPrefix(resolvedSource.path + "/") else {
            return sourceURL
        }
        try fileManager.createDirectory(at: targetParent, withIntermediateDirectories: true)
        let destinationURL = uniqueFolderURL(
            directory: targetParent,
            folderName: sourceURL.lastPathComponent,
            excluding: sourceURL
        )
        try withRelocatedNoteLinks(from: sourceURL, to: destinationURL, isDirectory: true) { _ in
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
        replaceRecentPathPrefix(sourceURL, with: destinationURL)
        replacePrimaryFloatingNotePath(sourceURL, with: destinationURL)
        replaceLibraryPinnedNotePathPrefix(sourceURL, with: destinationURL)
        replaceLibraryFolderDisclosurePathPrefix(sourceURL, with: destinationURL)
        replaceLibraryFolderOrderPathPrefix(sourceURL, with: destinationURL)
        replacePreferredDirectory(sourceURL, with: destinationURL)
        invalidateSearchIndexContents()
        return destinationURL
    }

    public func trashFolder(at directory: URL) throws -> URL {
        try trashFolderWithNoteURLs(at: directory).directory
    }

    public func trashFolderWithNoteURLs(
        at directory: URL,
        knownNoteURLs: [URL]? = nil
    ) throws -> (directory: URL, noteURLs: [URL]) {
        let originalDirectory = directory.standardizedFileURL
        let folderTrashRoot = trashDirectory().appendingPathComponent("Folders", isDirectory: true)
        try fileManager.createDirectory(at: folderTrashRoot, withIntermediateDirectories: true)
        let trashedDirectory = uniqueFolderURL(
            directory: folderTrashRoot,
            folderName: originalDirectory.lastPathComponent.isEmpty ? "Folder" : originalDirectory.lastPathComponent
        )
        try fileManager.moveItem(at: originalDirectory, to: trashedDirectory)

        let deletionDate = Date()
        var metadata = storedTrashedNotesMetadata()
        metadata[metadataKey(for: trashedDirectory)] = TrashedNoteMetadata(
            originalPath: originalDirectory.path,
            deletedAt: deletionDate
        )
        storeTrashedNotesMetadata(metadata)
        let trashedFiles: [URL]
        if let knownNoteURLs {
            let originalPathPrefix = originalDirectory.path + "/"
            var seenPaths = Set<String>()
            trashedFiles = knownNoteURLs.compactMap { noteURL in
                let notePath = noteURL.standardizedFileURL.path
                guard notePath.hasPrefix(originalPathPrefix) else { return nil }
                let relativePath = String(notePath.dropFirst(originalPathPrefix.count))
                let trashedURL = trashedDirectory
                    .appendingPathComponent(relativePath)
                    .standardizedFileURL
                guard seenPaths.insert(trashedURL.path).inserted else { return nil }
                return trashedURL
            }
        } else {
            trashedFiles = markdownFiles(in: trashedDirectory)
        }
        removePreferredDirectory(originalDirectory)
        forgetRecentPathPrefix(originalDirectory)
        removeLibraryPinnedNotePaths(in: originalDirectory)
        removeLibraryFolderDisclosurePaths(in: originalDirectory)
        removeLibraryFolderIconNames(in: originalDirectory)
        invalidateSearchIndexContents()
        return (trashedDirectory, trashedFiles)
    }

    public func trashDirectory() -> URL {
        appSupportDirectory.appendingPathComponent("Trash", isDirectory: true)
    }

    public func listTrashedNotes(limit: Int = 200) -> [NoteSearchResult] {
        let metadata = storedTrashedNotesMetadata()
        var notes: [NoteSearchResult] = []

        for fileURL in markdownFiles(in: trashDirectory()) {
            let note = (try? loadNote(at: fileURL)) ?? (
                title: fileURL.deletingPathExtension().lastPathComponent,
                body: "",
                tags: []
            )
            let modifiedAt = resolvedTrashedNoteMetadata(for: fileURL, in: metadata)?.metadata.deletedAt
                ?? fileModificationDate(for: fileURL)
                ?? Date()
            notes.append(NoteSearchResult(
                url: fileURL,
                title: note.title,
                snippet: MarkdownEditorDocument.firstPreviewLine(in: note.body) ?? "",
                modifiedAt: modifiedAt,
                tags: note.tags,
                hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: note.body),
                thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: note.body, relativeTo: fileURL)
            ))
        }

        return notes
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { $0 }
    }

    public func searchTrashedNotes(
        query: String,
        limit: Int,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult] {
        guard limit > 0 else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return listTrashedNotes(limit: limit) }
        let parsedQuery = NoteSearchQuery(trimmedQuery)
        let metadata = storedTrashedNotesMetadata()
        guard let fileURLs = markdownFiles(
            in: trashDirectory(),
            cancellationCheck: cancellationCheck
        ) else {
            return []
        }

        var results: [NoteSearchResult] = []
        results.reserveCapacity(min(limit, fileURLs.count))
        for fileURL in fileURLs {
            guard !cancellationCheck() else { return [] }
            let fileSize = (
                try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
            )??.uint64Value ?? 0
            guard fileSize <= Self.maximumSearchIndexedFileSize else { continue }

            let loaded = try? loadNote(at: fileURL)
            guard !cancellationCheck() else { return [] }
            let title = loaded?.title ?? fileURL.deletingPathExtension().lastPathComponent
            let body = loaded?.body ?? ""
            let tags = loaded?.tags ?? []
            guard parsedQuery.matches(title: title, body: body, tags: tags) else { continue }

            let modifiedAt = resolvedTrashedNoteMetadata(for: fileURL, in: metadata)?.metadata.deletedAt
                ?? fileModificationDate(for: fileURL)
                ?? Date()
            let result = NoteSearchResult(
                url: fileURL,
                title: title,
                snippet: parsedQuery.snippet(in: body, fallback: MarkdownEditorDocument.firstPreviewLine(in: body) ?? ""),
                modifiedAt: modifiedAt,
                tags: tags,
                hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: body),
                thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: body, relativeTo: fileURL)
            )
            let insertionIndex = results.firstIndex {
                $0.modifiedAt < result.modifiedAt
            } ?? results.endIndex
            results.insert(result, at: insertionIndex)
            if results.count > limit {
                results.removeLast()
            }
        }
        return results
    }

    public func trashedNoteCount() -> Int {
        markdownFiles(in: trashDirectory()).count
    }

    public func trashNote(at url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        let trashDirectory = trashDirectory()
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)

        let trashedURL = uniqueTrashURL(for: standardizedURL, in: trashDirectory)
        try fileManager.moveItem(at: standardizedURL, to: trashedURL)
        forgetRecentFile(standardizedURL)

        var metadata = storedTrashedNotesMetadata()
        metadata[metadataKey(for: trashedURL)] = TrashedNoteMetadata(
            originalPath: standardizedURL.path,
            deletedAt: Date()
        )
        storeTrashedNotesMetadata(metadata)
        setLibraryNotePinned(false, at: standardizedURL)
        markSearchIndexDirty(at: [standardizedURL])
        return trashedURL
    }

    public func protectedAttachmentReferenceSources() throws -> [ProtectedAttachmentReferenceSource] {
        var sources: [ProtectedAttachmentReferenceSource] = []
        try forEachProtectedAttachmentReferenceSource { source, markdown in
            sources.append(ProtectedAttachmentReferenceSource(source: source, markdown: markdown))
        }
        return sources
    }

    public func forEachProtectedAttachmentReferenceSource(
        cancellationCheck: @Sendable () -> Bool = { Task.isCancelled },
        _ consume: (AttachmentReferenceSource, String) throws -> Void
    ) throws {
        let metadata = storedTrashedNotesMetadata()
        let trash = trashDirectory()
        if fileManager.fileExists(atPath: trash.path) {
            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(at: trash,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in enumerationError = error; return false }) else { throw CocoaError(.fileReadUnknown) }
            for case let url as URL in enumerator {
                if cancellationCheck() { throw CancellationError() }
                guard ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()),
                      try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                guard let original = resolvedTrashedNoteMetadata(for: url, in: metadata) else { throw CocoaError(.fileReadCorruptFile) }
                try consume(AttachmentReferenceSource(resolutionURL: URL(fileURLWithPath: original.originalPath),
                    identityURL: url, kind: .trash), String(contentsOf: url, encoding: .utf8))
            }
            if let enumerationError { throw enumerationError }
        }
        let drafts = appSupportDirectory.appendingPathComponent("Drafts", isDirectory: true)
        if fileManager.fileExists(atPath: drafts.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for url in try fileManager.contentsOfDirectory(at: drafts, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                if cancellationCheck() { throw CancellationError() }
                let draft = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: url))
                let noteURL = draft.sourcePath.map { URL(fileURLWithPath: $0) }
                    ?? URL(fileURLWithPath: draft.selectedDirectoryPath).appendingPathComponent(".draft.md")
                try consume(AttachmentReferenceSource(resolutionURL: noteURL, identityURL: url, kind: .draft), draft.body)
            }
        }
    }

    public func restoreTrashedNote(at url: URL) throws -> URL {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        let standardizedTrashURL = url.standardizedFileURL
        var metadata = storedTrashedNotesMetadata()
        let metadataKey = metadataKey(for: standardizedTrashURL)
        let resolvedMetadata = resolvedTrashedNoteMetadata(
            for: standardizedTrashURL,
            in: metadata
        )
        let originalURL = resolvedMetadata
            .map { URL(fileURLWithPath: $0.originalPath) }
            ?? notesDirectory.appendingPathComponent(standardizedTrashURL.lastPathComponent)
        let restoreDirectory = originalURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: restoreDirectory, withIntermediateDirectories: true)

        let restoredURL = uniqueRestoredURL(for: originalURL)
        let originalText = try String(contentsOf: standardizedTrashURL, encoding: .utf8)
        let relocation: NoteAttachmentRelocation
        if let resolvedMetadata, resolvedMetadata.key != metadataKey {
            relocation = try relocatingAttachmentsIfNeeded(in: originalText,
                from: standardizedTrashURL.deletingLastPathComponent(), to: restoreDirectory,
                restoringFolder: (URL(fileURLWithPath: resolvedMetadata.key),
                    URL(fileURLWithPath: resolvedMetadata.metadata.originalPath)))
        } else { relocation = NoteAttachmentRelocation(markdown: originalText, copiedURLs: []) }
        do {
            if relocation.markdown == originalText {
                try moveUnchangedCoordinatedNote(
                    from: standardizedTrashURL,
                    to: restoredURL,
                    expectedContents: originalText
                )
            } else {
                try commitUpdatedNote(from: standardizedTrashURL, to: restoredURL,
                    content: relocation.markdown, expectedContents: originalText)
            }
        } catch {
            removeRelocatedAttachments(relocation.copiedURLs, inside: relocation.cleanupRoot)
            throw error
        }
        if resolvedMetadata?.key == metadataKey {
            metadata.removeValue(forKey: metadataKey)
        }
        storeTrashedNotesMetadata(metadata)
        rememberRecentFile(restoredURL, replacing: standardizedTrashURL)
        markSearchIndexDirty(at: [restoredURL])
        return restoredURL
    }

    public func permanentlyDeleteTrashedNote(at url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        if fileManager.fileExists(atPath: standardizedURL.path) {
            try fileManager.removeItem(at: standardizedURL)
        }
        var metadata = storedTrashedNotesMetadata()
        metadata.removeValue(forKey: metadataKey(for: standardizedURL))
        storeTrashedNotesMetadata(metadata)
        forgetRecentFile(standardizedURL)
        setLibraryNotePinned(false, at: standardizedURL)
        markSearchIndexDirty(at: [standardizedURL])
    }

    func markdownFiles(in root: URL) -> [URL] {
        markdownFiles(in: root, cancellationCheck: { false }) ?? []
    }

    func markdownFiles(
        in root: URL,
        cancellationCheck: @Sendable () -> Bool
    ) -> [URL]? {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]

        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var results: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard !cancellationCheck() else { return nil }
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else {
                continue
            }
            if values.isDirectory == true {
                if url.lastPathComponent.caseInsensitiveCompare(Self.attachmentDirectoryName) == .orderedSame {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            if ["md", "markdown", "txt"].contains(ext) {
                results.append(url)
            }
        }

        return results
    }

    func parseStoredDocument(_ text: String) -> (body: String, tags: [String]) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return (normalized, [])
        }

        let lines = normalized.components(separatedBy: "\n")
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
            return (normalized, [])
        }

        let frontMatter = Array(lines[1..<closingIndex])
        let body = Array(lines[(closingIndex + 1)...]).joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        return (
            body,
            MarkdownEditorDocument.normalizedTags(frontMatterTags(in: frontMatter))
        )
    }

    private func writeNote(
        to url: URL,
        title: String,
        body: String,
        tags: [String] = [],
        preservingFrontMatterFrom existingText: String? = nil
    ) throws {
        try storedNoteContent(
            title: title,
            body: body,
            tags: tags,
            preservingFrontMatterFrom: existingText
        )
            .write(to: url, atomically: true, encoding: .utf8)
    }

    public func matchesStoredNoteContent(
        title: String,
        body: String,
        tags: [String] = [],
        expectedContents: String
    ) -> Bool {
        storedNoteContent(
            title: title,
            body: body,
            tags: tags,
            preservingFrontMatterFrom: expectedContents
        ) == expectedContents
    }

    func storedNoteContent(
        title: String,
        body: String,
        tags: [String],
        preservingFrontMatterFrom existingText: String? = nil
    ) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .newlines)
        let normalizedTags = MarkdownEditorDocument.normalizedTags(tags)

        let content: String
        if trimmedTitle.isEmpty {
            content = trimmedBody.isEmpty ? "" : "\(trimmedBody)\n"
        } else if trimmedBody.isEmpty {
            content = "# \(trimmedTitle)\n"
        } else {
            content = "# \(trimmedTitle)\n\n\(trimmedBody)\n"
        }

        if let existingText,
           let frontMatter = frontMatterLines(in: existingText) {
            let updatedLines = frontMatterTags(in: frontMatter) == normalizedTags
                ? frontMatter : updatingFrontMatterTags(frontMatter, tags: normalizedTags)
            return "---\n\(updatedLines.joined(separator: "\n"))\n---\n\n\(content)"
        }

        guard !normalizedTags.isEmpty else { return content }
        let tagLines = normalizedTags.map { "- \($0)" }.joined(separator: "\n")
        return "---\ntags:\n\(tagLines)\n---\n\n\(content)"
    }

    private func frontMatterLines(in text: String) -> [String]? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return nil }
        let lines = normalized.components(separatedBy: "\n")
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else { return nil }
        return Array(lines[1..<closingIndex])
    }

    func frontMatterTags(in lines: [String]) -> [String] {
        guard let range = frontMatterTagBlockRange(in: lines) else { return [] }
        let firstLine = lines[range.lowerBound]
        let colon = firstLine.firstIndex(of: ":")!
        let inlineValue = String(firstLine[firstLine.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)
        if inlineValue.hasPrefix("["), inlineValue.hasSuffix("]") {
            let values = inlineValue.dropFirst().dropLast().split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            return MarkdownEditorDocument.normalizedTags(values)
        }
        let tags = lines[range].dropFirst().compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { return nil }
            return String(trimmed.dropFirst(2))
        }
        return MarkdownEditorDocument.normalizedTags(tags)
    }

    func updatingFrontMatterTags(_ lines: [String], tags: [String]) -> [String] {
        var updated = lines
        let replacement = tags.isEmpty ? [] : ["tags:"] + tags.map { "  - \($0)" }
        if let range = frontMatterTagBlockRange(in: lines) {
            let preservedComments = lines[range].dropFirst().filter {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            }
            updated.replaceSubrange(range, with: replacement + preservedComments)
        } else if !replacement.isEmpty {
            if updated.last?.isEmpty == false {
                updated.append("")
            }
            updated.append(contentsOf: replacement)
        }
        return updated
    }

    private func frontMatterTagBlockRange(in lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { frontMatterKey(in: $0) == "tags" }) else {
            return nil
        }
        let end = lines.indices.dropFirst(start + 1).first(where: {
            frontMatterKey(in: lines[$0]) != nil
        }) ?? lines.endIndex
        return start..<end
    }

    private func frontMatterKey(in line: String) -> String? {
        guard let first = line.first,
              !first.isWhitespace,
              let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-"
        }) else {
            return nil
        }
        return key.lowercased()
    }

    private func commitUpdatedNote(from sourceURL: URL, to destinationURL: URL, content: String, expectedContents: String, sourceIsCoordinated: Bool = false) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        if sourceIsCoordinated {
            // The expected-content save already owns the source. Acquiring it again deadlocks.
            coordinator.coordinate(writingItemAt: destinationURL, options: [], error: &coordinationError) { destinationURL in
                result = Result {
                    try commitCoordinatedNote(from: sourceURL, to: destinationURL, content: content, expectedContents: expectedContents)
                }
            }
        } else {
            coordinator.coordinate(
                writingItemAt: sourceURL, options: .forMoving,
                writingItemAt: destinationURL, options: [], error: &coordinationError
            ) { sourceURL, destinationURL in
                result = Result {
                    try commitCoordinatedNote(from: sourceURL, to: destinationURL, content: content, expectedContents: expectedContents)
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private func moveUnchangedCoordinatedNote(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedContents: String
    ) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: sourceURL, options: .forMoving,
            writingItemAt: destinationURL, options: [], error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            result = Result {
                guard try String(contentsOf: coordinatedSource, encoding: .utf8) == expectedContents else {
                    throw NoteLinkRelocationError.changed(sourceURL)
                }
                try fileManager.moveItem(at: coordinatedSource, to: coordinatedDestination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private func commitCoordinatedNote(from sourceURL: URL, to destinationURL: URL, content: String, expectedContents: String) throws {
        let originalCreationDate = (try? fileManager.attributesOfItem(atPath: sourceURL.path)[.creationDate]) as? Date
        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".mudsnote-update-\(UUID().uuidString).tmp")
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        try content.write(to: stagingURL, atomically: true, encoding: .utf8)
        if let originalCreationDate {
            try? fileManager.setAttributes([.creationDate: originalCreationDate], ofItemAtPath: stagingURL.path)
        }
        try updateNoteCommitHook?(.afterStaging)
        guard try String(contentsOf: sourceURL, encoding: .utf8) == expectedContents else {
            throw NoteLinkRelocationError.changed(sourceURL)
        }
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        do {
            try updateNoteCommitHook?(.afterDestinationCommit)
            guard try String(contentsOf: sourceURL, encoding: .utf8) == expectedContents else {
                throw NoteLinkRelocationError.changed(sourceURL)
            }
            try fileManager.removeItem(at: sourceURL)
        } catch {
            if (try? String(contentsOf: destinationURL, encoding: .utf8)) == content {
                try? fileManager.removeItem(at: destinationURL)
            } else if fileManager.fileExists(atPath: destinationURL.path) {
                throw NoteLinkRelocationError.changedDestination(destinationURL)
            }
            throw error
        }
    }

    private func preserveConflictingUpdate(
        originalURL: URL,
        title: String,
        body: String,
        tags: [String],
        expectedContents: String
    ) throws -> NoteUpdateResult {
        let pathExtension = originalURL.pathExtension.isEmpty ? "md" : originalURL.pathExtension
        let recoveryURL = uniqueURLPreservingExtension(
            directory: originalURL.deletingLastPathComponent(),
            filenameStem: "\(originalURL.deletingPathExtension().lastPathComponent) (Mudsnote Conflict)",
            pathExtension: pathExtension
        )
        let recoveryContents = storedNoteContent(
            title: title,
            body: body,
            tags: tags,
            preservingFrontMatterFrom: expectedContents
        )
        try recoveryContents.write(to: recoveryURL, atomically: true, encoding: .utf8)
        rememberRecentFile(recoveryURL)
        markSearchIndexDirty(at: [originalURL, recoveryURL])
        return NoteUpdateResult(
            url: recoveryURL,
            sourceContents: recoveryContents,
            conflictedOriginalURL: originalURL
        )
    }

    private func relocatingAttachmentsIfNeeded(
        in markdown: String,
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        restoringFolder: (source: URL, destination: URL)? = nil
    ) throws -> NoteAttachmentRelocation {
        let sourceDirectory = sourceDirectory.standardizedFileURL
        let destinationDirectory = destinationDirectory.standardizedFileURL
        guard sourceDirectory != destinationDirectory else {
            return NoteAttachmentRelocation(markdown: markdown, copiedURLs: [])
        }
        let sourceRoot = (restoringFolder?.source ?? sourceDirectory
            .appendingPathComponent(Self.attachmentDirectoryName)).standardizedFileURL.resolvingSymlinksInPath()
        let destinationRoot = (restoringFolder?.destination ?? destinationDirectory
            .appendingPathComponent(Self.attachmentDirectoryName)).standardizedFileURL
        let cleanupRoot = (restoringFolder?.destination.resolvingSymlinksInPath()
            ?? destinationDirectory.resolvingSymlinksInPath()
                .appendingPathComponent(Self.attachmentDirectoryName)).standardizedFileURL
        var destinationsBySourcePath: [String: URL] = [:]
        var copiedURLs: [URL] = []
        let result = NSMutableString(string: markdown)
        do {
            for reference in MarkdownNoteReferenceParser.destinations(in: markdown).reversed() {
                let candidates = reference.localFileCandidates(relativeTo: sourceDirectory.appendingPathComponent(".note.md"))
                    .map { candidate -> URL in
                        if restoringFolder != nil, candidate.path.hasPrefix(destinationRoot.path + "/") {
                            return sourceRoot.appendingPathComponent(String(candidate.path.dropFirst(destinationRoot.path.count + 1)))
                        }
                        return candidate
                    }
                guard let sourceURL = candidates.map({ $0.resolvingSymlinksInPath() }).first(where: {
                    $0.path.hasPrefix(sourceRoot.path + "/")
                        && $0.pathComponents.contains(where: { $0.caseInsensitiveCompare(Self.attachmentDirectoryName) == .orderedSame })
                        && fileManager.fileExists(atPath: $0.path)
                        && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                }) else { continue }
                // Ordinary wiki note links keep the existing note's identity.
                // Folder recovery also restores these local attachment notes.
                if restoringFolder == nil, reference.kind == .wiki, !reference.isEmbedded,
                   ["md", "markdown"].contains(sourceURL.pathExtension.lowercased()) { continue }
                let destinationURL: URL
                if let existing = destinationsBySourcePath[sourceURL.path] { destinationURL = existing }
                else {
                    let preferredURL = destinationRoot.appendingPathComponent(String(sourceURL.path.dropFirst(sourceRoot.path.count + 1)))
                    try fileManager.createDirectory(at: preferredURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let canonicalRoot = cleanupRoot.resolvingSymlinksInPath().path
                    let canonicalParent = preferredURL.deletingLastPathComponent().resolvingSymlinksInPath().path
                    guard canonicalParent == canonicalRoot
                        || canonicalParent.hasPrefix(canonicalRoot + "/") else {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    let selected = attachmentDestination(for: sourceURL, preferred: preferredURL)
                    destinationURL = selected.url
                    if selected.needsCopy {
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                        copiedURLs.append(destinationURL)
                    }
                    destinationsBySourcePath[sourceURL.path] = destinationURL
                }
                let base = destinationDirectory.pathComponents, target = destinationURL.pathComponents
                var common = 0
                while common < min(base.count, target.count), base[common] == target[common] { common += 1 }
                let relative = (Array(repeating: "..", count: base.count - common) + target.dropFirst(common)).joined(separator: "/")
                let suffix = reference.destination.firstIndex(where: { $0 == "?" || $0 == "#" })
                    .map { String(reference.destination[$0...]) } ?? ""
                result.replaceCharacters(in: reference.destinationRange, with: markdownEncodedPath(relative) + suffix)
            }
        } catch {
            removeRelocatedAttachments(copiedURLs, inside: cleanupRoot)
            throw error
        }
        return NoteAttachmentRelocation(markdown: result as String, copiedURLs: copiedURLs,
            destinationURLs: Array(destinationsBySourcePath.values), cleanupRoot: cleanupRoot)
    }

    private func attachmentDestination(for source: URL, preferred: URL) -> (url: URL, needsCopy: Bool) {
        var candidate = preferred
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            if fileManager.contentsEqual(atPath: source.path, andPath: candidate.path) { return (candidate, false) }
            let stem = preferred.deletingPathExtension().lastPathComponent
            let name = preferred.pathExtension.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(preferred.pathExtension)"
            candidate = preferred.deletingLastPathComponent().appendingPathComponent(name)
            index += 1
        }
        return (candidate, true)
    }

    private func markdownEncodedPath(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private func removeRelocatedAttachments(_ urls: [URL], inside cleanupRoot: URL?) {
        guard let cleanupRoot else { return }
        let canonicalRoot = cleanupRoot.resolvingSymlinksInPath().standardizedFileURL
        for url in urls.reversed() {
            let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard canonicalURL.path.hasPrefix(canonicalRoot.path + "/") else { continue }
            try? fileManager.removeItem(at: canonicalURL)
            var directory = canonicalURL.deletingLastPathComponent()
            while directory == canonicalRoot || directory.path.hasPrefix(canonicalRoot.path + "/") {
                // Only prune empty attachment directories, never the restored note tree.
                guard directory.pathComponents.contains(where: {
                    $0.caseInsensitiveCompare(Self.attachmentDirectoryName) == .orderedSame
                }) else { break }
                guard let contents = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                ), contents.isEmpty else {
                    break
                }
                try? fileManager.removeItem(at: directory)
                if directory == canonicalRoot
                    || directory.lastPathComponent.caseInsensitiveCompare(Self.attachmentDirectoryName) == .orderedSame {
                    break
                }
                directory.deleteLastPathComponent()
            }
        }
    }

    private func uniqueFileURL(for title: String, in directory: URL) -> URL {
        let base = filenameStem(for: title)
        return uniqueURL(directory: directory, baseName: base, excluding: nil)
    }

    private func uniqueUpdatedFileURL(for title: String, currentURL: URL, in directory: URL) -> URL {
        var base = filenameStem(for: title)
        // Title-driven renaming keeps the note's original date prefix.
        let currentName = currentURL.lastPathComponent as NSString
        if let oldMatch = Self.leadingDatePrefixRegex.firstMatch(in: currentURL.lastPathComponent, range: NSRange(location: 0, length: currentName.length)),
           let newMatch = Self.leadingDatePrefixRegex.firstMatch(in: base, range: NSRange(location: 0, length: (base as NSString).length)),
           let newRange = Range(newMatch.range, in: base) {
            base.replaceSubrange(newRange, with: currentName.substring(with: oldMatch.range))
        }
        let excludedURL = currentURL.deletingLastPathComponent() == directory ? currentURL : nil
        return uniqueURLPreservingExtension(
            directory: directory,
            filenameStem: base,
            pathExtension: currentURL.pathExtension.isEmpty ? "md" : currentURL.pathExtension,
            excluding: excludedURL
        )
    }

    private func uniqueURL(directory: URL, baseName: String, excluding existingURL: URL?) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).md")
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) && candidate != existingURL {
            candidate = directory.appendingPathComponent("\(baseName)-\(counter).md")
            counter += 1
        }

        return candidate
    }

    private func uniqueTrashURL(for url: URL, in directory: URL) -> URL {
        uniqueURLPreservingExtension(
            directory: directory,
            filenameStem: url.deletingPathExtension().lastPathComponent,
            pathExtension: url.pathExtension.isEmpty ? "md" : url.pathExtension
        )
    }

    private func uniqueRestoredURL(for url: URL) -> URL {
        uniqueURLPreservingExtension(
            directory: url.deletingLastPathComponent(),
            filenameStem: url.deletingPathExtension().lastPathComponent,
            pathExtension: url.pathExtension.isEmpty ? "md" : url.pathExtension
        )
    }

    private func uniqueURLPreservingExtension(
        directory: URL,
        filenameStem: String,
        pathExtension: String,
        excluding existingURL: URL? = nil
    ) -> URL {
        let ext = pathExtension.isEmpty ? "md" : pathExtension
        var candidate = directory.appendingPathComponent(filenameStem).appendingPathExtension(ext)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) && candidate != existingURL {
            candidate = directory.appendingPathComponent("\(filenameStem)-\(counter)").appendingPathExtension(ext)
            counter += 1
        }

        return candidate
    }

    private func uniqueFolderURL(directory: URL, folderName: String, excluding existingURL: URL? = nil) -> URL {
        var candidate = directory.appendingPathComponent(folderName, isDirectory: true)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) && candidate != existingURL {
            candidate = directory.appendingPathComponent("\(folderName) \(counter)", isDirectory: true)
            counter += 1
        }

        return candidate
    }

    private func sanitizedFolderName(from name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "新建文件夹" : cleaned
    }

    private func filenameStem(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "note-" + Self.filenameTimestamp.string(from: Date())
        let raw = trimmed.isEmpty ? fallback : trimmed.lowercased()

        let allowed = raw.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }

        let allowedString = String(allowed)
        let slug = Self.consecutiveHyphensRegex.stringByReplacingMatches(
            in: allowedString,
            range: NSRange(location: 0, length: (allowedString as NSString).length),
            withTemplate: "-"
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if slug.isEmpty {
            return fallback
        }

        let datePrefix = Self.datePrefix.string(from: Date())
        return "\(datePrefix)-\(slug.prefix(48))"
    }

    private func rememberRecentFile(_ url: URL, replacing oldURL: URL? = nil) {
        var items = (defaults.array(forKey: NoteStoreDefaultsKey.recentFiles) as? [String]) ?? []
        if let oldURL {
            items.removeAll { $0 == oldURL.path }
        }
        items.removeAll { $0 == url.path }
        items.insert(url.path, at: 0)
        let trimmedItems = Array(items.prefix(40))
        defaults.set(trimmedItems, forKey: NoteStoreDefaultsKey.recentFiles)

        var metadata = storedRecentMetadata()
        if let oldURL {
            metadata.removeValue(forKey: oldURL.path)
        }
        metadata[url.path] = Date().timeIntervalSince1970
        let retainedPaths = Set(trimmedItems)
        metadata = metadata.filter { retainedPaths.contains($0.key) }
        defaults.set(metadata, forKey: NoteStoreDefaultsKey.recentFileMetadata)
    }

    private func forgetRecentFile(_ url: URL) {
        var items = (defaults.array(forKey: NoteStoreDefaultsKey.recentFiles) as? [String]) ?? []
        items.removeAll { $0 == url.path }
        defaults.set(items, forKey: NoteStoreDefaultsKey.recentFiles)

        var metadata = storedRecentMetadata()
        metadata.removeValue(forKey: url.path)
        defaults.set(metadata, forKey: NoteStoreDefaultsKey.recentFileMetadata)
    }

    private func forgetRecentPathPrefix(_ oldDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        var items = (defaults.array(forKey: NoteStoreDefaultsKey.recentFiles) as? [String]) ?? []
        items.removeAll { path in
            path == oldPath || path.hasPrefix(oldPath + "/")
        }
        defaults.set(items, forKey: NoteStoreDefaultsKey.recentFiles)

        var metadata = storedRecentMetadata()
        metadata = metadata.filter { path, _ in
            path != oldPath && !path.hasPrefix(oldPath + "/")
        }
        defaults.set(metadata, forKey: NoteStoreDefaultsKey.recentFileMetadata)
    }

    private func replaceRecentPathPrefix(_ oldDirectory: URL, with newDirectory: URL) {
        let oldPath = oldDirectory.standardizedFileURL.path
        let newPath = newDirectory.standardizedFileURL.path
        let items = ((defaults.array(forKey: NoteStoreDefaultsKey.recentFiles) as? [String]) ?? []).map { path in
            if path == oldPath {
                return newPath
            }
            if path.hasPrefix(oldPath + "/") {
                return newPath + String(path.dropFirst(oldPath.count))
            }
            return path
        }
        defaults.set(items, forKey: NoteStoreDefaultsKey.recentFiles)

        var updatedMetadata: [String: TimeInterval] = [:]
        for (path, timestamp) in storedRecentMetadata() {
            if path == oldPath {
                updatedMetadata[newPath] = timestamp
            } else if path.hasPrefix(oldPath + "/") {
                updatedMetadata[newPath + String(path.dropFirst(oldPath.count))] = timestamp
            } else {
                updatedMetadata[path] = timestamp
            }
        }
        defaults.set(updatedMetadata, forKey: NoteStoreDefaultsKey.recentFileMetadata)
    }

    private func storedRecentMetadata() -> [String: TimeInterval] {
        let rawMetadata = defaults.dictionary(forKey: NoteStoreDefaultsKey.recentFileMetadata) ?? [:]
        var metadata: [String: TimeInterval] = [:]
        for (path, rawValue) in rawMetadata {
            if let timestamp = rawValue as? TimeInterval {
                metadata[path] = timestamp
            } else if let number = rawValue as? NSNumber {
                metadata[path] = number.doubleValue
            }
        }
        return metadata
    }

    private func recentModifiedDate(for url: URL, metadata: [String: TimeInterval]) -> Date {
        if let timestamp = metadata[url.path] {
            return Date(timeIntervalSince1970: timestamp)
        }
        return dateFromFilename(for: url) ?? Date()
    }

    private func dateFromFilename(for url: URL) -> Date? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard Self.leadingDatePrefixRegex.firstMatch(
            in: stem,
            range: NSRange(location: 0, length: (stem as NSString).length)
        ) != nil else {
            return nil
        }
        return Self.datePrefix.date(from: String(stem.prefix(10)))
    }

    private func fileModificationDate(for url: URL) -> Date? {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    private func storedTrashedNotesMetadata() -> [String: TrashedNoteMetadata] {
        guard let data = defaults.data(forKey: NoteStoreDefaultsKey.trashedNotesMetadata) else {
            return [:]
        }
        return (try? PropertyListDecoder().decode([String: TrashedNoteMetadata].self, from: data)) ?? [:]
    }

    private func storeTrashedNotesMetadata(_ metadata: [String: TrashedNoteMetadata]) {
        if let data = try? PropertyListEncoder().encode(metadata) {
            defaults.set(data, forKey: NoteStoreDefaultsKey.trashedNotesMetadata)
        }
    }

    private func metadataKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func resolvedTrashedNoteMetadata(
        for url: URL,
        in metadata: [String: TrashedNoteMetadata]
    ) -> (key: String, originalPath: String, metadata: TrashedNoteMetadata)? {
        let standardizedURL = url.standardizedFileURL
        let directKey = metadataKey(for: standardizedURL)
        if let directMetadata = metadata[directKey] {
            return (directKey, directMetadata.originalPath, directMetadata)
        }

        let trashRootPath = trashDirectory().standardizedFileURL.path
        var ancestor = standardizedURL.deletingLastPathComponent()
        while ancestor.path.hasPrefix(trashRootPath + "/") {
            let ancestorKey = metadataKey(for: ancestor)
            if let folderMetadata = metadata[ancestorKey] {
                let relativePath = relativePath(from: ancestor, to: standardizedURL)
                let originalURL = URL(
                    fileURLWithPath: folderMetadata.originalPath,
                    isDirectory: true
                ).appendingPathComponent(relativePath)
                return (ancestorKey, originalURL.standardizedFileURL.path, folderMetadata)
            }
            ancestor.deleteLastPathComponent()
        }
        return nil
    }

    private func relativePath(from root: URL, to fileURL: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static let datePrefix: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let filenameTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
