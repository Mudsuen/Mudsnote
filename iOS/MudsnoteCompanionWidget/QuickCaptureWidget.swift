import SwiftUI
import WidgetKit

struct QuickCaptureWidget: Widget {
    private let kind = "MudsnoteQuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { entry in
            QuickCaptureWidgetView(entry: entry)
                .containerBackground(Color(red: 0.03, green: 0.04, blue: 0.05), for: .widget)
                .widgetURL(CaptureWidgetRoute.text.url)
        }
        .configurationDisplayName("Mudsnote Capture")
        .description("Open Mudsnote for text, audio, or image capture.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct MudsnoteActionsWidget: Widget {
    private let kind = "MudsnoteActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { entry in
            MudsnoteActionsWidgetView(entry: entry)
                .containerBackground(MudsnoteWidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Mudsnote Actions")
        .description("Search notes, capture speech, or start a quick note.")
        .supportedFamilies([.systemMedium])
    }
}

private struct QuickCaptureEntry: TimelineEntry {
    let date: Date
}

private struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        completion(Timeline(entries: [QuickCaptureEntry(date: .now)], policy: .never))
    }
}

private struct QuickCaptureWidgetView: View {
    let entry: QuickCaptureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MudsnoteWidgetStyle.accent)
                    Text("Mudsnote")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 8)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(MudsnoteWidgetStyle.accent, in: Circle())
                Spacer(minLength: 8)
                Text("Quick Note")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Capture an idea")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct MudsnoteActionsWidgetView: View {
    let entry: QuickCaptureEntry

    var body: some View {
        VStack(spacing: 10) {
            Link(destination: CaptureWidgetRoute.search.url) {
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search Notes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Find anything in Mudsnote")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.50))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(MudsnoteWidgetStyle.raised, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                MudsnoteActionLink(
                    route: .audio,
                    title: "Voice input",
                    systemImage: "waveform"
                )
                MudsnoteActionLink(
                    route: .text,
                    title: "Quick Note",
                    systemImage: "square.and.pencil"
                )
            }
        }
    }
}

private enum CaptureWidgetRoute {
    case search
    case text
    case audio
    case image

    var url: URL {
        switch self {
        case .search:
            return URL(string: "mudsnote://search")!
        case .text:
            return URL(string: "mudsnote://capture?mode=text")!
        case .audio:
            return URL(string: "mudsnote://capture?mode=audio")!
        case .image:
            return URL(string: "mudsnote://capture?mode=image")!
        }
    }
}

private struct MudsnoteActionLink: View {
    var route: CaptureWidgetRoute
    var title: LocalizedStringKey
    var systemImage: String

    var body: some View {
        Link(destination: route.url) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(MudsnoteWidgetStyle.accent, in: Circle())
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(MudsnoteWidgetStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum MudsnoteWidgetStyle {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.055)
    static let raised = Color.white.opacity(0.075)
    static let accent = Color(red: 0.94, green: 0.78, blue: 0.28)
}
