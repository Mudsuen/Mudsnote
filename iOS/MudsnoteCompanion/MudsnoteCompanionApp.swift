import SwiftUI

@main
struct MudsnoteCompanionApp: App {
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
