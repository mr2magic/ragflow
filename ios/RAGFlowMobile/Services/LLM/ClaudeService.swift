import Foundation

final class ClaudeService: LLMService {
    private let apiKey: String
    private let braveApiKey: String
    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var onToolActivity: ((String?) -> Void)?   // reports "Searching Brave…" etc.

    init(apiKey: String, braveApiKey: String = "") {
        self.apiKey = apiKey
        self.braveApiKey = braveApiKey
    }

    func complete(messages: [LLMMessage], context: [Chunk]) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.missingApiKey
        }
        let system = buildSystemPrompt(context: context)
        let tools = AgentTools.all.map(\.asDict)
        let executor = ToolExecutor(braveApiKey: self.braveApiKey)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentMessages = messages

                    // Tool use loop — max 3 rounds
                    for _ in 0..<3 {
                        let body = buildBody(system: system, messages: currentMessages, tools: tools, stream: false)
                        let data = try await post(body: body)
                        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            throw LLMError.badResponse
                        }

                        let stopReason = json["stop_reason"] as? String
                        let contentBlocks = json["content"] as? [[String: Any]] ?? []

                        if stopReason == "tool_use" {
                            // Collect all tool calls, execute, then continue
                            var toolResults: [[String: Any]] = []

                            for block in contentBlocks {
                                guard let type = block["type"] as? String, type == "tool_use",
                                      let toolId = block["id"] as? String,
                                      let toolName = block["name"] as? String,
                                      let toolInput = block["input"] as? [String: Any] else { continue }

                                let label = toolName == "brave_search" ? "Searching Brave…" : "Reading page…"
                                await MainActor.run { self.onToolActivity?(label) }

                                let result = await executor.execute(name: toolName, input: toolInput)
                                toolResults.append([
                                    "type": "tool_result",
                                    "tool_use_id": toolId,
                                    "content": result
                                ])
                            }

                            await MainActor.run { self.onToolActivity?(nil) }

                            // Append assistant + tool_result to conversation
                            currentMessages.append(LLMMessage(
                                role: .assistant,
                                content: (try? JSONSerialization.data(withJSONObject: contentBlocks))
                                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                            ))
                            currentMessages.append(LLMMessage(
                                role: .user,
                                content: (try? JSONSerialization.data(withJSONObject: toolResults))
                                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                            ))
                        } else {
                            // Final response — stream it out
                            let text = contentBlocks
                                .filter { ($0["type"] as? String) == "text" }
                                .compactMap { $0["text"] as? String }
                                .joined()

                            // Emit in chunks for a streaming feel
                            let words = text.split(separator: " ", omittingEmptySubsequences: false)
                            for word in words {
                                if Task.isCancelled { break }
                                continuation.yield(String(word) + " ")
                                try await Task.sleep(for: .milliseconds(5))
                            }
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

    // MARK: - Helpers

    private func post(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.badResponse
        }
        return data
    }

    private func buildBody(system: String, messages: [LLMMessage], tools: [[String: Any]], stream: Bool) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 2048,
            "stream": stream,
            "system": system,
            "tools": tools,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
    }

    private func buildSystemPrompt(context: [Chunk]) -> String {
        let excerpts = context.enumerated().map { i, chunk in
            "[\(i + 1)] \(chunk.chapterTitle.map { "(\($0)) " } ?? "")\(chunk.content)"
        }.joined(separator: "\n\n")

        return """
        You are a reading assistant. Answer using the provided excerpts when possible.
        Cite excerpt numbers [1], [2], etc. when referencing them.
        If the question needs current information not in the excerpts, use the brave_search tool.
        If asked to read a URL, use the jina_reader tool.

        EXCERPTS:
        \(excerpts)
        """
    }
}

enum LLMError: LocalizedError {
    case badResponse, missingApiKey, serverError(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:     return "LLM returned an unexpected response."
        case .missingApiKey:   return "No AI provider configured. Open Settings and add your Claude API key, ChatGPT API key, or Ollama host."
        case .serverError(let msg): return msg
        }
    }
}
