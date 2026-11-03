import Foundation
import Testing
@testable import Mudsnote

@Suite("Application updates")
@MainActor
struct ApplicationUpdateTests {
    @Test func fixturesAndDevelopmentBundlesNeverCheckRealUpdates() {
        #expect(!ApplicationUpdateController.isEnabled(arguments: ["--visual-qa-notes-dir"],
            bundleURL: URL(fileURLWithPath: "/Applications/Mudsnote.app")))
        #expect(!ApplicationUpdateController.isEnabled(arguments: [],
            bundleURL: URL(fileURLWithPath: "/tmp/candidate/Mudsnote.app")))
    }

    @Test func updateFailureAndRollbackNeverClaimLatest() {
        #expect(ApplicationUpdateController.statusText(["status": "failed"]).contains("失败"))
        #expect(ApplicationUpdateController.statusText(["status": "backoff"]).contains("重试"))
        #expect(ApplicationUpdateController.statusText(["status": "unconfigured"]).contains("尚未配置"))
        #expect(ApplicationUpdateController.statusText(["status": "deferred", "reason": "rolled-back-release"]) == "已保留回退版本")
        #expect(ApplicationUpdateController.statusText(["status": "deferred", "reason": "app-in-use"]) == "发现新版本，退出后自动安装")
        #expect(ApplicationUpdateController.statusText(["status": "unchanged"]) == "已是最新发布版本")
    }
}
