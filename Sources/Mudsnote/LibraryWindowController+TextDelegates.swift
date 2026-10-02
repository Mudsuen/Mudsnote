import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func controlTextDidChange(_ obj: Notification) {
        guard let object = obj.object as AnyObject? else { return }

        if object === inlineFolderEditField {
            return
        }

        if object === searchField {
            scheduleSearchReloadFromTyping()
            return
        }

        if object === titleField {
            replaceUnifiedEditorTitle(titleField.stringValue)
            markDirty()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === inlineFolderEditField {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelInlineFolderEdit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitInlineFolderEdit()
                return true
            }
            return false
        }

        if control === titleField {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            window?.makeFirstResponder(editorTextView)
            editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
            editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
            return true
        }

        guard control === searchField else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            return clearSearchFromKeyboard()
        }
        // Text editing commands (including Backspace and caret movement) must
        // retain the typing debounce rather than synchronously scan the library.
        guard commandSelector == #selector(NSResponder.moveDown(_:))
            || commandSelector == #selector(NSResponder.moveUp(_:))
            || commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        flushPendingSearchReload()

        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            return stepSearchResult(.next)
        }

        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            return stepSearchResult(.previous)
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return loadFocusedNoteListResultFromSearch()
        }

        return false
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === editorTextView else { return false }

        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return moveMarkdownTableCellSelectionForLibrary(.next)
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return moveMarkdownTableCellSelectionForLibrary(.previous)
        }

        return false
    }

    func textDidChange(_ notification: Notification) {
        if let object = notification.object as AnyObject?, object === editorTextView {
            normalizeUnifiedTitleLineFormatting()
            let visibleText = editorTextView.string as NSString
            if isEditorShowingMarkdownSource {
                titleField.stringValue = visibleEditorMetadata().title
            } else if visibleText.length > 0 {
                titleField.stringValue = visibleText.substring(with: visibleText.paragraphRange(
                    for: NSRange(location: 0, length: 0)
                )).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                titleField.stringValue = ""
            }
            editorMetricsRefreshTask?.cancel()
            editorMetricsRefreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                let metadata = self.visibleEditorMetadata()
                self.titleField.stringValue = metadata.title
                self.updateWordCount(in: metadata.body)
                self.layoutEditorStatusLabel()
                self.editorMetricsRefreshTask = nil
            }
            libraryUserDidEdit()
        } else {
            markDirty()
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let object = notification.object as AnyObject?, object === editorTextView else { return }
        updateEditorSlashSuggestions()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === inlineFolderEditField,
              inlineFolderEditHasReceivedFocus,
              !isCommittingInlineFolderEdit else {
            return
        }
        commitInlineFolderEdit()
    }

    @objc
    func searchScopeChanged(_ sender: NSSegmentedControl) {
        cancelPendingSearchReload()
        performSearchReload()
    }
}
