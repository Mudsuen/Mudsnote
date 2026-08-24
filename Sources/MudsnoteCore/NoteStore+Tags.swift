import Foundation

public enum NoteTagMutationError: LocalizedError {
    case invalidTag
    case tagNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidTag:
            return "标签无效"
        case .tagNotFound:
            return "未找到该标签"
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
        var backups: [(url: URL, contents: String)] = []

        do {
            for file in preview.files {
                let source = try String(contentsOf: file.url, encoding: .utf8)
                let migration = inlineTagSourceMigration(from: source)
                guard migration.occurrenceCount > 0 else { continue }
                guard try String(contentsOf: file.url, encoding: .utf8) == source else {
                    throw CocoaError(.fileWriteFileExists)
                }

                backups.append((file.url, source))
                try migration.source.write(
                    to: file.url,
                    atomically: true,
                    encoding: .utf8
                )
            }
        } catch {
            for backup in backups.reversed() {
                try? backup.contents.write(
                    to: backup.url,
                    atomically: true,
                    encoding: .utf8
                )
            }
            markSearchIndexDirty(at: backups.map(\.url))
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
    public func deleteTag(_ input: String) throws -> Int {
        let tag = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !tag.isEmpty else { throw NoteTagMutationError.invalidTag }

        let urls = listNotesRefreshingIndex(limit: .max).map(\.url)
        var backups: [(url: URL, contents: String)] = []
        var changedURLs: [URL] = []

        do {
            for url in urls {
                let document = try loadNoteDocument(at: url)
                let tags = document.tags.filter {
                    $0.localizedCaseInsensitiveCompare(tag) != .orderedSame
                }
                guard tags != document.tags else { continue }

                backups.append((url, document.sourceContents))
                _ = try updateNoteInPlace(
                    at: url,
                    title: document.title,
                    body: document.body,
                    tags: tags
                )
                changedURLs.append(url)
            }
        } catch {
            for backup in backups.reversed() {
                try? backup.contents.write(to: backup.url, atomically: true, encoding: .utf8)
            }
            markSearchIndexDirty(at: backups.map(\.url))
            throw error
        }

        guard !changedURLs.isEmpty else { throw NoteTagMutationError.tagNotFound }
        markSearchIndexDirty(at: changedURLs)
        return changedURLs.count
    }
}
