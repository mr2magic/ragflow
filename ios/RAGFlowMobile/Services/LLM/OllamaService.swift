import Foundation

final class OllamaService: LLMService {
    private let host: String
    private let model: String

    /// Long-lived session: 10 min request timeout, unlimited resource timeout for streaming.
    /// Proxy is disabled — Ollama is always a local/LAN server and iCloud Private Relay
    /// cannot route requests to local hostnames (e.g. the-black-pearl:11434).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600   // wait up to 10 min for first byte
        config.timeoutIntervalForResource = 0    // no cap on total transfer time
        config.connectionProxyDictionary = [:]   // bypass iCloud Private Relay for local hosts
        return URLSession(configuration: config)
    }()

    private let params: ChatParams
    private(set) var lastUsage: TokenUsage?

    init(host: String, model: String, params: ChatParams = .default) {
        self.host = host
        self.model = model
        self.params = params
    }

    func complete(messages: [LLMMessage], context: [Chunk], books: [Book]) async throws -> AsyncThrowingStream<String, Error> {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.missingApiKey
        }
        guard let url = URL(string: "\(host)/api/chat") else {
            throw LLMError.missingApiKey
        }
        let system = buildSystemPrompt(context: context, books: books)
        let allMessages = [LLMMessage(role: .system, content: system)] + messages
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var bodyDict: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": allMessages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        if let temp = params.temperature { bodyDict["temperature"] = temp }
        if let topP = params.topP { bodyDict["top_p"] = topP }
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (bytes, response) = try await OllamaService.session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.serverError("Ollama: unexpected network response. Check that your Ollama host is reachable.")
        }
        if http.statusCode != 200 {
            // Read the error body so we can surface Ollama's actual message (e.g. "model not found").
            var body = ""
            for try await line in bytes.lines { body += line }
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["error"] as? String {
                throw LLMError.serverError("Ollama: \(msg)")
            }
            throw LLMError.serverError("Ollama returned HTTP \(http.statusCode).")
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
                            let input = json["prompt_eval_count"] as? Int ?? 0
                            let output = json["eval_count"] as? Int ?? 0
                            self.lastUsage = TokenUsage(inputTokens: input, outputTokens: output,
                                                        model: self.model, provider: .ollama)
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

    private func buildSystemPrompt(context: [Chunk], books: [Book]) -> String {
        buildEnterprisePrompt(context: context, books: books, extraInstructions: params.extraSystemPrompt)
    }
}
