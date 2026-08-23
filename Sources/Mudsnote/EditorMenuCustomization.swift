import Foundation
import MudsnoteCore

enum EditorContextMenuOption: String, CaseIterable {
    case undo
    case cut
    case copy
    case paste
    case insertTable
    case insertLink
    case insertAttachment

    var title: String {
        switch self {
        case .undo: return "撤销"
        case .cut: return "剪切"
        case .copy: return "拷贝"
        case .paste: return "粘贴"
        case .insertTable: return "插入表格"
        case .insertLink: return "插入链接"
        case .insertAttachment: return "插入附件"
        }
    }
}

enum SelectionToolbarOption: String, CaseIterable {
    case bold
    case italic
    case underline
    case strikethrough
    case highlight
    case conversion
    case checklist
    case bulletList
    case orderedList

    var title: String {
        switch self {
        case .bold: return "加粗"
        case .italic: return "斜体"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .highlight: return "高亮"
        case .conversion: return "正文与标题（Aa）"
        case .checklist: return "待办列表"
        case .bulletList: return "项目符号列表"
        case .orderedList: return "编号列表"
        }
    }
}

extension NoteStore {
    var enabledEditorContextMenuOptions: Set<EditorContextMenuOption> {
        get {
            guard let stored = editorContextMenuItemIdentifiers else {
                return Set(EditorContextMenuOption.allCases)
            }
            return Set(stored.compactMap(EditorContextMenuOption.init(rawValue:)))
        }
        set { editorContextMenuItemIdentifiers = EditorContextMenuOption.allCases.filter(newValue.contains).map(\.rawValue) }
    }

    var enabledSelectionToolbarOptions: Set<SelectionToolbarOption> {
        get {
            guard let stored = selectionToolbarItemIdentifiers else {
                return Set(SelectionToolbarOption.allCases)
            }
            return Set(stored.compactMap(SelectionToolbarOption.init(rawValue:)))
        }
        set { selectionToolbarItemIdentifiers = SelectionToolbarOption.allCases.filter(newValue.contains).map(\.rawValue) }
    }
}
