import Foundation
import SwiftUI
import UIKit

struct ExportedNotePDF: Identifiable {
    let url: URL

    var id: URL { url }
}

@MainActor
enum NotePDFExporter {
    enum ExportError: LocalizedError {
        case couldNotCreateDocument

        var errorDescription: String? {
            String(localized: "The PDF couldn’t be created.")
        }
    }

    private final class PageRenderer: UIPrintPageRenderer {
        private let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

        override var paperRect: CGRect { pageBounds }
        override var printableRect: CGRect { pageBounds.insetBy(dx: 54, dy: 54) }
    }

    static func export(
        title: String,
        markdown: String,
        modifiedAt: Date? = nil,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> ExportedNotePDF {
        let outputDirectory = directory.appendingPathComponent("Mudsnote PDF Exports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let outputURL = outputDirectory
            .appendingPathComponent(safeFileName(title))
            .appendingPathExtension("pdf")

        let formatter = UISimpleTextPrintFormatter(attributedText: makePrintableContent(
            title: title,
            markdown: markdown,
            modifiedAt: modifiedAt
        ))
        let renderer = PageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 1))
        guard renderer.numberOfPages > 0 else { throw ExportError.couldNotCreateDocument }

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(
            data,
            renderer.paperRect,
            [
                kCGPDFContextTitle as String: title,
                kCGPDFContextCreator as String: "Mudsnote"
            ]
        )
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: renderer.paperRect)
        }
        UIGraphicsEndPDFContext()

        guard data.length > 0 else { throw ExportError.couldNotCreateDocument }
        try data.write(to: outputURL, options: .atomic)
        return ExportedNotePDF(url: outputURL)
    }

    private static func makePrintableContent(
        title: String,
        markdown: String,
        modifiedAt: Date?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        paragraph.lineSpacing = 2

        result.append(NSAttributedString(
            string: title + "\n",
            attributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
        ))
        if let modifiedAt {
            result.append(NSAttributedString(
                string: modifiedAt.formatted(date: .long, time: .shortened) + "\n\n",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.darkGray
                ]
            ))
        }
        result.append(printableBody(markdown, title: title, paragraphStyle: paragraph))
        return result
    }

    private static func printableBody(
        _ markdown: String,
        title: String,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in printableLines(markdown, title: title) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                result.append(NSAttributedString(string: "\n"))
                continue
            }
            if trimmed.range(of: #"^\|?\s*:?-{3,}"#, options: .regularExpression) != nil {
                continue
            }

            let heading = MarkdownHeading(trimmed)
            let sourceText: String
            if let heading {
                sourceText = heading.title
            } else if let attachment = MarkdownAttachmentLine(trimmed) {
                sourceText = (attachment.path as NSString).lastPathComponent
            } else {
                sourceText = trimmed.replacingOccurrences(of: "|", with: "  |  ")
            }
            let inline = (try? AttributedString(
                markdown: sourceText,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(sourceText)
            let rendered = NSMutableAttributedString(attributedString: NSAttributedString(inline))
            let range = NSRange(location: 0, length: rendered.length)
            rendered.addAttributes(
                [.foregroundColor: UIColor.black, .paragraphStyle: paragraphStyle],
                range: range
            )
            if let heading {
                rendered.addAttribute(
                    .font,
                    value: UIFont.systemFont(
                        ofSize: max(16, 24 - CGFloat(heading.level * 2)),
                        weight: .bold
                    ),
                    range: range
                )
            }
            rendered.enumerateAttribute(.link, in: range) { value, linkRange, _ in
                if value != nil {
                    rendered.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: linkRange)
                }
            }
            result.append(rendered)
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    private static func printableLines(_ markdown: String, title: String) -> [String] {
        var lines = markdown.components(separatedBy: .newlines)
        if let first = lines.first,
           let heading = MarkdownHeading(first.trimmingCharacters(in: .whitespaces)),
           heading.title.localizedCaseInsensitiveCompare(title) == .orderedSame {
            lines.removeFirst()
            while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                lines.removeFirst()
            }
        }
        return lines
    }

    private static func safeFileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? String(localized: "Untitled Note") : String(sanitized.prefix(120))
    }
}

struct NoteActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
