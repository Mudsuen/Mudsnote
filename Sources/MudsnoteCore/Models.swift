import Foundation

public struct LoadedNoteDocument: Equatable, Sendable {
    public let title: String
    public let body: String
    public let tags: [String]
    public let sourceContents: String

    public init(title: String, body: String, tags: [String], sourceContents: String) {
        self.title = title
        self.body = body
        self.tags = tags
        self.sourceContents = sourceContents
    }
}

public struct LibraryLaunchNoteSnapshot: Equatable, Sendable {
    public let url: URL
    public let document: LoadedNoteDocument
    public let modifiedAt: Date
    public let createdAt: Date

    public init(
        url: URL,
        document: LoadedNoteDocument,
        modifiedAt: Date,
        createdAt: Date? = nil
    ) {
        self.url = url
        self.document = document
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt ?? modifiedAt
    }
}

public struct NoteUpdateResult: Equatable, Sendable {
    public let url: URL
    public let sourceContents: String
    public let conflictedOriginalURL: URL?

    public init(url: URL, sourceContents: String, conflictedOriginalURL: URL? = nil) {
        self.url = url
        self.sourceContents = sourceContents
        self.conflictedOriginalURL = conflictedOriginalURL
    }

    public var preservedConflict: Bool {
        conflictedOriginalURL != nil
    }
}

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
    public let createdAt: Date
    public let tags: [String]
    public let hasAttachments: Bool
    public let thumbnailURL: URL?

    public init(
        url: URL,
        title: String,
        snippet: String,
        modifiedAt: Date,
        createdAt: Date? = nil,
        tags: [String] = [],
        hasAttachments: Bool = false,
        thumbnailURL: URL? = nil
    ) {
        self.url = url
        self.title = title
        self.snippet = snippet
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt ?? modifiedAt
        self.tags = tags
        self.hasAttachments = hasAttachments
        self.thumbnailURL = thumbnailURL
    }
}

public enum NoteSearchFilter: String, CaseIterable, Sendable {
    case all
    case title
    case body
    case tags
    case attachments
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
    private static let previewListPrefixRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:#{1,6}\s+|[-*+]\s+(?:\[[ xX]\]\s*)?|\d+\.\s+|(?:\[\s?\]|【】)\s*)"#
    )
    private static let previewLinkRegex = try! NSRegularExpression(
        pattern: #"!?\[([^\]]*)\]\([^)]+\)"#
    )

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

    public static func wordCount(in text: String) -> Int {
        var count = 0
        var isInsideLatinWord = false

        for character in text {
            let isCJK = character.unicodeScalars.allSatisfy { scalar in
                let value = Int(scalar.value)
                return (0x3400...0x4DBF).contains(value)
                    || (0x4E00...0x9FFF).contains(value)
                    || (0x3040...0x30FF).contains(value)
                    || (0xAC00...0xD7AF).contains(value)
            }
            if isCJK {
                count += 1
                isInsideLatinWord = false
            } else if character.isLetter || character.isNumber {
                if !isInsideLatinWord {
                    count += 1
                    isInsideLatinWord = true
                }
            } else {
                isInsideLatinWord = false
            }
        }
        return count
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

    public static func containsAttachmentReference(in body: String) -> Bool {
        let loweredBody = body.lowercased()
        return loweredBody.contains("](attachments/")
            || loweredBody.contains("](./attachments/")
            || loweredBody.contains("](../attachments/")
            || loweredBody.contains("](/attachments/")
            || loweredBody.contains("![") && loweredBody.contains("(attachments/")
    }

    public static func firstPreviewLine(in body: String) -> String? {
        body.components(separatedBy: .newlines)
            .compactMap(previewText(fromMarkdownLine:))
            .first(where: { !$0.isEmpty })
    }

    public static func previewText(fromMarkdownLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else {
            return plainPreviewText(from: trimmed)
        }

        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cells.count >= 2 else { return trimmed }

        let isSeparator = cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
        guard !isSeparator else { return nil }
        return cells
            .compactMap(plainPreviewText(from:))
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    private static func plainPreviewText(from source: String) -> String? {
        var preview = source
        let fullRange = NSRange(location: 0, length: (preview as NSString).length)
        preview = previewListPrefixRegex.stringByReplacingMatches(
            in: preview,
            range: fullRange,
            withTemplate: ""
        )
        preview = previewLinkRegex.stringByReplacingMatches(
            in: preview,
            range: NSRange(location: 0, length: (preview as NSString).length),
            withTemplate: "$1"
        )
        for marker in ["**", "__", "~~", "`", "<u>", "</u>"] {
            preview = preview.replacingOccurrences(of: marker, with: "")
        }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func firstLocalImageURL(in body: String, relativeTo noteURL: URL) -> URL? {
        let pattern = #"!?\[[^\]]*\]\(([^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        let noteDirectory = noteURL.deletingLastPathComponent()
        let imageExtensions: Set<String> = ["apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"]

        for match in regex.matches(in: body, range: range) where match.numberOfRanges > 1 {
            var rawPath = nsBody.substring(with: match.range(at: 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>"))
            guard !rawPath.isEmpty,
                  !rawPath.localizedCaseInsensitiveContains("://") else { continue }

            if let fragmentIndex = rawPath.firstIndex(of: "#") {
                rawPath = String(rawPath[..<fragmentIndex])
            }
            if let queryIndex = rawPath.firstIndex(of: "?") {
                rawPath = String(rawPath[..<queryIndex])
            }

            let decodedPath = rawPath.removingPercentEncoding ?? rawPath
            let extensionName = (decodedPath as NSString).pathExtension.lowercased()
            guard imageExtensions.contains(extensionName) else { continue }

            if decodedPath.hasPrefix("/") {
                return URL(fileURLWithPath: decodedPath).standardizedFileURL
            }
            return noteDirectory.appendingPathComponent(decodedPath).standardizedFileURL
        }

        return nil
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    public static func inlineTags(in text: String) -> [String] {
        let characters = Array(text)
        var tags: [String] = []
        var index = 0

        while index < characters.count {
            if characters[index] == "#",
               (index == 0 || characters[index - 1].isWhitespace) {
                var end = index + 1
                while end < characters.count, characters[end].isMarkdownTagCharacter {
                    end += 1
                }
                while end > index + 1, characters[end - 1] == "/" {
                    end -= 1
                }
                if end > index + 1 {
                    tags.append(String(characters[(index + 1)..<end]))
                    index = end
                    continue
                }
            }
            index += 1
        }

        return normalizedTags(tags)
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

private extension Character {
    var isMarkdownTagCharacter: Bool {
        isLetter || isNumber || self == "_" || self == "-" || self == "/"
    }
}
