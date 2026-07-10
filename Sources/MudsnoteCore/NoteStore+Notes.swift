import Foundation

private struct TrashedNoteMetadata: Codable {
    let originalPath: String
    let deletedAt: Date
}

extension NoteStore {
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
        return fileURL
    }

    public func updateNote(at url: URL, title: String, body: String, tags: [String] = [], in directory: URL? = nil) throws -> URL {
        let currentDirectory = url.deletingLastPathComponent()
        let targetDirectory = directory ?? currentDirectory
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let desiredURL = uniqueUpdatedFileURL(for: title, currentURL: url, in: targetDirectory)
        if desiredURL != url {
            try fileManager.moveItem(at: url, to: desiredURL)
        }

        try writeNote(to: desiredURL, title: title, body: body, tags: tags)
        rememberRecentFile(desiredURL, replacing: desiredURL == url ? nil : url)
        if desiredURL.standardizedFileURL != url.standardizedFileURL {
            replaceLibraryPinnedNotePath(url, with: desiredURL)
        }
        return desiredURL
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
        try fileManager.moveItem(at: sourceURL, to: movedURL)
        rememberRecentFile(movedURL, replacing: sourceURL)
        replaceLibraryPinnedNotePath(sourceURL, with: movedURL)
        return movedURL
    }

    public func trashFolder(at directory: URL) throws -> URL {
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
        return trashedDirectory
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
        var tags: [String] = []
        var inTags = false

        for line in frontMatter {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "tags:" {
                inTags = true
                continue
            }

            if inTags, trimmed.hasPrefix("- ") {
                tags.append(String(trimmed.dropFirst(2)))
                continue
            }

            if !trimmed.isEmpty {
                inTags = false
            }
        }

        return (body, MarkdownEditorDocument.normalizedTags(tags))
    }

    private func writeNote(to url: URL, title: String, body: String, tags: [String] = []) throws {
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

        let storedContent: String
        if normalizedTags.isEmpty {
            storedContent = content
        } else {
            let tagLines = normalizedTags.map { "- \($0)" }.joined(separator: "\n")
            storedContent = "---\ntags:\n\(tagLines)\n---\n\n\(content)"
        }

        try storedContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private func uniqueFileURL(for title: String, in directory: URL) -> URL {
        let base = filenameStem(for: title)
        return uniqueURL(directory: directory, baseName: base, excluding: nil)
    }

    private func uniqueUpdatedFileURL(for title: String, currentURL: URL, in directory: URL) -> URL {
        let base = filenameStem(for: title)
        let excludedURL = currentURL.deletingLastPathComponent() == directory ? currentURL : nil
        return uniqueURL(directory: directory, baseName: base, excluding: excludedURL)
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

    private func uniqueURLPreservingExtension(directory: URL, filenameStem: String, pathExtension: String) -> URL {
        let ext = pathExtension.isEmpty ? "md" : pathExtension
        var candidate = directory.appendingPathComponent(filenameStem).appendingPathExtension(ext)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
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
