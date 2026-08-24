import AppKit
import Darwin
import Foundation
import MudsnoteCore

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--migrate-inline-tags") {
    let roots = arguments.indices.compactMap { index -> URL? in
        guard arguments[index] == "--root" else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return URL(
            fileURLWithPath: arguments[valueIndex],
            isDirectory: true
        ).standardizedFileURL
    }
    guard !roots.isEmpty else {
        FileHandle.standardError.write(Data("至少需要一个 --root 路径\n".utf8))
        exit(2)
    }

    do {
        let store = NoteStore()
        let result = arguments.contains("--apply")
            ? try store.migrateInlineTags(in: roots)
            : try store.inlineTagMigrationPreview(in: roots)
        let mode = arguments.contains("--apply") ? "已迁移" : "待迁移"
        print("\(mode)文件：\(result.fileCount)，正文标签：\(result.occurrenceCount)")
        for file in result.files {
            print("\(file.url.path)\t\(file.occurrenceCount)\t\(file.tags.joined(separator: ","))")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("标签迁移失败：\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppController()
application.delegate = delegate
withExtendedLifetime(delegate) {
    application.run()
}
