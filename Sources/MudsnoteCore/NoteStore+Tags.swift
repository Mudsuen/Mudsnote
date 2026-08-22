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

extension NoteStore {
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
