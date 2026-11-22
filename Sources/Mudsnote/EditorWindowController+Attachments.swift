import AppKit
import Foundation

extension EditorWindowController {
    func markdownTextView(_ textView: MarkdownTextView, pasteAttachmentsFrom pasteboard: NSPasteboard) -> Bool {
        guard textView === editorTextView,
              let payload = MarkdownAttachmentStorage.pastePayload(from: pasteboard) else {
            return false
        }

        do {
            switch payload {
            case .files(let fileURLs):
                for fileURL in fileURLs {
                    let storedURL = try MarkdownAttachmentStorage.storeFile(fileURL, in: selectedDirectoryURL)
                    insertStoredAttachment(storedURL)
                }
            case .imagePNG(let data):
                let storedURL = try MarkdownAttachmentStorage.storePastedPNG(data, in: selectedDirectoryURL)
                insertStoredAttachment(storedURL)
            }
        } catch {
            presentErrorAlert(message: "粘贴附件失败", details: error.localizedDescription)
        }
        return true
    }

    func chooseAndInsertAttachment() {
        let panel = NSOpenPanel()
        panel.title = "添加附件"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls {
                let storedURL = try MarkdownAttachmentStorage.storeFile(url, in: selectedDirectoryURL)
                insertStoredAttachment(storedURL)
            }
        } catch {
            presentErrorAlert(message: "添加附件失败", details: error.localizedDescription)
        }
    }

    private func insertStoredAttachment(_ fileURL: URL) {
        guard let storage = editorTextView.textStorage else { return }
        window?.makeFirstResponder(editorTextView)

        let selection = editorTextView.selectedRange()
        let string = storage.string as NSString
        var markdown = MarkdownAttachmentStorage.markdownReference(
            for: fileURL,
            relativeTo: selectedDirectoryURL
        )
        if selection.location > 0,
           string.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n" {
            markdown = "\n" + markdown
        }
        if NSMaxRange(selection) < string.length,
           !markdown.hasSuffix("\n") {
            markdown += "\n"
        }

        let renderingBaseURL = (activeFloatingNoteURL ?? fileURLForRendering)
        let rendered = MarkdownRichTextCodec.render(
            markdown: markdown,
            theme: theme,
            baseURL: renderingBaseURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )
        suppressTextDidChange = true
        storage.replaceCharacters(in: selection, with: rendered)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: selection.location + rendered.length, length: 0))
        scrollSelectionToVisible()
        userDidEdit()
    }

    var fileURLForRendering: URL {
        activeFloatingNoteURL ?? fileURL ?? selectedDirectoryURL.appendingPathComponent(".mudsnote-unsaved.md")
    }
}
