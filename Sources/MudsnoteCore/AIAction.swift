import Foundation

public enum AIActionID: String, CaseIterable, Sendable {
    case summarize
    case fix
    case todos

    public var displayName: String {
        switch self {
        case .summarize: return "总结"
        case .fix: return "修正拼写和语法"
        case .todos: return "提取待办"
        }
    }

    public var slashCommands: [String] {
        switch self {
        case .summarize: return ["summarize", "sum", "tldr"]
        case .fix: return ["fix", "proofread", "grammar"]
        case .todos: return ["todos", "actions", "tasks"]
        }
    }

    public var defaultOutputMode: AIOutputMode {
        switch self {
        case .summarize, .todos: return .insertBelow
        case .fix: return .replaceInput
        }
    }
}

public enum AIInputScope: Sendable {
    case selection
    case currentParagraph
    case wholeNote
}

public enum AIOutputMode: Sendable {
    case replaceInput
    case insertBelow
    case copyOnly
}

public struct AIRequest: Sendable {
    public let actionID: AIActionID
    public let noteTitle: String?
    public let inputMarkdown: String
    public let scope: AIInputScope
    public let userInstruction: String?

    public init(
        actionID: AIActionID,
        noteTitle: String?,
        inputMarkdown: String,
        scope: AIInputScope,
        userInstruction: String? = nil
    ) {
        self.actionID = actionID
        self.noteTitle = noteTitle
        self.inputMarkdown = inputMarkdown
        self.scope = scope
        self.userInstruction = userInstruction
    }
}

public enum AIError: LocalizedError, Equatable {
    case disabled
    case providerNotConfigured
    case localProviderUnavailable(String)
    case emptyInput
    case requestFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "AI 功能已关闭。请在设置中启用 AI。"
        case .providerNotConfigured:
            return "未找到本机 Codex。请在设置中确认 Codex 运行时。"
        case .localProviderUnavailable(let baseURL):
            return "无法启动本机 Codex：\(baseURL)"
        case .emptyInput:
            return "没有可发送给 AI 的文本。"
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "AI 提供方返回了无法解析的响应。"
        }
    }
}
