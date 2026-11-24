import AppKit
import Foundation
import MudsnoteCore

extension LibraryWindowController {
    func cancelNoteLinksRefresh() {
        noteLinksRefreshTask?.cancel()
        noteLinksRefreshTask = nil
        noteLinksRefreshGeneration += 1
    }

    func refreshNoteLinks(for noteURL: URL, body: String) {
        cancelNoteLinksRefresh()
        guard !noteLinksView.isSuppressed else {
            noteLinksView.update(.empty)
            return
        }
        let key = noteURL.standardizedFileURL
        if let cached = noteRelationsCache[key], cached.body == body {
            noteLinksView.update(cached.relations)
            return
        }
        noteLinksView.update(.empty)
        let generation = noteLinksRefreshGeneration
        let noteStore = noteStore
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }
            let relations = noteStore.linkRelations(
                for: noteURL,
                currentBody: body,
                roots: nil,
                cancellationCheck: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      generation == self.noteLinksRefreshGeneration,
                      self.selectedURL?.standardizedFileURL == noteURL.standardizedFileURL else {
                    return
                }
                self.noteLinksRefreshTask = nil
                if self.noteRelationsCache.count >= 24 { self.noteRelationsCache.removeAll() }
                self.noteRelationsCache[key] = (body, relations)
                self.noteLinksView.update(relations)
            }
        }
        noteLinksRefreshTask = task
    }

    func refreshNoteLinksAfterSave(
        for noteURL: URL,
        replacing previousURL: URL?,
        body: String
    ) {
        noteRelationsCache.removeValue(forKey: noteURL.standardizedFileURL)
        if let previousURL {
            noteRelationsCache.removeValue(forKey: previousURL.standardizedFileURL)
        }
        guard !noteLinksView.isSuppressed else { return }
        refreshNoteLinks(for: noteURL, body: body)
    }

    func openLinkedNote(at url: URL) {
        guard let currentURL = selectedURL?.standardizedFileURL,
              currentURL != url.standardizedFileURL else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        do {
            try openMarkdownDocumentForLibrary(at: url)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
        }
    }

    func setSelectedURLForLibrary(_ nextURL: URL?) {
        if nextURL == nil { unsavedDocumentID = UUID() }
        if selectedURL?.standardizedFileURL != nextURL?.standardizedFileURL {
            cancelNoteLinksRefresh()
            noteLinksView.update(.empty)
        }
        selectedURL = nextURL
    }
}
