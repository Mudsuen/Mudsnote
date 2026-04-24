import Foundation

extension NoteStore {
    public func knownSearchRoots() -> [URL] {
        let recentDirectories = listRecentFiles(limit: 50).map { $0.url.deletingLastPathComponent() }
        return deduplicatedDirectories(preferredDirectories + recentDirectories)
    }

    public func knownTags(limit: Int = 200) -> [String] {
        let roots = knownSearchRoots()
        var counts: [String: Int] = [:]

        for root in roots {
            for fileURL in markdownFiles(in: root) {
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                for tag in parseStoredDocument(text).tags {
                    counts[tag, default: 0] += 1
                }
            }
        }

        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(limit)
            .map(\.key)
    }

    public func searchNotes(query: String, limit: Int = 30, roots: [URL]? = nil) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return listRecentFiles(limit: limit).map { note in
                let snippet = (try? loadNote(at: note.url).body).flatMap(firstMeaningfulLine(from:)) ?? ""
                let tags = (try? loadNote(at: note.url).tags) ?? []
                return NoteSearchResult(url: note.url, title: note.title, snippet: snippet, modifiedAt: note.modifiedAt, tags: tags)
            }
        }

        let loweredQuery = trimmedQuery.lowercased()
        let searchRoots = roots ?? knownSearchRoots()
        var seenPaths = Set<String>()
        var scoredResults: [(result: NoteSearchResult, score: Int)] = []

        for root in searchRoots {
            for fileURL in markdownFiles(in: root) {
                let standardizedPath = fileURL.standardizedFileURL.path
                guard seenPaths.insert(standardizedPath).inserted else { continue }
                guard let scored = scoredMatch(for: fileURL, loweredQuery: loweredQuery) else { continue }
                scoredResults.append(scored)
            }
        }

        return scoredResults
            .sorted {
                if $0.score == $1.score {
                    return $0.result.modifiedAt > $1.result.modifiedAt
                }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map(\.result)
    }

    private func scoredMatch(for fileURL: URL, loweredQuery: String) -> (result: NoteSearchResult, score: Int)? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modifiedAt = attrs[.modificationDate] as? Date,
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let note = (try? loadNote(at: fileURL)) ?? (
            title: fileURL.deletingPathExtension().lastPathComponent,
            body: text,
            tags: []
        )

        let titleLower = note.title.lowercased()
        let bodyLower = note.body.lowercased()
        let tagsLower = note.tags.map { $0.lowercased() }
        guard titleLower.contains(loweredQuery) || bodyLower.contains(loweredQuery) || tagsLower.contains(where: { $0.contains(loweredQuery) }) else {
            return nil
        }

        let titleScore = titleLower.contains(loweredQuery) ? 100 : 0
        let occurrences = max(bodyLower.components(separatedBy: loweredQuery).count - 1, 0)
        let bodyScore = min(occurrences * 15, 90)
        let tagScore = tagsLower.contains(where: { $0 == loweredQuery }) ? 80 : (tagsLower.contains(where: { $0.contains(loweredQuery) }) ? 40 : 0)
        let snippet = snippet(from: note.body, query: loweredQuery)

        return (
            result: NoteSearchResult(
                url: fileURL,
                title: note.title,
                snippet: snippet,
                modifiedAt: modifiedAt,
                tags: note.tags
            ),
            score: titleScore + bodyScore + tagScore
        )
    }

    private func snippet(from body: String, query: String) -> String {
        let lines = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let match = lines.first(where: { $0.lowercased().contains(query) }) {
            return match
        }

        return lines.first ?? ""
    }

    private func firstMeaningfulLine(from body: String) -> String? {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}
