import Foundation

actor MarkdownFileStore {
    private struct SearchCacheEntry {
        var modifiedAt: Date
        var byteCount: Int
        var markdown: String
    }

    private var root: URL?
    private var cachedLibrarySnapshot: MarkdownLibrarySnapshot?
    private var searchCache: [String: SearchCacheEntry] = [:]
    private let fileManager = FileManager.default

    func configure(root: URL) {
        self.root = root
        cachedLibrarySnapshot = nil
        searchCache = [:]
    }

    func loadLibrarySnapshot() throws -> MarkdownLibrarySnapshot {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let inboxURL = root.appendingPathComponent("Inbox.md")
        let inboxMarkdown = try String(contentsOf: inboxURL, encoding: .utf8)
        let inboxItems = InboxParser.parse(inboxMarkdown)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var markdownFiles: [RecentMarkdownFile] = []
        var attachments: [LibraryAttachment] = []
        var dailyCount = 0
        var attachmentCount = 0
        var conflictWarnings: [String] = []

        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let relativePath = Self.relativePath(for: url, root: root)
                let lowercasedName = url.lastPathComponent.lowercased()
                if lowercasedName.contains("conflict") || lowercasedName.contains("conflicted copy") {
                    conflictWarnings.append(relativePath)
                }

                guard let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true else {
                    continue
                }

                if relativePath.hasPrefix("Attachments/") {
                    attachmentCount += 1
                    attachments.append(LibraryAttachment(
                        id: relativePath,
                        relativePath: relativePath,
                        fileName: url.lastPathComponent,
                        modifiedAt: values.contentModificationDate ?? .distantPast,
                        byteCount: Int64(values.fileSize ?? 0),
                        kind: LibraryAttachment.Kind(fileExtension: url.pathExtension)
                    ))
                }
                guard url.pathExtension.lowercased() == "md" else { continue }
                if relativePath.hasPrefix("Daily/") {
                    dailyCount += 1
                }
                markdownFiles.append(RecentMarkdownFile(
                    id: relativePath,
                    relativePath: relativePath,
                    title: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                ))
            }
        }

        let recentFiles = markdownFiles
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(24)
            .map { $0 }
        let allFiles = markdownFiles.sorted { $0.modifiedAt > $1.modifiedAt }
        let snapshot = MarkdownLibrarySnapshot(
            inboxItems: inboxItems,
            allFiles: allFiles,
            recentFiles: recentFiles,
            attachments: attachments.sorted { $0.modifiedAt > $1.modifiedAt },
            summary: LibrarySummary(
                allNotesCount: markdownFiles.count,
                inboxCount: inboxItems.count,
                dailyCount: dailyCount,
                attachmentCount: attachmentCount
            ),
            conflictWarnings: conflictWarnings.sorted()
        )
        cachedLibrarySnapshot = snapshot
        return snapshot
    }

    func loadInboxDeltaSnapshot() throws -> MarkdownLibrarySnapshot {
        guard let root else { throw FolderAccessError.missingFolder }
        guard var snapshot = cachedLibrarySnapshot else {
            return try loadLibrarySnapshot()
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let inboxURL = root.appendingPathComponent("Inbox.md")
        let inboxMarkdown = try String(contentsOf: inboxURL, encoding: .utf8)
        let inboxItems = InboxParser.parse(inboxMarkdown)
        let modifiedAt = try inboxURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate ?? .distantPast
        let inboxFile = RecentMarkdownFile(
            id: "Inbox.md",
            relativePath: "Inbox.md",
            title: "Inbox",
            modifiedAt: modifiedAt
        )

        snapshot.inboxItems = inboxItems
        snapshot.summary.inboxCount = inboxItems.count
        snapshot.allFiles = (snapshot.allFiles.filter { $0.relativePath != "Inbox.md" } + [inboxFile])
            .sorted { $0.modifiedAt > $1.modifiedAt }
        snapshot.recentFiles = snapshot.allFiles
            .prefix(24)
            .map { $0 }
        cachedLibrarySnapshot = snapshot
        return snapshot
    }

    func loadMarkdownDocument(relativePath: String) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let fileURL = AuthorizedLibraryPath.resolve(relativePath, within: root),
              fileURL.pathExtension.lowercased() == "md" else {
            throw MarkdownDocumentError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        return MarkdownDocument(
            id: relativePath,
            title: fileURL.deletingPathExtension().lastPathComponent,
            relativePath: relativePath,
            markdown: try String(contentsOf: fileURL, encoding: .utf8)
        )
    }

    func search(query: String, limit: Int = 80) throws -> [MarkdownSearchResult] {
        guard let root else { throw FolderAccessError.missingFolder }
        let terms = MarkdownSearch.normalizedTerms(query)
        guard !terms.isEmpty else { return [] }
        let files: [RecentMarkdownFile]
        if let cachedLibrarySnapshot {
            files = cachedLibrarySnapshot.allFiles
        } else {
            files = try loadLibrarySnapshot().allFiles
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        var matches: [MarkdownSearchResult] = []
        var activePaths = Set<String>()
        for file in files {
            try Task.checkCancellation()
            guard let url = AuthorizedLibraryPath.resolve(file.relativePath, within: root) else { continue }
            activePaths.insert(file.relativePath)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modifiedAt = values?.contentModificationDate ?? file.modifiedAt
            let byteCount = values?.fileSize ?? 0
            let markdown: String
            if let cached = searchCache[file.relativePath],
               cached.modifiedAt == modifiedAt,
               cached.byteCount == byteCount {
                markdown = cached.markdown
            } else {
                markdown = try boundedSearchText(from: url)
                if byteCount <= 256 * 1_024 {
                    searchCache[file.relativePath] = SearchCacheEntry(
                        modifiedAt: modifiedAt,
                        byteCount: byteCount,
                        markdown: markdown
                    )
                    trimSearchCacheIfNeeded()
                } else {
                    searchCache.removeValue(forKey: file.relativePath)
                }
            }

            if file.relativePath == "Inbox.md" {
                for memo in InboxParser.parse(markdown) {
                    if let result = MarkdownSearch.match(memo: memo, terms: terms) {
                        matches.append(result)
                    }
                }
            } else if let result = MarkdownSearch.match(file: file, markdown: markdown, terms: terms) {
                matches.append(result)
            }
        }
        searchCache = searchCache.filter { activePaths.contains($0.key) }

        return matches
            .sorted {
                if $0.score == $1.score { return $0.modifiedAt > $1.modifiedAt }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map { $0 }
    }

    func prepareAttachmentPreview(relativePath: String) throws -> URL {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let fileURL = AuthorizedLibraryPath.resolve(
            relativePath,
            within: root,
            constrainedTo: "Attachments"
        ) else {
            throw AttachmentPreviewError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw AttachmentPreviewError.invalidPath
        }

        let previewDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MudsnoteAttachmentPreview", isDirectory: true)
        try? fileManager.removeItem(at: previewDirectory)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let previewURL = previewDirectory.appendingPathComponent(fileURL.lastPathComponent)
        try fileManager.copyItem(at: fileURL, to: previewURL)
        return previewURL
    }

    func applyInboxMutation(_ mutation: InboxMutation) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let inboxURL = root.appendingPathComponent("Inbox.md")
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var mutationError: Error?
        coordinator.coordinate(writingItemAt: inboxURL, options: .forMerging, error: &coordinationError) { coordinatedURL in
            do {
                let markdown = try String(contentsOf: coordinatedURL, encoding: .utf8)
                var items = InboxParser.parse(markdown)
                guard let index = items.firstIndex(where: { $0.id == mutation.memoID }) else {
                    throw InboxMutationError.memoNotFound
                }

                switch mutation {
                case .delete:
                    items.remove(at: index)
                case .pin:
                    let item = items.remove(at: index)
                    items.insert(item, at: 0)
                case .addTag(_, let tag):
                    let normalizedTag = tag.hasPrefix("#") ? tag : "#\(tag)"
                    if items[index].body.split(whereSeparator: \.isWhitespace).contains(Substring(normalizedTag)) == false {
                        items[index].body += items[index].body.isEmpty ? normalizedTag : "\n\n\(normalizedTag)"
                    }
                case .replaceBody(_, let expectedBody, let newBody):
                    guard items[index].body == expectedBody else {
                        throw InboxMutationError.memoChanged
                    }
                    items[index].body = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let updatedMarkdown = InboxParser.markdown(forDisplayItems: items)
                try updatedMarkdown.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                mutationError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let mutationError { throw mutationError }
    }

    func preparePendingWrite(for draft: CaptureDraft, root: URL, now: Date = Date()) async throws -> PendingWrite {
        guard draft.canSend else { throw CaptureDraftError.empty }
        try CaptureAttachmentPolicy.validate(draft.attachments)
        let attachmentWrites = try attachmentWrites(for: draft.attachments, root: root, now: now)
        let markdown = Self.markdownBlock(
            body: draft.body,
            tags: draft.tags,
            attachmentReferences: zip(attachmentWrites, draft.attachments).map {
                MarkdownAttachmentReference(relativePath: $0.0.relativePath, kind: $0.1.referenceKind)
            },
            attachmentTags: draft.attachments.map(\.markdownTag),
            now: now
        )

        return PendingWrite(
            id: UUID(),
            createdAt: now,
            targetRelativePath: draft.target.relativePath(now: now),
            markdownBlock: markdown,
            attachments: attachmentWrites.map {
                PendingAttachment(relativePath: $0.relativePath, base64Data: $0.data.base64EncodedString())
            }
        )
    }

    func saveMarkdownDocument(
        relativePath: String,
        markdown: String,
        expectedMarkdown: String
    ) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let fileURL = AuthorizedLibraryPath.resolve(relativePath, within: root),
              fileURL.pathExtension.lowercased() == "md" else {
            throw MarkdownDocumentError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var saveError: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { coordinatedURL in
            do {
                let current = try String(contentsOf: coordinatedURL, encoding: .utf8)
                guard current == expectedMarkdown else {
                    throw MarkdownDocumentError.changedExternally
                }
                try markdown.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                saveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let saveError { throw saveError }
        cachedLibrarySnapshot = nil
        searchCache.removeValue(forKey: relativePath)
        return MarkdownDocument(
            id: relativePath,
            title: fileURL.deletingPathExtension().lastPathComponent,
            relativePath: relativePath,
            markdown: markdown
        )
    }

    private func boundedSearchText(from url: URL) throws -> String {
        let maximumBytes = 32 * 1_024 * 1_024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func trimSearchCacheIfNeeded() {
        let maximumEntries = 64
        guard searchCache.count > maximumEntries else { return }
        let overflow = searchCache.count - maximumEntries
        let oldestKeys = searchCache
            .sorted { $0.value.modifiedAt < $1.value.modifiedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            searchCache.removeValue(forKey: key)
        }
    }

    func performPendingWrite(_ pending: PendingWrite) async throws {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let target = AuthorizedLibraryPath.resolve(pending.targetRelativePath, within: root),
              target.pathExtension.lowercased() == "md" else {
            throw PendingWriteValidationError.invalidTargetPath
        }
        guard !pending.markdownBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PendingWriteValidationError.invalidMarkdown
        }

        let validatedAttachments = try pending.attachments.map { attachment in
            guard let url = AuthorizedLibraryPath.resolve(
                attachment.relativePath,
                within: root,
                constrainedTo: "Attachments"
            ) else {
                throw PendingWriteValidationError.invalidAttachmentPath
            }
            guard let data = Data(base64Encoded: attachment.base64Data), !data.isEmpty else {
                throw PendingWriteValidationError.invalidAttachmentData
            }
            return (url: url, data: data)
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        for attachment in validatedAttachments {
            let attachmentURL = attachment.url
            try fileManager.createDirectory(
                at: attachmentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(atPath: attachmentURL.path) else { continue }
            try attachment.data.write(to: attachmentURL, options: .atomic)
        }

        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: target.path) {
            try "# \(target.deletingPathExtension().lastPathComponent)\n\n".write(to: target, atomically: true, encoding: .utf8)
        }

        try appendPendingWriteIfNeeded(pending, to: target)
    }

    private func attachmentWrites(for attachments: [CaptureAttachment], root: URL, now: Date) throws -> [(relativePath: String, data: Data)] {
        let month = Self.monthFormatter.string(from: now)
        let timestamp = Self.attachmentFormatter.string(from: now)
        return attachments.enumerated().map { index, attachment in
            let suffix = attachments.count > 1 ? "-\(index + 1)" : ""
            let fileName = "\(attachment.filePrefix)-\(timestamp)\(suffix).\(attachment.preferredExtension)"
            return ("Attachments/\(month)/\(fileName)", attachment.data)
        }
    }

    private func appendPendingWriteIfNeeded(_ pending: PendingWrite, to target: URL) throws {
        let marker = "<!-- mudsnote-write:\(pending.id.uuidString.lowercased()) -->"
        let block = pending.markdownBlock + marker + "\n"
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: target, options: .forMerging, error: &coordinationError) { coordinatedURL in
            do {
                var existing = try Data(contentsOf: coordinatedURL)
                if let markerData = marker.data(using: .utf8), existing.range(of: markerData) != nil {
                    return
                }
                guard let blockData = block.data(using: .utf8) else { return }
                existing.append(blockData)
                try existing.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }

    static func markdownBlock(
        body: String,
        tags: String,
        attachmentReferences: [MarkdownAttachmentReference],
        attachmentTags: [String],
        now: Date
    ) -> String {
        var lines: [String] = [
            "",
            "## \(memoFormatter.string(from: now))",
            "",
        ]
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            lines.append(trimmedBody)
            lines.append("")
        }
        for reference in attachmentReferences {
            lines.append(reference.markdownLine)
        }
        if !attachmentReferences.isEmpty {
            lines.append("")
        }

        let tagLine = ([tags, attachmentTags.joined(separator: " ")]
            .joined(separator: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty })
            .joined(separator: " ")
        if !tagLine.isEmpty {
            lines.append(tagLine)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static let memoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM"
        return formatter
    }()

    private static let attachmentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

enum AuthorizedLibraryPath {
    static func resolve(
        _ relativePath: String,
        within root: URL,
        constrainedTo directory: String? = nil
    ) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let standardizedRoot = root.standardizedFileURL
        let candidate = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        guard candidate.path.hasPrefix(standardizedRoot.path + "/") else { return nil }
        guard !containsSymbolicLink(relativePath, within: standardizedRoot) else { return nil }
        if let directory {
            let allowedRoot = root
                .appendingPathComponent(directory, isDirectory: true)
                .standardizedFileURL
            guard candidate.path.hasPrefix(allowedRoot.path + "/") else { return nil }
        }
        return candidate
    }

    private static func containsSymbolicLink(_ relativePath: String, within root: URL) -> Bool {
        var current = root
        for component in relativePath.split(separator: "/") {
            current.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                return true
            }
        }
        return false
    }
}

struct RecentMarkdownFile: Identifiable, Equatable {
    var id: String
    var relativePath: String
    var title: String
    var modifiedAt: Date
}

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
        terms: [String]
    ) -> MarkdownSearchResult? {
        let title = normalize(file.title)
        let path = normalize(file.relativePath)
        let body = normalize(markdown)
        guard terms.allSatisfy({ title.contains($0) || path.contains($0) || body.contains($0) }) else {
            return nil
        }
        let score = terms.reduce(into: 0) { total, term in
            if title == term { total += 1_000 }
            else if title.hasPrefix(term) { total += 700 }
            else if title.contains(term) { total += 500 }
            if path.contains(term) { total += 180 }
            if body.contains(term) { total += 80 }
        }
        return MarkdownSearchResult(
            id: "file:\(file.relativePath)",
            title: file.title,
            context: context(in: markdown, matching: terms),
            location: file.relativePath,
            score: score,
            modifiedAt: file.modifiedAt,
            destination: .file(file)
        )
    }

    static func match(memo: MemoBlock, terms: [String]) -> MarkdownSearchResult? {
        let searchable = normalize([memo.body, memo.tags.joined(separator: " "), memo.dateText].joined(separator: " "))
        guard terms.allSatisfy(searchable.contains) else { return nil }
        let tagText = normalize(memo.tags.joined(separator: " "))
        let score = terms.reduce(into: 300) { total, term in
            if tagText.contains(term) { total += 250 }
            if searchable.contains(term) { total += 100 }
        }
        return MarkdownSearchResult(
            id: "memo:\(memo.id)",
            title: memo.body.split(separator: "\n").first.map(String.init) ?? String(localized: "Untitled memo"),
            context: context(in: memo.body, matching: terms),
            location: String(localized: "Inbox"),
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

struct MarkdownLibrarySnapshot: Equatable {
    var inboxItems: [MemoBlock]
    var allFiles: [RecentMarkdownFile]
    var recentFiles: [RecentMarkdownFile]
    var attachments: [LibraryAttachment]
    var summary: LibrarySummary
    var conflictWarnings: [String]
}

struct LibraryAttachment: Identifiable, Equatable {
    var id: String
    var relativePath: String
    var fileName: String
    var modifiedAt: Date
    var byteCount: Int64
    var kind: Kind

    enum Kind: Equatable {
        case image
        case audio
        case other

        init(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff":
                self = .image
            case "m4a", "wav", "mp3", "aac", "caf", "aif", "aiff":
                self = .audio
            default:
                self = .other
            }
        }

        var systemImage: String {
            switch self {
            case .image: "photo"
            case .audio: "waveform"
            case .other: "doc"
            }
        }
    }
}

struct MarkdownDocument: Identifiable, Equatable {
    var id: String
    var title: String
    var relativePath: String
    var markdown: String
}

enum MarkdownDocumentError: LocalizedError, Equatable {
    case invalidPath
    case changedExternally

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            String(localized: "This Markdown file is outside the authorized library.")
        case .changedExternally:
            String(localized: "This note changed elsewhere. Reopen it before editing again.")
        }
    }
}

enum CaptureDraftError: LocalizedError, Equatable {
    case empty

    var errorDescription: String? {
        String(localized: "Add text or an attachment before saving.")
    }
}

enum PendingWriteValidationError: LocalizedError, Equatable {
    case invalidTargetPath
    case invalidAttachmentPath
    case invalidAttachmentData
    case invalidMarkdown

    var errorDescription: String? {
        String(localized: "A pending capture is damaged and was not written.")
    }
}

enum AttachmentPreviewError: LocalizedError, Equatable {
    case invalidPath

    var errorDescription: String? {
        String(localized: "This attachment is outside the authorized library.")
    }
}

struct LibrarySummary: Equatable {
    var allNotesCount = 0
    var inboxCount = 0
    var dailyCount = 0
    var attachmentCount = 0
}

enum InboxMutation: Equatable {
    case delete(memoID: String)
    case pin(memoID: String)
    case addTag(memoID: String, tag: String)
    case replaceBody(memoID: String, expectedBody: String, newBody: String)

    var memoID: String {
        switch self {
        case .delete(let memoID), .pin(let memoID), .addTag(let memoID, _), .replaceBody(let memoID, _, _): memoID
        }
    }
}

enum InboxMutationError: LocalizedError, Equatable {
    case memoNotFound
    case memoChanged

    var errorDescription: String? {
        String(localized: "The memo changed before this action completed. Refresh and try again.")
    }
}

extension MarkdownAttachmentReference {
    var markdownLine: String {
        switch kind {
        case .image:
            return "![Image](\(relativePath))"
        case .audio:
            return "[Audio](\(relativePath))"
        }
    }
}
