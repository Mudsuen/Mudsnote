import AppKit

/// One document's editing state. Tab switches never borrow another document's
/// undo stack or lose an edit while its background save is pending.
@MainActor
final class LibraryDocumentTab {
    let id = UUID()
    var url: URL?
    var title = "新标签页"
    var buffer: NSAttributedString?
    var sourceContents: String?
    var tags: [String] = []
    var selection = NSRange(location: 0, length: 0)
    var scrollOrigin = NSPoint.zero
    var revision = 0
    var isDirty = false
    var isSourceMode = false
    var isCreatingNote = false
    var saveFailed = false
    var closeAfterSave = false
    var targetDirectory: URL?
    let undoManager = UndoManager()

    init(url: URL? = nil, title: String = "新标签页") {
        self.url = url
        self.title = title
        undoManager.levelsOfUndo = 100
    }
}
