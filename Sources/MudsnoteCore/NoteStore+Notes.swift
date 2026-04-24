import Foundation

extension NoteStore {
    public func listRecentFiles(limit: Int = 8) -> [NoteFile] {
        let recentPaths = (defaults.array(forKey: NoteStoreDefaultsKey.recentFiles) as? [String]) ?? []

        return recentPaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: url.path),
                  let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let modifiedAt = attrs[.modificationDate] as? Date else {
                return nil
            }

            let title = (try? loadNote(at: url).title) ?? url.deletingPathExtension().lastPathComponent
            return NoteFile(url: url, title: title, modifiedAt: modifiedAt)
        }
        .prefix(limit)
        .map { $0 }
    }

    public func loadNote(at url: URL) throws -> (title: String, body: String, tags: [String]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = parseStoredDocument(text)
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

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        return (fallbackTitle, parsed.body.trimmingCharacters(in: .whitespacesAndNewlines), parsed.tags)
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
        rememberRecentFile(desiredURL)
        return desiredURL
    }

    func markdownFiles(in root: URL) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]

        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var results: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else {
                continue
            }

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

    private func rememberRecentFile(_ url: URL) {
        var items = (defaults.array(forKey: NoteStoreDefaultsKey.recentFiles) as? [String]) ?? []
        items.removeAll { $0 == url.path }
        items.insert(url.path, at: 0)
        defaults.set(Array(items.prefix(40)), forKey: NoteStoreDefaultsKey.recentFiles)
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
