import Foundation

struct MemoBlock: Identifiable, Equatable {
    var id: String
    var dateText: String
    var body: String
    var tags: [String]
    var writeMarker: String? = nil

    var preview: String {
        let compact = body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !Self.isAttachmentLine($0) }
            .joined(separator: " ")
        return compact.isEmpty ? "Attachment memo" : compact
    }

    var hasAttachments: Bool {
        body.contains("![") || body.contains("](Attachments/")
    }

    var hasChecklist: Bool {
        body.range(
            of: #"(?m)^\s*[-*+]\s+\[[ xX]\]\s+"#,
            options: .regularExpression
        ) != nil
    }

    var hasUncheckedChecklist: Bool {
        body.range(
            of: #"(?m)^\s*[-*+]\s+\[ \]\s+"#,
            options: .regularExpression
        ) != nil
    }

    private static func isAttachmentLine(_ line: String) -> Bool {
        line.hasPrefix("![[")
            || line.range(of: #"^!\[[^\]]*\]\([^)]+\)$"#, options: .regularExpression) != nil
            || line.range(of: #"^\[[^\]]+\]\([^)]+\)$"#, options: .regularExpression) != nil
    }
}

enum InboxParser {
    private static let tagsMarkerPrefix = "<!-- mudsnote-tags:"

    static func parse(_ markdown: String) -> [MemoBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MemoBlock] = []
        var currentDate: String?
        var currentLines: [String] = []
        var currentWriteMarker: String?

        func flush() {
            guard let currentDate else { return }
            var bodyLines = currentLines
            var tags: [String] = []
            if let index = bodyLines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(tagsMarkerPrefix)
            }) {
                let marker = bodyLines.remove(at: index)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let value = marker
                    .dropFirst(tagsMarkerPrefix.count)
                    .dropLast(marker.hasSuffix("-->") ? 3 : 0)
                tags = value.split(separator: ",").compactMap {
                    MarkdownTagSyntax.normalizedTag(String($0))
                }
            }
            let body = bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let id = "\(currentDate)-\(blocks.count)"
            blocks.append(MemoBlock(
                id: id,
                dateText: currentDate,
                body: body,
                tags: tags,
                writeMarker: currentWriteMarker
            ))
        }

        for line in lines {
            if line.hasPrefix("## "), isMemoHeading(String(line.dropFirst(3))) {
                flush()
                currentDate = String(line.dropFirst(3))
                currentLines = []
                currentWriteMarker = nil
            } else if currentDate != nil, isWriteMarker(line) {
                currentWriteMarker = line
            } else if currentDate != nil {
                currentLines.append(line)
            }
        }
        flush()
        return blocks.reversed()
    }

    static func markdown(forDisplayItems items: [MemoBlock]) -> String {
        var output = "# Inbox\n\n"
        for memo in items.reversed() {
            output += "## \(memo.dateText)\n\n"
            if !memo.tags.isEmpty {
                output += "\(tagsMarkerPrefix) \(memo.tags.joined(separator: ", ")) -->\n\n"
            }
            output += memo.body.trimmingCharacters(in: .whitespacesAndNewlines)
            output += "\n\n"
            if let writeMarker = memo.writeMarker {
                output += writeMarker
                output += "\n\n"
            }
        }
        return output
    }

    private static func isMemoHeading(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil
    }

    private static func isWriteMarker(_ value: String) -> Bool {
        value.range(
            of: #"^<!-- mudsnote-write:[0-9a-fA-F-]{36} -->$"#,
            options: .regularExpression
        ) != nil
    }
}
