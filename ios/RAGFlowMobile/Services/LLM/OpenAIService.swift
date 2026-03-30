import Foundation

final class OpenAIService: LLMService {
    private let apiKey: String
    private let model = "gpt-4o"
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func complete(messages: [LLMMessage], context: [Chunk], books: [Book]) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.missingApiKey
        }
        let system = buildSystemPrompt(context: context, books: books)
        let body = buildBody(system: system, messages: messages)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await post(body: body)
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first,
                          let message = first["message"] as? [String: Any],
                          let text = message["content"] as? String else {
                        throw LLMError.badResponse
                    }

                    // Emit word-by-word for a streaming feel, matching ClaudeService behaviour
                    let words = text.split(separator: " ", omittingEmptySubsequences: false)
                    for word in words {
                        if Task.isCancelled { break }
                        continuation.yield(String(word) + " ")
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func post(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let _ = response as? HTTPURLResponse,
               let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw LLMError.serverError(message)
            }
            throw LLMError.badResponse
        }
        return data
    }

    private func buildBody(system: String, messages: [LLMMessage]) -> [String: Any] {
        var allMessages: [[String: Any]] = [
            ["role": "system", "content": system]
        ]
        allMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        return [
            "model": model,
            "max_tokens": 2048,
            "messages": allMessages
        ]
    }

    private func buildSystemPrompt(context: [Chunk], books: [Book]) -> String {
        let catalog = books.isEmpty ? "" : """
        LIBRARY (\(books.count) document\(books.count == 1 ? "" : "s")):
        \(books.enumerated().map { i, b in
            "  \(i + 1). \"\(b.title)\"\(b.author.isEmpty ? "" : " — \(b.author)") (\(b.chunkCount) chunks)"
        }.joined(separator: "\n"))

        """
        let excerpts = context.enumerated().map { i, chunk in
            "[\(i + 1)] \(chunk.chapterTitle.map { "(\($0)) " } ?? "")\(chunk.content)"
        }.joined(separator: "\n\n")

        return """
        You are a reading assistant with access to the documents listed below.
        When asked what documents or books are available, always enumerate the full LIBRARY list.
        Answer using the provided excerpts when possible.
        Cite excerpt numbers [1], [2], etc. when referencing them.

        \(catalog)EXCERPTS:
        \(excerpts)
        """
    }
}
