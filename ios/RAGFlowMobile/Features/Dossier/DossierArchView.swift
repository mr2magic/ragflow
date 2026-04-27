import SwiftUI

/// Chat session archive — LOG tab. Date-grouped sessions with grounding stamps and query previews.
struct DossierArchiveView: View {
    let kb: KnowledgeBase

    @State private var enriched: [EnrichedSession] = []
    @State private var chatSession: ChatSession?
    @State private var sessionToRename: ChatSession?
    @State private var renameText = ""
    @State private var sessionToDelete: ChatSession?

    private let db = DatabaseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if enriched.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .background(DT.manila)
        .sheet(item: $chatSession) { session in
            DossierChatView(kb: kb, session: session)
        }
        .sheet(item: $sessionToRename) { _ in
            RenameSheet(title: "Rename Chat", text: $renameText) {
                commitRename()
            }
        }
        .confirmationDialog(
            "Delete \"\(sessionToDelete?.name ?? "this chat")\"?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("All messages in this chat will be permanently deleted.")
        }
        .onAppear { reload() }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ARCHIVE")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                Button { newChat() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DT.stamp)
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Session list (date-grouped)

    private var groupedSessions: [(label: String, sessions: [EnrichedSession])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        var groups: [String: [EnrichedSession]] = [:]
        for es in enriched {
            let day = cal.startOfDay(for: es.session.createdAt)
            let label: String
            if day == today {
                label = "TODAY"
            } else if day == yesterday {
                label = "YESTERDAY"
            } else {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMM d"
                label = fmt.string(from: day).uppercased()
            }
            groups[label, default: []].append(es)
        }

        let orderedLabels = groups.keys.sorted { a, b in
            let rank: (String) -> Int = { s in
                if s == "TODAY" { return 0 }
                if s == "YESTERDAY" { return 1 }
                return 2
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a > b
        }

        return orderedLabels.map { label in
            (label: label, sessions: groups[label]!.sorted { $0.session.createdAt > $1.session.createdAt })
        }
    }

    private var sessionList: some View {
        List {
            ForEach(groupedSessions, id: \.label) { group in
                Section {
                    ForEach(group.sessions) { es in
                        sessionRow(es)
                            .listRowBackground(DT.card)
                            .listRowSeparatorTint(DT.rule)
                            .contextMenu {
                                Button("Rename") {
                                    renameText = es.session.name
                                    sessionToRename = es.session
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    sessionToDelete = es.session
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    sessionToDelete = es.session
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(group.label)
                        .font(DT.mono(9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(DT.inkFaint)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DT.manila)
    }

    private func sessionRow(_ es: EnrichedSession) -> some View {
        let stamp = es.groundingStamp
        let idx = (enriched.firstIndex(where: { $0.id == es.id }) ?? 0) + 1
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(String(format: "#%04d", idx))
                    .font(DT.mono(10, weight: .bold))
                    .foregroundStyle(DT.inkFaint)
                Text(es.session.createdAt, style: .time)
                    .font(DT.mono(9))
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                Text(stamp.label)
                    .font(DT.mono(8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(stamp.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(stamp.color, lineWidth: 1.5))
                    .opacity(0.9)
            }

            if let preview = es.queryPreview {
                Text("\u{201C}\(preview)\u{201D}")
                    .font(DT.serif(13))
                    .italic()
                    .foregroundStyle(DT.inkSoft)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text("KB · \(kb.name)")
                    .font(DT.mono(9))
                    .tracking(0.5)
                    .foregroundStyle(DT.inkFaint)
                if es.sourceCount > 0 {
                    Text("\(es.sourceCount) CITED")
                        .font(DT.mono(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(DT.green)
                }
                Spacer()
                Button { chatSession = es.session } label: {
                    Text("REOPEN →")
                        .font(DT.mono(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DT.ribbon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 44))
                .foregroundStyle(DT.inkFaint)
            Text("NO SESSIONS")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Start a new chat from the Query tab to begin building your archive.")
                .font(DT.serif(14))
                .italic()
                .foregroundStyle(DT.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { newChat() } label: {
                Text("NEW CHAT")
                    .font(DT.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DT.stamp)
                    .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func reload() {
        let sessions = (try? db.allSessions(kbId: kb.id)) ?? []
        enriched = sessions.map { session in
            let preview = try? db.firstUserMessage(sessionId: session.id)
            let sources = (try? db.sourceCount(sessionId: session.id)) ?? 0
            return EnrichedSession(session: session, queryPreview: preview, sourceCount: sources)
        }
    }

    private func newChat() {
        let session = ChatSession(id: UUID().uuidString, kbId: kb.id, name: "Chat", createdAt: Date())
        try? db.saveSession(session)
        reload()
        chatSession = session
    }

    private func commitRename() {
        guard let session = sessionToRename,
              !renameText.trimmingCharacters(in: .whitespaces).isEmpty else {
            sessionToRename = nil
            return
        }
        try? db.renameSession(id: session.id, name: renameText.trimmingCharacters(in: .whitespaces))
        reload()
        sessionToRename = nil
    }

    private func confirmDelete() {
        guard let session = sessionToDelete else { return }
        try? db.deleteSession(session.id)
        reload()
        sessionToDelete = nil
    }
}

// MARK: - EnrichedSession

private struct EnrichedSession: Identifiable {
    let session: ChatSession
    let queryPreview: String?
    let sourceCount: Int

    var id: String { session.id }

    var groundingStamp: (label: String, color: Color) {
        switch sourceCount {
        case 2...: return ("GROUNDED",   DT.green)
        case 1:    return ("PARTIAL",    DT.amber)
        default:   return ("UNGROUNDED", DT.stamp)
        }
    }
}
