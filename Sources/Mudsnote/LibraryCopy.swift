import Foundation

enum LibraryCopy {
    static let home = "首页"
    static let allICloudNotes = "所有 iCloud 笔记"
    static let inbox = "收件箱"
    static let notes = "笔记"
    static let recentlyDeleted = "最近删除"
    static let folders = "文件夹"
    static let tags = "标签"
    static let pinned = "置顶"
    static let today = "今天"
    static let yesterday = "昨天"
    static let previousSevenDays = "过去 7 天"
    static let previousThirtyDays = "过去 30 天"
    static let search = "搜索"
    static let searchNotes = "搜索笔记"
    static let loadingFolders = "正在载入文件夹…"
    static let noFolders = "没有文件夹"
    static let searching = "正在搜索…"
    static let noResults = "没有结果"
    static let recentlyDeletedIsEmpty = "最近删除为空"
    static let noNotes = "没有笔记"
    static let newNote = "新建笔记"
    static let noAdditionalText = "无其他内容"

    static func noteCount(_ count: Int) -> String {
        "\(count) 条笔记"
    }

    static func resultCount(_ count: Int) -> String {
        "\(count) 条结果"
    }
}
