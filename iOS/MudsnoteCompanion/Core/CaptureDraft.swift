import Foundation

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
            return "Inbox"
        case .daily(let date):
            return "Daily \(Self.dayFormatter.string(from: date))"
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
}

enum MarkdownAttachmentKind: String, Equatable {
    case image
    case audio
}

struct MarkdownAttachmentReference: Equatable {
    var relativePath: String
    var kind: MarkdownAttachmentKind
}
