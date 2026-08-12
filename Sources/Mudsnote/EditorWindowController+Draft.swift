import AppKit
import Foundation
import MudsnoteCore

extension EditorWindowController {

    func markDocumentDirty() {
        guard !suppressAutosave else { return }
        draftContentRevision &+= 1
        isDirty = true
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistDraftInBackground()
            }
        }
    }

    func persistDraft(force: Bool) throws {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        guard isDirty || force else { return }

        draftPersistenceGeneration &+= 1
        try draftPersistenceCoordinator.flush(currentDraftPersistenceAction())
        isDirty = false
    }

    private func persistDraftInBackground() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        guard isDirty else { return }

        let revision = draftContentRevision
        draftPersistenceGeneration &+= 1
        let generation = draftPersistenceGeneration
        let action = currentDraftPersistenceAction()
        draftPersistenceCoordinator.enqueue(action) { [weak self] result in
            guard let self,
                  self.draftContentRevision == revision,
                  self.draftPersistenceGeneration == generation else {
                return
            }
            switch result {
            case .success:
                self.isDirty = false
            case .failure(let error):
                self.handleDraftPersistenceFailure(error)
            }
        }
    }

    func flushPendingDraftAutosaveForTesting() async {
        persistDraftInBackground()
        draftPersistenceCoordinator.waitUntilIdle()
        await Task.yield()
    }

    private func currentDraftPersistenceAction() -> DraftPersistenceAction {
        let document = currentDocument()
        guard !document.title.isEmpty || !document.body.isEmpty else {
            return .delete(currentDraftID)
        }
        return .save(DraftSnapshot(
            id: currentDraftID,
            sourcePath: activeFloatingNoteURL?.path ?? fileURL?.path,
            selectedDirectoryPath: selectedDirectoryURL.path,
            title: document.title,
            body: document.body,
            tags: document.tags,
            updatedAt: Date()
        ))
    }

    @discardableResult
    func prepareForApplicationTermination() -> Bool {
        do {
            try persistDraft(force: false)
            return true
        } catch {
            handleDraftPersistenceFailure(error)
            return false
        }
    }

    private func handleDraftPersistenceFailure(_ error: Error) {
        statusLabel.stringValue = "草稿保存失败，当前编辑仍保留"
        NSSound.beep()
        if let draftPersistenceErrorHandler {
            draftPersistenceErrorHandler(error)
        } else {
            presentErrorAlert(
                message: "无法保存草稿",
                details: "窗口保持打开，当前编辑没有被丢弃。\n\n\(error.localizedDescription)"
            )
        }
    }

    func currentDocument() -> MarkdownEditorDocument {
        if isQuickCaptureMode {
            return QuickCaptureDocumentState(
                title: "",
                bodyMarkdown: serializedBodyMarkdown()
            ).document
        }
        let markdown = serializedBodyMarkdown()
        return MarkdownEditorDocument.parse(editorText: markdown, tags: mergedDocumentTags(from: markdown))
    }

    func currentQuickCaptureTitleValue() -> String {
        QuickCaptureDocumentState.derivedTitle(from: serializedBodyMarkdown())
    }

    func serializedBodyMarkdown() -> String {
        guard let storage = editorTextView.textStorage else { return "" }
        return MarkdownRichTextCodec.serialize(storage, theme: theme)
            .trimmingCharacters(in: CharacterSet.newlines)
    }
}
