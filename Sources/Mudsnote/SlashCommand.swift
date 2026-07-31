import AppKit
import Carbon.HIToolbox
import Foundation
import MudsnoteCore

enum SlashCommand: CaseIterable {
    case heading1, heading2, heading3, checklist, bulletList, orderedList, divider
    case aiSummarize, aiFix, aiTodos

    var identifier: String {
        switch self {
        case .heading1: return "heading1"
        case .heading2: return "heading2"
        case .heading3: return "heading3"
        case .checklist: return "checklist"
        case .bulletList: return "bulletList"
        case .orderedList: return "orderedList"
        case .divider: return "divider"
        case .aiSummarize: return "aiSummarize"
        case .aiFix: return "aiFix"
        case .aiTodos: return "aiTodos"
        }
    }

    var title: String {
        switch self {
        case .heading1: return "一级标题"
        case .heading2: return "二级标题"
        case .heading3: return "三级标题"
        case .checklist: return "待办列表"
        case .bulletList: return "项目符号列表"
        case .orderedList: return "编号列表"
        case .divider: return "分割线"
        case .aiSummarize: return "AI 总结"
        case .aiFix: return "AI 修正"
        case .aiTodos: return "AI 提取待办"
        }
    }

    var subtitle: String {
        switch self {
        case .heading1, .heading2, .heading3: return "将当前行改为标题"
        case .checklist: return "开始一个待办项"
        case .bulletList: return "开始一个项目符号项"
        case .orderedList: return "开始一个编号项"
        case .divider: return "插入分割线"
        case .aiSummarize: return "总结选中内容或当前笔记"
        case .aiFix: return "修正选中内容或当前段落"
        case .aiTodos: return "提取 Markdown 待办项"
        }
    }

    var searchAliases: [String] {
        switch self {
        case .heading1: return ["heading 1", "h1"]
        case .heading2: return ["heading 2", "h2"]
        case .heading3: return ["heading 3", "h3"]
        case .checklist: return ["todo", "to-do", "checklist"]
        case .bulletList: return ["bullet", "bulleted", "list"]
        case .orderedList: return ["numbered", "ordered", "number"]
        case .divider: return ["divider", "line"]
        case .aiSummarize: return ["summarize", "summary", "sum", "tldr"]
        case .aiFix: return ["fix", "proofread", "grammar", "ai fix"]
        case .aiTodos: return ["todos", "actions", "tasks"]
        }
    }

    var symbolName: String {
        switch self {
        case .heading1: return "1.square"
        case .heading2: return "2.square"
        case .heading3: return "3.square"
        case .checklist: return "checkmark.square"
        case .bulletList: return "list.bullet"
        case .orderedList: return "list.number"
        case .divider: return "minus"
        case .aiSummarize: return "text.quote"
        case .aiFix: return "wand.and.stars"
        case .aiTodos: return "checklist"
        }
    }

    var aiActionID: AIActionID? {
        switch self {
        case .aiSummarize: return .summarize
        case .aiFix: return .fix
        case .aiTodos: return .todos
        default: return nil
        }
    }

    static func matching(_ query: String, includesAI: Bool) -> [SlashCommand] {
        let normalizedQuery = normalizedSearchText(query)
        return allCases.filter { command in
            guard includesAI || command.aiActionID == nil else { return false }
            guard !normalizedQuery.isEmpty else { return true }

            let localizedText = [command.title, command.subtitle].map(normalizedSearchText)
            if localizedText.contains(where: { $0.contains(normalizedQuery) }) {
                return true
            }
            let stableEnglishTerms = [command.identifier] + command.searchAliases
            return stableEnglishTerms
                .map(normalizedSearchText)
                .contains { $0.hasPrefix(normalizedQuery) }
        }
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}

@MainActor
protocol SlashCommandInputSourceSessioning: AnyObject {
    var isActive: Bool { get }
    @discardableResult
    func beginIfAllowed(hasMarkedText: Bool, editorIsFirstResponder: Bool) -> Bool
    func end()
}

@MainActor
final class SlashCommandInputSourceSession: SlashCommandInputSourceSessioning {
    private var previousInputSource: TISInputSource?
    private var selectedASCIIInputSourceID: String?

    var isActive: Bool {
        previousInputSource != nil
    }

    @discardableResult
    func beginIfAllowed(hasMarkedText: Bool, editorIsFirstResponder: Bool) -> Bool {
        guard !isActive, !hasMarkedText, editorIsFirstResponder else { return false }

        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let ascii = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
        guard inputSourceID(current) != inputSourceID(ascii) else { return false }
        guard TISSelectInputSource(ascii) == noErr else { return false }

        previousInputSource = current
        selectedASCIIInputSourceID = inputSourceID(ascii)
        return true
    }

    func end() {
        guard let previousInputSource else { return }
        defer {
            self.previousInputSource = nil
            selectedASCIIInputSourceID = nil
        }

        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard inputSourceID(current) == selectedASCIIInputSourceID else {
            return
        }
        _ = TISSelectInputSource(previousInputSource)
    }

    private func inputSourceID(_ inputSource: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
