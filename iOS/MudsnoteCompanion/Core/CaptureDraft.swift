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
    case audio(data: Data, preferredExtension: String)

    var markdownTag: String {
        switch self {
        case .image:
            return "#图片"
        case .audio:
            return "#语音"
        }
    }

    var filePrefix: String {
        switch self {
        case .image:
            return "IMG"
        case .audio:
            return "audio"
        }
    }

    var data: Data {
        switch self {
        case .image(let data, _), .audio(let data, _):
            return data
        }
    }

    var preferredExtension: String {
        switch self {
        case .image(_, let preferredExtension), .audio(_, let preferredExtension):
            return preferredExtension
        }
    }

    var referenceKind: MarkdownAttachmentKind {
        switch self {
        case .image:
            return .image
        case .audio:
            return .audio
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
}

enum CaptureAttachmentPolicy {
    static let maximumAttachmentCount = 8
    static let maximumImageBytes = 15 * 1_024 * 1_024
    static let maximumAudioBytes = 25 * 1_024 * 1_024
    static let maximumDraftBytes = 32 * 1_024 * 1_024

    static func validateAppending(_ attachment: CaptureAttachment, to existing: [CaptureAttachment]) throws {
        guard existing.count < maximumAttachmentCount else {
            throw CaptureAttachmentError.tooMany(maximum: maximumAttachmentCount)
        }
        let individualLimit: Int
        switch attachment {
        case .image:
            individualLimit = maximumImageBytes
        case .audio:
            individualLimit = maximumAudioBytes
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
    case tooMany(maximum: Int)
    case tooLarge(maximumBytes: Int)
    case draftTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return String(localized: "The attachment is empty.")
        case .unsupportedImage:
            return String(localized: "Choose a supported image file.")
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
    case audio
}

struct MarkdownAttachmentReference: Equatable {
    var relativePath: String
    var kind: MarkdownAttachmentKind
}
