import SwiftUI

struct DossierMessageBubble: View {
    let message: Message
    let index: Int
    var onTap: (() -> Void)? = nil

    @AppStorage("showAttachmentChips") private var showAttachmentChips = true

    private var isUser: Bool { message.role == .user }

    private var groundingStamp: (label: String, color: Color) {
        switch message.sources.count {
        case 2...: return ("GROUNDED",   DT.green)
        case 1:    return ("PARTIAL",    DT.amber)
        default:   return ("UNGROUNDED", DT.stamp)
        }
    }

    var body: some View {
        Group {
            if isUser {
                userBubble
            } else {
                assistantMemo
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityLabel(isUser ? "You: \(message.content)" : "Response: \(message.content)")
        // D-CHAT4 — Copy message via long-press
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - User: request form card

    private var userBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REQ. \(String(format: "%04d", index + 1))")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(DT.stamp)
                    .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(DT.mono(9))
                    .foregroundStyle(DT.inkFaint)
            }
            .padding(.horizontal, DT.cardPadding)

            VStack(alignment: .leading, spacing: 0) {
                Text(message.content)
                    .font(DT.serif(15))
                    .italic()
                    .foregroundStyle(DT.ink)
                    .lineSpacing(3)

                if showAttachmentChips && !message.attachmentNames.isEmpty {
                    attachmentChips
                        .padding(.top, 8)
                }
            }
            .padding(DT.cardPadding)
            .background(DT.card)
            .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
        }
    }

    // MARK: - Attachment chips

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.attachmentNames, id: \.self) { name in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DT.stamp)
                            .accessibilityHidden(true)
                        Text(name)
                            .font(DT.mono(9, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(DT.inkSoft)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DT.manila)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(DT.rule, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Assistant: memo card

    private var assistantMemo: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MEMO")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(DT.ink)
                    .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                Spacer()
                if !message.sources.isEmpty {
                    Text("\(message.sources.count) CITED")
                        .font(DT.mono(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DT.green)
                }
            }
            .padding(.horizontal, DT.cardPadding)

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(message.content)
                        .font(DT.serif(14.5))
                        .foregroundStyle(DT.ink)
                        .lineSpacing(4)

                    if !message.sources.isEmpty {
                        sourcesSection
                    }
                }
                .padding(DT.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Grounding stamp — border-only, rotated
                let stamp = groundingStamp
                Text(stamp.label)
                    .font(DT.mono(8, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(stamp.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(stamp.color, lineWidth: 1.5))
                    .rotationEffect(.degrees(8))
                    .opacity(0.88)
                    .padding(.top, 10)
                    .padding(.trailing, 14)
            }
            .background(DT.card)
            .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(DT.rule.opacity(0.6)).frame(height: 0.5)
            Text("ATTACHMENTS · \(message.sources.count)")
                .font(DT.mono(9))
                .tracking(1.5)
                .foregroundStyle(DT.inkSoft)
                .padding(.top, 4)

            ForEach(Array(message.sources.enumerated()), id: \.element.id) { i, src in
                HStack(alignment: .top, spacing: 8) {
                    Text("[\(i + 1)]")
                        .font(DT.mono(10, weight: .bold))
                        .foregroundStyle(DT.stamp)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(src.documentTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DT.ink)
                        Text(src.preview)
                            .font(DT.serif(12))
                            .italic()
                            .foregroundStyle(DT.inkSoft)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(DT.manila.opacity(0.6))
                .overlay(alignment: .leading) {
                    Rectangle().fill(DT.stamp).frame(width: 3)
                }
            }
        }
    }
}
