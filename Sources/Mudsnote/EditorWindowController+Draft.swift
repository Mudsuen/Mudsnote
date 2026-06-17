import AppKit
import Foundation
import MudsnoteCore

extension EditorWindowController {

    func markDocumentDirty() {
        guard !suppressAutosave else { return }
        isDirty = true
        statusLabel.stringValue = "自动保存中"
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.persistDraft(force: false) }
        }
    }

    func persistDraft(force: Bool) {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        guard isDirty || force else { return }

        let document = currentDocument()

        if document.title.isEmpty && document.body.isEmpty {
            noteStore.deleteDraft(id: currentDraftID)
            statusLabel.stringValue = fileURL == nil && activeFloatingNoteURL == nil ? "Markdown" : "编辑中"
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

        do {
            try noteStore.saveDraft(snapshot)
            statusLabel.stringValue = "已保存"
        } catch {
            statusLabel.stringValue = "保存失败"
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
