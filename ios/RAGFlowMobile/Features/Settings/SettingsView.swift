import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SettingsStore.shared
    @AppStorage("app_theme") private var themeRaw: String = AppTheme.simple.rawValue
    @AppStorage("showAttachmentChips") private var showAttachmentChips = true
    @State private var ollamaModels: [String] = []
    @State private var isFetchingModels = false
    @State private var connectionStatus: ConnectionStatus = .idle

    private var isDossier: Bool { AppTheme(rawValue: themeRaw) == .dossier }

    enum ConnectionStatus {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                providerSection
                if store.config.provider == .claude { claudeSection }
                if store.config.provider == .openAI { openAISection }
                if store.config.provider == .ollama { ollamaSection }
                agentToolsSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(isDossier ? DT.manila : Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: store.theme) { _, _ in store.save() }
            .onChange(of: store.config.provider) { _, _ in store.save() }
            .onChange(of: store.config.claudeApiKey) { _, _ in store.save() }
            .onChange(of: store.config.openAIApiKey) { _, _ in store.save() }
            .onChange(of: store.config.braveSearchApiKey) { _, _ in store.save() }
            .onChange(of: store.config.ollamaHost) { _, _ in store.save() }
            .onChange(of: store.config.ollamaModel) { _, _ in store.save() }
            .onChange(of: store.config.useCloudKitSync) { _, _ in store.save() }
            .task { await loadOllamaModels() }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $store.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Show attachment chips in chat", isOn: $showAttachmentChips)
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

    // MARK: - OpenAI / ChatGPT

    private var openAISection: some View {
        Section {
            SecureField("API Key", text: $store.config.openAIApiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("ChatGPT (OpenAI)")
        } footer: {
            Text("Your key is stored in the iOS Keychain and never transmitted except to api.openai.com.")
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

    // MARK: - iCloud Sync

    @ObservedObject private var ckSync = CloudKitSyncService.shared

    private var iCloudSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: $store.config.useCloudKitSync)
                .help("Mirror Knowledge Bases and chat history to iCloud so they're available on all your devices.")

            if store.config.useCloudKitSync {
                if ckSync.isSyncing {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Syncing…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: { Task { await ckSync.sync() } }) {
                        Label("Sync Now", systemImage: "arrow.clockwise.icloud")
                    }
                    if let last = ckSync.lastSyncDate {
                        LabeledContent("Last Synced") {
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let err = ckSync.syncError {
                        Label(err, systemImage: "xmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if store.config.useCloudKitSync && !ckSync.isAvailable {
                Label("Sign in to iCloud in Settings to enable sync", systemImage: "person.icloud")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Syncs Knowledge Base settings and chat history. Document files and embeddings are not synced — re-import documents on each device.")
                .font(.footnote)
        }
        .task {
            if store.config.useCloudKitSync {
                await ckSync.checkAvailability()
            }
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
            Text("Web Augmentation (Claude only)")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if !store.config.braveSearchApiKey.isEmpty {
                    Label("Web search is active — the AI may answer from the internet, not just your knowledge base.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
                Text("Optional. Providing a Brave Search API key enables web search for Claude responses. \u{26A0}\u{FE0F} This overrides RAG-only mode — the AI will draw on web results in addition to your knowledge base. Leave empty to enforce knowledge-base-only answers.")
                    .font(.footnote)
            }
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
        dismiss()
    }

    private func resetAllData() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        try? DatabaseService.shared.wipeAllData()
        AuthService.shared.signOut()
        dismiss()
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
