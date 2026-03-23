import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var isLoading = false
    @Published var isTyping = false
    @Published var showError = false
    @Published var errorMessage = ""

    let kb: KnowledgeBase
    @Published var activeKBs: [KnowledgeBase]

    private let rag = RAGService.shared
    private let settings = SettingsStore.shared
    private let db = DatabaseService.shared
    private var streamTask: Task<Void, Never>?
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init(kb: KnowledgeBase) {
        self.kb = kb
        self.activeKBs = [kb]
        self.messages = (try? db.loadMessages(kbId: kb.id)) ?? []
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

    func send() async {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        input = ""
        isLoading = true
        isTyping = true
        haptics.impactOccurred()

        messages.append(Message(role: .user, content: query))
        messages.append(Message(role: .assistant, content: ""))
        let assistantIndex = messages.count - 1

        streamTask = Task {
            do {
                let chunks = try await retrieveChunks(for: query)
                messages[assistantIndex].sources = chunks.map { ChunkSource(from: $0) }

                let llm = makeLLMService(config: settings.config)
                let history = messages.dropLast().map {
                    LLMMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
                }

                let stream = try await llm.complete(messages: Array(history), context: chunks)

                for try await token in stream {
                    if Task.isCancelled { break }
                    isTyping = false
                    messages[assistantIndex].content += token
                }

                // Persist both messages once the stream completes normally
                if !Task.isCancelled {
                    let userMsg = messages[assistantIndex - 1]
                    let assistantMsg = messages[assistantIndex]
                    try? db.saveMessages([userMsg, assistantMsg], kbId: kb.id)
                }
            } catch is CancellationError {
                if messages[assistantIndex].content.isEmpty {
                    messages.removeLast(2)
                }
            } catch {
                isTyping = false
                messages[assistantIndex].content = "Error: \(error.localizedDescription)"
                errorMessage = error.localizedDescription
                showError = true
            }

            isLoading = false
            isTyping = false
        }

        await streamTask?.value
    }

    private func retrieveChunks(for query: String) async throws -> [Chunk] {
        var results: [Chunk] = []
        if settings.config.provider == .ollama {
            let embService = EmbeddingService(host: settings.config.ollamaHost)
            if let queryVec = try? await embService.embed(text: query) {
                for activeKB in activeKBs {
                    let chunks = try rag.retrieveWithEmbedding(query: query, queryEmbedding: queryVec, kbId: activeKB.id)
                    results.append(contentsOf: chunks)
                }
                return results
            }
        }
        for activeKB in activeKBs {
            let chunks = try rag.retrieve(query: query, kbId: activeKB.id)
            results.append(contentsOf: chunks)
        }
        return results
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
        try? db.deleteMessages(kbId: kb.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
