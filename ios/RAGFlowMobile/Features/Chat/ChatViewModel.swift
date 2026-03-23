import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input = ""
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    let book: Book
    private let rag = RAGService.shared
    private let settings = SettingsStore.shared

    init(book: Book) {
        self.book = book
    }

    func send() async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let query = input
        input = ""
        isLoading = true

        let userMessage = Message(role: .user, content: query)
        messages.append(userMessage)

        var assistantMessage = Message(role: .assistant, content: "")
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        do {
            let chunks = try rag.retrieve(query: query)
            let llm = makeLLMService(config: settings.config)

            let history = messages.dropLast().map {
                LLMMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
            }

            let stream = try await llm.complete(messages: Array(history), context: chunks)

            for try await token in stream {
                messages[assistantIndex].content += token
            }
        } catch {
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}
