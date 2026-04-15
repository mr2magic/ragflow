import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Intent configuration

struct SelectKBIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Knowledge Base"
    static var description = IntentDescription("Choose the knowledge base to open.")

    @Parameter(title: "Knowledge Base")
    var kbName: String?

    @Parameter(title: "Knowledge Base ID")
    var kbId: String?
}

// MARK: - Model

struct QuickQueryEntry: TimelineEntry {
    let date: Date
    let kbName: String
    let kbId: String
    let docCount: Int
}

// MARK: - Provider

struct QuickQueryProvider: AppIntentTimelineProvider {
    typealias Entry = QuickQueryEntry
    typealias Intent = SelectKBIntent

    func placeholder(in context: Context) -> QuickQueryEntry {
        QuickQueryEntry(date: .now, kbName: "Research", kbId: "", docCount: 12)
    }

    func snapshot(for configuration: SelectKBIntent, in context: Context) async -> QuickQueryEntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: SelectKBIntent, in context: Context) async -> Timeline<QuickQueryEntry> {
        let entry = makeEntry(for: configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(for config: SelectKBIntent) -> QuickQueryEntry {
        let kbs = WidgetGroupDefaults.kbList
        // Use configured KB if valid, otherwise first KB, otherwise empty
        let kb: [String: String]?
        if let id = config.kbId, let match = kbs.first(where: { $0["id"] == id }) {
            kb = match
        } else {
            kb = kbs.first
        }
        return QuickQueryEntry(
            date: .now,
            kbName: kb?["name"] ?? "No KB",
            kbId: kb?["id"] ?? "",
            docCount: 0
        )
    }
}

// MARK: - View

struct QuickQueryWidgetView: View {
    let entry: QuickQueryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundStyle(.orange)
                Text("Quick Query")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(entry.kbName)
                .font(.headline)
                .lineLimit(2)
            Text("Tap to chat")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .widgetURL(entry.kbId.isEmpty ? .ragflowHome : .ragflowKB(id: entry.kbId))
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct QuickQueryWidget: Widget {
    let kind = "QuickQueryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectKBIntent.self, provider: QuickQueryProvider()) { entry in
            QuickQueryWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Query")
        .description("Tap to open a specific knowledge base and start chatting.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
