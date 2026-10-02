import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore

extension NSAttributedString.Key {
    static let qmAutomaticTitleBaseline = NSAttributedString.Key("MudsnoteAutomaticTitleBaseline")
    static let qmParagraphKind = NSAttributedString.Key("MudsnoteParagraphKind")
    static let qmCode = NSAttributedString.Key("MudsnoteCode")
    static let qmLinkURL = NSAttributedString.Key("MudsnoteLinkURL")
    static let qmAutomaticLink = NSAttributedString.Key("MudsnoteAutomaticLink")
    static let qmTag = NSAttributedString.Key("MudsnoteTag")
    static let qmMetadataTagReserve = NSAttributedString.Key("MudsnoteMetadataTagReserve")
    static let qmImageMarkdown = NSAttributedString.Key("MudsnoteImageMarkdown")
    static let qmImageFilePath = NSAttributedString.Key("MudsnoteImageFilePath")
    static let qmAttachmentMarkdown = NSAttributedString.Key("MudsnoteAttachmentMarkdown")
    static let qmAttachmentFilePath = NSAttributedString.Key("MudsnoteAttachmentFilePath")
    static let qmAttachmentMetadata = NSAttributedString.Key("MudsnoteAttachmentMetadata")
    static let qmTableID = NSAttributedString.Key("MudsnoteTableID")
    static let qmTableRow = NSAttributedString.Key("MudsnoteTableRow")
    static let qmTableColumn = NSAttributedString.Key("MudsnoteTableColumn")
    static let qmTableColumnCount = NSAttributedString.Key("MudsnoteTableColumnCount")
    static let qmTableColumnAlignment = NSAttributedString.Key("MudsnoteTableColumnAlignment")
    static let qmTablePlaceholder = NSAttributedString.Key("MudsnoteTablePlaceholder")
    static let qmTableTerminalNewline = NSAttributedString.Key("MudsnoteTableTerminalNewline")
    static let qmSearchHighlight = NSAttributedString.Key("MudsnoteSearchHighlight")
    static let qmHighlight = NSAttributedString.Key("MudsnoteHighlight")
}

final class MarkdownImageAttachmentReference: NSObject {
    let range: NSRange
    let path: String
    let naturalSize: NSSize
    let displaySize: NSSize

    init(range: NSRange, path: String, naturalSize: NSSize, displaySize: NSSize) {
        self.range = range
        self.path = path
        self.naturalSize = naturalSize
        self.displaySize = displaySize
    }
}

final class MarkdownImageResizeMenuCommand: NSObject {
    let fileURL: URL
    let preferredWidth: Double?

    init(fileURL: URL, preferredWidth: Double?) {
        self.fileURL = fileURL
        self.preferredWidth = preferredWidth
    }
}

final class MarkdownAttachmentReference: NSObject {
    let path: String
    let markdown: String
    let metadata: String

    init(path: String, markdown: String, metadata: String) {
        self.path = path
        self.markdown = markdown
        self.metadata = metadata
    }
}

final class MarkdownLinkReference: NSObject {
    let range: NSRange
    let label: String
    let url: String

    init(range: NSRange, label: String, url: String) {
        self.range = range
        self.label = label
        self.url = url
    }
}

enum MarkdownLinkDestination: Equatable {
    case localMarkdown(URL)
    case external(URL)
}

func markdownLinkDestination(_ rawValue: String, relativeTo sourceURL: URL?) -> MarkdownLinkDestination? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let sourceURL,
       let localURL = MarkdownLocalLinkResolver.fileURL(for: trimmed, relativeTo: sourceURL) {
        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        return ["md", "markdown", "txt"].contains(localURL.pathExtension.lowercased())
            ? .localMarkdown(localURL)
            : .external(localURL)
    }

    guard let externalURL = openableMarkdownLinkURL(trimmed) else { return nil }
    return .external(externalURL)
}

func openableMarkdownLinkURL(_ rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let url = URL(string: trimmed),
       let scheme = url.scheme?.lowercased(),
       ["http", "https", "mailto", "tel"].contains(scheme) {
        return url
    }

    guard !trimmed.contains(":") else { return nil }
    return URL(string: "https://\(trimmed)")
}

let markdownItalicObliqueness: CGFloat = 0.16

