import Foundation

enum ShareExtensionReference {
    static let note = """
    Share Extension implementation boundary:
    - Extract URL, plain text, selected text, and images from NSExtensionItem.
    - Convert inputs into CaptureDraft.
    - Present CaptureConsoleView in an extension-safe hosting controller.
    - If the folder bookmark is unavailable in the extension process, enqueue through app group storage.
    """
}
