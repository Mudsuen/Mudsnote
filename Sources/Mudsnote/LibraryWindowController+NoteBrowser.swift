import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func numberOfRows(in tableView: NSTableView) -> Int {
        listRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch listRows[row] {
        case .group(let title):
            let identifier = NSUserInterfaceItemIdentifier("LibraryGroupHeaderCell")
            let cell: LibraryGroupHeaderCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? LibraryGroupHeaderCellView {
                cell = reused
            } else {
                cell = LibraryGroupHeaderCellView()
                cell.identifier = identifier
            }
            cell.titleLabel.stringValue = title
            cell.isFirstGroup = row == 0
            return cell
        case .note(let note):
            return noteCell(for: note, tableView: tableView)
        }
    }

    func noteCell(for note: NoteSearchResult, tableView: NSTableView) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("LibraryNoteCell")
        let cell: LibraryNoteCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? LibraryNoteCellView {
            cell = reused
        } else {
            cell = LibraryNoteCellView()
            cell.identifier = identifier
        }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cell.titleLabel.attributedStringValue = highlightedSearchString(
            noteListDisplayTitle(for: note),
            font: cell.titleLabel.font ?? .systemFont(ofSize: LibraryNotesLayout.noteTitleFontSize, weight: .medium),
            baseColor: panelPrimaryTextColor(),
            query: query
        )
        cell.snippetLabel.attributedStringValue = highlightedSearchString(
            noteListSnippetText(for: note),
            font: cell.snippetLabel.font ?? .systemFont(ofSize: LibraryNotesLayout.noteSnippetFontSize),
            baseColor: panelSecondaryTextColor(),
            query: query
        )
        let thumbnailImage = thumbnailImage(for: note)
        cell.thumbnailImageView.image = thumbnailImage
        cell.thumbnailImageView.isHidden = thumbnailImage == nil
        cell.attachmentImageView.isHidden = !note.hasAttachments || thumbnailImage != nil
        cell.metaLabel.stringValue = noteListFolderText(for: note)
        return cell
    }

    func noteListDisplayTitle(for note: NoteSearchResult) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else { return title }
        let fallback = note.url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? LibraryCopy.newNote : fallback
    }

    func thumbnailImage(for note: NoteSearchResult) -> NSImage? {
        guard let thumbnailURL = note.thumbnailURL else {
            return nil
        }
        let key = thumbnailURL.standardizedFileURL.path
        if let cached = thumbnailImageCache.object(forKey: key as NSString) {
            return cached.image
        }

        guard hasRequestedWindowPresentation else {
            return decodeThumbnailImageSynchronously(at: thumbnailURL, key: key)
        }

        scheduleThumbnailImageLoad(at: thumbnailURL, key: key)
        return nil
    }

    func decodeThumbnailImageSynchronously(at url: URL, key: String) -> NSImage? {
        thumbnailImageDecodeCountForLibrary += 1
        let image = thumbnailDecoder(url).map {
            NSImage(cgImage: $0, size: NSSize(width: 44, height: 44))
        }
        cacheThumbnailImage(image, key: key)
        return image
    }

    func scheduleThumbnailImageLoad(at url: URL, key: String) {
        guard thumbnailImageLoadTasks[key] == nil else { return }

        thumbnailImageDecodeCountForLibrary += 1
        let thumbnailDecoder = thumbnailDecoder
        let task = Task.detached(priority: .utility) { [weak self] in
            let decoded = LibraryThumbnailDecodeResult(image: thumbnailDecoder(url))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled, let self else { return }
                self.thumbnailImageLoadTasks[key] = nil

                let image = decoded.image.map {
                    NSImage(cgImage: $0, size: NSSize(width: 44, height: 44))
                }
                self.cacheThumbnailImage(image, key: key)
                guard self.window?.isVisible == true else { return }
                self.scheduleThumbnailReload(for: key)
            }
        }
        thumbnailImageLoadTasks[key] = task
    }

    func rebuildThumbnailRowIndex() {
        var rowsByPath: [String: IndexSet] = [:]
        for (row, listRow) in listRows.enumerated() {
            guard let path = listRow.note?.thumbnailURL?.standardizedFileURL.path else { continue }
            rowsByPath[path, default: []].insert(row)
        }
        thumbnailRowsByPath = rowsByPath
    }

    func rebuildGalleryIndexes() {
        var itemsByPath: [String: Set<IndexPath>] = [:]
        var noteIndexPaths: [String: IndexPath] = [:]
        for (section, gallerySection) in gallerySections.enumerated() {
            for (item, note) in gallerySection.notes.enumerated() {
                let indexPath = IndexPath(item: item, section: section)
                let notePath = note.url.standardizedFileURL.path
                if noteIndexPaths[notePath] == nil { noteIndexPaths[notePath] = indexPath }
                guard let path = note.thumbnailURL?.standardizedFileURL.path else { continue }
                itemsByPath[path, default: []].insert(indexPath)
            }
        }
        galleryIndexPathsByNotePath = noteIndexPaths
        thumbnailItemsByPath = itemsByPath
    }

    func scheduleThumbnailReload(for path: String) {
        pendingThumbnailReloadPaths.insert(path)
        guard !thumbnailReloadScheduled else { return }
        thumbnailReloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingThumbnailReloads()
        }
    }

    func flushPendingThumbnailReloads() {
        guard thumbnailReloadScheduled else { return }
        thumbnailReloadScheduled = false
        let paths = pendingThumbnailReloadPaths
        pendingThumbnailReloadPaths.removeAll()
        guard window?.isVisible == true else { return }

        var matchingRows = IndexSet()
        var matchingItems = Set<IndexPath>()
        for path in paths {
            if let rows = thumbnailRowsByPath[path] {
                matchingRows.formUnion(rows)
            }
            if let items = thumbnailItemsByPath[path] {
                matchingItems.formUnion(items)
            }
        }

        guard !matchingRows.isEmpty || !matchingItems.isEmpty else { return }
        thumbnailReloadBatchCountForLibrary += 1
        if !matchingRows.isEmpty {
            tableView.reloadData(
                forRowIndexes: matchingRows,
                columnIndexes: IndexSet(integer: 0)
            )
        }
        if noteListViewMode == .gallery,
           hasRequestedWindowPresentation,
           !matchingItems.isEmpty {
            // Thumbnail completion changes pixels, not the collection's items.
            // Reloading a selected item recreates its view without its highlight.
            for indexPath in matchingItems {
                guard let item = galleryCollectionView.item(at: indexPath) as? LibraryGalleryItem,
                      let note = galleryNote(at: indexPath) else { continue }
                item.updateThumbnail(thumbnailImage(for: note))
            }
        }
    }

    func cacheThumbnailImage(_ image: NSImage?, key: String) {
        let pixelCost = image == nil ? 1 : 88 * 88 * 4
        thumbnailImageCache.setObject(
            LibraryThumbnailCacheEntry(image: image),
            forKey: key as NSString,
            cost: pixelCost
        )
    }

    nonisolated static func makeListThumbnailCGImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 88,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func waitForThumbnailLoadsForLibrary() async {
        let tasks = Array(thumbnailImageLoadTasks.values)
        for task in tasks {
            await task.value
        }
        flushPendingThumbnailReloads()
    }

    func highlightedSearchString(
        _ text: String,
        font: NSFont,
        baseColor: NSColor,
        query: String
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraphStyle
        ])
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !text.isEmpty else { return attributed }

        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let match = nsText.range(
                of: trimmedQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound, match.length > 0 else { break }

            attributed.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.34),
                .foregroundColor: panelPrimaryTextColor()
            ], range: match)

            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return attributed
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard listRows.indices.contains(row) else { return false }
        if case .group = listRows[row] {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        note(at: row) != nil
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let note = note(at: row) else { return nil }
        return note.url as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        draggingImageForRowsWith rowIndexes: IndexSet,
        tableColumns: [NSTableColumn],
        event: NSEvent,
        offset dragImageOffset: UnsafeMutablePointer<NSPoint>
    ) -> NSImage {
        if let image = noteDragPreviewImageForLibrary(rowIndexes: rowIndexes) {
            dragImageOffset.pointee = NSPoint(x: -18, y: 18)
            return image
        }

        return tableView.dragImageForRows(with: rowIndexes, tableColumns: tableColumns, event: event, offset: dragImageOffset)
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        session.draggingFormation = noteDragPreviewCountForLibrary(rowIndexes: rowIndexes) > 1 ? .pile : .default
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if note(at: row) == nil {
            return LibraryNotesLayout.noteGroupRowHeight
        }
        return LibraryNotesLayout.noteRowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LibraryNoteRowView()
        rowView.isGroupRow = note(at: row) == nil
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === tableView,
              !suppressSelectionChanges else { return }
        synchronizeGallerySelectionFromTable()
        handleNoteBrowserSelectionChange()
    }

    func handleNoteBrowserSelectionChange() {
        let previousURL = selectedURL
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            if preservesCurrentLoadedNoteForMultiSelection() {
                updateToolbarActionState()
            } else {
                loadSelectedRow()
            }
        } catch {
            restoreNoteBrowserSelection(to: previousURL)
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    func restoreNoteBrowserSelection(to url: URL?) {
        suppressSelectionChanges = true
        if let url,
           let row = rowIndex(for: url.standardizedFileURL.path) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        guard collectionView === galleryCollectionView else { return 0 }
        return gallerySections.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard collectionView === galleryCollectionView,
              gallerySections.indices.contains(section) else { return 0 }
        return gallerySections[section].notes.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: LibraryGalleryItem.identifier,
            for: indexPath
        )
        guard let galleryItem = item as? LibraryGalleryItem,
              let note = galleryNote(at: indexPath) else {
            return item
        }
        let rawPreview = note.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        galleryItem.configure(
            title: noteListDisplayTitle(for: note),
            preview: rawPreview.isEmpty ? LibraryCopy.noAdditionalText : rawPreview,
            date: noteListDateText(for: noteListDisplayDateForLibrary(note)),
            metadata: noteListFolderText(for: note),
            thumbnail: thumbnailImage(for: note)
        )
        return galleryItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> NSView {
        guard kind == NSCollectionView.elementKindSectionHeader,
              gallerySections.indices.contains(indexPath.section) else {
            return NSView()
        }
        let view = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: LibraryGallerySectionHeaderView.identifier,
            for: indexPath
        )
        if let header = view as? LibraryGallerySectionHeaderView {
            header.titleLabel.stringValue = gallerySections[indexPath.section].title ?? ""
        }
        return view
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> NSSize {
        guard gallerySections.indices.contains(section), gallerySections[section].title != nil else {
            return .zero
        }
        return NSSize(width: 1, height: LibraryNotesLayout.gallerySectionHeaderHeight)
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        handleGallerySelectionChange()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        handleGallerySelectionChange()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        galleryNote(at: indexPath)?.url as NSURL?
    }

    func galleryNote(at indexPath: IndexPath) -> NoteSearchResult? {
        guard gallerySections.indices.contains(indexPath.section),
              gallerySections[indexPath.section].notes.indices.contains(indexPath.item) else {
            return nil
        }
        return gallerySections[indexPath.section].notes[indexPath.item]
    }

    func galleryIndexPath(for standardizedPath: String) -> IndexPath? {
        galleryIndexPathsByNotePath[standardizedPath]
    }

    func reloadGalleryData() {
        guard noteListViewMode == .gallery else { return }
        gallerySections = LibraryGalleryProjection.sections(from: listRows)
        guard hasRequestedWindowPresentation else { return }
        galleryCollectionView.reloadData()
    }

    func reloadNoteBrowserData(
        animation: LibraryNoteMutationAnimation? = nil,
        previousRows: [LibraryNoteListRow] = [],
        refreshedNotePaths: Set<String> = []
    ) {
        let canAnimate = animation != nil
            && hasRequestedWindowPresentation
            && window?.isVisible == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let refreshPlan = LibraryNoteListMutationPlan(
            previousRows: previousRows,
            currentRows: listRows,
            refreshingNotePaths: refreshedNotePaths
        ) {
            tableView.beginUpdates()
            if !refreshPlan.removedRows.isEmpty {
                tableView.removeRows(at: refreshPlan.removedRows, withAnimation: [])
            }
            if !refreshPlan.insertedRows.isEmpty {
                tableView.insertRows(at: refreshPlan.insertedRows, withAnimation: [])
            }
            tableView.endUpdates()
        } else if canAnimate,
           let animation,
           let plan = LibraryNoteListMutationPlan(
               previousRows: previousRows,
               currentRows: listRows,
               animation: animation
           ) {
            tableView.beginUpdates()
            if !plan.removedRows.isEmpty {
                tableView.removeRows(at: plan.removedRows, withAnimation: [.effectFade, .slideUp])
            }
            if !plan.insertedRows.isEmpty {
                tableView.insertRows(at: plan.insertedRows, withAnimation: [.effectGap, .slideDown])
            }
            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }

        reloadGalleryData()
        if canAnimate, noteListViewMode == .gallery {
            galleryCollectionView.alphaValue = 0.72
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                galleryCollectionView.animator().alphaValue = 1
            }
        }
    }

    func synchronizeGallerySelectionFromTable() {
        guard noteListViewMode == .gallery, hasRequestedWindowPresentation else { return }
        let selectedPaths = Set(tableView.selectedRowIndexes.compactMap { row in
            note(at: row)?.url.standardizedFileURL.path
        })
        let indexPaths = Set(selectedPaths.compactMap(galleryIndexPath(for:)))
        suppressGallerySelectionChanges = true
        galleryCollectionView.selectionIndexPaths = indexPaths
        suppressGallerySelectionChanges = false
    }

    func synchronizeTableSelectionFromGallery() {
        let selectedPaths = Set(galleryCollectionView.selectionIndexPaths.compactMap { indexPath in
            galleryNote(at: indexPath)?.url.standardizedFileURL.path
        })
        let rows = IndexSet(listRows.indices.filter { row in
            guard let note = listRows[row].note else { return false }
            return selectedPaths.contains(note.url.standardizedFileURL.path)
        })
        suppressSelectionChanges = true
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        suppressSelectionChanges = false
    }

    func handleGallerySelectionChange() {
        guard !suppressGallerySelectionChanges else { return }
        synchronizeTableSelectionFromGallery()
        handleNoteBrowserSelectionChange()
    }

    func galleryContextMenuForLibrary(at indexPath: IndexPath) -> NSMenu? {
        synchronizeTableSelectionFromGallery()
        guard let row = rowIndex(for: galleryNote(at: indexPath)?.url.standardizedFileURL.path ?? "") else {
            return nil
        }
        return noteContextMenuForLibrary(row: row)
    }

    @objc
    func galleryDoubleClicked(_ sender: NSClickGestureRecognizer) {
        let location = sender.location(in: galleryCollectionView)
        guard let indexPath = galleryCollectionView.indexPathForItem(at: location) else { return }
        galleryCollectionView.selectionIndexPaths = [indexPath]
        synchronizeTableSelectionFromGallery()
        openSelectedGalleryNoteInList()
    }

    func handleGalleryKeyCommand(_ command: LibraryNoteKeyCommand) -> Bool {
        switch command {
        case .open:
            guard !galleryCollectionView.selectionIndexPaths.isEmpty else { return false }
            openSelectedGalleryNoteInList()
            return true
        case .delete:
            return handleNoteListKeyCommand(.delete)
        case .moveDown, .moveUp:
            return false
        }
    }

    func openSelectedGalleryNoteInList() {
        setNoteListViewModeForLibrary(.list)
        loadSelectedRow()
        editorTextView.window?.makeFirstResponder(editorTextView)
    }
}
