import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case ollama = "Ollama"

    var id: String { rawValue }
}

struct LLMConfig {
    var provider: LLMProvider
    var claudeApiKey: String
    var braveSearchApiKey: String
    var ollamaHost: String
    var ollamaModel: String

    static let `default` = LLMConfig(
        provider: .claude,
        claudeApiKey: "",
        braveSearchApiKey: "",
        ollamaHost: "http://localhost:11434",
        ollamaModel: "llama3.2"
    )
}
