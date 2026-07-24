import AppKit
import Foundation
import MudsnoteCore

extension EditorWindowController {

    func markDocumentDirty() {
        guard !suppressAutosave else { return }
        isDirty = true
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try self.persistDraft(force: false)
                } catch {
                    self.handleDraftPersistenceFailure(error)
                }
            }
        }
    }

    func persistDraft(force: Bool) throws {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        guard isDirty || force else { return }

        let document = currentDocument()

        if document.title.isEmpty && document.body.isEmpty {
            deleteDraftSnapshot(currentDraftID)
            isDirty = false
            return
        }

        let snapshot = DraftSnapshot(
            id: currentDraftID,
            sourcePath: activeFloatingNoteURL?.path ?? fileURL?.path,
            selectedDirectoryPath: selectedDirectoryURL.path,
            title: document.title,
            body: document.body,
            tags: document.tags,
            updatedAt: Date()
        )

        try saveDraftSnapshot(snapshot)
        isDirty = false
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
                title: currentQuickCaptureTitleValue(),
                bodyMarkdown: serializedBodyMarkdown()
            ).document
        }
        let markdown = serializedBodyMarkdown()
        return MarkdownEditorDocument.parse(editorText: markdown, tags: mergedDocumentTags(from: markdown))
    }

    func currentQuickCaptureTitleValue() -> String {
        quickCaptureTitleTextView?.string
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func serializedBodyMarkdown() -> String {
        guard let storage = editorTextView.textStorage else { return "" }
        return MarkdownRichTextCodec.serialize(storage, theme: theme)
            .trimmingCharacters(in: CharacterSet.newlines)
    }
}
