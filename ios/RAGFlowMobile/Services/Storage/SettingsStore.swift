import Foundation
import Security

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var config: LLMConfig = .default

    private let defaults = UserDefaults.standard

    private init() {
        load()
    }

    /// True when the active provider has enough configuration to attempt a request.
    var isConfigured: Bool {
        switch config.provider {
        case .claude:  return !config.claudeApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openAI:  return !config.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ollama:  return !config.ollamaHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           && !config.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func save() {
        defaults.set(config.provider.rawValue, forKey: "llm_provider")
        defaults.set(config.ollamaHost, forKey: "ollama_host")
        defaults.set(config.ollamaModel, forKey: "ollama_model")
        saveToKeychain(key: "claude_api_key", value: config.claudeApiKey)
        saveToKeychain(key: "openai_api_key", value: config.openAIApiKey)
        saveToKeychain(key: "brave_search_api_key", value: config.braveSearchApiKey)
    }

    private func load() {
        let provider = LLMProvider(rawValue: defaults.string(forKey: "llm_provider") ?? "") ?? .claude
        let ollamaHost = defaults.string(forKey: "ollama_host") ?? "http://localhost:11434"
        let ollamaModel = defaults.string(forKey: "ollama_model") ?? ""
        let claudeKey = loadFromKeychain(key: "claude_api_key") ?? ""
        let openAIKey = loadFromKeychain(key: "openai_api_key") ?? ""
        let braveKey = loadFromKeychain(key: "brave_search_api_key") ?? ""

        config = LLMConfig(
            provider: provider,
            claudeApiKey: claudeKey,
            openAIApiKey: openAIKey,
            braveSearchApiKey: braveKey,
            ollamaHost: ollamaHost,
            ollamaModel: ollamaModel
        )
    }

    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
