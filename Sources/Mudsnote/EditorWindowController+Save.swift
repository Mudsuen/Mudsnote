import AppKit
import Foundation
import MudsnoteCore

extension EditorWindowController {

    @objc func savePressed() {
        let document = currentDocument()

        if document.title.isEmpty && document.body.isEmpty {
            noteStore.deleteDraft(id: currentDraftID)
            window?.close()
            return
        }

        do {
            let previousDraftID = currentDraftID
            let savedURL: URL

            if let fileURL {
                savedURL = try noteStore.updateNote(
                    at: fileURL,
                    title: document.title,
                    body: document.body,
                    tags: document.tags,
                    in: selectedDirectoryURL
                )
            } else {
                savedURL = try noteStore.saveNewNote(
                    title: document.title,
                    body: document.body,
                    tags: document.tags,
                    in: selectedDirectoryURL
                )
            }

            fileURL = savedURL
            selectedDirectoryURL = savedURL.deletingLastPathComponent()
            noteStore.deleteDraft(id: previousDraftID)
            noteStore.deleteDraft(id: currentDraftID)
            isDirty = false
            onSave(savedURL)
            window?.close()
        } catch {
            presentErrorAlert(message: "Failed to save note", details: error.localizedDescription)
        }
    }

    @objc func cancelPressed() {
        window?.close()
    }

    @objc func searchPressed() {
        onRequestSearch()
    }

    @objc func quickCaptureDirectoryPressed() {
        guard let directory = chooseDirectory(startingAt: selectedDirectoryURL)?.standardizedFileURL else { return }
        selectedDirectoryURL = directory
        isDirty = true
        refreshChrome()
        persistDraft(force: true)
    }

    func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}
