import WidgetKit
import SwiftUI

// MARK: - Model

struct KBStatusEntry: TimelineEntry {
    let date: Date
    let kbCount: Int
    let docCount: Int
    let topKBs: [(id: String, name: String)]
}

// MARK: - Provider

struct KBStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> KBStatusEntry {
        KBStatusEntry(date: .now, kbCount: 3, docCount: 42, topKBs: [
            ("1", "Research"), ("2", "Work Notes"), ("3", "Personal")
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (KBStatusEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KBStatusEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 30 minutes
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> KBStatusEntry {
        let kbs = WidgetGroupDefaults.kbList
        let top = kbs.prefix(3).map { (id: $0["id"] ?? "", name: $0["name"] ?? "") }
        return KBStatusEntry(
            date: .now,
            kbCount: kbs.count,
            docCount: WidgetGroupDefaults.totalDocumentCount,
            topKBs: Array(top)
        )
    }
}

// MARK: - Views

struct KBStatusWidgetView: View {
    let entry: KBStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.blue)
                Text("RAGFlow")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("\(entry.kbCount)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text(entry.kbCount == 1 ? "Knowledge Base" : "Knowledge Bases")
                .font(.caption)
                .foregroundStyle(.secondary)
            if family != .systemSmall {
                Divider()
                Text("\(entry.docCount) documents indexed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .widgetURL(.ragflowHome)
    }
}

struct KBStatusMediumView: View {
    let entry: KBStatusEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.blue)
                    Text("RAGFlow").font(.caption.bold()).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entry.kbCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(entry.kbCount == 1 ? "KB" : "KBs")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(entry.docCount) docs")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.topKBs, id: \.id) { kb in
                    Link(destination: .ragflowKB(id: kb.id)) {
                        Label(kb.name, systemImage: "folder")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Widget

struct KBStatusWidget: Widget {
    let kind = "KBStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KBStatusProvider()) { entry in
            Group {
                if entry.topKBs.isEmpty || [WidgetFamily.systemMedium, .systemLarge].contains(family(for: entry)) {
                    KBStatusMediumView(entry: entry)
                } else {
                    KBStatusWidgetView(entry: entry)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("KB Status")
        .description("See your knowledge base count and top KBs at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    private func family(for _: KBStatusEntry) -> WidgetFamily { .systemSmall }
}
