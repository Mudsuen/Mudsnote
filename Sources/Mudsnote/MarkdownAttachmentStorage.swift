import AppKit
import Foundation
import MudsnoteCore

enum MarkdownPasteAttachmentPayload: Equatable {
    case files([URL])
    case imagePNG(Data)
}

enum MarkdownAttachmentStorage {
    private static let imageExtensions: Set<String> = [
        "apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]

    static func pastePayload(from pasteboard: NSPasteboard) -> MarkdownPasteAttachmentPayload? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? [])
            .filter { url in
                guard url.isFileURL else { return false }
                return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            }
        if !fileURLs.isEmpty {
            return .files(fileURLs)
        }

        if pasteboard.availableType(from: [.html, .rtf, .rtfd]) != nil {
            let hasImageData = pasteboard.availableType(from: [.png, .tiff]) != nil
            if !hasImageData || !isBrowserCopiedImagePasteboard(pasteboard) {
                return nil
            }
        }

        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return .imagePNG(pngData)
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return .imagePNG(pngData)
    }

    /// Distinguishes browser "Copy Image" (which puts TIFF/PNG + an `<img>` HTML wrapper and
    /// empty or URL-only plain text on the pasteboard) from rich-text webpage selections.
    private static func isBrowserCopiedImagePasteboard(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: [.rtf, .rtfd]) != nil {
            return false
        }
        guard let htmlData = pasteboard.data(forType: .html),
              let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .utf16),
              html.range(of: "<img", options: .caseInsensitive) != nil else {
            return false
        }
        let plain = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if plain.isEmpty {
            return true
        }
        if let url = URL(string: plain), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return true
        }
        let strippedHTML = html
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return strippedHTML.isEmpty
    }

    static func storeFile(_ sourceURL: URL, in noteDirectory: URL, now: Date = Date()) throws -> URL {
        let directory = try attachmentDirectory(in: noteDirectory, now: now)
        let destination = uniqueDestination(
            named: sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent,
            in: directory
        )
        if sourceURL.standardizedFileURL.path != destination.standardizedFileURL.path {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
        return destination
    }

    static func storePastedPNG(_ data: Data, in noteDirectory: URL, now: Date = Date()) throws -> URL {
        let directory = try attachmentDirectory(in: noteDirectory, now: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let destination = uniqueDestination(
            named: "Pasted Image \(formatter.string(from: now)).png",
            in: directory
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func markdownReference(for fileURL: URL, relativeTo noteDirectory: URL) -> String {
        let relativePath = relativeMarkdownPath(for: fileURL, from: noteDirectory)
        if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
            return "![Image](\(relativePath))"
        }

        let rawLabel = fileURL.deletingPathExtension().lastPathComponent
        let label = escapedMarkdownLabel(rawLabel.isEmpty ? "Attachment" : rawLabel)
        return "[\(label)](\(relativePath))"
    }

    private static func attachmentDirectory(in noteDirectory: URL, now: Date) throws -> URL {
        let components = Calendar.current.dateComponents([.year, .month], from: now)
        let year = String(components.year ?? 1970)
        let month = String(format: "%02d", components.month ?? 1)
        let directory = noteDirectory
            .appendingPathComponent(NoteStore.attachmentDirectoryName, isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func uniqueDestination(named filename: String, in directory: URL) -> URL {
        let sourceURL = URL(fileURLWithPath: filename)
        let fileExtension = sourceURL.pathExtension
        let baseName = fileExtension.isEmpty
            ? filename
            : sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(filename)
        var copyIndex = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName)-\(copyIndex)"
                : "\(baseName)-\(copyIndex).\(fileExtension)"
            candidate = directory.appendingPathComponent(candidateName)
            copyIndex += 1
        }
        return candidate
    }

    private static func relativeMarkdownPath(for fileURL: URL, from noteDirectory: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let basePath = noteDirectory.standardizedFileURL.path
        let relativePath = filePath.hasPrefix(basePath + "/")
            ? String(filePath.dropFirst(basePath.count + 1))
            : fileURL.lastPathComponent
        return relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
    }

    private static func escapedMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
