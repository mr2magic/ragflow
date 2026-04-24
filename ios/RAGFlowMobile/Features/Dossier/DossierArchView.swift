import SwiftUI

/// Chat session archive — shown on the LOG tab of DossierKBDetailView.
/// Lists all sessions for the KB in Dossier style; tap to open, swipe to delete.
struct DossierArchiveView: View {
    let kb: KnowledgeBase

    @State private var sessions: [ChatSession] = []
    @State private var chatSession: ChatSession?
    @State private var sessionToRename: ChatSession?
    @State private var renameText = ""
    @State private var sessionToDelete: ChatSession?

    private let db = DatabaseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if sessions.isEmpty {
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

    // MARK: - Session list

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                Button { chatSession = session } label: {
                    sessionRow(session)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename") {
                        renameText = session.name
                        sessionToRename = session
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        sessionToDelete = session
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        sessionToDelete = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowBackground(DT.card)
                .listRowSeparatorTint(DT.rule)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DT.manila)
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(DT.serif(14))
                    .foregroundStyle(DT.ink)
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DT.mono(10))
                    .foregroundStyle(DT.inkFaint)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DT.inkFaint)
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
        sessions = (try? db.allSessions(kbId: kb.id)) ?? []
    }

    private func newChat() {
        let session = ChatSession(
            id: UUID().uuidString,
            kbId: kb.id,
            name: "Chat",
            createdAt: Date()
        )
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
