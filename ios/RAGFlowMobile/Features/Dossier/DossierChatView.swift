import SwiftUI

struct DossierChatView: View {
    let kb: KnowledgeBase

    @StateObject private var vm: ChatViewModel
    @FocusState private var inputFocused: Bool

    init(kb: KnowledgeBase) {
        self.kb = kb
        let session = ChatSession(id: UUID().uuidString, kbId: kb.id, name: "Query", createdAt: Date())
        _vm = StateObject(wrappedValue: ChatViewModel(kb: kb, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            messageList
            inputBar
        }
        .background(DT.manila)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("QUERY")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                Text(String(kb.name.prefix(20)))
                    .font(DT.mono(10))
                    .tracking(1)
                    .foregroundStyle(DT.inkFaint)
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DT.rowSpacing) {
                    if vm.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { i, msg in
                            DossierMessageBubble(message: msg, index: i)
                                .id(msg.id)
                        }
                    }
                    if vm.isTyping {
                        typingIndicator
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, DT.pagePadding)
                .padding(.vertical, 8)
            }
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: vm.isTyping) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DT.rule).frame(height: 0.5)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Interrogate the dossier…", text: $vm.input, axis: .vertical)
                    .font(DT.serif(14))
                    .foregroundStyle(DT.ink)
                    .lineLimit(1...5)
                    .focused($inputFocused)

                Button(action: sendMessage) {
                    Text("SEND")
                        .font(DT.mono(10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DT.inkFaint : DT.stamp)
                        .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                }
                .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.vertical, 10)
        }
        .background(DT.manila)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Text("AWAITING QUERY")
                .font(DT.mono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            if !vm.suggestedPrompts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(vm.suggestedPrompts.prefix(3), id: \.self) { prompt in
                        Button {
                            vm.input = prompt
                            sendMessage()
                        } label: {
                            Text(prompt)
                                .font(DT.serif(13))
                                .italic()
                                .foregroundStyle(DT.inkSoft)
                                .multilineTextAlignment(.leading)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DT.card)
                                .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.pagePadding)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Typing indicator

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            Text("PROCESSING")
                .font(DT.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(DT.inkFaint)
            ProgressView()
                .scaleEffect(0.6)
                .tint(DT.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.pagePadding)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = vm.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await vm.send() }
    }
}
