import Foundation

final class OllamaService: LLMService {
    private let host: String
    private let model: String

    init(host: String, model: String) {
        self.host = host
        self.model = model
    }

    func complete(messages: [LLMMessage], context: [Chunk]) async throws -> AsyncThrowingStream<String, Error> {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.missingApiKey
        }
        guard let url = URL(string: "\(host)/api/chat") else {
            throw LLMError.missingApiKey
        }
        let system = buildSystemPrompt(context: context)
        var allMessages = [LLMMessage(role: .system, content: system)] + messages
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": true,
            "messages": allMessages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        if http.statusCode != 200 {
            // Read the error body so we can surface Ollama's actual message (e.g. "model not found").
            var body = ""
            for try await line in bytes.lines { body += line }
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["error"] as? String {
                throw LLMError.serverError("Ollama: \(msg)")
            }
            throw LLMError.badResponse
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? [String: Any],
                              let content = message["content"] as? String else { continue }

                        continuation.yield(content)

                        if (json["done"] as? Bool) == true {
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
}
