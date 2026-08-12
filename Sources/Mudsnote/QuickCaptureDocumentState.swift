import Foundation
import MudsnoteCore

struct QuickCaptureDocumentState {
    static let maximumDerivedTitleLength = 80

    let title: String
    let bodyMarkdown: String

    var normalizedTitle: String {
        Self.derivedTitle(from: normalizedBody)
    }

    var normalizedBody: String {
        Self.unifiedMarkdown(legacyTitle: title, bodyMarkdown: bodyMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func derivedTitle(from markdown: String) -> String {
        let firstContentLine = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let firstContentLine,
              let preview = MarkdownEditorDocument.previewText(fromMarkdownLine: firstContentLine) else {
            return ""
        }

        let normalized = preview
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "" }

        let terminators = Set<Character>([".", "?", "!", "。", "？", "！"])
        let closingPunctuation = Set<Character>(["\"", "'", "”", "’", "」", "』", "》", "】", ")", "）"])
        let characters = Array(normalized)
        var sentenceEnd = characters.endIndex
        if let terminatorIndex = characters.firstIndex(where: terminators.contains) {
            sentenceEnd = characters.index(after: terminatorIndex)
            while sentenceEnd < characters.endIndex,
                  terminators.contains(characters[sentenceEnd]) || closingPunctuation.contains(characters[sentenceEnd]) {
                sentenceEnd = characters.index(after: sentenceEnd)
            }
        }

        return String(characters[..<sentenceEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumDerivedTitleLength)
            .description
    }

    static func unifiedMarkdown(legacyTitle: String, bodyMarkdown: String) -> String {
        let normalizedLegacyTitle = legacyTitle
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalizedLegacyTitle.isEmpty else { return bodyMarkdown }

        let normalizedBody = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty else { return normalizedLegacyTitle }

        let derivedBodyTitle = derivedTitle(from: normalizedBody)
        if titlesMatch(normalizedLegacyTitle, derivedBodyTitle) {
            return bodyMarkdown
        }
        return normalizedLegacyTitle + "\n\n" + bodyMarkdown
    }

    private static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        func comparable(_ value: String) -> String {
            value
                .trimmingCharacters(in: CharacterSet(
                    charactersIn: " \t\r\n.?!。？！\"'”’」』》】)）"
                ))
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        return !lhs.isEmpty && comparable(lhs) == comparable(rhs)
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

}
