import SwiftUI

struct ChatView: View {
    let kb: KnowledgeBase
    let session: ChatSession
    @StateObject private var vm: ChatViewModel
    @FocusState private var inputFocused: Bool
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showSettings = false
    @State private var showClearConfirm = false

    init(kb: KnowledgeBase, session: ChatSession) {
        self.kb = kb
        self.session = session
        _vm = StateObject(wrappedValue: ChatViewModel(kb: kb, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            kbScopeBar
            Divider()
            // Compact orange banner only shown once messages exist —
            // the empty state handles the no-provider case more prominently.
            if !settings.isConfigured && !vm.messages.isEmpty {
                providerBanner
            }
            messageList
            Divider()
            inputBar
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        // sessionTitle updates after auto-naming from the first message
        .navigationTitle(vm.sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Share chat history when conversation has content
            if !vm.messages.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: vm.conversationExport,
                        subject: Text(vm.sessionTitle),
                        message: Text("Exported from RAGFlow")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share conversation")
                }
            }
        }
        .confirmationDialog("Clear conversation?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { vm.clearConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages will be deleted. This cannot be undone.")
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    private var activeModelLabel: String {
        switch settings.config.provider {
        case .claude:  return "Claude"
        case .openAI:  return "ChatGPT"
        case .ollama:
            let m = settings.config.ollamaModel
            return m.isEmpty ? "Ollama" : "\(m) · Ollama"
        }
    }

    // MARK: - KB Scope Bar

    private var kbScopeBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Searching in:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(activeModelLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if !vm.messages.isEmpty {
                    Button(action: { showClearConfirm = true }) {
                        Label("Clear Chat", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.8))
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Clear chat history")
                }

                if !vm.availableKBsToAdd.isEmpty {
                    Menu {
                        ForEach(vm.availableKBsToAdd) { kb in
                            Button(action: { vm.addKB(kb) }) {
                                Label(kb.name, systemImage: "square.stack.3d.up")
                            }
                        }
                    } label: {
                        Label("Add KB", systemImage: "plus.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    .accessibilityLabel("Add another knowledge base")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.activeKBs) { activeKB in
                        HStack(spacing: 5) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.caption2.weight(.semibold))
                                .accessibilityHidden(true)
                            Text(activeKB.name)
                                .font(.caption.weight(.semibold))
                            if vm.activeKBs.count > 1 {
                                Button(action: { vm.removeKB(activeKB) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.tint.opacity(0.6))
                                }
                                .accessibilityLabel("Remove \(activeKB.name)")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    // MARK: - Provider Banner (compact — only shown when messages already exist)

    private var providerBanner: some View {
        Button(action: { showSettings = true }) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No AI provider configured")
                        .font(.subheadline.weight(.semibold))
                    Text("Tap to open Settings and add your API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No AI provider configured. Tap to open Settings.")
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if vm.messages.isEmpty {
                        emptyChatPrompts
                    }
                    ForEach(vm.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if vm.isTyping {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.isTyping) { _, typing in if typing { scrollToBottom(proxy, id: "typing") } }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, id: AnyHashable? = nil) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let id { proxy.scrollTo(id, anchor: .bottom) }
            else if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: - Empty State

    private var emptyChatPrompts: some View {
        VStack(spacing: Spacing.lg) {
            if !settings.isConfigured {
                // Full hero when no provider is configured
                VStack(spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(spacing: Spacing.sm) {
                        Text("AI Provider Required")
                            .font(.title3.weight(.semibold))

                        Text("Add an API key or configure Ollama in Settings to start chatting.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xxl)
                    }

                    Button("Open Settings") { showSettings = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(.vertical, Spacing.xxl)
            } else if !vm.hasDocuments {
                // No documents in this KB — remind user to import first
                VStack(spacing: Spacing.md) {
                    Image(systemName: "tray")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    VStack(spacing: Spacing.sm) {
                        Text("No Documents Yet")
                            .font(.title3.weight(.semibold))

                        Text("Import documents into **\(kb.name)** before chatting. The AI answers from your indexed content.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xxl)
                    }
                }
                .padding(.vertical, Spacing.xxl)
            } else {
                // Normal empty state with suggested prompts
                Image(systemName: "text.book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, Spacing.sm)
                    .accessibilityHidden(true)

                Text("Ask anything about the documents in **\(kb.name)**")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: Spacing.sm) {
                    ForEach(vm.suggestedPrompts, id: \.self) { prompt in
                        Button(action: {
                            vm.input = prompt
                            inputFocused = true
                        }) {
                            Text(prompt)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, 10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about \(kb.name)…", text: $vm.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.vertical, 8)
                .focused($inputFocused)
                .onSubmit { Task { await vm.send() } }

            if vm.isLoading {
                Button(action: vm.stop) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Stop generating")
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: { Task { await vm.send() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(vm.input.isEmpty ? .secondary : .accentColor)
                }
                .disabled(vm.input.isEmpty)
                .accessibilityLabel("Send message")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: vm.isLoading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: Message
    @State private var showSources = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                if message.role == .user { Spacer(minLength: 60) }

                Text(message.content.isEmpty ? " " : message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundStyle(message.role == .user ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .contextMenu {
                        Button(action: copyMessage) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    .textSelection(.enabled)

                if message.role == .assistant { Spacer(minLength: 60) }
            }

            if message.role == .assistant && !message.sources.isEmpty {
                sourcesDisclosure
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(Color(.secondarySystemBackground))
    }

    private var sourcesDisclosure: some View {
        DisclosureGroup(
            isExpanded: $showSources,
            content: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passages from your documents the AI read to form this answer. Numbers match [1] [2] references in the response.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 2)
                    ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, source in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("[\(index + 1)]")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if let title = source.chapterTitle {
                                    Text(title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(source.preview + "…")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                        if source.id != message.sources.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 4)
            },
            label: {
                Label("\(message.sources.count) passages used", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        )
        .padding(.horizontal, 4)
        .frame(maxWidth: 280, alignment: .leading)
    }

    private func copyMessage() {
        UIPasteboard.general.string = message.content
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.secondary)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { phase = 2 }
        .accessibilityLabel("AI is typing")
    }
}
