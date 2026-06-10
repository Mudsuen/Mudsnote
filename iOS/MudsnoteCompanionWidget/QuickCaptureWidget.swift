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
            Link(destination: CaptureWidgetRoute.text.url) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .semibold))
                    .widgetAccentable()
            }
        default:
            VStack(spacing: 8) {
                CaptureLinkTile(route: .text, systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 8) {
                    CaptureLinkTile(route: .audio, systemImage: "waveform")
                    CaptureLinkTile(route: .image, systemImage: "photo")
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private enum CaptureWidgetRoute {
    case text
    case audio
    case image

    var url: URL {
        switch self {
        case .text:
            return URL(string: "mudsnote://capture?mode=text")!
        case .audio:
            return URL(string: "mudsnote://capture?mode=audio")!
        case .image:
            return URL(string: "mudsnote://capture?mode=image")!
        }
    }
}

private struct CaptureLinkTile: View {
    var route: CaptureWidgetRoute
    var systemImage: String

    var body: some View {
        Link(destination: route.url) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
