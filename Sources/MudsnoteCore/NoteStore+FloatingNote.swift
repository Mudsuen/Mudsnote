import Foundation

extension NoteStore {
    /// The hotkey's primary floating note is a real Markdown document, so the
    /// library and floating editor share one source of truth across launches.
    public var primaryFloatingNoteURL: URL? {
        get {
            defaults.string(forKey: "mudsnote.primaryFloatingNotePath")
                .map { URL(fileURLWithPath: $0).standardizedFileURL }
        }
        set { defaults.set(newValue?.standardizedFileURL.path, forKey: "mudsnote.primaryFloatingNotePath") }
    }

    func replacePrimaryFloatingNotePath(_ oldURL: URL, with newURL: URL) {
        guard let current = primaryFloatingNoteURL else { return }
        let oldPath = oldURL.standardizedFileURL.path
        let path = current.standardizedFileURL.path
        guard path == oldPath || path.hasPrefix(oldPath + "/") else { return }
        primaryFloatingNoteURL = URL(fileURLWithPath:
            newURL.standardizedFileURL.path + String(path.dropFirst(oldPath.count)))
    }

    public func preparePrimaryFloatingNote() throws -> URL {
        if let draft = loadDraft(id: "floating-note"),
           !draft.title.isEmpty || !draft.body.isEmpty || !draft.tags.isEmpty {
            // A checkpoint makes retrying an interrupted conversion idempotent.
            // Never overwrite a document that diverged from the recoverable draft.
            let candidate = draft.sourcePath.map { URL(fileURLWithPath: $0) } ?? primaryFloatingNoteURL
            let existing = candidate.flatMap { try? loadNoteDocument(at: $0) }
            let url: URL
            if let candidate, let existing,
               existing.title == draft.title, existing.body == draft.body,
               existing.tags == draft.tags {
                url = candidate
            } else {
                url = try saveNewNote(title: draft.title, body: draft.body, tags: draft.tags,
                    in: URL(fileURLWithPath: draft.selectedDirectoryPath, isDirectory: true))
            }
            try saveDraft(DraftSnapshot(id: draft.id, sourcePath: url.path,
                selectedDirectoryPath: url.deletingLastPathComponent().path,
                title: draft.title, body: draft.body, tags: draft.tags, updatedAt: draft.updatedAt))
            primaryFloatingNoteURL = url
            deleteDraft(id: draft.id)
            return url
        }
        if let url = primaryFloatingNoteURL, fileManager.fileExists(atPath: url.path) {
            // A read error must not silently replace the user's existing note.
            _ = try loadNoteDocument(at: url)
            return url
        }
        let url = try saveNewNote(title: "", body: "")
        primaryFloatingNoteURL = url
        return url
    }
}
