import CryptoKit
import Foundation
import PDFKit
import UIKit
import Vision

protocol AttachmentTextRecognizing: Sendable {
    func recognizeText(at url: URL) async throws -> String
}

struct AttachmentSearchDocument: Equatable, Sendable {
    var relativePath: String
    var text: String

    var fileName: String { (relativePath as NSString).lastPathComponent }
}

struct VisionAttachmentTextRecognizer: AttachmentTextRecognizing {
    private static let maximumPDFPages = 12
    private static let maximumImageDimension: CGFloat = 2_048
    private static let maximumRecognizedCharacters = 32 * 1_024

    func recognizeText(at url: URL) async throws -> String {
        try Task.checkCancellation()
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff":
            let handler = VNImageRequestHandler(url: url)
            return try Self.recognizedText(using: handler)
        case "pdf":
            return try Self.recognizedText(inPDFAt: url)
        default:
            return ""
        }
    }

    private static func recognizedText(inPDFAt url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, maximumPDFPages) {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let scale = min(
                maximumImageDimension / bounds.width,
                maximumImageDimension / bounds.height,
                2
            )
            let size = CGSize(
                width: max(1, bounds.width * scale),
                height: max(1, bounds.height * scale)
            )
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = image.cgImage else { continue }
            let pageText = try recognizedText(
                using: VNImageRequestHandler(cgImage: cgImage)
            )
            if !pageText.isEmpty { pages.append(pageText) }
            if pages.joined(separator: "\n").count >= maximumRecognizedCharacters { break }
        }
        return String(pages.joined(separator: "\n").prefix(maximumRecognizedCharacters))
    }

    private static func recognizedText(using handler: VNImageRequestHandler) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.015 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        let text = observations.compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        return String(text.prefix(maximumRecognizedCharacters))
    }
}

actor AttachmentTextIndex {
    private struct CacheEntry: Codable {
        var modifiedAt: Date
        var byteCount: Int
        var text: String
        var lastAccessedAt: Date
    }

    private struct CacheState: Codable {
        var version: Int
        var entries: [String: CacheEntry]
    }

    private static let cacheVersion = 1
    private static let maximumFileBytes = 32 * 1_024 * 1_024
    private static let maximumEntries = 512
    private let recognizer: any AttachmentTextRecognizing
    private let cacheURL: URL?
    private var entries: [String: CacheEntry] = [:]
    private var hasLoadedCache = false

    init(
        recognizer: any AttachmentTextRecognizing = VisionAttachmentTextRecognizer(),
        cacheURL: URL? = AttachmentTextIndex.defaultCacheURL
    ) {
        self.recognizer = recognizer
        self.cacheURL = cacheURL
    }

    func text(relativePath: String, root: URL) async throws -> String? {
        try Task.checkCancellation()
        loadCacheIfNeeded()
        guard let url = AuthorizedLibraryPath.resolve(
            relativePath,
            within: root,
            constrainedTo: "Attachments"
        ) else { return nil }

        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        )
        guard values.isRegularFile == true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= Self.maximumFileBytes else { return nil }
        let modifiedAt = values.contentModificationDate ?? .distantPast
        let key = Self.cacheKey(root: root, relativePath: relativePath)
        if var cached = entries[key],
           cached.modifiedAt == modifiedAt,
           cached.byteCount == byteCount {
            cached.lastAccessedAt = .now
            entries[key] = cached
            return cached.text.isEmpty ? nil : cached.text
        }

        let recognized = try await recognizer.recognizeText(at: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        entries[key] = CacheEntry(
            modifiedAt: modifiedAt,
            byteCount: byteCount,
            text: recognized,
            lastAccessedAt: .now
        )
        trimIfNeeded()
        persistCache()
        return recognized.isEmpty ? nil : recognized
    }

    private func loadCacheIfNeeded() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let state = try? JSONDecoder().decode(CacheState.self, from: data),
              state.version == Self.cacheVersion else { return }
        entries = state.entries
        trimIfNeeded()
    }

    private func persistCache() {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let state = CacheState(version: Self.cacheVersion, entries: entries)
            try JSONEncoder().encode(state).write(to: cacheURL, options: .atomic)
        } catch {
            // Search remains usable when the disposable OCR cache cannot be written.
        }
    }

    private func trimIfNeeded() {
        guard entries.count > Self.maximumEntries else { return }
        let overflow = entries.count - Self.maximumEntries
        for key in entries
            .sorted(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
            .prefix(overflow)
            .map(\.key) {
            entries.removeValue(forKey: key)
        }
    }

    private static func cacheKey(root: URL, relativePath: String) -> String {
        let rootDigest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(rootDigest):\(relativePath)"
    }

    private static var defaultCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mudsnote", isDirectory: true)
            .appendingPathComponent("AttachmentTextIndex-v1.json")
    }
}

enum MarkdownAttachmentSearch {
    private static let markdownLinkExpression = try! NSRegularExpression(
        pattern: #"!?\[[^\]]*\]\(([^)\n]+)\)"#
    )
    private static let wikiLinkExpression = try! NSRegularExpression(
        pattern: #"!\[\[([^\]]+)\]\]"#
    )

    static func relativePaths(in markdown: String) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        var activeFence: Character?
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = trimmed.first,
               (marker == "`" || marker == "~"),
               trimmed.prefix(3).allSatisfy({ $0 == marker }) {
                activeFence = activeFence == nil ? marker : (activeFence == marker ? nil : activeFence)
                continue
            }
            guard activeFence == nil else { continue }
            appendMatches(from: line, expression: markdownLinkExpression, paths: &paths, seen: &seen)
            appendMatches(from: line, expression: wikiLinkExpression, paths: &paths, seen: &seen)
        }
        return paths
    }

    private static func appendMatches(
        from line: String,
        expression: NSRegularExpression,
        paths: inout [String],
        seen: inout Set<String>
    ) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        expression.enumerateMatches(in: line, range: range) { match, _, _ in
            guard let match,
                  let swiftRange = Range(match.range(at: 1), in: line) else { return }
            var path = String(line[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasPrefix("<"), path.hasSuffix(">") {
                path = String(path.dropFirst().dropLast())
            }
            path = path.removingPercentEncoding ?? path
            guard path.hasPrefix("Attachments/"),
                  seen.insert(path).inserted else { return }
            paths.append(path)
        }
    }
}
