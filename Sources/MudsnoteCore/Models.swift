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
