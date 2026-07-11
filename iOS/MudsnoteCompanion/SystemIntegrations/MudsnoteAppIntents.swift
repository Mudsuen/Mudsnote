import AppIntents
import Foundation

struct CaptureMemoIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Memo"
    static var description = IntentDescription("Open Mudsnote to the quick capture console.")
    static var openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(CaptureRoute.text.rawValue, forKey: SystemEntryRequest.pendingRouteKey)
        return .result()
    }
}

struct CaptureImageIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Image"
    static var description = IntentDescription("Open Mudsnote to quick capture with the image tool ready.")
    static var openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(CaptureRoute.image.rawValue, forKey: SystemEntryRequest.pendingRouteKey)
        return .result()
    }
}

struct CaptureAudioIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Audio"
    static var description = IntentDescription("Open Mudsnote to quick capture with the audio tool ready.")
    static var openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(CaptureRoute.audio.rawValue, forKey: SystemEntryRequest.pendingRouteKey)
        return .result()
    }
}

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureMemoIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Quick note in \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: CaptureImageIntent(),
            phrases: [
                "Capture image in \(.applicationName)",
                "Add photo to \(.applicationName)"
            ],
            shortTitle: "Capture Image",
            systemImageName: "photo"
        )

        AppShortcut(
            intent: CaptureAudioIntent(),
            phrases: [
                "Capture audio in \(.applicationName)",
                "Record audio in \(.applicationName)"
            ],
            shortTitle: "Capture Audio",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: AppendToInboxIntent(),
            phrases: [
                "Append to Inbox in \(.applicationName)",
                "Add memo to \(.applicationName)"
            ],
            shortTitle: "Append Inbox",
            systemImageName: "tray.and.arrow.down"
        )

        AppShortcut(
            intent: AppendToDailyIntent(),
            phrases: [
                "Append to Daily in \(.applicationName)",
                "Add daily note to \(.applicationName)"
            ],
            shortTitle: "Append Daily",
            systemImageName: "calendar.badge.plus"
        )
    }
}

struct AppendToInboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Append to Inbox"
    static var description = IntentDescription("Append text to Inbox.md when Mudsnote has an authorized folder.")

    @Parameter(title: "Text")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult {
        let access = FolderAccessService()
        guard let root = try access.resolvePersistedFolder() else {
            throw FolderAccessError.missingFolder
        }
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let draft = CaptureDraft(body: text, target: .inbox)
        let pending = try await store.preparePendingWrite(for: draft, root: root)
        try await store.performPendingWrite(pending)
        return .result()
    }
}

struct AppendToDailyIntent: AppIntent {
    static var title: LocalizedStringResource = "Append to Daily"
    static var description = IntentDescription("Append text to today's Daily Markdown file.")

    @Parameter(title: "Text")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult {
        let access = FolderAccessService()
        guard let root = try access.resolvePersistedFolder() else {
            throw FolderAccessError.missingFolder
        }
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let draft = CaptureDraft(body: text, target: .daily(Date()))
        let pending = try await store.preparePendingWrite(for: draft, root: root)
        try await store.performPendingWrite(pending)
        return .result()
    }
}

#if MUDSNOTE_WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct QuickCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickCaptureWidget", provider: Provider()) { _ in
            VStack(alignment: .leading, spacing: 10) {
                Text("Mudsnote")
                    .font(.headline)
                Text("What's on your mind?")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Quick Note", intent: CaptureMemoIntent())
                    Button("Daily", intent: CaptureMemoIntent())
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: Date())], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}
#endif
