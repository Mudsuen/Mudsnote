import Foundation

public enum NoteTagMutationError: LocalizedError {
    case invalidTag
    case tagNotFound
    case partialMutation(completed: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidTag:
            return "标签无效"
        case .tagNotFound:
            return "未找到该标签"
        case let .partialMutation(completed, reason):
            return "已更新 \(completed) 篇笔记，其余未完成：\(reason)"
        }
    }
}

public struct InlineTagFileMigration: Equatable, Sendable {
    public let url: URL
    public let occurrenceCount: Int
    public let tags: [String]
}

public struct InlineTagLibraryMigration: Equatable, Sendable {
    public let files: [InlineTagFileMigration]

    public var fileCount: Int { files.count }
    public var occurrenceCount: Int {
        files.reduce(0) { $0 + $1.occurrenceCount }
    }
}

extension NoteStore {
    public func inlineTagMigrationPreview(
        in roots: [URL]
    ) throws -> InlineTagLibraryMigration {
        var seenPaths = Set<String>()
        let files = roots.flatMap(markdownFiles(in:))
            .map(\.standardizedFileURL)
            .filter { seenPaths.insert($0.path).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let migrations = try files.compactMap { url -> InlineTagFileMigration? in
            let source = try String(contentsOf: url, encoding: .utf8)
            let migration = inlineTagSourceMigration(from: source)
            guard migration.occurrenceCount > 0 else { return nil }
            return InlineTagFileMigration(
                url: url,
                occurrenceCount: migration.occurrenceCount,
                tags: migration.extractedTags
            )
        }
        return InlineTagLibraryMigration(files: migrations)
    }

    @discardableResult
    public func migrateInlineTags(
        in roots: [URL]
    ) throws -> InlineTagLibraryMigration {
        let preview = try inlineTagMigrationPreview(in: roots)
        var committedURLs: [URL] = []

        do {
            for file in preview.files {
                let source = try String(contentsOf: file.url, encoding: .utf8)
                let migration = inlineTagSourceMigration(from: source)
                guard migration.occurrenceCount > 0 else { continue }
                try replaceTagMutationContents(at: file.url, expected: source, replacement: migration.source)
                committedURLs.append(file.url)
            }
        } catch {
            markSearchIndexDirty(at: committedURLs)
            if !committedURLs.isEmpty {
                throw NoteTagMutationError.partialMutation(completed: committedURLs.count, reason: error.localizedDescription)
            }
            throw error
        }

        markSearchIndexDirty(at: preview.files.map(\.url))
        return preview
    }

    private func inlineTagSourceMigration(
        from source: String
    ) -> (
        source: String,
        extractedTags: [String],
        occurrenceCount: Int
    ) {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        if normalized.hasPrefix("---\n"),
           let closingIndex = lines.dropFirst().firstIndex(of: "---") {
            let frontMatter = Array(lines[1..<closingIndex])
            let body = Array(lines[(closingIndex + 1)...]).joined(separator: "\n")
            let migration = MarkdownEditorDocument.extractingInlineTags(from: body)
            guard migration.occurrenceCount > 0 else {
                return (source, [], 0)
            }
            let tags = MarkdownEditorDocument.normalizedTags(
                frontMatterTags(in: frontMatter) + migration.tags
            )
            let updatedFrontMatter = updatingFrontMatterTags(
                frontMatter,
                tags: tags
            )
            return (
                "---\n\(updatedFrontMatter.joined(separator: "\n"))\n---\n\(migration.body)",
                migration.tags,
                migration.occurrenceCount
            )
        }

        let migration = MarkdownEditorDocument.extractingInlineTags(from: normalized)
        guard migration.occurrenceCount > 0 else {
            return (source, [], 0)
        }
        let tagLines = migration.tags.map { "  - \($0)" }.joined(separator: "\n")
        return (
            "---\ntags:\n\(tagLines)\n---\n\n\(migration.body)",
            migration.tags,
            migration.occurrenceCount
        )
    }

    @discardableResult
    public func deleteTag(_ input: String, roots: [URL]? = nil, additionalNoteURLs: [URL] = []) throws -> Int {
        try replaceTag(input, with: nil, roots: roots, additionalNoteURLs: additionalNoteURLs)
    }

    public func renameTag(_ input: String, to newName: String, roots: [URL]? = nil, additionalNoteURLs: [URL] = []) throws -> Int {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !name.isEmpty, !name.contains("\n"), !name.contains("\r") else {
            throw NoteTagMutationError.invalidTag
        }
        return try replaceTag(input, with: name, roots: roots, additionalNoteURLs: additionalNoteURLs)
    }

    private func replaceTag(_ input: String, with replacement: String?, roots: [URL]?, additionalNoteURLs: [URL]) throws -> Int {
        let tag = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !tag.isEmpty else { throw NoteTagMutationError.invalidTag }

        let matches = listNotesRefreshingIndex(limit: .max, roots: roots).filter { note in
            note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }.map(\.url)
        let urls = Set((matches + additionalNoteURLs).map(\.standardizedFileURL))
        var committedURLs: [URL] = []
        var changedURLs: [URL] = []

        do {
            for url in urls.sorted(by: { $0.path < $1.path }) {
                let document = try loadNoteDocument(at: url)
                let tags = MarkdownEditorDocument.normalizedTags(document.tags.compactMap { existing in
                    existing.localizedCaseInsensitiveCompare(tag) == .orderedSame ? replacement : existing
                })
                guard tags != document.tags else { continue }

                let written = storedNoteContent(title: document.title, body: document.body,
                    tags: tags, preservingFrontMatterFrom: document.sourceContents)
                try replaceTagMutationContents(at: url, expected: document.sourceContents, replacement: written)
                committedURLs.append(url)
                changedURLs.append(url)
            }
        } catch {
            markSearchIndexDirty(at: committedURLs)
            if !committedURLs.isEmpty {
                throw NoteTagMutationError.partialMutation(completed: committedURLs.count, reason: error.localizedDescription)
            }
            throw error
        }

        guard !changedURLs.isEmpty else { throw NoteTagMutationError.tagNotFound }
        markSearchIndexDirty(at: changedURLs)
        return changedURLs.count
    }
    func replaceTagMutationContents(at url: URL, expected: String, replacement: String) throws {
        noteMutationLock.lock()
        defer { noteMutationLock.unlock() }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
            do {
                guard try String(contentsOf: coordinated, encoding: .utf8) == expected else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
                }
                try replacement.write(to: coordinated, atomically: true, encoding: .utf8)
            } catch { writeError = error }
        }
        if let error = coordinationError ?? (writeError as NSError?) { throw error }
    }


}
