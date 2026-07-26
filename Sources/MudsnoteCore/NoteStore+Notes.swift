import Foundation

private struct TrashedNoteMetadata: Codable {
    let originalPath: String
    let deletedAt: Date
}

private struct NoteAttachmentRelocation {
    let markdown: String
    let copiedURLs: [URL]
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

    private func recentTitle(for url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        stem = stem.replacingOccurrences(
            of: #"^\d{4}-\d{2}-\d{2}-"#,
            with: "",
            options: .regularExpression
        )
        let title = stem
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
    }

    public func loadNote(at url: URL) throws -> (title: String, body: String, tags: [String]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        return loadedNote(from: text, at: url)
    }

    func loadedNote(from text: String, at url: URL) -> (title: String, body: String, tags: [String]) {
        let parsed = parseStoredDocument(text)
        let trimmedBody = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = parsed.body.components(separatedBy: .newlines)

        if let firstLine = lines.first, firstLine.hasPrefix("# ") {
            let title = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            var bodyLines = Array(lines.dropFirst())
            if bodyLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                bodyLines.removeFirst()
            }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
        let fileURL = uniqueFileURL(for: title, in: targetDirectory)
        try writeNote(to: fileURL, title: title, body: body, tags: tags)
        rememberRecentFile(fileURL)
        markSearchIndexDirty(at: [fileURL])
        return fileURL
    }

    public func updateNote(at url: URL, title: String, body: String, tags: [String] = [], in directory: URL? = nil) throws -> URL {
        let sourceURL = url.standardizedFileURL
        let currentDirectory = sourceURL.deletingLastPathComponent()
        let targetDirectory = directory ?? currentDirectory
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let existingText = try String(contentsOf: sourceURL, encoding: .utf8)
        let desiredURL = uniqueUpdatedFileURL(for: title, currentURL: sourceURL, in: targetDirectory)
        let relocation = try relocatingAttachmentsIfNeeded(
            in: body,
            from: currentDirectory,
            to: targetDirectory
        )
        var didCommitRelocation = false
        defer {
            if !didCommitRelocation {
                removeRelocatedAttachments(relocation.copiedURLs, inside: targetDirectory)
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
            try commitUpdatedNote(
                from: sourceURL,
                to: desiredURL,
                content: storedNoteContent(
                    title: title,
                    body: relocation.markdown,
                    tags: tags,
                    preservingFrontMatterFrom: existingText
                )
            )
        }
        didCommitRelocation = true

        rememberRecentFile(desiredURL, replacing: desiredURL == sourceURL ? nil : sourceURL)
        if desiredURL != sourceURL {
            replaceLibraryPinnedNotePath(sourceURL, with: desiredURL)
        }
        markSearchIndexDirty(at: [sourceURL, desiredURL])
        return desiredURL
    }

    public func updateNoteInPlace(at url: URL, title: String, body: String, tags: [String] = []) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        let existingText = try? String(contentsOf: standardizedURL, encoding: .utf8)
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
        let oldDirectory = directory.standardizedFileURL
        let folderName = sanitizedFolderName(from: name)
        let newDirectory = uniqueFolderURL(
            directory: oldDirectory.deletingLastPathComponent(),
            folderName: folderName,
            excluding: oldDirectory
        )
        if oldDirectory != newDirectory {
            try fileManager.moveItem(at: oldDirectory, to: newDirectory)
            replaceRecentPathPrefix(oldDirectory, with: newDirectory)
            replaceLibraryPinnedNotePathPrefix(oldDirectory, with: newDirectory)
            replaceLibraryFolderDisclosurePathPrefix(oldDirectory, with: newDirectory)
            invalidateSearchIndexContents()
        }
        replacePreferredDirectory(oldDirectory, with: newDirectory)
        return newDirectory
    }

