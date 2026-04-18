import Foundation

public struct NoteFile: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let modifiedAt: Date

    public init(url: URL, title: String, modifiedAt: Date) {
        self.url = url
        self.title = title
        self.modifiedAt = modifiedAt
    }
}

public struct NoteSearchResult: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let snippet: String
    public let modifiedAt: Date
    public let tags: [String]

    public init(url: URL, title: String, snippet: String, modifiedAt: Date, tags: [String] = []) {
        self.url = url
        self.title = title
        self.snippet = snippet
        self.modifiedAt = modifiedAt
        self.tags = tags
    }
}

public struct DraftSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let sourcePath: String?
    public let selectedDirectoryPath: String
    public let title: String
    public let body: String
    public let tags: [String]
    public let updatedAt: Date

    public init(
        id: String,
        sourcePath: String?,
        selectedDirectoryPath: String,
        title: String,
        body: String,
        tags: [String] = [],
        updatedAt: Date
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.selectedDirectoryPath = selectedDirectoryPath
        self.title = title
        self.body = body
        self.tags = tags
        self.updatedAt = updatedAt
    }
}

public struct StoredWindowOrigin: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct StoredWindowFrame: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MarkdownEditorDocument: Equatable, Sendable {
    public let title: String
    public let body: String
    public let tags: [String]

    public init(title: String, body: String, tags: [String] = []) {
        self.title = title
        self.body = body
        self.tags = tags
    }

    public var editorText: String {
        Self.composeEditorText(title: title, body: body)
    }

    public static func composeEditorText(title: String, body: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle.isEmpty {
            return trimmedBody
        }

        if trimmedBody.isEmpty {
            return "# \(trimmedTitle)"
        }

        return "# \(trimmedTitle)\n\n\(trimmedBody)"
    }

    public static func parse(editorText: String, tags: [String] = []) -> MarkdownEditorDocument {
        let normalized = editorText.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return MarkdownEditorDocument(title: "", body: "", tags: normalizedTags(tags))
        }

