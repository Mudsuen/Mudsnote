import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func applyDocument(
        title: String,
        body: String,
        tags: [String],
        renderedBody: NSAttributedString? = nil,
        preservedSelection: NSRange? = nil
    ) {
        editorMetricsRefreshTask?.cancel()
        editorMetricsRefreshTask = nil
        editorSearchHighlightRefreshTask?.cancel()
        editorSearchHighlightRefreshTask = nil
        suppressEditorChanges = true
        isEditorShowingMarkdownSource = false
        editorTextView.isRichText = true
        editorTextView.markdownPasteTheme = theme
        titleField.stringValue = title
        selectedTags = tags
        let unifiedMarkdown = MarkdownEditorDocument.composeEditorText(
            title: title,
            body: body,
            hasMetadataTags: !tags.isEmpty
        )
        editorTextView.replaceAllContent(with:
            renderedBody ?? MarkdownRichTextCodec.render(
                markdown: unifiedMarkdown,
                theme: theme,
                baseURL: selectedURL,
                imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
            )
        )
        markLoadedUnifiedTitleFormatting()
        editorTextView.setMetadataTags(tags) { [weak self] tag in
            self?.removeSelectedMetadataTag(tag)
        }
        editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
        let requestedSelection = preservedSelection ?? NSRange(location: 0, length: 0)
        let contentLength = editorTextView.textStorage?.length ?? 0
        let location = min(requestedSelection.location, contentLength)
        let length = min(requestedSelection.length, max(contentLength - location, 0))
        editorTextView.setSelectedRange(NSRange(location: location, length: length))
        suppressEditorChanges = false
        updateWordCount()
        layoutEditorStatusLabel()
    }

    func updateWordCount() {
        updateWordCount(in: visibleEditorMetadata().body)
    }

    func updateWordCount(in body: String) {
        let count = MarkdownEditorDocument.wordCount(in: body)
        wordCountLabel.stringValue = "\(count) 字"
        wordCountLabel.setAccessibilityValue(wordCountLabel.stringValue)
    }

    func visibleEditorMetadata() -> (title: String, body: String) {
        let visibleText = editorTextView.string
        if isEditorShowingMarkdownSource {
            let document = MarkdownEditorDocument.parse(
                editorText: visibleText,
                tags: selectedTags
            )
            return (document.title, document.body)
        }

        let text = visibleText as NSString
        guard text.length > 0 else { return ("", "") }
        let titleParagraph = text.paragraphRange(for: NSRange(location: 0, length: 0))
        let title = text.substring(with: titleParagraph)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyStart = NSMaxRange(titleParagraph)
        let body = bodyStart < text.length ? text.substring(from: bodyStart) : ""
        return (title, body)
    }

    func normalizedEditorMarkdownBody() -> String {
        normalizedMarkdownBody(currentEditorMarkdownBody())
    }

    func replaceUnifiedEditorTitle(_ title: String) {
        let document = currentEditorDocument()
        let markdown = MarkdownEditorDocument.composeEditorText(
            title: title,
            body: document.body,
            hasMetadataTags: !selectedTags.isEmpty
        )
        let selection = editorTextView.selectedRange()
        suppressEditorChanges = true
        editorTextView.replaceAllContent(with:
            MarkdownRichTextCodec.render(
                markdown: markdown,
                theme: theme,
                baseURL: selectedURL,
                imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
            )
        )
        markLoadedUnifiedTitleFormatting()
        editorTextView.setMetadataTags(selectedTags) { [weak self] tag in
            self?.removeSelectedMetadataTag(tag)
        }
        suppressEditorChanges = false
        let contentLength = editorTextView.textStorage?.length ?? 0
        editorTextView.setSelectedRange(NSRange(location: min(selection.location, contentLength), length: 0))
    }

    func markLoadedUnifiedTitleFormatting() {
        guard let storage = editorTextView.textStorage, storage.length > 0 else { return }
        let first = (storage.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        storage.addAttribute(.qmAutomaticTitleBaseline,
                             value: theme.baseAttributes(for: .paragraph), range: first)
    }

    func normalizeUnifiedTitleLineFormatting() {
        guard !suppressEditorChanges,
              !isEditorShowingMarkdownSource,
              let storage = editorTextView.textStorage else {
            return
        }
        guard storage.length > 0 else {
            editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
            return
        }

        let firstParagraph = (storage.string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        // Only demote formatting that was applied because this text was the
        // document title. Explicit headings elsewhere have no such marker.
        let bodyRange = NSRange(location: NSMaxRange(firstParagraph),
                                length: storage.length - NSMaxRange(firstParagraph))
        var demotions: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttribute(.qmAutomaticTitleBaseline, in: bodyRange) { value, range, _ in
            if let baseline = value as? [NSAttributedString.Key: Any] {
                demotions.append((range, baseline))
            }
        }
        if !demotions.isEmpty {
            storage.beginEditing()
            for (range, baseline) in demotions {
                storage.addAttributes(baseline, range: range)
                storage.removeAttribute(.qmAutomaticTitleBaseline, range: range)
                storage.removeAttribute(.qmMetadataTagReserve, range: range)
            }
            storage.endEditing()
        }
        let hasTrailingNewline = (storage.string as NSString)
            .substring(with: firstParagraph)
            .hasSuffix("\n")
        let titleRange = NSRange(
            location: 0,
            length: max(firstParagraph.length - (hasTrailingNewline ? 1 : 0), 0)
        )
        guard titleRange.length > 0 else { return }

        var headingAttributes = theme.baseAttributes(for: .heading(level: 1))
        let reserve = storage.attribute(.qmMetadataTagReserve, at: 0, effectiveRange: nil) as? CGFloat ?? 0
        if reserve > 0,
           let style = (headingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.paragraphSpacing += reserve
            headingAttributes[.paragraphStyle] = style
        }
        var changedRanges: [NSRange] = []
        storage.enumerateAttributes(in: titleRange) { attributes, range, _ in
            if headingAttributes.contains(where: { key, value in
                guard let existing = attributes[key] as? NSObject else { return true }
                return !existing.isEqual(value)
            }) {
                changedRanges.append(range)
            }
        }
        guard !changedRanges.isEmpty else { return }
        suppressEditorChanges = true
        storage.beginEditing()
        for range in changedRanges {
            if storage.attribute(.qmAutomaticTitleBaseline, at: range.location, effectiveRange: nil) == nil {
                let attributes = storage.attributes(at: range.location, effectiveRange: nil)
                var baseline = theme.baseAttributes(for: .paragraph)
                for key in headingAttributes.keys {
                    if let value = attributes[key] { baseline[key] = value }
                }
                storage.addAttribute(.qmAutomaticTitleBaseline, value: baseline, range: range)
            }
            storage.addAttributes(headingAttributes, range: range)
        }
        storage.endEditing()
        suppressEditorChanges = false
    }

    func normalizedMarkdownBody(_ body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cachedLoadedNote(for note: NoteSearchResult) -> LoadedLibraryNoteCacheEntry? {
        loadedNoteCache.entry(forKey: loadedNoteCacheKey(for: note.url))
    }

    @discardableResult
    func cacheLoadedNote(
        _ loaded: LoadedLibraryNote,
        for note: NoteSearchResult,
        fileModifiedAt: Date? = nil
    ) -> LoadedLibraryNoteCacheEntry {
        let modifiedAt = fileModifiedAt ?? note.modifiedAt
        let cached = LoadedLibraryNoteCacheEntry(
            loaded: loaded,
            fileModifiedAt: modifiedAt
        )
        loadedNoteCache.insert(cached, forKey: loadedNoteCacheKey(for: note.url))
        let noteStore = noteStore
        let noteURL = note.url
        let createdAt = note.createdAt
        launchNoteCacheQueue.async {
            noteStore.cacheLibraryLaunchNote(
                loaded,
                at: noteURL,
                modifiedAt: modifiedAt,
                createdAt: createdAt
            )
        }
        return cached
    }

    func scheduleCachedNoteValidation(
        _ cached: LoadedLibraryNoteCacheEntry,
        for note: NoteSearchResult
    ) {
        let generation = noteLoadGeneration
        let editorRevision = editorContentRevision
        let fileModificationDateLoader = fileModificationDateLoader
        let noteLoader = noteLoader
        let cachedModifiedAt = cached.fileModifiedAt
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let currentModifiedAt = fileModificationDateLoader(note.url),
                  !Task.isCancelled else {
                await MainActor.run {
                    guard let self, generation == self.noteLoadGeneration else { return }
                    self.noteLoadTask = nil
                }
                return
            }

            guard abs(currentModifiedAt.timeIntervalSince(cachedModifiedAt)) >= 0.001 else {
                await MainActor.run {
                    guard let self, generation == self.noteLoadGeneration else { return }
                    self.noteLoadTask = nil
                }
                return
            }

            let result = Result<LoadedLibraryNote, Error> {
                try noteLoader(note.url)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      generation == self.noteLoadGeneration,
                      editorRevision == self.editorContentRevision,
                      self.selectedNoteStillMatchesInitialLoad(note) else {
                    return
                }
                self.noteLoadTask = nil
                self.loadedNoteCache.removeEntry(forKey: self.loadedNoteCacheKey(for: note.url))
                guard !self.isDirty else { return }
                switch result {
                case .success(let loaded):
                    let refreshed = self.cacheLoadedNote(
                        loaded,
                        for: note,
                        fileModifiedAt: currentModifiedAt
                    )
                    self.applyLoadedNote(refreshed, for: note, preservingEditorSelection: true)
                case .failure(let error):
                    self.presentErrorAlert(message: "无法刷新笔记", details: error.localizedDescription)
                }
            }
        }
        noteLoadTask = task
    }

    func prefetchAdjacentNotes(around note: NoteSearchResult) {
        guard let index = notes.firstIndex(where: {
            $0.url.standardizedFileURL.path == note.url.standardizedFileURL.path
        }) else { return }

        let lowerBound = max(0, index - 2)
        let upperBound = min(notes.count, index + 3)
        let candidates = notes[lowerBound..<upperBound].filter {
            $0.url.standardizedFileURL.path != note.url.standardizedFileURL.path
                && loadedNoteCache.entry(forKey: loadedNoteCacheKey(for: $0.url)) == nil
        }
        guard !candidates.isEmpty else { return }

        let noteStore = noteStore
        let cache = loadedNoteCache
        notePrefetchTask?.cancel()
        let task = Task.detached(priority: .utility) {
            for candidate in candidates {
                guard !Task.isCancelled else { return }
                let key = candidate.url.standardizedFileURL.path as NSString
                guard cache.entry(forKey: key) == nil,
                      let loaded = try? noteStore.loadNoteDocument(at: candidate.url) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                let modifiedAt = Self.fileModificationDate(at: candidate.url) ?? candidate.modifiedAt
                cache.insert(
                    LoadedLibraryNoteCacheEntry(loaded: loaded, fileModifiedAt: modifiedAt),
                    forKey: key
                )
            }
        }
        notePrefetchTask = task
    }

    func loadedNoteCacheKey(for url: URL) -> NSString {
        url.path as NSString
    }

    nonisolated static func fileModificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    func fileModificationDate(at url: URL) -> Date? {
        Self.fileModificationDate(at: url)
    }

    func hasCachedLoadedNoteForLibrary(at url: URL) -> Bool {
        loadedNoteCache.entry(forKey: loadedNoteCacheKey(for: url)) != nil
    }

    func waitForActiveNoteLoadForLibrary() async {
        let task = noteLoadTask
        await task?.value
    }

    var hasReleasedDeferredLaunchWorkForLibrary: Bool {
        hasReleasedDeferredLaunchWork
    }

    func waitForNoteLinksRefreshForLibrary() async {
        let task = noteLinksRefreshTask
        await task?.value
    }

    func applyEditorSearchHighlightsForCurrentQuery() {
        applyEditorSearchHighlights(query: searchField.stringValue)
    }

    func applyEditorSearchHighlights(query: String) {
        guard let storage = editorTextView.textStorage else { return }
        let wasSuppressingEditorChanges = suppressEditorChanges
        suppressEditorChanges = true
        defer { suppressEditorChanges = wasSuppressingEditorChanges }

        removeEditorSearchHighlights()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, storage.length > 0 else { return }

        let nsText = storage.string as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        var foundMatch = false
        while searchRange.location < nsText.length {
            let match = nsText.range(
                of: trimmedQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound, match.length > 0 else { break }

            storage.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.30),
                .qmSearchHighlight: true
            ], range: match)
            foundMatch = true

            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        hasEditorSearchHighlights = foundMatch
    }

    func removeEditorSearchHighlights() {
        guard hasEditorSearchHighlights else { return }
        guard let storage = editorTextView.textStorage, storage.length > 0 else {
            hasEditorSearchHighlights = false
            return
        }
        editorSearchHighlightRemovalScanCount += 1
        let wasSuppressingEditorChanges = suppressEditorChanges
        suppressEditorChanges = true
        defer { suppressEditorChanges = wasSuppressingEditorChanges }

        let fullRange = NSRange(location: 0, length: storage.length)
        var highlightedRanges: [NSRange] = []
        storage.enumerateAttribute(.qmSearchHighlight, in: fullRange, options: []) { value, range, _ in
            if value != nil {
                highlightedRanges.append(range)
            }
        }
        for range in highlightedRanges {
            storage.removeAttribute(.qmSearchHighlight, range: range)
            var location = range.location
            while location < NSMaxRange(range) {
                var effectiveRange = NSRange(location: 0, length: 0)
                let isDocumentHighlight = (storage.attribute(
                    .qmHighlight,
                    at: location,
                    effectiveRange: &effectiveRange
                ) as? Bool) == true
                let clippedRange = NSIntersectionRange(range, effectiveRange)
                if isDocumentHighlight {
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor.systemYellow.withAlphaComponent(0.38),
                        range: clippedRange
                    )
                } else {
                    storage.removeAttribute(.backgroundColor, range: clippedRange)
                }
                location = NSMaxRange(clippedRange)
            }
        }
        hasEditorSearchHighlights = false
    }

    var editorSearchHighlightRemovalScanCountForLibrary: Int {
        editorSearchHighlightRemovalScanCount
    }
}
