import SwiftUI

@main
struct MudsnoteCompanionApp: App {
    @StateObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        MudsnoteUITestLaunchConfiguration.prepareIfNeeded()
        _appModel = StateObject(wrappedValue: AppModel())
        AppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .task {
                    appModel.consumeSystemEntryRequest()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        appModel.consumeSystemEntryRequest()
                    }
                }
                .onOpenURL { url in
                    appModel.handle(url: url)
                }
                .preferredColorScheme(.dark)
        }
    }
}

private enum MudsnoteUITestLaunchConfiguration {
    private static let resetArgument = "-ui-testing-reset"
    private static let fixtureFolderArgument = "-ui-testing-fixture-folder"
    private static let invalidBookmarkArgument = "-ui-testing-invalid-bookmark"
    private static let fixtureFolderName = "MudsnoteUITestLibrary"

    static func prepareIfNeeded() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(resetArgument)
                || arguments.contains(fixtureFolderArgument)
                || arguments.contains(invalidBookmarkArgument)
        else { return }

        let access = FolderAccessService()
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fixtureFolderName, isDirectory: true)

        if arguments.contains(resetArgument) {
            access.forgetPersistedFolder()
            UserDefaults.standard.removeObject(forKey: SystemEntryRequest.pendingRouteKey)
            try? FileManager.default.removeItem(at: root)
        }

        if arguments.contains(fixtureFolderArgument) {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try FolderInitializer.initialize(root)
                if let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=") {
                    try image.write(
                        to: root.appendingPathComponent("Attachments/ui-test.png"),
                        options: .atomic
                    )
                }
                try Data("Quick Look fixture".utf8).write(
                    to: root.appendingPathComponent("Attachments/ui-test.txt"),
                    options: .atomic
                )
                let projects = root.appendingPathComponent("Projects", isDirectory: true)
                try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
                try "# UI Lifecycle\n\nRestore this note end to end.\n\n[QA Document](Attachments/ui-test.txt)\n\n| Item | Status |\n| --- | --- |\n| Preview | Ready |\n".write(
                    to: projects.appendingPathComponent("UI Lifecycle.md"),
                    atomically: true,
                    encoding: .utf8
                )
                try access.persistFolder(root)
            } catch {
                assertionFailure("Could not prepare the Mudsnote UI-test library: \(error)")
            }
        }

        if arguments.contains(invalidBookmarkArgument) {
            UserDefaults.standard.set(
                Data("invalid-bookmark".utf8),
                forKey: FolderAccessService.DefaultsKey.bookmarkData
            )
        }
        #endif
    }
}
