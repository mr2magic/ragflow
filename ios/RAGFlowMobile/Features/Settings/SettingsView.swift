import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var ollamaModels: [String] = []
    @State private var isFetchingModels = false
    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                if store.config.provider == .claude { claudeSection }
                if store.config.provider == .ollama { ollamaSection }
                agentToolsSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .onChange(of: store.config.provider) { _, _ in store.save() }
            .onChange(of: store.config.claudeApiKey) { _, _ in store.save() }
            .onChange(of: store.config.braveSearchApiKey) { _, _ in store.save() }
            .onChange(of: store.config.ollamaHost) { _, _ in store.save() }
            .onChange(of: store.config.ollamaModel) { _, _ in store.save() }
            .task { await loadOllamaModels() }
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        Section("LLM Provider") {
            Picker("Provider", selection: $store.config.provider) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Claude

    private var claudeSection: some View {
        Section {
            SecureField("API Key", text: $store.config.claudeApiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Claude")
        } footer: {
            Text("Your key is stored in the iOS Keychain and never transmitted except to api.anthropic.com.")
                .font(.footnote)
        }
    }

    // MARK: - Ollama

    private var ollamaSection: some View {
        Section {
            TextField("Host", text: $store.config.ollamaHost)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)

            if ollamaModels.isEmpty {
                HStack {
                    TextField("Model", text: $store.config.ollamaModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if isFetchingModels {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            } else {
                Picker("Model", selection: $store.config.ollamaModel) {
                    if store.config.ollamaModel.isEmpty {
                        Text("Select a model…").tag("")
                    }
                    ForEach(ollamaModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            Button(action: testConnection) {
                HStack {
                    switch connectionStatus {
                    case .idle:
                        Label("Test Connection", systemImage: "network")
                    case .testing:
                        ProgressView().scaleEffect(0.8)
                        Text("Testing…")
                    case .success:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(connectionStatus == .testing)

        } header: {
            Text("Ollama")
        } footer: {
            Text("Connect to an Ollama instance on your local network or at localhost.")
                .font(.footnote)
        }
    }

    // MARK: - Agent Tools

    private var agentToolsSection: some View {
        Section {
            SecureField("Brave Search API Key", text: $store.config.braveSearchApiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Agent Tools")
        } footer: {
            Text("Optional. Enables web search when chatting with Claude. Get a free key at brave.com/search/api.")
                .font(.footnote)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section {
            Button(role: .destructive, action: resetOnboarding) {
                Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive, action: resetAllData) {
                Label("Wipe All App Data", systemImage: "trash")
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("These options are only visible in DEBUG builds.")
                .font(.footnote)
        }
    }

    private func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }

    private func resetAllData() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        try? DatabaseService.shared.wipeAllData()
    }
    #endif

    // MARK: - Actions

    private func loadOllamaModels() async {
        guard store.config.provider == .ollama else { return }
        isFetchingModels = true
        ollamaModels = await OllamaModelsService.fetchModels(host: store.config.ollamaHost)
        isFetchingModels = false
        if !ollamaModels.isEmpty && !ollamaModels.contains(store.config.ollamaModel) {
            store.config.ollamaModel = ollamaModels.first ?? store.config.ollamaModel
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        Task {
            let models = await OllamaModelsService.fetchModels(host: store.config.ollamaHost)
            if models.isEmpty {
                connectionStatus = .failure("No response from \(store.config.ollamaHost)")
            } else {
                ollamaModels = models
                connectionStatus = .success
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .seconds(3))
                connectionStatus = .idle
            }
        }
    }
}

extension SettingsView.ConnectionStatus: Equatable {
    static func == (lhs: SettingsView.ConnectionStatus, rhs: SettingsView.ConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.testing, .testing), (.success, .success): return true
        case (.failure(let a), .failure(let b)): return a == b
        default: return false
        }
    }
}
