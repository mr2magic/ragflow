import Foundation

final class OpenAIService: LLMService {
    private let apiKey: String
    private let model = "gpt-4o"
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private(set) var lastUsage: TokenUsage?

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
                        // Surface any API-level error embedded in the response
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errObj = json["error"] as? [String: Any],
                           let msg = errObj["message"] as? String {
                            throw LLMError.serverError(msg)
                        }
                        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                        throw LLMError.serverError("OpenAI returned unexpected response: \(preview)")
                    }

                    // Capture token usage
                    if let usage = json["usage"] as? [String: Any] {
                        let input = usage["prompt_tokens"] as? Int ?? 0
                        let output = usage["completion_tokens"] as? Int ?? 0
                        self.lastUsage = TokenUsage(inputTokens: input, outputTokens: output,
                                                    model: self.model, provider: .openAI)
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
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.serverError("OpenAI: unexpected network response. Check your internet connection.")
        }
        guard http.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw LLMError.serverError("OpenAI error (\(http.statusCode)): \(message)")
            }
            throw LLMError.serverError("OpenAI returned HTTP \(http.statusCode).")
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
        buildEnterprisePrompt(context: context, books: books)
    }
}
