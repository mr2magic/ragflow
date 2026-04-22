import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case openAI = "ChatGPT"
    case ollama = "Ollama"

    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-6"
        case .openAI: return "gpt-4o"
        case .ollama: return ""
        }
    }

    /// Static model list for Claude and OpenAI. Empty for Ollama (fetched dynamically).
    var availableModels: [String] {
        switch self {
        case .claude: return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        case .openAI: return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1", "o1-mini", "o3-mini"]
        case .ollama: return []
        }
    }
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
