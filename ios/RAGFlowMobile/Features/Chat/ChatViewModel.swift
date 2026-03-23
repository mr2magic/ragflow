import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var isLoading = false
    @Published var isTyping = false       // true before first token arrives
    @Published var showError = false
    @Published var errorMessage = ""

    let book: Book
    private let rag = RAGService.shared
    private let settings = SettingsStore.shared
    private var streamTask: Task<Void, Never>?
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init(book: Book) {
        self.book = book
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
                let chunks = try rag.retrieve(query: query)
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
                    messages.remove(at: assistantIndex)
                    messages.removeLast()
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
