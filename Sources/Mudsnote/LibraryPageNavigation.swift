import AppKit
import MudsnoteCore

struct LibraryPageState: Equatable {
    var overview: Bool
    var url: URL?
    var scope: LibraryScope
    var query: String
}

extension LibraryWindowController {
    var currentLibraryPage: LibraryPageState {
        let url = isShowingOverview
            ? overviewState?.cards.first(where: { $0.id == overviewView?.selectedID })?.url
            : selectedURL
        return LibraryPageState(overview: isShowingOverview, url: url, scope: selectedScope, query: searchField.stringValue)
    }

    @discardableResult func beginLibraryPageNavigation() -> Bool {
        guard commitOverviewEditor() else { return false }
        guard !isRestoringLibraryPage, hasRequestedWindowPresentation else { return true }
        let page = currentLibraryPage
        if pageBackStack.last != page { pageBackStack.append(page) }
        if pageBackStack.count > 100 { pageBackStack.removeFirst() }
        pageForwardStack.removeAll()
        window?.toolbar?.validateVisibleItems()
        return true
    }

    @objc func navigateLibraryBack() { restoreLibraryPage(back: true) }
    @objc func navigateLibraryForward() { restoreLibraryPage(back: false) }

    private func restoreLibraryPage(back: Bool) {
        guard let target = back ? pageBackStack.last : pageForwardStack.last,
              commitOverviewEditor() else { return }
        do {
            let loaded = try target.url.map { try noteLoader($0) }
            let current = currentLibraryPage
            isRestoringLibraryPage = true
            defer { isRestoringLibraryPage = false }
            cancelActiveNoteLoad()
            if target.overview {
                showOverview()
                guard isShowingOverview else { return }
                if let url = target.url, let loaded {
                    let note = sourceCountSnapshot.first(where: { $0.url == url })
                        ?? NoteSearchResult(url: url, title: loaded.title, snippet: loaded.body, modifiedAt: Date())
                    guard finishOpeningOverviewNote(note, loaded: loaded) else { return }
                }
            } else {
                guard leaveOverview() else { return }
                selectedScope = target.scope
                searchField.stringValue = target.query
                reloadNotes(selecting: target.url, loadFirstIfNeeded: false, refreshCounts: false)
                if let url = target.url, let loaded {
                    let note = sourceCountSnapshot.first(where: { $0.url == url })
                        ?? NoteSearchResult(url: url, title: loaded.title, snippet: loaded.body, modifiedAt: Date())
                    isLoadingInitialNote = false; isCreatingNewNote = false
                    applyLoadedNoteResult(.success(loaded), for: note)
                } else {
                    setSelectedURLForLibrary(nil); selectedSourceContents = nil
                    isCreatingNewNote = true; setEditorEditable(true)
                    applyDocument(title: "", body: "", tags: []); isDirty = false
                }
            }
            if back { pageBackStack.removeLast(); pageForwardStack.append(current) }
            else { pageForwardStack.removeLast(); pageBackStack.append(current) }
            updateToolbarActionState()
        } catch { presentErrorAlert(message: "无法返回笔记", details: error.localizedDescription) }
    }

    func remapLibraryPageHistory(from old: URL?, to new: URL) {
        guard let old, old != new else { return }
        for index in pageBackStack.indices where pageBackStack[index].url == old { pageBackStack[index].url = new }
        for index in pageForwardStack.indices where pageForwardStack[index].url == old { pageForwardStack[index].url = new }
    }
}
