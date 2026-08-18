import Foundation

public struct AIMemorySyncResult: Equatable, Sendable {
    public let destinationURL: URL
    public let didWrite: Bool
    public let syncedAt: Date

    public init(destinationURL: URL, didWrite: Bool, syncedAt: Date) {
        self.destinationURL = destinationURL
        self.didWrite = didWrite
        self.syncedAt = syncedAt
    }
}

public struct AIMemorySyncService: Sendable {
    public let memoryDirectory: URL
    public let destinationRoot: URL
    private let calendar: Calendar

    public init(
        memoryDirectory: URL,
        destinationRoot: URL,
        calendar: Calendar = .current
    ) {
        self.memoryDirectory = memoryDirectory.standardizedFileURL
        self.destinationRoot = destinationRoot.standardizedFileURL
        self.calendar = calendar
    }

    public func sync(
        lastSyncDate: Date?,
        now: Date = Date(),
        force: Bool = false
    ) throws -> AIMemorySyncResult {
        let destinationDirectory = destinationRoot.appendingPathComponent("AI-memory", isDirectory: true)
        let destinationURL = destinationDirectory.appendingPathComponent("Mudsnote Core Memory.md")
        if !force, let lastSyncDate, calendar.isDate(lastSyncDate, inSameDayAs: now) {
            return AIMemorySyncResult(destinationURL: destinationURL, didWrite: false, syncedAt: lastSyncDate)
        }

        let snapshot = try makeSnapshot(now: now)
        let current = try? String(contentsOf: destinationURL, encoding: .utf8)
        let didWrite = current != snapshot
        if didWrite {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            try snapshot.write(to: destinationURL, atomically: true, encoding: .utf8)
        }
        return AIMemorySyncResult(destinationURL: destinationURL, didWrite: didWrite, syncedAt: now)
    }

    func makeSnapshot(now: Date) throws -> String {
        let sourceNames = ["memory_summary.md", "MEMORY.md"]
        let sections = try sourceNames.flatMap { name -> [String] in
            let url = memoryDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let markdown = try String(contentsOf: url, encoding: .utf8)
            return Self.mudsnoteSections(in: markdown)
        }
        let uniqueSections = sections.reduce(into: [String]()) { result, section in
            if !result.contains(section) {
                result.append(section)
            }
        }
        let sourceBody = uniqueSections.isEmpty
            ? "_No Mudsnote-specific core memory was found._"
            : uniqueSections.joined(separator: "\n\n")
        return """
        ---
        tags:
          - AI-memory
          - Mudsnote
        generated: \(now.ISO8601Format())
        source: local-codex-memory
        ---

        # Mudsnote Core Memory

        This note is generated from Mudsnote-specific sections of the local AI memory. Unrelated project sections are not imported.

        \(sourceBody)
        """
    }

    static func mudsnoteSections(in markdown: String) -> [String] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var sections: [String] = []
        var current: [String] = []
        var capturedHeadingLevel: Int?

        func flush() {
            let section = current.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !section.isEmpty {
                sections.append(section)
            }
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let headingLevel = line.prefix(while: { $0 == "#" }).count
            let isHeading = headingLevel > 0
                && line.dropFirst(headingLevel).first?.isWhitespace == true
            if isHeading {
                let heading = line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    .lowercased()
                let matches = heading.contains("mudsnote")
                    || heading.contains("quickmarkdown")
                    || heading.contains("/users/donald/code/mudsnote")
                if let activeHeadingLevel = capturedHeadingLevel {
                    if headingLevel <= activeHeadingLevel {
                        flush()
                        startCapture(
                            matches: matches,
                            headingLevel: headingLevel,
                            line: line,
                            capturedHeadingLevel: &capturedHeadingLevel,
                            current: &current
                        )
                    } else {
                        current.append(line)
                    }
                } else {
                    startCapture(
                        matches: matches,
                        headingLevel: headingLevel,
                        line: line,
                        capturedHeadingLevel: &capturedHeadingLevel,
                        current: &current
                    )
                }
            } else if capturedHeadingLevel != nil {
                current.append(line)
            }
        }
        if capturedHeadingLevel != nil {
            flush()
        }
        return sections
    }

    private static func startCapture(
        matches: Bool,
        headingLevel: Int,
        line: String,
        capturedHeadingLevel: inout Int?,
        current: inout [String]
    ) {
        capturedHeadingLevel = matches ? headingLevel : nil
        if matches {
            current.append(line)
        }
    }
}
