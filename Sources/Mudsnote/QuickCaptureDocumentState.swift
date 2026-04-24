import Foundation
import MudsnoteCore

struct QuickCaptureDocumentState {
    let title: String
    let bodyMarkdown: String

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBody: String {
        bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var tags: [String] {
        Self.extractedInlineTags(from: normalizedBody)
    }

    var document: MarkdownEditorDocument {
        MarkdownEditorDocument(title: normalizedTitle, body: normalizedBody, tags: tags)
    }

    var hasMeaningfulContent: Bool {
        !normalizedTitle.isEmpty || !normalizedBody.isEmpty || !tags.isEmpty
    }

    static func extractedInlineTags(from text: String) -> [String] {
        let characters = Array(text)
        var tags: [String] = []
        var index = 0

        while index < characters.count {
            if characters[index] == "#",
               (index == 0 || characters[index - 1].isWhitespace) {
                var end = index + 1
                while end < characters.count, characters[end].isTagCharacter {
                    end += 1
                }
                if end > index + 1 {
                    tags.append(String(characters[(index + 1)..<end]))
                    index = end
                    continue
                }
            }
            index += 1
        }

        return MarkdownEditorDocument.normalizedTags(tags)
    }

    static func containsTag(_ tag: String, in bodyMarkdown: String) -> Bool {
        let normalized = MarkdownEditorDocument.normalizedTags([tag]).first?.lowercased()
        guard let normalized else { return false }
        return extractedInlineTags(from: bodyMarkdown).contains { $0.lowercased() == normalized }
    }

    static func toggledTag(_ tag: String, in bodyMarkdown: String) -> String {
        guard let normalizedTag = MarkdownEditorDocument.normalizedTags([tag]).first else {
            return bodyMarkdown
        }

        if containsTag(normalizedTag, in: bodyMarkdown) {
            return removingTag(normalizedTag, from: bodyMarkdown)
        }

        return appendingTag(normalizedTag, to: bodyMarkdown)
    }

    private static func appendingTag(_ tag: String, to bodyMarkdown: String) -> String {
        let trimmed = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "#\(tag)"
        }
        return trimmed + "\n#\(tag)"
    }

    private static func removingTag(_ tag: String, from bodyMarkdown: String) -> String {
        let pattern = "(^|\\s)#" + NSRegularExpression.escapedPattern(for: tag) + "(?=$|\\s)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return bodyMarkdown
        }

        let nsString = bodyMarkdown as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let replaced = regex.stringByReplacingMatches(
            in: bodyMarkdown,
            options: [],
            range: fullRange,
            withTemplate: "$1"
        )

        let collapsedSpaces = replaced.replacingOccurrences(
            of: #"(?m)[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        let collapsedLines = collapsedSpaces.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return collapsedLines.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