        let lines = normalized.components(separatedBy: "\n")
        guard let firstContentIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return MarkdownEditorDocument(title: "", body: "", tags: normalizedTags(tags))
        }

        let firstLine = lines[firstContentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let title = extractedTitle(from: firstLine)
        let remainingLines = Array(lines.dropFirst(firstContentIndex + 1))
        let body = remainingLines
            .drop { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return MarkdownEditorDocument(title: title, body: body, tags: normalizedTags(tags))
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private static func extractedTitle(from line: String) -> String {
        let headingPattern = #"^#{1,6}\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: headingPattern) {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges > 1 {
                return nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class NoteStore: @unchecked Sendable {
    public static let minimumPanelOpacity = 0.62
    public static let maximumPanelOpacity = 0.96
    public static let defaultPanelOpacity = 0.78

    private enum DefaultsKey {
        static let hotKey = "mudsnote.hotkey"
        static let floatingHotKey = "mudsnote.floatingHotKey"
        static let saveShortcut = "mudsnote.saveShortcut"
        static let notesDirectory = "mudsnote.notesDirectory"
        static let extraDirectories = "mudsnote.extraDirectories"
        static let panelOpacity = "mudsnote.panelOpacity"
        static let recentFiles = "mudsnote.recentFiles"
        static let quickCaptureFrameX = "mudsnote.quickCaptureFrameX"
        static let quickCaptureFrameY = "mudsnote.quickCaptureFrameY"
        static let quickCaptureFrameWidth = "mudsnote.quickCaptureFrameWidth"
        static let quickCaptureFrameHeight = "mudsnote.quickCaptureFrameHeight"
        static let floatingFrameX = "mudsnote.floatingFrameX"
        static let floatingFrameY = "mudsnote.floatingFrameY"
        static let floatingFrameWidth = "mudsnote.floatingFrameWidth"
        static let floatingFrameHeight = "mudsnote.floatingFrameHeight"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let appSupportDirectory: URL

    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        appSupportDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.appSupportDirectory = appSupportDirectory ?? Self.defaultAppSupportDirectory(fileManager: fileManager)
    }

    public var notesDirectory: URL {
        get {
            if let raw = defaults.string(forKey: DefaultsKey.notesDirectory), !raw.isEmpty {
                return URL(fileURLWithPath: raw, isDirectory: true)
            }
            return Self.defaultNotesDirectory(fileManager: fileManager)
        }
        set {
            defaults.set(newValue.path, forKey: DefaultsKey.notesDirectory)
        }
    }

    public var hotKeyString: String {
        get {
            defaults.string(forKey: DefaultsKey.hotKey) ?? "option+shift+n"
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.hotKey)
        }
    }

    public var floatingNoteHotKeyString: String {
        get {
            defaults.string(forKey: DefaultsKey.floatingHotKey) ?? "option+r"
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.floatingHotKey)
        }
    }

    public var saveShortcutString: String {
        get {
            defaults.string(forKey: DefaultsKey.saveShortcut) ?? "command+return"
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.saveShortcut)
        }
    }

    public var preferredDirectories: [URL] {
        deduplicatedDirectories([notesDirectory] + storedExtraDirectories())
    }

    public var panelOpacity: Double {
        get {
            let stored = defaults.object(forKey: DefaultsKey.panelOpacity) as? Double
            return min(max(stored ?? Self.defaultPanelOpacity, Self.minimumPanelOpacity), Self.maximumPanelOpacity)
        }
        set {
            defaults.set(min(max(newValue, Self.minimumPanelOpacity), Self.maximumPanelOpacity), forKey: DefaultsKey.panelOpacity)
        }
    }

    public var quickCaptureWindowFrame: StoredWindowFrame? {
        get {
            guard defaults.object(forKey: DefaultsKey.quickCaptureFrameX) != nil,
                  defaults.object(forKey: DefaultsKey.quickCaptureFrameY) != nil,
                  defaults.object(forKey: DefaultsKey.quickCaptureFrameWidth) != nil,
                  defaults.object(forKey: DefaultsKey.quickCaptureFrameHeight) != nil else {
                return nil
            }

            let x = defaults.double(forKey: DefaultsKey.quickCaptureFrameX)
            let y = defaults.double(forKey: DefaultsKey.quickCaptureFrameY)
            let width = defaults.double(forKey: DefaultsKey.quickCaptureFrameWidth)
            let height = defaults.double(forKey: DefaultsKey.quickCaptureFrameHeight)
            return StoredWindowFrame(x: x, y: y, width: width, height: height)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: DefaultsKey.quickCaptureFrameX)
                defaults.removeObject(forKey: DefaultsKey.quickCaptureFrameY)
                defaults.removeObject(forKey: DefaultsKey.quickCaptureFrameWidth)
                defaults.removeObject(forKey: DefaultsKey.quickCaptureFrameHeight)
                return
            }

            defaults.set(newValue.x, forKey: DefaultsKey.quickCaptureFrameX)
            defaults.set(newValue.y, forKey: DefaultsKey.quickCaptureFrameY)
            defaults.set(newValue.width, forKey: DefaultsKey.quickCaptureFrameWidth)
            defaults.set(newValue.height, forKey: DefaultsKey.quickCaptureFrameHeight)
        }
    }

    public var floatingNoteWindowFrame: StoredWindowFrame? {
        get {
            guard defaults.object(forKey: DefaultsKey.floatingFrameX) != nil,
                  defaults.object(forKey: DefaultsKey.floatingFrameY) != nil,
                  defaults.object(forKey: DefaultsKey.floatingFrameWidth) != nil,
                  defaults.object(forKey: DefaultsKey.floatingFrameHeight) != nil else {
                return nil
            }

            let x = defaults.double(forKey: DefaultsKey.floatingFrameX)
            let y = defaults.double(forKey: DefaultsKey.floatingFrameY)
            let width = defaults.double(forKey: DefaultsKey.floatingFrameWidth)
            let height = defaults.double(forKey: DefaultsKey.floatingFrameHeight)
            return StoredWindowFrame(x: x, y: y, width: width, height: height)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: DefaultsKey.floatingFrameX)
                defaults.removeObject(forKey: DefaultsKey.floatingFrameY)
                defaults.removeObject(forKey: DefaultsKey.floatingFrameWidth)
                defaults.removeObject(forKey: DefaultsKey.floatingFrameHeight)
                return
            }

            defaults.set(newValue.x, forKey: DefaultsKey.floatingFrameX)
            defaults.set(newValue.y, forKey: DefaultsKey.floatingFrameY)
            defaults.set(newValue.width, forKey: DefaultsKey.floatingFrameWidth)
            defaults.set(newValue.height, forKey: DefaultsKey.floatingFrameHeight)
        }
    }

    public var quickCaptureWindowOrigin: StoredWindowOrigin? {
        get {
            guard let frame = quickCaptureWindowFrame else { return nil }
            return StoredWindowOrigin(x: frame.x, y: frame.y)
        }
        set {
            guard let newValue else {
                quickCaptureWindowFrame = nil
                return
            }

            let current = quickCaptureWindowFrame
            quickCaptureWindowFrame = StoredWindowFrame(
                x: newValue.x,
                y: newValue.y,
                width: current?.width ?? 412,
                height: current?.height ?? 314
            )
        }
    }

    public func ensureNotesDirectory() throws {
        try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }

    public func configurePreferredDirectories(_ directories: [URL], defaultDirectory: URL) {
        let normalizedDefault = defaultDirectory.standardizedFileURL
        notesDirectory = normalizedDefault

        let extras = deduplicatedDirectories(directories)
            .filter { $0.standardizedFileURL.path != normalizedDefault.path }
            .map(\.path)
        defaults.set(extras, forKey: DefaultsKey.extraDirectories)
    }

    public func addPreferredDirectory(_ directory: URL) {
        configurePreferredDirectories(preferredDirectories + [directory], defaultDirectory: notesDirectory)
    }

    public func listRecentFiles(limit: Int = 8) -> [NoteFile] {
        let recentPaths = (defaults.array(forKey: DefaultsKey.recentFiles) as? [String]) ?? []

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

    public func knownSearchRoots() -> [URL] {
        let recentDirectories = listRecentFiles(limit: 50).map { $0.url.deletingLastPathComponent() }
        return deduplicatedDirectories(preferredDirectories + recentDirectories)
    }

    public func knownTags(limit: Int = 200) -> [String] {
        let roots = knownSearchRoots()
        var counts: [String: Int] = [:]

        for root in roots {
            for fileURL in markdownFiles(in: root) {
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                for tag in parseStoredDocument(text).tags {
                    counts[tag, default: 0] += 1
                }
            }
        }

        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(limit)
            .map(\.key)
    }

    public func searchNotes(query: String, limit: Int = 30, roots: [URL]? = nil) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return listRecentFiles(limit: limit).map { note in
                let snippet = (try? loadNote(at: note.url).body).flatMap(firstMeaningfulLine(from:)) ?? ""
                let tags = (try? loadNote(at: note.url).tags) ?? []
                return NoteSearchResult(url: note.url, title: note.title, snippet: snippet, modifiedAt: note.modifiedAt, tags: tags)
            }
        }

        let loweredQuery = trimmedQuery.lowercased()
        let searchRoots = roots ?? knownSearchRoots()
        var seenPaths = Set<String>()
        var scoredResults: [(result: NoteSearchResult, score: Int)] = []

        for root in searchRoots {
            for fileURL in markdownFiles(in: root) {
                let standardizedPath = fileURL.standardizedFileURL.path
                guard seenPaths.insert(standardizedPath).inserted else { continue }
                guard let scored = scoredMatch(for: fileURL, loweredQuery: loweredQuery) else { continue }
                scoredResults.append(scored)
            }
        }

        return scoredResults
            .sorted {
                if $0.score == $1.score {
                    return $0.result.modifiedAt > $1.result.modifiedAt
                }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map(\.result)
    }

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

    public static func defaultNotesDirectory(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("Mudsnote", isDirectory: true)
    }

    public static func defaultAppSupportDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Mudsnote", isDirectory: true)
    }

    private func draftsDirectory() -> URL {
        appSupportDirectory.appendingPathComponent("Drafts", isDirectory: true)
    }

    private func storedExtraDirectories() -> [URL] {
        ((defaults.array(forKey: DefaultsKey.extraDirectories) as? [String]) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }

    private func deduplicatedDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for directory in directories {
            let standardized = directory.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                result.append(standardized)
            }
        }

        return result
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

    private func scoredMatch(for fileURL: URL, loweredQuery: String) -> (result: NoteSearchResult, score: Int)? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modifiedAt = attrs[.modificationDate] as? Date,
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let note = (try? loadNote(at: fileURL)) ?? (
            title: fileURL.deletingPathExtension().lastPathComponent,
            body: text,
            tags: []
        )

        let titleLower = note.title.lowercased()
        let bodyLower = note.body.lowercased()
        let tagsLower = note.tags.map { $0.lowercased() }
        guard titleLower.contains(loweredQuery) || bodyLower.contains(loweredQuery) || tagsLower.contains(where: { $0.contains(loweredQuery) }) else {
            return nil
        }

        let titleScore = titleLower.contains(loweredQuery) ? 100 : 0
        let occurrences = max(bodyLower.components(separatedBy: loweredQuery).count - 1, 0)
        let bodyScore = min(occurrences * 15, 90)
        let tagScore = tagsLower.contains(where: { $0 == loweredQuery }) ? 80 : (tagsLower.contains(where: { $0.contains(loweredQuery) }) ? 40 : 0)
        let snippet = snippet(from: note.body, query: loweredQuery)

        return (
            result: NoteSearchResult(
                url: fileURL,
                title: note.title,
                snippet: snippet,
                modifiedAt: modifiedAt,
                tags: note.tags
            ),
            score: titleScore + bodyScore + tagScore
        )
    }

    private func markdownFiles(in root: URL) -> [URL] {
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
        var items = (defaults.array(forKey: DefaultsKey.recentFiles) as? [String]) ?? []
        items.removeAll { $0 == url.path }
        items.insert(url.path, at: 0)
        defaults.set(Array(items.prefix(40)), forKey: DefaultsKey.recentFiles)
    }

    private func snippet(from body: String, query: String) -> String {
        let lines = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let match = lines.first(where: { $0.lowercased().contains(query) }) {
            return match
        }

        return lines.first ?? ""
    }

    private func firstMeaningfulLine(from body: String) -> String? {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func parseStoredDocument(_ text: String) -> (body: String, tags: [String]) {
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
