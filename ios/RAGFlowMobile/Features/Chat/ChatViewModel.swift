import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var isLoading = false
    @Published var isTyping = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var suggestedPrompts: [String] = []
    /// False when the primary KB has no indexed documents — shown as a warning in the empty state.
    @Published var hasDocuments = true
    /// Current session display name — kept in sync when auto-naming fires after the first message.
    @Published var sessionTitle: String
    @Published var hasMoreMessages = false
    @Published var isLoadingMoreMessages = false

    private static let pageSize = 50
    private var loadedOffset = 0

    // MARK: Per-chat LLM overrides
    @Published var modelOverride: String?  { didSet { persistParams() } }
    @Published var temperature: Double?    { didSet { persistParams() } }
    @Published var topP: Double?           { didSet { persistParams() } }
    @Published var systemPrompt: String?   { didSet { persistParams() } }
    /// Nil = send full history. N = send only the last N messages to the LLM.
    @Published var historyWindow: Int?     { didSet { persistParams() } }

    let kb: KnowledgeBase
    let session: ChatSession
    @Published var activeKBs: [KnowledgeBase]

    private let rag = RAGService.shared
    private let settings = SettingsStore.shared
    private let db = DatabaseService.shared
    private var streamTask: Task<Void, Never>?
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    /// Prevents auto-naming from firing more than once per session.
    private var hasAutoNamed = false

    init(kb: KnowledgeBase, session: ChatSession) {
        self.kb = kb
        self.session = session
        self.sessionTitle = session.name
        self.activeKBs = [kb]
        self.modelOverride = session.modelOverride
        self.temperature = session.temperature
        self.topP = session.topP
        self.systemPrompt = session.systemPrompt
        self.historyWindow = session.historyWindow
        let page = (try? db.loadMessages(sessionId: session.id,
                                         limit: Self.pageSize, offset: 0)) ?? []
        self.messages = page
        self.loadedOffset = page.count
        let total = (try? db.countMessages(sessionId: session.id)) ?? 0
        self.hasMoreMessages = total > page.count
        buildSuggestedPrompts()
    }

    func loadMoreMessages() async {
        guard hasMoreMessages, !isLoadingMoreMessages else { return }
        isLoadingMoreMessages = true
        let older = (try? db.loadMessages(sessionId: session.id,
                                          limit: Self.pageSize, offset: loadedOffset)) ?? []
        loadedOffset += older.count
        let total = (try? db.countMessages(sessionId: session.id)) ?? 0
        messages = older + messages
        hasMoreMessages = loadedOffset < total
        isLoadingMoreMessages = false
    }

    private func buildSuggestedPrompts() {
        let books = (try? db.allBooks(kbId: kb.id)) ?? []
        hasDocuments = !books.isEmpty
        guard !books.isEmpty else {
            suggestedPrompts = []
            return
        }

        let titles = books.prefix(3).map(\.title)
        var prompts: [String] = []

        switch titles.count {
        case 1:
            prompts = [
                "Summarize the key points in \"\(titles[0])\".",
                "What are the main themes or conclusions in \"\(titles[0])\"?",
                "What are the most important facts from \"\(titles[0])\"?"
            ]
        case 2:
            prompts = [
                "Summarize the key points in \"\(titles[0])\".",
                "What does \"\(titles[1])\" cover?",
                "Compare the main ideas in \"\(titles[0])\" and \"\(titles[1])\"."
            ]
        default:
            prompts = [
                "Summarize the key points in \"\(titles[0])\".",
                "What topics are covered across \(books.count) documents in \(kb.name)?",
                "Compare the main ideas in \"\(titles[0])\" and \"\(titles[1])\"."
            ]
        }

        suggestedPrompts = prompts
    }

    var availableKBsToAdd: [KnowledgeBase] {
        let activeIDs = Set(activeKBs.map(\.id))
        return ((try? db.allKBs()) ?? []).filter { !activeIDs.contains($0.id) }
    }

    func addKB(_ kb: KnowledgeBase) {
        guard !activeKBs.contains(where: { $0.id == kb.id }) else { return }
        activeKBs.append(kb)
    }

    func removeKB(_ kb: KnowledgeBase) {
        guard activeKBs.count > 1 else { return } // must keep at least one
        activeKBs.removeAll { $0.id == kb.id }
    }

    /// Plain-text export of the full conversation for sharing.
    var conversationExport: String {
        let header = "Chat in \(kb.name) — \(session.createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"
        let body = messages.map { msg -> String in
            let role = msg.role == .user ? "You" : "Ragion"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")
        return header + body
    }

    private func persistParams() {
        try? db.updateSessionParams(
            id: session.id,
            modelOverride: modelOverride,
            temperature: temperature,
            topP: topP,
            systemPrompt: systemPrompt,
            historyWindow: historyWindow
        )
    }

    func send() async {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        input = ""
        isLoading = true
        isTyping = true
        haptics.impactOccurred()

        let userMsg = Message(role: .user, content: query)
        messages.append(userMsg)
        messages.append(Message(role: .assistant, content: ""))
        let assistantIndex = messages.count - 1

        // Persist the user message immediately so it survives cancellation or navigation away.
        try? db.saveMessages([userMsg], sessionId: session.id, kbId: kb.id)

        // Auto-name the session from the first user message (fires once, only when
        // the session still has the default "Chat" name).
        if !hasAutoNamed && session.name == "Chat" {
            hasAutoNamed = true
            let raw = query.prefix(50).trimmingCharacters(in: .whitespacesAndNewlines)
            let autoName = raw.count < query.count ? raw + "…" : raw
            try? db.renameSession(id: session.id, name: autoName)
            sessionTitle = autoName
        }

        streamTask = Task {
            // Keep the process alive for ~30 seconds after a Stage Manager window switch
            // so typical LLM responses complete before the OS suspends the stream.
            let bgToken = UIApplication.shared.beginBackgroundTask(withName: "RAGFlow: LLM stream") {}
            defer { UIApplication.shared.endBackgroundTask(bgToken) }

            do {
                let (chunks, docTitles) = try await retrieveChunks(for: query)

                // RAG1: block the LLM when no KB passages were retrieved so the
                // model cannot fall back to general training knowledge.
                if chunks.isEmpty {
                    messages[assistantIndex].content = "No relevant passages were found in your knowledge base for this question. Try rephrasing, or add more documents to your knowledge base."
                    try? db.saveMessages([messages[assistantIndex]], sessionId: session.id, kbId: kb.id)
                    isLoading = false
                    isTyping = false
                    return
                }

                messages[assistantIndex].sources = chunks.map {
                    ChunkSource(from: $0, documentTitle: docTitles[$0.bookId] ?? "")
                }

                let chatParams = ChatParams(
                    modelOverride: modelOverride,
                    temperature: temperature,
                    topP: topP,
                    extraSystemPrompt: systemPrompt ?? ""
                )
                let llm = makeLLMService(config: settings.config, params: chatParams)
                let fullHistory = messages.dropLast().map {
                    LLMMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
                }
                let history = historyWindow.map { Array(fullHistory.suffix($0)) } ?? fullHistory
                let allBooks = activeKBs.flatMap { (try? db.allBooks(kbId: $0.id)) ?? [] }

                let stream = try await llm.complete(messages: Array(history), context: chunks, books: allBooks)

                for try await token in stream {
                    if Task.isCancelled { break }
                    isTyping = false
                    messages[assistantIndex].content += token
                }

                // Attach token usage from the completed response
                messages[assistantIndex].tokenUsage = llm.lastUsage

                // Persist assistant message on normal completion (or partial if cancelled mid-stream).
                let assistantMsg = messages[assistantIndex]
                if !assistantMsg.content.isEmpty {
                    try? db.saveMessages([assistantMsg], sessionId: session.id, kbId: kb.id)
                }
            } catch is CancellationError {
                let assistantMsg = messages[assistantIndex]
                if assistantMsg.content.isEmpty {
                    // Nothing useful streamed — remove both from memory and undo the user save.
                    messages.removeLast(2)
                    try? db.deleteMessage(id: userMsg.id.uuidString)
                } else {
                    try? db.saveMessages([assistantMsg], sessionId: session.id, kbId: kb.id)
                }
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                // URLSession throws .cancelled (code -999) when a Swift Task is cancelled
                // mid-stream (e.g. user taps Stop). Treat identically to CancellationError —
                // suppress the alert so the user doesn't see a spurious error message.
                let assistantMsg = messages[assistantIndex]
                if assistantMsg.content.isEmpty {
                    messages.removeLast(2)
                    try? db.deleteMessage(id: userMsg.id.uuidString)
                } else {
                    try? db.saveMessages([assistantMsg], sessionId: session.id, kbId: kb.id)
                }
            } catch {
                isTyping = false
                messages[assistantIndex].content = "Error: \(error.localizedDescription)"
                try? db.saveMessages([messages[assistantIndex]], sessionId: session.id, kbId: kb.id)
                errorMessage = error.localizedDescription
                showError = true
            }

            isLoading = false
            isTyping = false
        }

        await streamTask?.value
    }

    /// Returns retrieved chunks and a bookId→title lookup for citation building.
    private func retrieveChunks(for query: String) async throws -> ([Chunk], [String: String]) {
        // Pre-compute query embedding for vector search (Ollama only).
        if settings.config.provider == .ollama {
            let embService = EmbeddingService(host: settings.config.ollamaHost)
            rag.currentQueryEmbedding = try? await embService.embed(text: query)
        }
        defer { rag.currentQueryEmbedding = nil }

        var results: [Chunk] = []
        var docTitles: [String: String] = [:]

        for activeKB in activeKBs {
            // Re-fetch KB from DB so retrieval always uses current settings
            // (topK, topN, threshold). Without this, changes made in Retrieval
            // Settings after navigation are ignored because activeKBs holds a
            // value-type snapshot from init time.
            let liveKB = (try? db.kb(id: activeKB.id)) ?? activeKB

            // Build title lookup for all documents in this KB
            let docs = (try? db.allBooks(kbId: activeKB.id)) ?? []
            for doc in docs { docTitles[doc.id] = doc.title }

            let chunks = try rag.retrieve(query: query, kb: liveKB)
            results.append(contentsOf: chunks)
        }
        return (results, docTitles)
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isLoading = false
        isTyping = false
    }

    func clearConversation() {
        stop()
        messages.removeAll()
        try? db.deleteSession(session.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
