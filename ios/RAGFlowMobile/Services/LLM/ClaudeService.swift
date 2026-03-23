import Foundation

final class ClaudeService: LLMService {
    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func complete(messages: [LLMMessage], context: [Chunk]) async throws -> AsyncThrowingStream<String, Error> {
        let system = buildSystemPrompt(context: context)
        let body = buildRequestBody(system: system, messages: messages)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("true", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.badResponse
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "),
                              let data = line.dropFirst(6).data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type_ = json["type"] as? String else { continue }

                        if type_ == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        } else if type_ == "message_stop" {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildSystemPrompt(context: [Chunk]) -> String {
        let excerpts = context.enumerated().map { i, chunk in
            "[\(i + 1)] \(chunk.chapterTitle.map { "(\($0)) " } ?? "")\(chunk.content)"
        }.joined(separator: "\n\n")

        return """
        You are a reading assistant. Answer questions using the provided book excerpts.
        Cite excerpt numbers when relevant. If the answer isn't in the excerpts, say so.

        EXCERPTS:
        \(excerpts)
        """
    }

    private func buildRequestBody(system: String, messages: [LLMMessage]) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
    }
}

enum LLMError: LocalizedError {
    case badResponse
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .badResponse: return "LLM returned an unexpected response."
        case .missingApiKey: return "No API key configured. Go to Settings."
        }
    }
}
