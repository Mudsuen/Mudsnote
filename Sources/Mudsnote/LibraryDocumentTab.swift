import AppKit

@MainActor
final class LibraryDocumentTab {
    let id = UUID()
    var url: URL?
    var title: String
    var isDirty = false

    init(url: URL? = nil, title: String = "新标签页") {
        self.url = url
        self.title = title
    }
}
