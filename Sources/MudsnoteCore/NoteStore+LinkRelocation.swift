import Foundation

private struct RelocatedNoteLinkWrite {
    let url: URL
    let original: String
    let replacement: String
}

enum NoteLinkRelocationError: LocalizedError {
    case changed(URL)
    case recovery(URL)
    case changedDestination(URL)

    var errorDescription: String? {
        switch self {
        case .changed(let url):
            return "笔记“\(url.deletingPathExtension().lastPathComponent)”已发生变化，移动或改名已取消。请重试。"
        case .recovery(let url):
            return "移动或改名未完成。已保留外部修改，原文备份位于：\(url.path)"
        case .changedDestination(let url):
            return "目标文件已被其他应用修改，已保留：\(url.path)"
        }
    }
}

extension NoteStore {
    /// Prepare references against the old paths, then commit the filesystem move last.
    /// The caller's source text may contain unsaved edits; only other notes are rewritten here.
    func withRelocatedNoteLinks(
        from source: URL,
        to destination: URL,
        isDirectory: Bool = false,
        sourceContents: String? = nil,
        expectedSourceContents: String? = nil,
        copiedAttachmentURLs: [URL] = [],
        commit: (String?) throws -> Void
    ) throws {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard source != destination else {
            try commit(sourceContents)
            return
        }

        let urls = try noteURLsForLinkRelocation(source: source, isDirectory: isDirectory)
        let paths = Set(urls.map(\.path))
        func movedURL(_ url: URL) -> URL {
            if url == source { return destination }
            if isDirectory, url.path.hasPrefix(source.path + "/") {
                return URL(fileURLWithPath: destination.path + url.path.dropFirst(source.path.count))
            }
            return url
        }

        var writes: [RelocatedNoteLinkWrite] = []
        var relocatedSource = sourceContents
        let copiedAttachmentPaths = Set(copiedAttachmentURLs.map { $0.standardizedFileURL.path })
        for url in urls {
            if !isDirectory, url == source {
                if let contents = sourceContents {
                    relocatedSource = rewritingRelocatedNoteLinks(
                        contents, source: url, destination: destination,
                        knownPaths: paths, copiedAttachmentPaths: copiedAttachmentPaths, movedURL: movedURL
                    )
                }
                continue
            }
            let original = try String(contentsOf: url, encoding: .utf8)
            let replacement = rewritingRelocatedNoteLinks(
                original, source: url, destination: movedURL(url),
                knownPaths: paths, movedURL: movedURL
            )
            if original != replacement {
                writes.append(RelocatedNoteLinkWrite(url: url, original: original, replacement: replacement))
            }
        }

        // Keep durable originals until all reference writes and the move have succeeded.
        // A failed rollback never overwrites a new external edit.
        let recoveryURL = try stageLinkRelocationRecovery(writes)
        var applied: [RelocatedNoteLinkWrite] = []
        do {
            for write in writes {
                try replaceNoteLinks(at: write.url, expecting: write.original, with: write.replacement)
                applied.append(write)
                try updateNoteCommitHook?(.afterReferenceWrite)
            }
            for write in writes {
                guard try String(contentsOf: write.url, encoding: .utf8) == write.replacement else {
                    throw NoteLinkRelocationError.changed(write.url)
                }
            }
            if let expectedSourceContents,
               try String(contentsOf: source, encoding: .utf8) != expectedSourceContents {
                throw NoteLinkRelocationError.changed(source)
            }
            try commit(relocatedSource)
        } catch {
            var rollbackFailed = false
            for write in applied.reversed() {
                do {
                    try replaceNoteLinks(at: write.url, expecting: write.replacement, with: write.original)
                } catch {
                    rollbackFailed = true
                }
            }
            markSearchIndexDirty(at: writes.map(\.url))
            if rollbackFailed, let recoveryURL {
                throw NoteLinkRelocationError.recovery(recoveryURL)
            }
            if let recoveryURL { try? fileManager.removeItem(at: recoveryURL) }
            throw error
        }
        markSearchIndexDirty(at: writes.map { movedURL($0.url) } + writes.map(\.url))
        if let recoveryURL { try? fileManager.removeItem(at: recoveryURL) }
    }

