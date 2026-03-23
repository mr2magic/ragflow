import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("LLM Provider") {
                    Picker("Provider", selection: $store.config.provider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if store.config.provider == .claude {
                    Section("Claude") {
                        SecureField("API Key", text: $store.config.claudeApiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                    }
                }

                if store.config.provider == .ollama {
                    Section("Ollama") {
                        TextField("Host", text: $store.config.ollamaHost)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Model", text: $store.config.ollamaModel)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section {
                    Button("Save Settings") {
                        store.save()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
