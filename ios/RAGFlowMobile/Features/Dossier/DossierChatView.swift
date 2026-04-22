import SwiftUI

// D-CHAT1 — Session persistence: shell owns session state; .id(session.id) forces
// @StateObject recreation in DossierChatContent whenever the session changes (new chat).
struct DossierChatView: View {
    let kb: KnowledgeBase
    @State private var session: ChatSession

    init(kb: KnowledgeBase) {
        self.kb = kb
        _session = State(initialValue: Self.loadOrCreateSession(kb: kb))
    }

    var body: some View {
        DossierChatContent(kb: kb, session: session) { newSession in
            session = newSession
        }
        .id(session.id)
    }

    private static func loadOrCreateSession(kb: KnowledgeBase) -> ChatSession {
        let db = DatabaseService.shared
        if let existing = try? db.allSessions(kbId: kb.id).first {
            return existing
        }
        let s = ChatSession(id: UUID().uuidString, kbId: kb.id, name: "Chat", createdAt: Date())
        try? db.saveSession(s)
        return s
    }
}

// MARK: - Content view (owns ChatViewModel)

private struct DossierChatContent: View {
    let kb: KnowledgeBase
    let session: ChatSession
    let onNewSession: (ChatSession) -> Void

    @StateObject private var vm: ChatViewModel
    @FocusState private var inputFocused: Bool
    @State private var showClearConfirm = false     // D-CHAT6
    @ObservedObject private var settings = SettingsStore.shared

    init(kb: KnowledgeBase, session: ChatSession, onNewSession: @escaping (ChatSession) -> Void) {
        self.kb = kb
        self.session = session
        self.onNewSession = onNewSession
        _vm = StateObject(wrappedValue: ChatViewModel(kb: kb, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if !settings.isConfigured && !vm.messages.isEmpty {
                providerBanner   // D-CHAT9
            }
            messageList
            inputBar
        }
        .background(DT.manila)
        // D-CHAT8 — Handoff
        .userActivity("com.dhorn.ragflowmobile.chat") { activity in
            activity.title = kb.name
            activity.isEligibleForHandoff = true
            activity.userInfo = ["kbId": kb.id, "sessionId": session.id]
        }
        // D-CHAT6 — Clear confirmation
        .confirmationDialog("Clear this conversation?",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) { vm.clearConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages will be permanently deleted.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("QUERY")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                // D-CHAT5 — Export
                ShareLink(item: vm.conversationExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                .disabled(vm.messages.isEmpty)
                .opacity(vm.messages.isEmpty ? 0.3 : 1)
                // D-CHAT6 — Clear
                Button { showClearConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                .disabled(vm.messages.isEmpty)
                .opacity(vm.messages.isEmpty ? 0.3 : 1)
                // D-CHAT7 — New chat
                Button { newChat() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                Text(String(kb.name.prefix(20)))
                    .font(DT.mono(10))
                    .tracking(1)
                    .foregroundStyle(DT.inkFaint)
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Provider banner (D-CHAT9)

    private var providerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white)
            Text("LLM not configured — open Settings to add a provider")
                .font(DT.mono(10))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.vertical, 6)
        .background(DT.amber)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DT.rowSpacing) {
                    if vm.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { i, msg in
                            DossierMessageBubble(message: msg, index: i)
                                .id(msg.id)
                        }
                    }
                    if vm.isTyping {
                        typingIndicator
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, DT.pagePadding)
                .padding(.vertical, 8)
            }
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: vm.isTyping) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DT.rule).frame(height: 0.5)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Interrogate the dossier…", text: $vm.input, axis: .vertical)
                    .font(DT.serif(14))
                    .foregroundStyle(DT.ink)
                    .lineLimit(1...5)
                    .focused($inputFocused)

                // D-CHAT3 — Stop button when streaming
                if vm.isLoading {
                    Button {
                        vm.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.red.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        Text("SEND")
                            .font(DT.mono(10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? DT.inkFaint : DT.stamp)
                            .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                    }
                    .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.vertical, 10)
        }
        .background(DT.manila)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Text("AWAITING QUERY")
                .font(DT.mono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            if !vm.suggestedPrompts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(vm.suggestedPrompts.prefix(3), id: \.self) { prompt in
                        Button {
                            vm.input = prompt
                            sendMessage()
                        } label: {
                            Text(prompt)
                                .font(DT.serif(13))
                                .italic()
                                .foregroundStyle(DT.inkSoft)
                                .multilineTextAlignment(.leading)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DT.card)
                                .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.pagePadding)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Typing indicator

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            Text("PROCESSING")
                .font(DT.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(DT.inkFaint)
            ProgressView()
                .scaleEffect(0.6)
                .tint(DT.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.pagePadding)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = vm.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await vm.send() }
    }

    // D-CHAT7 — New chat
    private func newChat() {
        let db = DatabaseService.shared
        let s = ChatSession(id: UUID().uuidString, kbId: kb.id, name: "Chat", createdAt: Date())
        try? db.saveSession(s)
        onNewSession(s)
    }
}
