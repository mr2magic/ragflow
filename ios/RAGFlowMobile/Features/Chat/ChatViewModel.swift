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
    private let rag = RAGService.shared
    private let settings = SettingsStore.shared
    private var streamTask: Task<Void, Never>?
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init(kb: KnowledgeBase) {
        self.kb = kb
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
        if settings.config.provider == .ollama {
            let embService = EmbeddingService(host: settings.config.ollamaHost)
            if let queryVec = try? await embService.embed(text: query) {
                return try rag.retrieveWithEmbedding(query: query, queryEmbedding: queryVec, kbId: kb.id)
            }
        }
        return try rag.retrieve(query: query, kbId: kb.id)
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
