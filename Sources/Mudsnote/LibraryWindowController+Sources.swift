import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func rebuildSourceRows(includeTags: Bool) {
        sourceTreeNeedsScopeRebuild = false
        let wasSynchronizingSelection = isSynchronizingSourceOutlineSelection
        let wasRestoringExpansion = isRestoringSourceOutlineExpansion
        isSynchronizingSourceOutlineSelection = true
        isRestoringSourceOutlineExpansion = true
        defer {
            isSynchronizingSourceOutlineSelection = wasSynchronizingSelection
            isRestoringSourceOutlineExpansion = wasRestoringExpansion
        }
        if !includeTags {
            sourceTagNames = []
        }

        sourceOutlineItemsByIdentifier.removeAll(keepingCapacity: true)
        sourceOutlineItemsByScopeIdentifier.removeAll(keepingCapacity: true)
        var roots: [LibrarySourceOutlineItem] = []

        let smartGroup = makeSourceOutlineItem(
            identifier: "group:mudsnote",
            kind: .group(title: "Mudsnote", section: nil)
        )
        smartGroup.append(makeSourceOutlineScopeItem(.recent))
        smartGroup.append(makeSourceOutlineScopeItem(.favorites))
        smartGroup.append(makeSourceOutlineScopeItem(.all))
        let previewFolders = externalPreviewFolderURLs()
        let filesGroup = makeSourceOutlineItem(
            identifier: "group:files",
            kind: .group(title: "FILES", section: .folders)
        )
        for folderRoot in makeSourceFolderOutlineRoots() {
            filesGroup.append(folderRoot)
        }
        for previewFolder in previewFolders where !sourceFolderTreeRows.contains(where: {
            $0.url.standardizedFileURL.path == previewFolder.standardizedFileURL.path
        }) {
            filesGroup.append(makeSourceOutlineScopeItem(.folder(previewFolder)))
        }
        if inlineFolderEditOperation == nil {
            if !sourceFoldersLoaded && sourceFolderTreeRows.isEmpty {
                filesGroup.append(makeSourceOutlineItem(
                    identifier: "status:folders:loading",
                    kind: .status(LibraryCopy.loadingFolders)
                ))
            } else if sourceFolderTreeRows.isEmpty {
                filesGroup.append(makeSourceOutlineItem(
                    identifier: "status:folders:empty",
                    kind: .status(LibraryCopy.noFolders)
                ))
            }
        }
        filesGroup.append(makeSourceOutlineScopeItem(.trash))
        roots.append(filesGroup)

        let tagsGroup = makeSourceOutlineItem(
            identifier: "group:tags",
            kind: .group(title: LibraryCopy.tags, section: .tags)
        )
        for tag in sourceTagNames {
            tagsGroup.append(makeSourceOutlineScopeItem(.tag(tag)))
        }
        roots.append(tagsGroup)

        sourceOutlineRootItems = roots
        sourceOutlineView.reloadData()
        restoreSourceOutlineExpansion()
        if hasLoadedSourceCounts {
            refreshSourceCounts(using: sourceCountSnapshot)
        }
        refreshSourceSelection()
        focusInlineFolderEditField()
    }

    func makeSourceOutlineItem(
        identifier: String,
        kind: LibrarySourceOutlineItem.Kind
    ) -> LibrarySourceOutlineItem {
        let item = LibrarySourceOutlineItem(identifier: identifier, kind: kind)
        sourceOutlineItemsByIdentifier[identifier] = item
        if let scope = item.scope {
            sourceOutlineItemsByScopeIdentifier[sourceOutlineIdentifier(for: scope)] = item
        }
        return item
    }

    func makeSourceOutlineScopeItem(_ scope: LibraryScope) -> LibrarySourceOutlineItem {
        makeSourceOutlineItem(
            identifier: sourceOutlineIdentifier(for: scope),
            kind: .scope(scope)
        )
    }

    func makeSourceOutlineNoteItem(_ note: NoteSearchResult) -> LibrarySourceOutlineItem {
        makeSourceOutlineItem(
            identifier: "note:\(note.url.standardizedFileURL.path)",
            kind: .note(note)
        )
    }

    func sourceOutlineIdentifier(for scope: LibraryScope) -> String {
        switch scope {
        case .all:
            return "scope:all"
        case .recent:
            return "scope:recent"
        case .favorites:
            return "scope:favorites"
        case .inbox:
            return "scope:inbox"
        case .folder(let url):
            return "scope:folder:\(url.standardizedFileURL.path)"
        case .tag(let tag):
            return "scope:tag:\(tag.folding(options: [.caseInsensitive], locale: .current))"
        case .trash:
            return "scope:trash"
        }
    }

    func makeSourceFolderOutlineRoots() -> [LibrarySourceOutlineItem] {
        var roots: [LibrarySourceOutlineItem] = []
        var ancestors: [LibrarySourceOutlineItem] = []

        for folderRow in sourceFolderTreeRows {
            while ancestors.count > folderRow.depth {
                ancestors.removeLast()
            }

            let folderPath = folderRow.url.standardizedFileURL.path
            let item: LibrarySourceOutlineItem
            if case .rename(let folderURL) = inlineFolderEditOperation,
               folderURL.standardizedFileURL.path == folderPath {
                item = makeSourceOutlineItem(
                    identifier: "inline:rename:\(folderPath)",
                    kind: .inlineFolderEdit(.rename(folderURL: folderRow.url))
                )
            } else {
                item = makeSourceOutlineScopeItem(.folder(folderRow.url))
            }

            if let parent = ancestors.last {
                parent.append(item)
            } else {
                roots.append(item)
            }
            ancestors.append(item)
        }

        let treeNotes: [NoteSearchResult]
        switch selectedScope {
        case .recent:
            treeNotes = recentNoteResults(limit: 80, allNotes: sourceCountSnapshot)
        case .favorites:
            let pinnedPaths = Set(noteStore.libraryPinnedNotePaths)
            treeNotes = sourceCountSnapshot.filter {
                pinnedPaths.contains($0.url.standardizedFileURL.path)
            }
        default:
            treeNotes = sourceCountSnapshot
        }
        let notesByParentPath = Dictionary(grouping: treeNotes) {
            $0.url.deletingLastPathComponent().standardizedFileURL.path
        }
        for folderRow in sourceFolderTreeRows.reversed() {
            let folderPath = folderRow.url.standardizedFileURL.path
            guard let folderItem = sourceOutlineItemsByScopeIdentifier[
                sourceOutlineIdentifier(for: .folder(folderRow.url))
            ] else { continue }
            let directNotes = (notesByParentPath[folderPath] ?? []).sorted {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                return titleOrder == .orderedSame
                    ? $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                    : titleOrder == .orderedAscending
            }
            for note in directNotes {
                folderItem.append(makeSourceOutlineNoteItem(note))
            }
        }

        if case .create(let parentURL) = inlineFolderEditOperation {
            let editItem = makeSourceOutlineItem(
                identifier: "inline:create:\(parentURL.standardizedFileURL.path)",
                kind: .inlineFolderEdit(.create(parentURL: parentURL))
            )
            if let parent = sourceOutlineItemsByScopeIdentifier[sourceOutlineIdentifier(for: .folder(parentURL))] {
                parent.children.insert(editItem, at: 0)
                editItem.parent = parent
            } else {
                roots.insert(editItem, at: 0)
            }
        }

        return roots
    }

    func externalPreviewFolderURLs() -> [URL] {
        var seenPaths = Set<String>()
        return externallyOpenedDocumentsByPath.values
            .map { $0.url.deletingLastPathComponent().standardizedFileURL }
            .filter { seenPaths.insert($0.path).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func restoreSourceOutlineExpansion() {
        let wasRestoringExpansion = isRestoringSourceOutlineExpansion
        isRestoringSourceOutlineExpansion = true
        defer { isRestoringSourceOutlineExpansion = wasRestoringExpansion }
        if let smartGroup = sourceOutlineItemsByIdentifier["group:mudsnote"] {
            sourceOutlineView.expandItem(smartGroup, expandChildren: false)
        }
        if !sourceFoldersSectionCollapsed,
           let filesGroup = sourceOutlineItemsByIdentifier["group:files"] {
            sourceOutlineView.expandItem(filesGroup, expandChildren: false)
        }
        if !sourceTagsSectionCollapsed,
           let tagsGroup = sourceOutlineItemsByIdentifier["group:tags"] {
            sourceOutlineView.expandItem(tagsGroup, expandChildren: false)
        }
        for folderRow in sourceFolderTreeRows {
            let path = folderRow.url.standardizedFileURL.path
            guard let item = sourceOutlineItemsByScopeIdentifier[
                    sourceOutlineIdentifier(for: .folder(folderRow.url))
                  ] ?? sourceOutlineItemsByIdentifier["inline:rename:\(path)"],
                  !item.children.isEmpty,
                  isSourceFolderExpanded(path: path, depth: folderRow.depth) else {
                continue
            }
            sourceOutlineView.expandItem(item, expandChildren: false)
        }
        if let editItem = sourceOutlineItemsByIdentifier.values.first(where: {
            if case .inlineFolderEdit = $0.kind { return true }
            return false
        }) {
            var parent = editItem.parent
            while let current = parent {
                sourceOutlineView.expandItem(current, expandChildren: false)
                parent = current.parent
            }
        }
    }

    func isSourceSectionCollapsed(_ section: LibrarySourceSection) -> Bool {
        switch section {
        case .folders:
            return sourceFoldersSectionCollapsed
        case .tags:
            return sourceTagsSectionCollapsed
        }
    }

    func scheduleDeferredSourceFolderLoad() {
        sourceFolderLoadGeneration += 1
        let generation = sourceFolderLoadGeneration
        guard !sourceFoldersSectionCollapsed,
              !sourceFoldersLoaded,
              !sourceFoldersLoading else { return }
        sourceFoldersLoading = true
        let preferredDirectories = noteStore.preferredDirectories
        let folderOrderPaths = noteStore.libraryFolderOrderPaths
        let collapsedPaths = collapsedFolderPaths
        let expandedPaths = expandedFolderPaths
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let treeRows = Self.folderTreeRowsForSourceList(
                from: preferredDirectories,
                orderedPaths: folderOrderPaths
            )
            let rows = Self.visibleFolderRowsForSourceList(
                from: treeRows,
                collapsedFolderPaths: collapsedPaths,
                expandedFolderPaths: expandedPaths
            )
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.sourceFolderLoadGeneration else {
                    self.sourceFoldersLoading = false
                    self.scheduleDeferredSourceFolderLoad()
                    return
                }
                self.sourceFoldersLoaded = true
                self.sourceFoldersLoading = false
                self.sourceFolderTreeRows = treeRows
                self.sourceFolderRows = rows
                self.rebuildSourceRows(includeTags: self.sourceTagsLoaded)
                self.reloadNotesForNavigation(selecting: self.selectedURL, loadFirstIfNeeded: false)
            }
        }
    }

    func loadSourceFoldersForLibrary() {
        reloadSourceFolderRowsForCurrentState()
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    func scheduleDeferredSourceTagLoad(forEditor: Bool = false) {
        guard forEditor || !sourceTagsSectionCollapsed,
              !sourceTagsLoaded,
              !sourceTagsLoading else { return }
        sourceTagsLoading = true
        sourceTagLoadGeneration += 1
        let generation = sourceTagLoadGeneration
        let noteStore = noteStore
        let preferredDirectories = noteStore.preferredDirectories
        DispatchQueue.global(qos: .utility).async { [weak self] in
            noteStore.prewarmSearchIndex(roots: preferredDirectories)
            let tags = noteStore.knownTags(limit: .max, roots: preferredDirectories)
            DispatchQueue.main.async {
                guard let self,
                      generation == self.sourceTagLoadGeneration else { return }
                self.sourceTagsLoading = false
                self.applySourceTagsForLibrary(tags)
                if self.editorTagSuggestion != nil { self.updateEditorSlashSuggestions() }
            }
        }
    }

    func applyCachedSourceTags(from notes: [NoteSearchResult]) {
        let tags = Self.mostFrequentTags(in: notes, limit: .max)
        guard !tags.isEmpty else { return }
        sourceTagLoadGeneration += 1
        sourceTagsLoading = false
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
    }

    func applySourceTagsFromValidatedSnapshot(_ notes: [NoteSearchResult]) {
        let tags = Self.mostFrequentTags(in: notes, limit: .max)
        guard tags != sourceTagNames || !sourceTagsLoaded else { return }
        sourceTagLoadGeneration += 1
        sourceTagsLoading = false
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
    }

    static func mostFrequentTags(
        in notes: [NoteSearchResult],
        limit: Int
    ) -> [String] {
        var tagCounts: [String: (displayName: String, count: Int)] = [:]
        for tag in notes.flatMap(\.tags) {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive], locale: .current)
            let previous = tagCounts[key]
            tagCounts[key] = (previous?.displayName ?? trimmed, (previous?.count ?? 0) + 1)
        }
        return tagCounts.values
            .sorted {
                $0.count == $1.count
                    ? $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    : $0.count > $1.count
            }
            .prefix(limit)
            .map(\.displayName)
    }

    func loadSourceTagsForLibrary() {
        guard !sourceTagsLoaded, !sourceTagsLoading else { return }
        applySourceTagsForLibrary(noteStore.knownTags(limit: .max, roots: noteStore.preferredDirectories))
    }

    func applySourceTagsForLibrary(_ tags: [String]) {
        guard !sourceTagsLoaded else { return }
        sourceTagsLoaded = true
        sourceTagNames = tags
        rebuildSourceRows(includeTags: true)
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    func invalidateSourceTagsForLibrary() {
        sourceTagLoadGeneration += 1
        sourceTagsLoaded = false
        sourceTagsLoading = false
        sourceTagNames = []
    }

    func reloadSourceFolderRowsForCurrentState() {
        sourceFoldersLoaded = true
        sourceFoldersLoading = false
        applySourceFolderTreeRows(Self.folderTreeRowsForSourceList(
            from: noteStore.preferredDirectories,
            orderedPaths: noteStore.libraryFolderOrderPaths
        ))
    }

    func applySourceFolderTreeRows(_ treeRows: [LibraryFolderRow]) {
        sourceFolderLoadGeneration += 1
        sourceFoldersLoaded = true
        sourceFoldersLoading = false
        sourceFolderTreeRows = treeRows
        sourceFolderRows = Self.visibleFolderRowsForSourceList(
            from: sourceFolderTreeRows,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
        rebuildSourceRows(includeTags: sourceTagsLoaded)
    }

    func projectSourceFolderTreeRows(_ treeRows: [LibraryFolderRow]) {
        guard !sourceFoldersLoaded else {
            applySourceFolderTreeRows(treeRows)
            return
        }

        let wasLoading = sourceFoldersLoading
        sourceFolderLoadGeneration += 1
        sourceFolderTreeRows = treeRows
        sourceFolderRows = Self.visibleFolderRowsForSourceList(
            from: sourceFolderTreeRows,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        if !wasLoading {
            sourceFoldersLoading = false
            scheduleDeferredSourceFolderLoad()
        }
    }

    func rootFolderRowsForSourceList() -> [LibraryFolderRow] {
        Self.rootFolderRowsForSourceList(
            from: noteStore.preferredDirectories,
            orderedPaths: noteStore.libraryFolderOrderPaths
        )
    }

    nonisolated static func rootFolderRowsForSourceList(
        from directories: [URL],
        orderedPaths: [String] = []
    ) -> [LibraryFolderRow] {
        sortedFolderURLs(rootPreferredDirectories(from: directories), orderedPaths: orderedPaths).map {
            LibraryFolderRow(url: $0, depth: 0, hasChildren: false)
        }
    }

    nonisolated static func folderTreeRowsForSourceList(
        from directories: [URL],
        orderedPaths: [String] = []
    ) -> [LibraryFolderRow] {
        let preferredRoots = sortedFolderURLs(
            rootPreferredDirectories(from: directories),
            orderedPaths: orderedPaths
        )
        var seenPaths = Set<String>()
        var rows: [LibraryFolderRow] = []

        for root in preferredRoots {
            appendFolderTreeRows(
                root,
                depth: 0,
                maxDepth: 3,
                orderedPaths: orderedPaths,
                seenPaths: &seenPaths,
                rows: &rows
            )
        }

        return rows
    }

    nonisolated static func visibleFolderRowsForSourceList(
        from treeRows: [LibraryFolderRow],
        collapsedFolderPaths: Set<String>,
        expandedFolderPaths: Set<String>
    ) -> [LibraryFolderRow] {
        var hiddenDescendantDepth: Int?
        var visibleRows: [LibraryFolderRow] = []

        for row in treeRows {
            if let hiddenDepth = hiddenDescendantDepth {
                if row.depth > hiddenDepth {
                    continue
                }
                hiddenDescendantDepth = nil
            }

            visibleRows.append(row)
            if !isSourceFolderExpanded(
                path: row.url.standardizedFileURL.path,
                depth: row.depth,
                collapsedFolderPaths: collapsedFolderPaths,
                expandedFolderPaths: expandedFolderPaths
            ) {
                hiddenDescendantDepth = row.depth
            }
        }

        return visibleRows
    }

    nonisolated static func rootPreferredDirectories(from directories: [URL]) -> [URL] {
        let standardized = directories.map(\.standardizedFileURL)
        return standardized.filter { candidate in
            !standardized.contains { other in
                other != candidate && candidate.path.hasPrefix(other.path + "/")
            }
        }
    }

    nonisolated static func appendFolderTreeRows(
        _ folderURL: URL,
        depth: Int,
        maxDepth: Int,
        orderedPaths: [String],
        seenPaths: inout Set<String>,
        rows: inout [LibraryFolderRow]
    ) {
        let standardized = folderURL.standardizedFileURL
        guard seenPaths.insert(standardized.path).inserted else { return }
        let children = sortedFolderURLs(childFolderURLs(of: standardized), orderedPaths: orderedPaths)
        rows.append(LibraryFolderRow(url: standardized, depth: depth, hasChildren: !children.isEmpty))
        guard depth < maxDepth else { return }

        for child in children {
            appendFolderTreeRows(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                orderedPaths: orderedPaths,
                seenPaths: &seenPaths,
                rows: &rows
            )
        }
    }

    nonisolated static func sortedFolderURLs(_ urls: [URL], orderedPaths: [String]) -> [URL] {
        let ranks = Dictionary(uniqueKeysWithValues: orderedPaths.enumerated().map { ($0.element, $0.offset) })
        return urls.sorted { lhs, rhs in
            let lhsRank = ranks[lhs.standardizedFileURL.path]
            let rhsRank = ranks[rhs.standardizedFileURL.path]
            if let lhsRank, let rhsRank, lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhsRank != nil { return true }
            if rhsRank != nil { return false }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    func isSourceFolderExpanded(path: String, depth: Int) -> Bool {
        Self.isSourceFolderExpanded(
            path: path,
            depth: depth,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
    }

    nonisolated static func isSourceFolderExpanded(
        path: String,
        depth: Int,
        collapsedFolderPaths: Set<String>,
        expandedFolderPaths: Set<String>
    ) -> Bool {
        if depth == 0 {
            return !collapsedFolderPaths.contains(path)
        }
        return expandedFolderPaths.contains(path)
    }

    nonisolated static func childFolderURLs(of folderURL: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        return children.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isDirectory == true
                && values.isHidden != true
                && url.lastPathComponent.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) != .orderedSame
        }
        .sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    func sourceTitle(for scope: LibraryScope) -> String {
        switch scope {
        case .folder(let url):
            return folderTitle(for: url)
        default:
            return scope.buttonTitle
        }
    }

    func noteListTitle(for scope: LibraryScope) -> String {
        switch scope {
        case .tag(let tag):
            return libraryDisplayTag(tag)
        default:
            return sourceTitle(for: scope)
        }
    }

    func folderTitle(for url: URL) -> String {
        let standardizedURL = url.standardizedFileURL
        return standardizedURL.lastPathComponent.isEmpty ? LibraryCopy.notes : standardizedURL.lastPathComponent
    }

    func refreshSourceSelection() {
        let selectedNoteItem = isShowingSidebarTree ? selectedTreeNoteURL.flatMap {
            sourceOutlineItemsByIdentifier["note:\($0.standardizedFileURL.path)"]
        } : nil
        guard let item = selectedNoteItem
            ?? sourceOutlineItemsByScopeIdentifier[sourceOutlineIdentifier(for: selectedScope)] else {
            return
        }
        let row = sourceOutlineView.row(forItem: item)
        guard row >= 0 else { return }
        let wasSynchronizingSelection = isSynchronizingSourceOutlineSelection
        isSynchronizingSourceOutlineSelection = true
        sourceOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isSynchronizingSourceOutlineSelection = wasSynchronizingSelection
        refreshVisibleSourceOutlinePresentation()
    }

    func refreshVisibleSourceOutlinePresentation() {
        updateSidebarScopeButton()
        let visibleRows = sourceOutlineView.rows(in: sourceOutlineView.visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
            guard let item = sourceOutlineView.item(atRow: row) as? LibrarySourceOutlineItem,
                  let cell = sourceOutlineView.view(
                    atColumn: 0,
                    row: row,
                    makeIfNecessary: false
                  ) as? LibrarySourceOutlineCellView else {
                continue
            }
            configureSourceOutlineCell(cell, for: item)
        }
    }

    func sourceTitlesForLibrary() -> [String] {
        sourceOutlineItemsByScopeIdentifier.values.compactMap { item in
            item.scope.map(sourceTitle(for:))
        }
    }

    func sourceTreeNoteTitlesForLibrary() -> [String] {
        sourceOutlineItemsByIdentifier.values.compactMap { item in
            item.note.map { $0.title }
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func sourceIconNameForLibrary(titled title: String) -> String? {
        guard let scope = sourceOutlineItemsByScopeIdentifier.values.compactMap(\.scope).first(where: {
            sourceTitle(for: $0).localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else {
            return nil
        }
        return sourceSymbolName(for: scope)
    }

    var selectedSourceTitleForLibrary: String {
        sourceTitle(for: selectedScope)
    }

    func visibleSourceTitlesForLibrary() -> [String] {
        (0..<sourceOutlineView.numberOfRows).compactMap { row in
            guard let item = sourceOutlineView.item(atRow: row) as? LibrarySourceOutlineItem,
                  let scope = item.scope else { return nil }
            return sourceTitle(for: scope)
        }
    }

    func sourceFolderURLsForLibrary() -> [URL] {
        var seenPaths = Set<String>()
        return (sourceFolderTreeRows.map(\.url) + externalPreviewFolderURLs()).filter {
            seenPaths.insert($0.standardizedFileURL.path).inserted
        }
    }

    var editorSlashSuggestionTitlesForLibrary: [String] {
        if let editorTagSuggestion { return editorTagSuggestion.items.map { "#\($0)" } }
        if let editorNoteSuggestion {
            return editorNoteSuggestion.items.map(\.title)
        }
        return editorSlashSuggestion?.commands.map(\.title) ?? []
    }

    func waitForEditorNoteSuggestionsForTesting() async {
        await editorNoteSuggestionTask?.value
    }

    func acceptEditorSlashSuggestionForLibrary(at index: Int) {
        acceptEditorSlashSuggestion(at: index)
    }

    @discardableResult
    func importExternalLibraryItemForTesting(_ sourceURL: URL, to targetDirectory: URL) throws -> URL {
        try importExternalLibraryItem(sourceURL, to: targetDirectory)
    }

    @discardableResult
    func selectSourceForLibrary(titled title: String) -> Bool {
        guard let item = sourceOutlineItemsByScopeIdentifier.values.first(where: {
            guard let scope = $0.scope else { return false }
            return sourceTitle(for: scope).localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else { return false }
        var parent = item.parent
        while let current = parent {
            sourceOutlineView.expandItem(current, expandChildren: false)
            parent = current.parent
        }
        let row = sourceOutlineView.row(forItem: item)
        guard row >= 0 else { return false }
        let scope = item.scope
        let previousScope = selectedScope
        sourceOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if let scope, selectedScope != scope || selectedScope == previousScope {
            guard activateSourceScope(scope) else { return false }
        }
        sourceOutlineView.scrollRowToVisible(row)
        sourceOutlineView.window?.makeFirstResponder(sourceOutlineView)
        return true
    }

    @discardableResult
    func setSourceFolderExpandedForLibrary(_ folderURL: URL, expanded: Bool) -> Bool {
        guard let item = sourceOutlineItemsByScopeIdentifier[
            sourceOutlineIdentifier(for: .folder(folderURL))
        ], !item.children.isEmpty else { return false }
        if expanded {
            sourceOutlineView.expandItem(item, expandChildren: false)
        } else {
            sourceOutlineView.collapseItem(item, collapseChildren: true)
        }
        return true
    }

    func isSourceFolderExpandedForLibrary(_ folderURL: URL) -> Bool {
        guard let item = sourceOutlineItemsByScopeIdentifier[
            sourceOutlineIdentifier(for: .folder(folderURL))
        ] else { return false }
        return sourceOutlineView.isItemExpanded(item)
    }

    func sourceCountTextForLibrary(titled title: String) -> String? {
        guard let item = sourceOutlineItemsByScopeIdentifier.values.first(where: {
            guard let scope = $0.scope else { return false }
            return sourceTitle(for: scope).localizedCaseInsensitiveCompare(title) == .orderedSame
        }), let scope = item.scope else { return nil }
        return sourceCountText(item.count, for: scope)
    }

    func toggleSourceTagsSectionForLibrary() {
        toggleSourceSection(.tags)
    }

    func toggleSourceFoldersSectionForLibrary() {
        toggleSourceSection(.folders)
    }

    func sourceOutlineLevelForLibrary(titled title: String) -> Int? {
        guard let item = sourceOutlineItemsByScopeIdentifier.values.first(where: {
            guard let scope = $0.scope else { return false }
            return sourceTitle(for: scope).localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else { return nil }
        var level = 0
        var parent = item.parent
        while parent != nil {
            level += 1
            parent = parent?.parent
        }
        return level
    }

    func isSourceGroupExpandedForLibrary(titled title: String) -> Bool? {
        guard let item = sourceOutlineItemsByIdentifier.values.first(where: {
            guard case .group(let groupTitle, _) = $0.kind else { return false }
            return groupTitle.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) else { return nil }
        return sourceOutlineView.isItemExpanded(item)
    }

    var sourceOutlineInstantiatedCellCountForLibrary: Int {
        let visibleRows = sourceOutlineView.rows(in: sourceOutlineView.visibleRect)
        guard visibleRows.location != NSNotFound else { return 0 }
        return (visibleRows.location..<(visibleRows.location + visibleRows.length)).reduce(into: 0) {
            count, row in
            if sourceOutlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                is LibrarySourceOutlineCellView {
                count += 1
            }
        }
    }

    func currentSourceFolderPaths() -> Set<String> {
        Set(
            sourceFolderRows.map { $0.url.standardizedFileURL.path }
                + externalPreviewFolderURLs().map(\.path)
        )
    }

    func inboxDirectoryForCurrentSourceSnapshot() -> URL {
        if let sourceInboxDirectory {
            return sourceInboxDirectory
        }
        let candidates = noteStore.preferredDirectories + sourceFolderTreeRows.map(\.url)
        if let inbox = candidates.enumerated().min(by: { lhs, rhs in
            let lhsRank = Self.inboxDirectoryRank(lhs.element.lastPathComponent)
            let rhsRank = Self.inboxDirectoryRank(rhs.element.lastPathComponent)
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }), Self.inboxDirectoryRank(inbox.element.lastPathComponent) < Int.max {
            return inbox.element.standardizedFileURL
        }
        return noteStore.notesDirectory
            .appendingPathComponent("Inbox", isDirectory: true)
            .standardizedFileURL
    }

    nonisolated static func inboxDirectoryRank(_ name: String) -> Int {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "inbox" { return 0 }
        if normalized.hasSuffix("-inbox")
            || normalized.hasSuffix("_inbox")
            || normalized.hasSuffix(" inbox") {
            return 1
        }
        return Int.max
    }

    func refreshSourceCounts(
        using allNotes: [NoteSearchResult],
        countIndex precomputedCountIndex: LibrarySourceCountIndex? = nil,
        recentCount _: Int? = nil
    ) {
        let recentCount = min(allNotes.count, 80)
        let countIndex = precomputedCountIndex ?? LibrarySourceCountIndex(
            notes: allNotes,
            folderPaths: currentSourceFolderPaths(),
            inboxDirectory: inboxDirectoryForCurrentSourceSnapshot()
        )
        applySourceCounts(
            allNotesCount: allNotes.count,
            recentCount: recentCount,
            trashCount: trashedNotesSnapshot.count,
            countIndex: countIndex
        )
    }

    func scheduleSourceCountRefresh(using allNotes: [NoteSearchResult]) {
        sourceCountRefreshTask?.cancel()
        sourceCountRefreshGeneration += 1
        let generation = sourceCountRefreshGeneration
        let folderPaths = currentSourceFolderPaths()
        let trashCount = trashedNotesSnapshot.count
        let noteStore = noteStore
        let willLoad = backgroundSourceCountWillLoad

        sourceCountRefreshTask = Task.detached(priority: .utility) { [weak self] in
            willLoad()
            let inboxDirectory = noteStore.preferredInboxDirectory
            let recentCount = min(allNotes.count, 80)
            let countIndex = LibrarySourceCountIndex(
                notes: allNotes,
                folderPaths: folderPaths,
                inboxDirectory: inboxDirectory
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      generation == self.sourceCountRefreshGeneration,
                      folderPaths == self.currentSourceFolderPaths() else { return }
                self.sourceCountRefreshTask = nil
                self.sourceInboxDirectory = inboxDirectory
                self.applySourceCounts(
                    allNotesCount: allNotes.count,
                    recentCount: recentCount,
                    trashCount: trashCount,
                    countIndex: countIndex
                )
            }
        }
    }

    func applySourceCounts(
        allNotesCount: Int,
        recentCount: Int,
        trashCount: Int,
        countIndex: LibrarySourceCountIndex
    ) {
        hasLoadedSourceCounts = true
        // Reading shared pins loads a JSON file. Read once per batch, never once per note.
        let pinnedPaths = Set(noteStore.libraryPinnedNotePaths)
        for item in sourceOutlineItemsByScopeIdentifier.values {
            guard let scope = item.scope else { continue }
            let count: Int
            switch scope {
            case .all:
                count = allNotesCount
            case .recent:
                count = recentCount
            case .favorites:
                count = sourceCountSnapshot.lazy.filter {
                    pinnedPaths.contains($0.url.standardizedFileURL.path)
                }.count
            case .inbox:
                count = countIndex.inboxCount
            case .trash:
                count = trashCount
            case .folder(let url):
                count = countIndex.count(
                    forFolder: url,
                    includingDescendants: noteStore.libraryIncludesSubfolderNotes
                )
            case .tag(let tag):
                count = countIndex.count(forTag: tag)
            }
            item.count = count
        }
        refreshVisibleSourceOutlinePresentation()
    }

    func sourceCountText(_ count: Int?, for scope: LibraryScope) -> String {
        guard let count else { return "" }
        switch scope {
        case .folder:
            return String(count)
        default:
            return count > 0 ? String(count) : ""
        }
    }
}
