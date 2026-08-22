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
                let body = Self.removingInlineTag(tag, from: document.body)
                guard tags != document.tags || body != document.body else { continue }

                backups.append((url, document.sourceContents))
                _ = try updateNoteInPlace(
                    at: url,
                    title: document.title,
                    body: body,
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

    private static func removingInlineTag(_ tag: String, from markdown: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}_/#(])#\#(escaped)(?![\p{L}\p{N}_-])"#,
            options: [.caseInsensitive]
        ) else { return markdown }

        var insideFence: Character?
        return markdown.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = trimmed.first,
               (marker == "`" || marker == "~"),
               trimmed.prefix(3).allSatisfy({ $0 == marker }) {
                insideFence = insideFence == nil ? marker : (insideFence == marker ? nil : insideFence)
                return line
            }
            guard insideFence == nil else { return line }

            let mutable = NSMutableString(string: line)
            let codeRanges = inlineCodeRanges(in: mutable)
            let matches = expression.matches(
                in: line,
                range: NSRange(location: 0, length: mutable.length)
            ).filter { match in
                codeRanges.allSatisfy {
                    NSIntersectionRange($0, match.range).length == 0
                }
            }
            for match in matches.reversed() {
                var range = match.range
                if NSMaxRange(range) < mutable.length {
                    let next = mutable.character(at: NSMaxRange(range))
                    if next == 32 || next == 9 {
                        range.length += 1
                    }
                } else if range.location > 0 {
                    let previous = mutable.character(at: range.location - 1)
                    if previous == 32 || previous == 9 {
                        range.location -= 1
                        range.length += 1
                    }
                }
                mutable.replaceCharacters(in: range, with: "")
            }
            return mutable as String
        }.joined(separator: "\n")
    }

    private static func inlineCodeRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < source.length {
            let opening = source.range(
                of: "`",
                options: [],
                range: NSRange(location: cursor, length: source.length - cursor)
            )
            guard opening.location != NSNotFound else { break }
            var runLength = 1
            while opening.location + runLength < source.length,
                  source.character(at: opening.location + runLength) == 96 {
                runLength += 1
            }
            let marker = String(repeating: "`", count: runLength)
            let contentStart = opening.location + runLength
            let closing = source.range(
                of: marker,
                options: [],
                range: NSRange(location: contentStart, length: source.length - contentStart)
            )
            guard closing.location != NSNotFound else { break }
            let range = NSRange(
                location: opening.location,
                length: NSMaxRange(closing) - opening.location
            )
            ranges.append(range)
            cursor = NSMaxRange(range)
        }
        return ranges
    }
}
