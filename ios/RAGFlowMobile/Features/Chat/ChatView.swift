import SwiftUI

struct ChatView: View {
    let kb: KnowledgeBase
    @StateObject private var vm: ChatViewModel
    @FocusState private var inputFocused: Bool
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showSettings = false

    init(kb: KnowledgeBase) {
        self.kb = kb
        _vm = StateObject(wrappedValue: ChatViewModel(kb: kb))
    }

    var body: some View {
        VStack(spacing: 0) {
            kbScopeBar
            Divider()
            if !settings.isConfigured {
                providerBanner
            }
            messageList
            Divider()
            inputBar
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    // MARK: - KB Scope Bar

    private var kbScopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.activeKBs) { activeKB in
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.caption2)
                        Text(activeKB.name)
                            .font(.caption.weight(.medium))
                        if vm.activeKBs.count > 1 {
                            Button(action: { vm.removeKB(activeKB) }) {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
                }

                if !vm.availableKBsToAdd.isEmpty {
                    Menu {
                        ForEach(vm.availableKBsToAdd) { kb in
                            Button(action: { vm.addKB(kb) }) {
                                Label(kb.name, systemImage: "square.stack.3d.up")
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Provider Banner

    private var providerBanner: some View {
        Button(action: { showSettings = true }) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.10))
        }
        .buttonStyle(.plain)
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

    // MARK: - Empty State Prompts

    private var emptyChatPrompts: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)

            Text("Ask anything about the documents in **\(kb.name)**")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(suggestedPrompts, id: \.self) { prompt in
                    Button(action: {
                        vm.input = prompt
                        inputFocused = true
                    }) {
                        Text(prompt)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var suggestedPrompts: [String] {
        [
            "Summarize the key points in this corpus.",
            "What are the most important findings or conclusions?",
            "What topics are covered across these documents?"
        ]
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
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: { Task { await vm.send() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(vm.input.isEmpty ? .secondary : .accentColor)
                }
                .disabled(vm.input.isEmpty)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: vm.isLoading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(role: .destructive, action: vm.clearConversation) {
                    Label("Clear Conversation", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(vm.messages.isEmpty)
        }
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
                    ForEach(message.sources) { source in
                        VStack(alignment: .leading, spacing: 2) {
                            if let title = source.chapterTitle {
                                Text(title)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
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
                Label("\(message.sources.count) sources", systemImage: "doc.text.magnifyingglass")
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

// MARK: - Bubble Shape

private struct BubbleShape: Shape {
    let role: Message.Role

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tailR: CGFloat = 4
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
        return path
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
    }
}
