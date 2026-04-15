import WidgetKit
import SwiftUI

// MARK: - Model

struct RecentChatEntry: TimelineEntry {
    let date: Date
    let chatTitle: String
    let kbName: String
    let hasContent: Bool
}

// MARK: - Provider

struct RecentChatProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentChatEntry {
        RecentChatEntry(date: .now, chatTitle: "Summarize Q1 report", kbName: "Work Notes", hasContent: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentChatEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentChatEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> RecentChatEntry {
        let title = WidgetGroupDefaults.recentChatTitle
        let kbName = WidgetGroupDefaults.recentChatKBName
        return RecentChatEntry(
            date: .now,
            chatTitle: title,
            kbName: kbName,
            hasContent: !title.isEmpty
        )
    }
}

// MARK: - View

struct RecentChatWidgetView: View {
    let entry: RecentChatEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(.purple)
                Text("Recent Chat")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.hasContent {
                Text(entry.chatTitle)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(entry.kbName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No chats yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .widgetURL(.ragflowHome)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct RecentChatWidget: Widget {
    let kind = "RecentChatWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentChatProvider()) { entry in
            RecentChatWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Chat")
        .description("Jump back into your most recent RAGFlow conversation.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
