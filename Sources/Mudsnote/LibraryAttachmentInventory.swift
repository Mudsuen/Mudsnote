import Foundation
import MudsnoteCore

enum LibraryAttachmentState: Int, Sendable, CaseIterable {
    case unknown
    case missing
    case unreferenced
    case referenced

    var title: String {
        switch self {
        case .unknown: return "待核实"
        case .missing:
            return "缺失"
        case .unreferenced:
            return "未引用"
        case .referenced:
            return "已引用"
        }
    }
}

struct LibraryAttachmentItem: Equatable, Sendable {
    let url: URL
    let state: LibraryAttachmentState
    let byteCount: Int64?
    let referencingNotes: [URL]
    var protectedSources: [AttachmentReferenceSource] = []

    var filename: String {
        url.lastPathComponent
    }

    var referenceSummary: String {
        if !protectedSources.isEmpty {
            let drafts = protectedSources.filter { $0.kind == .draft }.count
            let trash = protectedSources.filter { $0.kind == .trash }.count
            return "\(referencingNotes.count + protectedSources.count) 个来源 · \(drafts) 份草稿 · \(trash) 篇回收站笔记"
        }
        switch state {
        case .unknown: return "引用扫描不完整"
        case .missing:
            return referencingNotes.count == 1
                ? "1 篇笔记中的链接失效"
                : "\(referencingNotes.count) 篇笔记中的链接失效"
        case .unreferenced:
            return "没有笔记引用"
        case .referenced:
            return referencingNotes.count == 1
                ? "1 篇笔记引用"
                : "\(referencingNotes.count) 篇笔记引用"
        }
    }
}

struct LibraryAttachmentScan: Sendable {
    var items: [LibraryAttachmentItem]
    var isComplete = true
}

enum LibraryAttachmentInventory {
    private static let noteExtensions = Set(["md", "markdown", "txt"])

    static func build(
        roots: [URL], protectedSources: [ProtectedAttachmentReferenceSource] = [],
        noteStore: NoteStore? = nil, fileManager: FileManager = .default,
        cancellationCheck: @Sendable () -> Bool = { Task.isCancelled }
    ) -> [LibraryAttachmentItem] {
        scan(roots: roots, protectedSources: protectedSources, noteStore: noteStore,
            fileManager: fileManager, cancellationCheck: cancellationCheck).items
    }

    static func scan(
        roots: [URL], protectedSources: [ProtectedAttachmentReferenceSource] = [],
        noteStore: NoteStore? = nil, fileManager: FileManager = .default,
        cancellationCheck: @Sendable () -> Bool = { Task.isCancelled }
    ) -> LibraryAttachmentScan {
        let roots = deduplicatedRoots(roots)
        var complete = true
        var noteURLs: [URL] = []
        var attachmentURLsByPath: [String: URL] = [:]
        for root in roots {
            if cancellationCheck() { return LibraryAttachmentScan(items: [], isComplete: false) }
            collectFiles(under: root, fileManager: fileManager, noteURLs: &noteURLs,
                attachmentURLsByPath: &attachmentURLsByPath, complete: &complete, cancellationCheck: cancellationCheck)
        }
        var sourcesByAttachment: [String: Set<AttachmentReferenceSource>] = [:]
        func consume(_ source: AttachmentReferenceSource, _ markdown: String) {
            for reference in MarkdownNoteReferenceParser.destinations(in: markdown, cancellationCheck: cancellationCheck) {
                let candidates = reference.localFileCandidates(relativeTo: source.resolutionURL).filter { candidate in
                    candidate.pathComponents.contains { $0.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) == .orderedSame }
                        && roots.contains { candidate.path.hasPrefix($0.path + "/") }
                }
                // Wiki links can omit a note extension. Protect every existing
                // candidate if ambiguous, rather than granting deletion rights.
                let existing = candidates.filter { attachmentURLsByPath[$0.path] != nil }
                let targets = existing.isEmpty ? Array(candidates.prefix(1)) : existing
                for target in targets { sourcesByAttachment[target.path, default: []].insert(source) }
            }
        }
        // Only one active note's text is held at a time.
        for noteURL in noteURLs {
            if cancellationCheck() { return LibraryAttachmentScan(items: [], isComplete: false) }
            do {
                consume(AttachmentReferenceSource(resolutionURL: noteURL, identityURL: noteURL, kind: .note),
                    try String(contentsOf: noteURL, encoding: .utf8))
            } catch { complete = false }
        }
        for entry in protectedSources {
            if cancellationCheck() { return LibraryAttachmentScan(items: [], isComplete: false) }
            consume(entry.source, entry.markdown)
        }
        if let noteStore {
            do { try noteStore.forEachProtectedAttachmentReferenceSource(cancellationCheck: cancellationCheck, consume) }
            catch { complete = false }
        }
        if cancellationCheck() { return LibraryAttachmentScan(items: [], isComplete: false) }
        let items = Set(attachmentURLsByPath.keys).union(sourcesByAttachment.keys).map { path in
            let url = attachmentURLsByPath[path] ?? URL(fileURLWithPath: path)
            let sources = sourcesByAttachment[path, default: []].sorted { $0.identityURL.path < $1.identityURL.path }
            let exists = attachmentURLsByPath[path] != nil
            let state: LibraryAttachmentState = exists
                ? (sources.isEmpty ? (complete ? .unreferenced : .unknown) : .referenced)
                : (complete ? .missing : .unknown)
            let bytes = exists ? (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0.map(Int64.init) } : nil
            return LibraryAttachmentItem(url: url, state: state, byteCount: bytes,
                referencingNotes: sources.compactMap(\.openableNoteURL),
                protectedSources: sources.filter { $0.kind != .note })
        }.sorted(by: attachmentSort)
        return LibraryAttachmentScan(items: items, isComplete: complete)
    }

    static func localAttachmentTargets(in markdown: String) -> [String] {
        MarkdownNoteReferenceParser.destinations(in: markdown).map(\.destination)
    }

    private static func collectFiles(
        under root: URL, fileManager: FileManager,
        noteURLs: inout [URL], attachmentURLsByPath: inout [String: URL],
        complete: inout Bool, cancellationCheck: @Sendable () -> Bool
    ) {
        var enumerationFailed = false
        guard let enumerator = fileManager.enumerator(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in enumerationFailed = true; return true }) else {
            complete = false; return
        }
        while let url = enumerator.nextObject() as? URL {
            if cancellationCheck() { complete = false; return }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                if url.pathComponents.contains(where: { $0.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) == .orderedSame }) {
                    attachmentURLsByPath[url.standardizedFileURL.path] = url.standardizedFileURL
                } else if noteExtensions.contains(url.pathExtension.lowercased()) { noteURLs.append(url.standardizedFileURL) }
            } catch { complete = false }
        }
        if enumerationFailed { complete = false }
    }

    private static func deduplicatedRoots(_ roots: [URL]) -> [URL] {
        let sorted = roots.map(\.standardizedFileURL).sorted {
            $0.path.count < $1.path.count
        }
        var retained: [URL] = []
        for root in sorted where !retained.contains(where: {
            root.path == $0.path || root.path.hasPrefix($0.path + "/")
        }) {
            retained.append(root)
        }
        return retained
    }

    private static func attachmentSort(
        _ lhs: LibraryAttachmentItem,
        _ rhs: LibraryAttachmentItem
    ) -> Bool {
        if lhs.state != rhs.state {
            return lhs.state.rawValue < rhs.state.rawValue
        }
        let nameOrder = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
    }
}
