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

    private static func isAttachmentLine(_ line: String) -> Bool {
        line.hasPrefix("![[")
            || line.range(of: #"^!\[[^\]]*\]\([^)]+\)$"#, options: .regularExpression) != nil
            || line.range(of: #"^\[[^\]]+\]\([^)]+\)$"#, options: .regularExpression) != nil
    }
}

enum InboxParser {
    static func parse(_ markdown: String) -> [MemoBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MemoBlock] = []
        var currentDate: String?
        var currentLines: [String] = []
        var currentWriteMarker: String?

        func flush() {
            guard let currentDate else { return }
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = body
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { $0.hasPrefix("#") }
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