enum MarkdownParagraphKind: Equatable {
    case paragraph
    case heading(level: Int)
    case bullet
    case ordered(index: Int)
    case checklist(checked: Bool)

    var prefix: String {
        switch self {
        case .paragraph, .heading:
            return ""
        case .bullet:
            return "\u{2022} "
        case .ordered(let index):
            return "\(index). "
        case .checklist(let checked):
            return checked ? "\u{2611} " : "\u{2610} "
        }
    }

    var prefixLength: Int {
        prefix.utf16.count
    }

    var encodedValue: String {
        switch self {
        case .paragraph:
            return "paragraph"
        case .heading(let level):
            return "heading:\(level)"
        case .bullet:
            return "bullet"
        case .ordered(let index):
            return "ordered:\(index)"
        case .checklist(let checked):
            return checked ? "check:1" : "check:0"
        }
    }

    static func decode(_ rawValue: Any?) -> MarkdownParagraphKind? {
        guard let string = rawValue as? String else { return nil }

        if string == "paragraph" { return .paragraph }
        if string == "bullet" { return .bullet }
        if string == "check:1" { return .checklist(checked: true) }
        if string == "check:0" { return .checklist(checked: false) }
        if string.hasPrefix("heading:"),
           let level = Int(string.replacingOccurrences(of: "heading:", with: "")) {
            return .heading(level: level)
        }
        if string.hasPrefix("ordered:"),
           let index = Int(string.replacingOccurrences(of: "ordered:", with: "")) {
            return .ordered(index: index)
        }

        return nil
    }
}

struct MarkdownEditorTheme {
    let textColor: NSColor
    let mutedTextColor: NSColor
    let accentColor: NSColor
    let bodyFont: NSFont
    let boldFont: NSFont
    let italicFont: NSFont
    let codeFont: NSFont
    var lineSpacing: CGFloat = 2
    var paragraphSpacing: CGFloat = 6

    func font(for paragraphKind: MarkdownParagraphKind) -> NSFont {
        switch paragraphKind {
        case .heading(let level):
            let size = max(24 - CGFloat(level * 2), 16)
            return NSFont.systemFont(ofSize: size, weight: .bold)
        default:
            return bodyFont
        }
    }

    func paragraphStyle(for paragraphKind: MarkdownParagraphKind) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing

        switch paragraphKind {
        case .bullet, .ordered, .checklist:
            let tab = NSTextTab(textAlignment: .left, location: 16, options: [:])
            style.tabStops = [tab]
            style.defaultTabInterval = 16
            style.firstLineHeadIndent = 0
            style.headIndent = 16
        default:
            style.firstLineHeadIndent = 0
            style.headIndent = 0
        }

        return style
    }

    func baseAttributes(for paragraphKind: MarkdownParagraphKind) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: paragraphKind),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle(for: paragraphKind),
            .qmParagraphKind: paragraphKind.encodedValue
        ]
    }
}

@MainActor
protocol MarkdownTextViewCommands: AnyObject {
    func markdownTextViewInsertNewline(_ textView: MarkdownTextView)
    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool
    func markdownTextViewToggleBold(_ textView: MarkdownTextView)
    func markdownTextViewToggleItalic(_ textView: MarkdownTextView)
    func markdownTextViewToggleUnderline(_ textView: MarkdownTextView)
    func markdownTextViewToggleStrikethrough(_ textView: MarkdownTextView)
    func markdownTextViewToggleHeading(_ textView: MarkdownTextView)
    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView)
    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView)
    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView)
    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, didDoubleClickAttachmentAt index: Int) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, didCommandClickLinkAt index: Int) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, pasteAttachmentsFrom pasteboard: NSPasteboard) -> Bool
}

extension MarkdownTextViewCommands {
    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool {
        false
    }

    func markdownTextView(_ textView: MarkdownTextView, didDoubleClickAttachmentAt index: Int) -> Bool {
        false
    }

    func markdownTextView(_ textView: MarkdownTextView, didCommandClickLinkAt index: Int) -> Bool {
        false
    }

    func markdownTextView(_ textView: MarkdownTextView, pasteAttachmentsFrom pasteboard: NSPasteboard) -> Bool {
        false
    }
}
