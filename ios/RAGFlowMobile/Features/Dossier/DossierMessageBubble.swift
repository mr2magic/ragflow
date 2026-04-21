import SwiftUI

struct DossierMessageBubble: View {
    let message: Message
    let index: Int

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            userBubble
        } else {
            assistantMemo
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
            }
            .padding(DT.cardPadding)
            .background(DT.card)
            .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
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
