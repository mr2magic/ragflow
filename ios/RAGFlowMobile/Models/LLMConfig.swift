import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case openAI = "ChatGPT"
    case ollama = "Ollama"

    var id: String { rawValue }
}

struct LLMConfig {
    var provider: LLMProvider
    var claudeApiKey: String
    var openAIApiKey: String
    var braveSearchApiKey: String
    var ollamaHost: String
    var ollamaModel: String
    /// Mirror Knowledge Bases and chat history to iCloud via CloudKit.
    var useCloudKitSync: Bool

    static let `default` = LLMConfig(
        provider: .claude,
        claudeApiKey: "",
        openAIApiKey: "",
        braveSearchApiKey: "",
        ollamaHost: "http://localhost:11434",
        ollamaModel: "llama3.2",
        useCloudKitSync: false
    )
}
