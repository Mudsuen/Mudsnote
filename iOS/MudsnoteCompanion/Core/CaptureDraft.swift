import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CaptureDraft: Equatable {
    var body: String = ""
    var tags: String = ""
    var target: CaptureTarget = .inbox
    var attachments: [CaptureAttachment] = []
    var createdAt: Date = Date()

    var canSend: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
}

enum CaptureTarget: Equatable, Identifiable {
    case inbox
    case daily(Date)
    case recent(String)

    var id: String {
        switch self {
        case .inbox:
            return "inbox"
        case .daily(let date):
            return "daily-\(Self.dayFormatter.string(from: date))"
        case .recent(let path):
            return "recent-\(path)"
        }
    }

    var label: String {
        switch self {
        case .inbox:
            return String(localized: "Inbox")
        case .daily(let date):
            return String(
                format: String(localized: "daily.with_date.format"),
                locale: .current,
                Self.dayFormatter.string(from: date)
            )
        case .recent(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    func relativePath(now: Date = Date()) -> String {
        switch self {
        case .inbox:
            return "Inbox.md"
        case .daily(let date):
            return "Daily/\(Self.dayFormatter.string(from: date)).md"
        case .recent(let path):
            return path
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum CaptureAttachment: Equatable {
    case image(data: Data, preferredExtension: String)
    case video(data: Data, preferredExtension: String, preferredBaseName: String)
    case audio(data: Data, preferredExtension: String)
    case file(data: Data, preferredExtension: String, preferredBaseName: String)

    var markdownTag: String {
        switch self {
        case .image:
            return "#图片"
        case .video:
            return "#视频"
        case .audio:
            return "#语音"
        case .file:
            return "#附件"
        }
    }

    var filePrefix: String {
        switch self {
        case .image:
            return "IMG"
        case .video(_, _, let preferredBaseName):
            return preferredBaseName
        case .audio:
            return "audio"
        case .file(_, _, let preferredBaseName):
            return preferredBaseName
        }
    }

    var data: Data {
        switch self {
        case .image(let data, _), .video(let data, _, _), .audio(let data, _), .file(let data, _, _):
            return data
        }
    }

    var preferredExtension: String {
        switch self {
        case .image(_, let preferredExtension),
             .video(_, let preferredExtension, _),
             .audio(_, let preferredExtension),
             .file(_, let preferredExtension, _):
            return preferredExtension
        }
    }

    var referenceKind: MarkdownAttachmentKind {
        switch self {
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case .file:
            return .file
        }
    }

    static func validatedImage(data: Data, suggestedExtension: String? = nil) throws -> CaptureAttachment {
        guard data.isEmpty == false else { throw CaptureAttachmentError.empty }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier),
              type.conforms(to: .image) else {
            throw CaptureAttachmentError.unsupportedImage
        }
        let detectedExtension = type.preferredFilenameExtension
            ?? suggestedExtension?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            ?? "img"
        return .image(
            data: data,
            preferredExtension: detectedExtension.lowercased() == "jpeg" ? "jpg" : detectedExtension.lowercased()
        )
    }

    static func validatedAudio(data: Data, preferredExtension: String = "m4a") throws -> CaptureAttachment {
        guard data.isEmpty == false else { throw CaptureAttachmentError.empty }
        return .audio(
            data: data,
            preferredExtension: preferredExtension.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
        )
    }

    static func validatedVideo(data: Data, suggestedName: String) throws -> CaptureAttachment {
        guard data.isEmpty == false else { throw CaptureAttachmentError.empty }
        let rawName = (suggestedName as NSString).deletingPathExtension
        let baseName = rawName
            .replacingOccurrences(of: #"[/\\:\x00]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestedExtension = (suggestedName as NSString).pathExtension
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased()
        let fileExtension = suggestedExtension.isEmpty ? "mov" : suggestedExtension
        guard let type = UTType(filenameExtension: fileExtension), type.conforms(to: .movie) else {
            throw CaptureAttachmentError.unsupportedVideo
        }
        return .video(
            data: data,
            preferredExtension: fileExtension,
            preferredBaseName: baseName.isEmpty ? "Video" : String(baseName.prefix(80))
        )
    }

    static func validatedFile(data: Data, suggestedName: String) throws -> CaptureAttachment {
        guard data.isEmpty == false else { throw CaptureAttachmentError.empty }
        let rawName = (suggestedName as NSString).deletingPathExtension
        let baseName = rawName
            .replacingOccurrences(of: #"[/\\:\x00]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawExtension = (suggestedName as NSString).pathExtension
        let fileExtension = rawExtension
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased()
        return .file(
            data: data,
            preferredExtension: fileExtension.isEmpty ? "bin" : fileExtension,
            preferredBaseName: baseName.isEmpty ? "file" : String(baseName.prefix(80))
        )
    }
}

enum CaptureAttachmentPolicy {
    static let maximumAttachmentCount = 8
    static let maximumImageBytes = 15 * 1_024 * 1_024
    static let maximumVideoBytes = 50 * 1_024 * 1_024
    static let maximumAudioBytes = 25 * 1_024 * 1_024
    static let maximumFileBytes = 25 * 1_024 * 1_024
    static let maximumDraftBytes = 64 * 1_024 * 1_024

    static func validateAppending(_ attachment: CaptureAttachment, to existing: [CaptureAttachment]) throws {
        guard existing.count < maximumAttachmentCount else {
            throw CaptureAttachmentError.tooMany(maximum: maximumAttachmentCount)
        }
        let individualLimit: Int
        switch attachment {
        case .image:
            individualLimit = maximumImageBytes
        case .video:
            individualLimit = maximumVideoBytes
        case .audio:
            individualLimit = maximumAudioBytes
        case .file:
            individualLimit = maximumFileBytes
        }
        guard attachment.data.count <= individualLimit else {
            throw CaptureAttachmentError.tooLarge(maximumBytes: individualLimit)
        }
        let totalBytes = existing.reduce(attachment.data.count) { $0 + $1.data.count }
        guard totalBytes <= maximumDraftBytes else {
            throw CaptureAttachmentError.draftTooLarge(maximumBytes: maximumDraftBytes)
        }
    }

    static func validate(_ attachments: [CaptureAttachment]) throws {
        var accepted: [CaptureAttachment] = []
        for attachment in attachments {
            try validateAppending(attachment, to: accepted)
            accepted.append(attachment)
        }
    }
}

enum CaptureAttachmentError: LocalizedError, Equatable {
    case empty
    case unsupportedImage
    case unsupportedVideo
    case tooMany(maximum: Int)
    case tooLarge(maximumBytes: Int)
    case draftTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return String(localized: "The attachment is empty.")
        case .unsupportedImage:
            return String(localized: "Choose a supported image file.")
        case .unsupportedVideo:
            return String(localized: "Choose a supported video file.")
        case .tooMany(let maximum):
            return String(
                format: String(localized: "attachment.maximum_count.format"),
                locale: .current,
                maximum
            )
        case .tooLarge(let maximumBytes):
            return String(
                format: String(localized: "attachment.maximum_size.format"),
                locale: .current,
                Self.megabytes(maximumBytes)
            )
        case .draftTooLarge(let maximumBytes):
            return String(
                format: String(localized: "attachment.maximum_draft_size.format"),
                locale: .current,
                Self.megabytes(maximumBytes)
            )
        }
    }

    private static func megabytes(_ bytes: Int) -> Int {
        bytes / 1_024 / 1_024
    }
}

enum MarkdownAttachmentKind: String, Equatable {
    case image
    case video
    case audio
    case file
}

struct MarkdownAttachmentReference: Equatable {
    var relativePath: String
    var kind: MarkdownAttachmentKind
}

actor CaptureDraftRecoveryStore {
    static let defaultDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    .appendingPathComponent("Mudsnote/CaptureDraft", isDirectory: true)

    private struct Metadata: Codable {
        var version: Int
        var body: String
        var tags: String
        var target: Target
        var createdAt: Date
        var attachments: [Attachment]
    }

    private enum Target: Codable {
        case inbox
        case daily(Date)
        case recent(String)
    }

    private struct Attachment: Codable {
        enum Kind: String, Codable {
            case image
            case video
            case audio
            case file
        }

        var kind: Kind
        var filename: String
        var preferredExtension: String
        var preferredBaseName: String?
    }

    private let directory: URL
    private let metadataURL: URL
    private var lastAttachments: [CaptureAttachment]?
    private var lastMetadata: Metadata?

    init(directory: URL = CaptureDraftRecoveryStore.defaultDirectory) {
        self.directory = directory
        self.metadataURL = directory.appendingPathComponent("draft.json")
    }

    func load() throws -> CaptureDraft? {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            lastAttachments = []
            lastMetadata = nil
            return nil
        }
        let metadata: Metadata
        do {
            metadata = try JSONDecoder.captureDraftRecovery.decode(
                Metadata.self,
                from: Data(contentsOf: metadataURL)
            )
        } catch {
            throw CaptureDraftRecoveryError.damaged
        }
        guard metadata.version == 1 else { throw CaptureDraftRecoveryError.unsupportedVersion }
        let attachments: [CaptureAttachment]
        do {
            attachments = try metadata.attachments.map { entry -> CaptureAttachment in
                guard entry.filename == URL(fileURLWithPath: entry.filename).lastPathComponent else {
                    throw CaptureDraftRecoveryError.damaged
                }
                let fileURL = directory.appendingPathComponent(entry.filename)
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                switch entry.kind {
                case .image:
                    return try CaptureAttachment.validatedImage(
                        data: data,
                        suggestedExtension: entry.preferredExtension
                    )
                case .video:
                    return try CaptureAttachment.validatedVideo(
                        data: data,
                        suggestedName: "\(entry.preferredBaseName ?? "Video").\(entry.preferredExtension)"
                    )
                case .audio:
                    return try CaptureAttachment.validatedAudio(
                        data: data,
                        preferredExtension: entry.preferredExtension
                    )
                case .file:
                    return try CaptureAttachment.validatedFile(
                        data: data,
                        suggestedName: "\(entry.preferredBaseName ?? "file").\(entry.preferredExtension)"
                    )
                }
            }
            try CaptureAttachmentPolicy.validate(attachments)
        } catch {
            throw CaptureDraftRecoveryError.damaged
        }
        let draft = CaptureDraft(
            body: metadata.body,
            tags: metadata.tags,
            target: captureTarget(metadata.target),
            attachments: attachments,
            createdAt: metadata.createdAt
        )
        guard draft.canSend else {
            try clear()
            return nil
        }
        lastAttachments = attachments
        lastMetadata = metadata
        return draft
    }

    func save(_ draft: CaptureDraft) throws {
        guard draft.canSend else {
            try clear()
            return
        }
        try CaptureAttachmentPolicy.validate(draft.attachments)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(resourceValues)

        var entries: [Attachment] = []
        for (index, attachment) in draft.attachments.enumerated() {
            if let previous = lastAttachments,
               let metadata = lastMetadata,
               previous.indices.contains(index),
               metadata.attachments.indices.contains(index),
               previous[index] == attachment,
               FileManager.default.fileExists(
                   atPath: directory.appendingPathComponent(metadata.attachments[index].filename).path
               ) {
                entries.append(metadata.attachments[index])
                continue
            }

            let filename = "attachment-\(UUID().uuidString.lowercased()).\(attachment.preferredExtension)"
            let fileURL = directory.appendingPathComponent(filename)
            try attachment.data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            entries.append(Attachment(
                kind: attachmentKind(attachment),
                filename: filename,
                preferredExtension: attachment.preferredExtension,
                preferredBaseName: attachmentBaseName(attachment)
            ))
        }

        let metadata = Metadata(
            version: 1,
            body: draft.body,
            tags: draft.tags,
            target: storedTarget(draft.target),
            createdAt: draft.createdAt,
            attachments: entries
        )
        let data = try JSONEncoder.captureDraftRecovery.encode(metadata)
        try data.write(
            to: metadataURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        let retained = Set(entries.map(\.filename) + [metadataURL.lastPathComponent])
        for url in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) where !retained.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        lastAttachments = draft.attachments
        lastMetadata = metadata
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        lastAttachments = []
        lastMetadata = nil
    }

    private func storedTarget(_ target: CaptureTarget) -> Target {
        switch target {
        case .inbox: .inbox
        case .daily(let date): .daily(date)
        case .recent(let path): .recent(path)
        }
    }

    private func captureTarget(_ target: Target) -> CaptureTarget {
        switch target {
        case .inbox: .inbox
        case .daily(let date): .daily(date)
        case .recent(let path): .recent(path)
        }
    }

    private func attachmentKind(_ attachment: CaptureAttachment) -> Attachment.Kind {
        switch attachment {
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .file: .file
        }
    }

    private func attachmentBaseName(_ attachment: CaptureAttachment) -> String? {
        switch attachment {
        case .video(_, _, let baseName), .file(_, _, let baseName): baseName
        case .image, .audio: nil
        }
    }
}

struct PhotoLibraryMovie: Transferable {
    var data: Data
    var suggestedName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let values = try received.file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw CaptureAttachmentError.empty }
            if let byteCount = values.fileSize,
               byteCount > CaptureAttachmentPolicy.maximumVideoBytes {
                throw CaptureAttachmentError.tooLarge(
                    maximumBytes: CaptureAttachmentPolicy.maximumVideoBytes
                )
            }
            return PhotoLibraryMovie(
                data: try Data(contentsOf: received.file, options: .mappedIfSafe),
                suggestedName: received.file.lastPathComponent
            )
        }
    }
}

enum CaptureDraftRecoveryError: LocalizedError, Equatable {
    case damaged
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .damaged:
            String(localized: "The saved quick note is damaged and could not be restored.")
        case .unsupportedVersion:
            String(localized: "The saved quick note was created by an incompatible app version.")
        }
    }
}

private extension JSONEncoder {
    static var captureDraftRecovery: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var captureDraftRecovery: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
