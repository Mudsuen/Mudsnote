import AppKit
import Foundation

@MainActor
enum MarkdownRichPasteNormalizer {
    static func markdown(from pasteboard: NSPasteboard, theme: MarkdownEditorTheme) -> String? {
        guard let imported = importedAttributedString(from: pasteboard),
              imported.length > 0,
              !containsAttachment(imported) else {
            return nil
        }

        let bodyFontSize = importedBodyFontSize(in: imported, fallback: theme.bodyFont.pointSize)
        let source = imported.string as NSString
        var lines: [String] = []
        var location = 0
        var nextOrderedListIndex: Int?

        while location < source.length {
            let paragraphRange = source.paragraphRange(for: NSRange(location: location, length: 0))
            let paragraphText = source.substring(with: paragraphRange)
            let trailingBreakLength = paragraphText.hasSuffix("\n") || paragraphText.hasSuffix("\r") ? 1 : 0
            let visibleRange = NSRange(
                location: paragraphRange.location,
                length: max(paragraphRange.length - trailingBreakLength, 0)
            )
            let kind = paragraphKind(
                for: visibleRange,
                in: imported,
                bodyFontSize: bodyFontSize,
                nextOrderedListIndex: nextOrderedListIndex
            )
            let contentRange = contentRange(for: visibleRange, kind: kind, in: imported)
            let inline = inlineMarkdown(in: contentRange, source: imported, paragraphKind: kind)
            lines.append(MarkdownRichTextCodec.markdownLine(for: kind, inlineContent: inline))
            if case .ordered(let index) = kind {
                nextOrderedListIndex = index + 1
            } else {
                nextOrderedListIndex = nil
            }
            location = NSMaxRange(paragraphRange)
        }

        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        let markdown = lines.joined(separator: "\n")
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : markdown
    }

    private static func importedAttributedString(from pasteboard: NSPasteboard) -> NSAttributedString? {
        let candidates: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.html, .html),
            (.rtf, .rtf),
            (.rtfd, .rtfd)
        ]

        for (pasteboardType, documentType) in candidates {
            guard let data = pasteboard.data(forType: pasteboardType), !data.isEmpty else { continue }
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: documentType,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            if let value = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                return value
            }
        }
        return nil
    }

    private static func containsAttachment(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private static func importedBodyFontSize(in attributedString: NSAttributedString, fallback: CGFloat) -> CGFloat {
        var weightedSizes: [(size: CGFloat, weight: Int)] = []
        attributedString.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let text = (attributedString.string as NSString).substring(with: range)
            let weight = max(text.filter { !$0.isWhitespace }.count, 1)
            weightedSizes.append((font.pointSize, weight))
        }

        guard !weightedSizes.isEmpty else { return fallback }
        let sorted = weightedSizes.sorted { $0.size < $1.size }
        let midpoint = max(sorted.reduce(0) { $0 + $1.weight } / 2, 1)
        var accumulated = 0
        for item in sorted {
            accumulated += item.weight
            if accumulated >= midpoint {
                return max(item.size, 1)
            }
        }
        return max(sorted.last?.size ?? fallback, 1)
    }

    private static func paragraphKind(
        for range: NSRange,
        in attributedString: NSAttributedString,
        bodyFontSize: CGFloat,
        nextOrderedListIndex: Int?
    ) -> MarkdownParagraphKind {
        guard range.length > 0 else { return .paragraph }

        let style = attributedString.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        if let marker = style?.textLists.last?.markerFormat.rawValue.lowercased() {
            if marker.contains("decimal") {
                let index = orderedListIndex(in: range, source: attributedString.string as NSString)
                    ?? nextOrderedListIndex
                    ?? style?.textLists.last?.startingItemNumber
                    ?? 1
                return .ordered(index: index)
            }
            return .bullet
        }

        var maximumFontSize: CGFloat = bodyFontSize
        var hasBoldFont = false
        attributedString.enumerateAttribute(.font, in: range) { value, _, _ in
            guard let font = value as? NSFont else { return }
            maximumFontSize = max(maximumFontSize, font.pointSize)
            hasBoldFont = hasBoldFont || NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        }
        guard hasBoldFont else { return .paragraph }

        let ratio = maximumFontSize / max(bodyFontSize, 1)
        if ratio >= 1.75 { return .heading(level: 1) }
        if ratio >= 1.35 { return .heading(level: 2) }
        if ratio >= 1.08 { return .heading(level: 3) }
        return .paragraph
    }

    private static func orderedListIndex(in range: NSRange, source: NSString) -> Int? {
        let text = source.substring(with: range)
        let pieces = text.split(separator: "\t", omittingEmptySubsequences: true)
        let marker = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(marker.prefix(while: \.isNumber))
    }

    private static func contentRange(
        for range: NSRange,
        kind: MarkdownParagraphKind,
        in attributedString: NSAttributedString
    ) -> NSRange {
        let isList: Bool
        switch kind {
        case .bullet, .ordered, .checklist:
            isList = true
        case .paragraph, .heading:
            isList = false
        }
        guard isList, range.length > 0 else { return range }
        let text = (attributedString.string as NSString).substring(with: range) as NSString
        guard text.hasPrefix("\t") else { return range }
        let secondTab = text.range(of: "\t", options: [], range: NSRange(location: 1, length: max(text.length - 1, 0)))
        guard secondTab.location != NSNotFound else { return range }
        let prefixLength = NSMaxRange(secondTab)
        return NSRange(location: range.location + prefixLength, length: max(range.length - prefixLength, 0))
    }

    private static func inlineMarkdown(
        in range: NSRange,
        source: NSAttributedString,
        paragraphKind: MarkdownParagraphKind
    ) -> String {
        guard range.length > 0 else { return "" }
        var result = ""

        source.enumerateAttributes(in: range) { attributes, runRange, _ in
            let clippedRange = NSIntersectionRange(runRange, range)
            let text = (source.string as NSString).substring(with: clippedRange)
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { return }

            let escaped = escapedMarkdownText(text)
            if let target = linkTarget(from: attributes[.link]) {
                result += "[\(escaped)](\(escapedMarkdownURL(target)))"
                return
            }

            if let font = attributes[.font] as? NSFont,
               font.isFixedPitch,
               !text.contains("`") {
                result += "`\(text)`"
                return
            }

            var wrapped = escaped
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                wrapped = "<u>\(wrapped)</u>"
            }
            if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
                wrapped = "~~\(wrapped)~~"
            }

            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                let isBold = traits.contains(.boldFontMask) && {
                    if case .heading = paragraphKind { return false }
                    return true
                }()
                let isItalic = traits.contains(.italicFontMask)
                if isBold && isItalic {
                    wrapped = "***\(wrapped)***"
                } else if isBold {
                    wrapped = "**\(wrapped)**"
                } else if isItalic {
                    wrapped = "*\(wrapped)*"
                }
            }
            result += wrapped
        }
        return result
    }

    private static func linkTarget(from value: Any?) -> String? {
        if let url = value as? URL { return url.absoluteString }
        if let value = value as? String { return value }
        return nil
    }

    private static func escapedMarkdownText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func escapedMarkdownURL(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: ")", with: "%29")
    }
}
