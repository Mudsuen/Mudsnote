import Foundation

extension NoteStore {
    public func saveDraft(_ snapshot: DraftSnapshot) throws {
        let directory = draftsDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        try data.write(to: draftFileURL(for: snapshot.id), options: .atomic)
    }

    public func loadDraft(id: String) -> DraftSnapshot? {
        let url = draftFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(DraftSnapshot.self, from: data)
    }

    public func deleteDraft(id: String) {
        try? fileManager.removeItem(at: draftFileURL(for: id))
    }

    private func draftsDirectory() -> URL {
        appSupportDirectory.appendingPathComponent("Drafts", isDirectory: true)
    }

    private func draftFileURL(for id: String) -> URL {
        let safeName = id.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        return draftsDirectory().appendingPathComponent(String(safeName) + ".json")
    }
}
