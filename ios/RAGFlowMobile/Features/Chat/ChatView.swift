import SwiftUI

struct ChatView: View {
    let book: Book
    @StateObject private var vm: ChatViewModel
    @FocusState private var inputFocused: Bool

    init(book: Book) {
        self.book = book
        _vm = StateObject(wrappedValue: ChatViewModel(book: book))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
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

            Text("Ask anything about **\(book.title)**")
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
            "Who are the main characters?",
            "What is the central theme?",
            "Summarize the opening chapter."
        ]
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about \(book.title)…", text: $vm.input, axis: .vertical)
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
    @State private var copied = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content.isEmpty ? " " : message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .foregroundStyle(message.role == .user ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .clipShape(BubbleShape(role: message.role))
                .contextMenu {
                    Button(action: copyMessage) {
                        Label(copied ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                    }
                }
                .textSelection(.enabled)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(Color(.secondarySystemBackground))
    }

    private func copyMessage() {
        UIPasteboard.general.string = message.content
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
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
