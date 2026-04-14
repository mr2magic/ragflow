import SwiftUI

/// Shows all chat sessions for a knowledge base.
/// Tapping a session navigates to ChatView for that session.
/// "New Chat" toolbar button creates a fresh session.
struct ConversationsListView: View {
    let kb: KnowledgeBase

    @State private var sessions: [ChatSession] = []
    @State private var selectedSession: ChatSession?
    @State private var sessionToRename: ChatSession?
    @State private var renameText = ""
    @State private var sessionToDelete: ChatSession?

    private let db = DatabaseService.shared

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedSession) { session in
            ChatView(kb: kb, session: session)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createNewSession) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        // MARK: - Rename Chat
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

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                Button {
                    selectedSession = session
                } label: {
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
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            VStack(spacing: Spacing.sm) {
                Text("No Chats Yet")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Start a new chat to ask questions about your documents in **\(kb.name)**.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: createNewSession) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func reload() {
        sessions = (try? db.allSessions(kbId: kb.id)) ?? []
    }

    private func createNewSession() {
        let session = ChatSession(
            id: UUID().uuidString,
            kbId: kb.id,
            name: "Chat",
            createdAt: Date()
        )
        try? db.saveSession(session)
        reload()
        selectedSession = session
    }

    private func commitRename() {
        guard let session = sessionToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty else {
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
