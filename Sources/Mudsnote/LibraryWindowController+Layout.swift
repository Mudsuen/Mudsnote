import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    var isSourceListVisibleForLibrary: Bool {
        if let sourceSplitViewItem {
            return !sourceSplitViewItem.isCollapsed
        }
        return sourceListView?.isHidden == false
    }

    var storedSourceColumnWidthForLibrary: CGFloat {
        LibraryNotesLayout.clampedSourceColumnWidth(
            CGFloat(noteStore.librarySourceColumnWidth ?? Double(LibraryNotesLayout.sourceColumnWidth))
        )
    }

    func applyStoredLibrarySplitLayoutForLibrary() {
        guard let splitView = librarySplitView,
              splitView.arrangedSubviews.count == 2,
              splitView.bounds.width > 0 else {
            return
        }

        isApplyingStoredSplitLayout = true
        defer { isApplyingStoredSplitLayout = false }

        let sourceList = splitView.arrangedSubviews[0]
        sourceSplitViewItem?.isCollapsed = !noteStore.librarySourceListVisible
        splitView.adjustSubviews()

        if !sourceList.isHidden {
            splitView.setPosition(storedSourceColumnWidthForLibrary, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
        }
    }

    func persistLibrarySplitLayoutForLibrary() {
        guard !isApplyingStoredSplitLayout,
              let splitView = librarySplitView,
              splitView.arrangedSubviews.count == 2 else {
            return
        }

        let sourceList = splitView.arrangedSubviews[0]
        if !sourceList.isHidden, sourceList.frame.width > 0 {
            noteStore.librarySourceColumnWidth = Double(
                LibraryNotesLayout.clampedSourceColumnWidth(sourceList.frame.width)
            )
        }
    }

    @objc
    func librarySplitViewDidResize(_ notification: Notification) {
        guard let resizedSplitView = notification.object as? NSSplitView,
              resizedSplitView === librarySplitView,
              !isApplyingStoredSplitLayout,
              window?.isVisible == true else {
            return
        }
        splitLayoutPersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.splitLayoutPersistenceWorkItem = nil
            self?.persistLibrarySplitLayoutForLibrary()
        }
        splitLayoutPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(160), execute: workItem)
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view === splitView.arrangedSubviews.last
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0:
            return LibraryNotesLayout.sourceColumnMinimumWidth
        default:
            return proposedMinimumPosition
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let editorLimit = splitView.bounds.width
            - LibraryNotesLayout.editorColumnMinimumWidth
            - splitView.dividerThickness
        switch dividerIndex {
        case 0:
            return min(LibraryNotesLayout.sourceColumnMaximumWidth, editorLimit)
        default:
            return proposedMaximumPosition
        }
    }

    @discardableResult
    func toggleSourceListForLibrary() -> Bool {
        setSourceListVisibleForLibrary(!isSourceListVisibleForLibrary)
    }

    @discardableResult
    func setSourceListVisibleForLibrary(_ isVisible: Bool) -> Bool {
        setSourceListVisibleForLibrary(isVisible, animated: false)
    }

    @discardableResult
    func setSourceListVisibleForLibrary(_ isVisible: Bool, animated: Bool) -> Bool {
        guard let sourceListView else { return false }
        guard isSourceListVisibleForLibrary != isVisible else { return isVisible }
        noteStore.librarySourceListVisible = isVisible
        applySourceVisibilityChrome(isVisible)
        if let sourceSplitViewItem {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = LibraryNotesLayout.sourceCollapseAnimationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    sourceSplitViewItem.animator().isCollapsed = !isVisible
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.restoreStoredPaneWidthsAfterSourceVisibilityChange()
                        self?.updateToolbarActionState()
                    }
                }
            } else {
                sourceSplitViewItem.isCollapsed = !isVisible
                restoreStoredPaneWidthsAfterSourceVisibilityChange()
            }
        } else {
            sourceListView.isHidden = !isVisible
        }
        updateToolbarActionState()
        return isSourceListVisibleForLibrary
    }

    func applySourceVisibilityChrome(_ isVisible: Bool) {
        for item in window?.toolbar?.items ?? []
        where item.itemIdentifier == Self.sourceTrackingSeparatorToolbarItemIdentifier {
            item.isHidden = !isVisible
        }
    }

    func restoreStoredPaneWidthsAfterSourceVisibilityChange() {
        guard let splitView = librarySplitView,
              splitView.arrangedSubviews.count == 2 else { return }
        isApplyingStoredSplitLayout = true
        defer { isApplyingStoredSplitLayout = false }
        splitView.adjustSubviews()
        if !splitView.arrangedSubviews[0].isHidden {
            splitView.setPosition(storedSourceColumnWidthForLibrary, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
        }
    }

    func setNoteListViewModeForLibrary(_ mode: LibraryNoteViewMode) {
        guard noteListViewMode != mode else {
            if mode == .gallery {
                window?.makeFirstResponder(galleryCollectionView)
            }
            return
        }

        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return
        }

        noteListViewMode = mode
        noteStore.libraryNoteViewModeRawValue = mode.rawValue
        applyNoteListViewModeChrome(animated: window?.isVisible == true)
    }

    func applyNoteListViewModeChrome(animated: Bool) {
        guard let editorStackView, let galleryScrollView else { return }
        let showsGallery = noteListViewMode == .gallery

        if showsGallery {
            reloadGalleryData()
            synchronizeGallerySelectionFromTable()
            galleryScrollView.isHidden = false
            galleryScrollView.alphaValue = 1
            editorStackView.isHidden = true
        } else {
            editorStackView.isHidden = false
            editorStackView.alphaValue = 1
            galleryScrollView.isHidden = true
        }
        updateNoteListEmptyState(query: searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))

        completeNoteListViewModeTransition(showingGallery: showsGallery)
    }

    func completeNoteListViewModeTransition(showingGallery: Bool) {
        if !showingGallery {
            applyStoredLibrarySplitLayoutForLibrary()
        }
        if showingGallery {
            window?.makeFirstResponder(galleryCollectionView)
        } else if selectedURL == nil {
            window?.makeFirstResponder(tableView)
        } else {
            window?.makeFirstResponder(editorTextView)
        }
    }

    static func externalScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0
        }
    }
}
