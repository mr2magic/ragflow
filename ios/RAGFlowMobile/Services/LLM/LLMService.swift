import Foundation

protocol LLMService {
    func complete(messages: [LLMMessage], context: [Chunk]) async throws -> AsyncThrowingStream<String, Error>
}

struct LLMMessage {
    var role: Role
    var content: String

    enum Role: String {
        case system, user, assistant
    }
}

func makeLLMService(config: LLMConfig) -> any LLMService {
    switch config.provider {
    case .claude:
        return ClaudeService(apiKey: config.claudeApiKey, braveApiKey: config.braveSearchApiKey)
    case .ollama:
        return OllamaService(host: config.ollamaHost, model: config.ollamaModel)
    }
}
