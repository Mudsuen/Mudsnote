import Foundation

struct MarkdownSearchResult: Identifiable, Equatable {
    enum Destination: Equatable {
        case file(RecentMarkdownFile)
        case memo(MemoBlock)
    }

    var id: String
    var title: String
    var context: String
    var location: String
    var score: Int
    var modifiedAt: Date
    var destination: Destination
}

enum MarkdownSearchScope: String, CaseIterable, Identifiable, Equatable {
    case all
    case notes
    case inbox

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .notes: String(localized: "Notes")
        case .inbox: String(localized: "Inbox")
        }
    }
}

enum MarkdownSearch {
    static func normalizedTerms(_ query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func match(
        file: RecentMarkdownFile,
        markdown: String,
        terms: [String],
        attachmentDocuments: [AttachmentSearchDocument] = []
    ) -> MarkdownSearchResult? {
        let title = normalize(file.title)
        let path = normalize(file.relativePath)
        let body = normalize(markdown)
        let attachmentTexts = attachmentDocuments.map { ($0, normalize($0.text)) }
        guard terms.allSatisfy({ term in
            title.contains(term)
                || path.contains(term)
                || body.contains(term)
                || attachmentTexts.contains(where: { $0.1.contains(term) })
        }) else {
            return nil
        }
        let score = terms.reduce(into: 0) { total, term in
            if title == term { total += 1_000 }
            else if title.hasPrefix(term) { total += 700 }
            else if title.contains(term) { total += 500 }
            if path.contains(term) { total += 180 }
            if body.contains(term) { total += 80 }
            if attachmentTexts.contains(where: { $0.1.contains(term) }) { total += 70 }
        }
        let matchedAttachment = attachmentTexts.first { document, normalizedText in
            terms.contains(where: normalizedText.contains)
        }?.0
        return MarkdownSearchResult(
            id: "file:\(file.relativePath)",
            title: file.title,
            context: matchedAttachment.map { context(in: $0.text, matching: terms) }
                ?? context(in: markdown, matching: terms),
            location: matchedAttachment.map { "\(file.relativePath) · \($0.fileName)" }
                ?? file.relativePath,
            score: score,
            modifiedAt: file.modifiedAt,
            destination: .file(file)
        )
    }

    static func match(
        memo: MemoBlock,
        terms: [String],
        attachmentDocuments: [AttachmentSearchDocument] = []
    ) -> MarkdownSearchResult? {
        let searchable = normalize([memo.body, memo.tags.joined(separator: " "), memo.dateText].joined(separator: " "))
        let attachmentTexts = attachmentDocuments.map { ($0, normalize($0.text)) }
        guard terms.allSatisfy({ term in
            searchable.contains(term)
                || attachmentTexts.contains(where: { $0.1.contains(term) })
        }) else { return nil }
        let tagText = normalize(memo.tags.joined(separator: " "))
        let score = terms.reduce(into: 300) { total, term in
            if tagText.contains(term) { total += 250 }
            if searchable.contains(term) { total += 100 }
            if attachmentTexts.contains(where: { $0.1.contains(term) }) { total += 70 }
        }
        let matchedAttachment = attachmentTexts.first { document, normalizedText in
            terms.contains(where: normalizedText.contains)
        }?.0
        return MarkdownSearchResult(
            id: "memo:\(memo.id)",
            title: memo.body.split(separator: "\n").first.map(String.init) ?? String(localized: "Untitled memo"),
            context: matchedAttachment.map { context(in: $0.text, matching: terms) }
                ?? context(in: memo.body, matching: terms),
            location: matchedAttachment.map { "\(String(localized: "Inbox")) · \($0.fileName)" }
                ?? String(localized: "Inbox"),
            score: score,
            modifiedAt: .distantPast,
            destination: .memo(memo)
        )
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private static func context(in markdown: String, matching terms: [String]) -> String {
        let meaningfulLines = markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("<!--") }
        let matched = meaningfulLines.first { line in
            let normalized = normalize(line)
            return terms.contains(where: normalized.contains)
        }
        let line = matched ?? meaningfulLines.first ?? ""
        return String(line.prefix(180))
    }
}