    private func noteURLsForLinkRelocation(source: URL, isDirectory: Bool) throws -> [URL] {
        // External standalone files do not grant access to unrelated library roots.
        // In particular an isolated store with no configured root must not enumerate user notes.
        let configured = preferredDirectories.map(\.standardizedFileURL).filter { root in
            defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory) != nil
                || root != notesDirectory.standardizedFileURL
                || source == root || source.path.hasPrefix(root.path + "/")
        }
        let belongsToLibrary = configured.contains { source == $0 || source.path.hasPrefix($0.path + "/") }
        var roots = belongsToLibrary ? configured : [isDirectory ? source : source.deletingLastPathComponent()]
        if isDirectory { roots.append(source) }
        roots = deduplicatedDirectories(roots).sorted { $0.path.count < $1.path.count }
        var visitedRoots: [URL] = []
        var urls = Set<URL>()
        if !isDirectory { urls.insert(source) }
        for root in roots {
            if visitedRoots.contains(where: { root == $0 || root.path.hasPrefix($0.path + "/") }) { continue }
            guard fileManager.fileExists(atPath: root.path) else { continue }
            visitedRoots.append(root)
            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in enumerationError = error; return false }
            ) else { throw CocoaError(.fileReadUnknown) }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true,
                      ["md", "markdown"].contains(url.pathExtension.lowercased()) else { continue }
                urls.insert(url.standardizedFileURL)
            }
            if let enumerationError { throw enumerationError }
        }
        return urls.sorted { $0.path < $1.path }
    }

    private func rewritingRelocatedNoteLinks(
        _ contents: String,
        source: URL,
        destination: URL,
        knownPaths: Set<String>,
        copiedAttachmentPaths: Set<String> = [],
        movedURL: (URL) -> URL
    ) -> String {
        let result = NSMutableString(string: contents)
        for reference in MarkdownNoteReferenceParser.references(in: contents).reversed() {
            let raw = reference.destination
            let separator = raw.firstIndex(where: { $0 == "#" || $0 == "?" }) ?? raw.endIndex
            let rawPath = String(raw[..<separator])
            let suffix = String(raw[separator...])
            guard !rawPath.isEmpty else { continue } // Same-document anchors survive a move unchanged.
            let decoded = rawPath.removingPercentEncoding ?? rawPath
            let target: URL?
            switch reference.kind {
            case .markdown:
                target = MarkdownLocalLinkResolver.fileURL(for: rawPath, relativeTo: source)
            case .wiki:
                target = relocatedWikiTarget(decoded, source: source, knownPaths: knownPaths)
            }
            guard let target else { continue }
            // Only destinations actually copied by the attachment pass are already relative
            // to the new note. Other Markdown attachments still need their original target.
            if reference.kind == .markdown,
               source.deletingLastPathComponent() != destination.deletingLastPathComponent(),
               !rawPath.hasPrefix("/"), !rawPath.hasPrefix("~/"), URL(string: rawPath)?.scheme == nil,
               let copiedTarget = MarkdownLocalLinkResolver.fileURL(for: rawPath, relativeTo: destination),
               copiedAttachmentPaths.contains(copiedTarget.standardizedFileURL.path) {
                continue
            }
            let relocatedTarget = movedURL(target)
            guard source != destination || target != relocatedTarget else { continue }

            let replacementPath: String
            if rawPath.hasPrefix("file:") {
                replacementPath = relocatedTarget.absoluteString
            } else if rawPath.hasPrefix("/") || rawPath.hasPrefix("~/") {
                replacementPath = encodedNoteLinkPath(relocatedTarget.path)
            } else {
                replacementPath = encodedNoteLinkPath(relativeNoteLinkPath(
                    from: destination.deletingLastPathComponent(), to: relocatedTarget
                ))
            }
            result.replaceCharacters(in: reference.destinationRange, with: replacementPath + suffix)
        }
        return result as String
    }

    private func relocatedWikiTarget(_ path: String, source: URL, knownPaths: Set<String>) -> URL? {
        guard URL(string: path)?.scheme == nil, !path.hasPrefix("~/") else { return nil }
        let suffixes = ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
            ? [path] : [path + ".md", path + ".markdown"]
        for suffix in suffixes {
            let direct = suffix.hasPrefix("/") ? URL(fileURLWithPath: suffix)
                : source.deletingLastPathComponent().appendingPathComponent(suffix)
            if knownPaths.contains(direct.standardizedFileURL.path) { return direct.standardizedFileURL }
        }
        let matches = knownPaths.filter { candidate in
            suffixes.contains { candidate.hasSuffix("/" + $0) }
        }
        if matches.count == 1, let match = matches.first { return URL(fileURLWithPath: match) }
        let pathURL = URL(fileURLWithPath: path)
        let basename = (["md", "markdown"].contains(pathURL.pathExtension.lowercased())
            ? pathURL.deletingPathExtension().lastPathComponent : pathURL.lastPathComponent).lowercased()
        let basenameMatches = knownPaths.filter {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased() == basename
        }
        guard basenameMatches.count == 1, let match = basenameMatches.first else { return nil }
        return URL(fileURLWithPath: match)
    }

    private func relativeNoteLinkPath(from directory: URL, to target: URL) -> String {
        let base = directory.standardizedFileURL.pathComponents
        let target = target.standardizedFileURL.pathComponents
        var common = 0
        while common < min(base.count, target.count), base[common] == target[common] { common += 1 }
        return (Array(repeating: "..", count: base.count - common) + target.dropFirst(common)).joined(separator: "/")
    }

    private func encodedNoteLinkPath(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private func replaceNoteLinks(at url: URL, expecting original: String, with replacement: String) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinatedURL in
            result = Result {
                guard try String(contentsOf: coordinatedURL, encoding: .utf8) == original else {
                    throw NoteLinkRelocationError.changed(url)
                }
                try replacement.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private func stageLinkRelocationRecovery(_ writes: [RelocatedNoteLinkWrite]) throws -> URL? {
        guard !writes.isEmpty else { return nil }
        let directory = appSupportDirectory.appendingPathComponent("Recovery/LinkUpdates/\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var paths: [String: String] = [:]
            for (index, write) in writes.enumerated() {
                let name = "\(index).md"
                try write.original.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
                paths[name] = write.url.path
            }
            try JSONEncoder().encode(paths).write(to: directory.appendingPathComponent("paths.json"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        return directory
    }
}
