import AppKit
import Foundation

@MainActor
final class ApplicationUpdateController {
    private var process: Process?
    private var lastCheck: Date?
    private(set) var status = "尚未检查更新"
    private var wantsResultAlert = false
    var onChange: (() -> Void)?
    let enabled: Bool

    init(arguments: Set<String>, bundleURL: URL = Bundle.main.bundleURL) {
        enabled = Self.isEnabled(arguments: arguments, bundleURL: bundleURL)
    }

    static func isEnabled(arguments: Set<String>, bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path == "/Applications/Mudsnote.app"
            && !arguments.contains("--visual-qa-notes-dir")
            && ProcessInfo.processInfo.environment["CI"] == nil
    }

    static var versionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版"
        let revision = info["MudsnoteSourceRevision"] as? String ?? "未标记"
        return "版本 \(version) · \(revision.prefix(7))"
    }

    static func statusText(_ result: [String: String]) -> String {
        switch result["status"] {
        case "unchanged": return "已是最新发布版本"
        case "installed": return "更新已安装，下次打开生效"
        case "unconfigured": return "尚未配置自动更新服务"
        case "backoff": return "更新暂不可用，稍后自动重试"
        case "deferred":
            if ["app-in-use", "app-started-during-staging"].contains(result["reason"]) {
                return "发现新版本，退出后自动安装"
            }
            if result["reason"] == "rolled-back-release" { return "已保留回退版本" }
            return "更新已延后，稍后自动重试"
        default: return "检查更新失败，稍后重试"
        }
    }

    func check(manual: Bool = false) {
        guard enabled else { return }
        if process != nil {
            wantsResultAlert = wantsResultAlert || manual
            return
        }
        if !manual, let lastCheck, Date().timeIntervalSince(lastCheck) < 900 { return }
        guard let helper = Bundle.main.url(forResource: "macos_update_check", withExtension: "py") else {
            finish(result: ["status": "failed"], manual: manual)
            return
        }
        lastCheck = Date()
        wantsResultAlert = manual
        status = "正在检查更新…"
        onChange?()
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [helper.path]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] _ in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let result = (try? JSONDecoder().decode([String: String].self, from: data)) ?? ["status": "failed"]
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process = nil
                self.finish(result: result, manual: self.wantsResultAlert)
            }
        }
        process = task
        do { try task.run() }
        catch {
            process = nil
            finish(result: ["status": "failed"], manual: manual)
        }
    }

    private func finish(result: [String: String], manual: Bool) {
        status = Self.statusText(result)
        onChange?()
        guard manual else { return }
        let alert = NSAlert()
        alert.messageText = status
        alert.informativeText = Self.versionLabel
        if result["status"] == "unconfigured" {
            alert.informativeText += "\n请先在这台 Mac 安装 Mudsnote 的私人更新服务。"
        }
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