    public func moveNote(at url: URL, to directory: URL) throws -> URL {
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
                removeRelocatedAttachments(relocation.copiedURLs, inside: targetDirectory)
            }
        }
        try commitUpdatedNote(from: sourceURL, to: movedURL, content: relocation.markdown)
        didCommitRelocation = true
        rememberRecentFile(movedURL, replacing: sourceURL)
        replaceLibraryPinnedNotePath(sourceURL, with: movedURL)
        markSearchIndexDirty(at: [sourceURL, movedURL])
        return movedURL
    }

    public func moveFolder(at url: URL, to parentDirectory: URL) throws -> URL {
        let sourceURL = url.standardizedFileURL
        let targetParent = parentDirectory.standardizedFileURL
        guard sourceURL != notesDirectory.standardizedFileURL,
              sourceURL.deletingLastPathComponent() != targetParent,
              !targetParent.path.hasPrefix(sourceURL.path + "/") else {
            return sourceURL
        }
        try fileManager.createDirectory(at: targetParent, withIntermediateDirectories: true)
        let destinationURL = uniqueFolderURL(
            directory: targetParent,
            folderName: sourceURL.lastPathComponent,
            excluding: sourceURL
        )
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        replaceRecentPathPrefix(sourceURL, with: destinationURL)
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

    public func trashFolderWithNoteURLs(at directory: URL) throws -> (directory: URL, noteURLs: [URL]) {
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
        let originalFiles = markdownFiles(in: trashedDirectory)
        for trashedFile in originalFiles {
            let relativePath = relativePath(from: trashedDirectory, to: trashedFile)
            let originalFile = originalDirectory.appendingPathComponent(relativePath)
            metadata[metadataKey(for: trashedFile)] = TrashedNoteMetadata(
                originalPath: originalFile.standardizedFileURL.path,
                deletedAt: deletionDate
            )
        }
        storeTrashedNotesMetadata(metadata)
        removePreferredDirectory(originalDirectory)
        forgetRecentPathPrefix(originalDirectory)
        removeLibraryPinnedNotePaths(in: originalDirectory)
        removeLibraryFolderDisclosurePaths(in: originalDirectory)
        removeLibraryFolderIconNames(in: originalDirectory)
        invalidateSearchIndexContents()
        return (trashedDirectory, originalFiles)
    }

    public func trashDirectory() -> URL {
        appSupportDirectory.appendingPathComponent("Trash", isDirectory: true)
    }

    public func listTrashedNotes(limit: Int = 200) -> [NoteSearchResult] {
        let metadata = storedTrashedNotesMetadata()
        var notes: [NoteSearchResult] = []

        for fileURL in markdownFiles(in: trashDirectory()) {
            let key = metadataKey(for: fileURL)
            let note = (try? loadNote(at: fileURL)) ?? (
                title: fileURL.deletingPathExtension().lastPathComponent,
                body: "",
                tags: []
            )
            let modifiedAt = metadata[key]?.deletedAt ?? fileModificationDate(for: fileURL) ?? Date()
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

    public func restoreTrashedNote(at url: URL) throws -> URL {
        let standardizedTrashURL = url.standardizedFileURL
        var metadata = storedTrashedNotesMetadata()
        let metadataKey = metadataKey(for: standardizedTrashURL)
        let originalURL = metadata[metadataKey]
            .map { URL(fileURLWithPath: $0.originalPath) }
            ?? notesDirectory.appendingPathComponent(standardizedTrashURL.lastPathComponent)
        let restoreDirectory = originalURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: restoreDirectory, withIntermediateDirectories: true)

        let restoredURL = uniqueRestoredURL(for: originalURL)
        try fileManager.moveItem(at: standardizedTrashURL, to: restoredURL)
        metadata.removeValue(forKey: metadataKey)
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
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]

        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var results: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
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
        return (body, frontMatterTags(in: frontMatter))
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

    private func storedNoteContent(
        title: String,
        body: String,
        tags: [String],
        preservingFrontMatterFrom existingText: String? = nil
    ) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let updatedLines = updatingFrontMatterTags(frontMatter, tags: normalizedTags)
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

    private func frontMatterTags(in lines: [String]) -> [String] {
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

    private func updatingFrontMatterTags(_ lines: [String], tags: [String]) -> [String] {
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

    private func commitUpdatedNote(from sourceURL: URL, to destinationURL: URL, content: String) throws {
        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".mudsnote-update-\(UUID().uuidString).tmp")
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        try content.write(to: stagingURL, atomically: true, encoding: .utf8)
        try updateNoteCommitHook?(.afterStaging)
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        do {
            try updateNoteCommitHook?(.afterDestinationCommit)
            try fileManager.removeItem(at: sourceURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private func relocatingAttachmentsIfNeeded(
        in markdown: String,
        from sourceDirectory: URL,
        to destinationDirectory: URL
    ) throws -> NoteAttachmentRelocation {
        let sourceDirectory = sourceDirectory.standardizedFileURL
        let destinationDirectory = destinationDirectory.standardizedFileURL
        guard sourceDirectory != destinationDirectory else {
            return NoteAttachmentRelocation(markdown: markdown, copiedURLs: [])
        }

        let pattern = #"!?\[[^\]\n]*\]\((<[^>\n]+>|[^)\n]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return NoteAttachmentRelocation(markdown: markdown, copiedURLs: [])
        }
        let sourceAttachmentRoot = sourceDirectory
            .appendingPathComponent(Self.attachmentDirectoryName, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let destinationAttachmentRoot = destinationDirectory
            .appendingPathComponent(Self.attachmentDirectoryName, isDirectory: true)
            .standardizedFileURL
        let matches = expression.matches(
            in: markdown,
            range: NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        )
        var replacements: [(range: Range<String.Index>, value: String)] = []
        var destinationsBySourcePath: [String: URL] = [:]
        var copiedURLs: [URL] = []

        do {
            for match in matches {
                guard match.numberOfRanges > 1,
                      let capturedRange = Range(match.range(at: 1), in: markdown),
                      let target = markdownAttachmentTarget(in: String(markdown[capturedRange])),
                      let sourceURL = localAttachmentURL(
                        for: target.value,
                        relativeTo: sourceDirectory,
                        inside: sourceAttachmentRoot
                      ) else {
                    continue
                }

                let destinationURL: URL
                if let existing = destinationsBySourcePath[sourceURL.path] {
                    destinationURL = existing
                } else {
                    let relativePath = String(
                        sourceURL.path.dropFirst(sourceAttachmentRoot.path.count + 1)
                    )
                    let preferredURL = destinationAttachmentRoot
                        .appendingPathComponent(relativePath)
                    try fileManager.createDirectory(
                        at: preferredURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    destinationURL = uniqueAttachmentURL(preferredURL)
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    destinationsBySourcePath[sourceURL.path] = destinationURL
                    copiedURLs.append(destinationURL)
                }

                let relativePath = String(
                    destinationURL.path.dropFirst(destinationDirectory.path.count + 1)
                )
                let encodedPath = markdownEncodedPath(relativePath)
                let value = target.isAngleBracketed ? "<\(encodedPath)>" : encodedPath
                let replacementStart = markdown.index(
                    capturedRange.lowerBound,
                    offsetBy: target.replacementOffset
                )
                let replacementEnd = markdown.index(
                    replacementStart,
                    offsetBy: target.replacementLength
                )
                replacements.append((replacementStart..<replacementEnd, value))
            }
        } catch {
            removeRelocatedAttachments(copiedURLs, inside: destinationDirectory)
            throw error
        }

        var relocatedMarkdown = markdown
        for replacement in replacements.reversed() {
            relocatedMarkdown.replaceSubrange(replacement.range, with: replacement.value)
        }
        return NoteAttachmentRelocation(markdown: relocatedMarkdown, copiedURLs: copiedURLs)
    }

    private func markdownAttachmentTarget(
        in capturedValue: String
    ) -> (value: String, replacementOffset: Int, replacementLength: Int, isAngleBracketed: Bool)? {
        let leadingWhitespace = capturedValue.prefix { $0.isWhitespace }.count
        let trimmedLeading = String(capturedValue.dropFirst(leadingWhitespace))
        if trimmedLeading.hasPrefix("<"), let closing = trimmedLeading.firstIndex(of: ">") {
            let value = String(trimmedLeading[trimmedLeading.index(after: trimmedLeading.startIndex)..<closing])
            return (value, leadingWhitespace, value.count + 2, true)
        }

        let trimmed = trimmedLeading.trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePattern = #"\s+["'][^"']*["']\s*$"#
        let target: String
        if let titleRange = trimmed.range(of: titlePattern, options: .regularExpression) {
            target = String(trimmed[..<titleRange.lowerBound])
        } else {
            target = trimmed
        }
        guard !target.isEmpty else { return nil }
        return (target, leadingWhitespace, target.count, false)
    }

    private func localAttachmentURL(
        for rawTarget: String,
        relativeTo sourceDirectory: URL,
        inside sourceAttachmentRoot: URL
    ) -> URL? {
        var target = rawTarget
        if let fragment = target.firstIndex(of: "#") {
            target = String(target[..<fragment])
        }
        if let query = target.firstIndex(of: "?") {
            target = String(target[..<query])
        }
        target = target.removingPercentEncoding ?? target
        guard !target.isEmpty,
              !target.hasPrefix("/"),
              !target.hasPrefix("~/"),
              URL(string: target)?.scheme == nil else {
            return nil
        }

        let resolved = sourceDirectory
            .appendingPathComponent(target)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(sourceAttachmentRoot.path + "/"),
              fileManager.fileExists(atPath: resolved.path),
              (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
            return nil
        }
        return resolved
    }

    private func uniqueAttachmentURL(_ preferredURL: URL) -> URL {
        guard fileManager.fileExists(atPath: preferredURL.path) else { return preferredURL }
        let pathExtension = preferredURL.pathExtension
        let stem = preferredURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let filename = pathExtension.isEmpty
                ? "\(stem)-\(index)"
                : "\(stem)-\(index).\(pathExtension)"
            let candidate = preferredURL.deletingLastPathComponent().appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func markdownEncodedPath(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private func removeRelocatedAttachments(_ urls: [URL], inside destinationDirectory: URL) {
        let attachmentRoot = destinationDirectory
            .appendingPathComponent(Self.attachmentDirectoryName, isDirectory: true)
            .standardizedFileURL
        for url in urls.reversed() {
            try? fileManager.removeItem(at: url)
            var directory = url.deletingLastPathComponent()
            while directory.path.hasPrefix(attachmentRoot.path),
                  directory != destinationDirectory {
                guard let contents = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                ), contents.isEmpty else {
                    break
                }
                try? fileManager.removeItem(at: directory)
                if directory == attachmentRoot { break }
                directory.deleteLastPathComponent()
            }
        }
    }

    private func uniqueFileURL(for title: String, in directory: URL) -> URL {
        let base = filenameStem(for: title)
        return uniqueURL(directory: directory, baseName: base, excluding: nil)
    }

    private func uniqueUpdatedFileURL(for title: String, currentURL: URL, in directory: URL) -> URL {
        let base = filenameStem(for: title)
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

        let slug = String(allowed)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

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
        guard stem.range(of: #"^\d{4}-\d{2}-\d{2}-"#, options: .regularExpression) != nil else {
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
