import SwiftUI

struct DossierKBCard: View {
    let kb: KnowledgeBase
    let index: Int
    let docCount: Int
    let chunkCount: Int
    var subtitle: String = ""
    var isSelected: Bool = false

    /// Cycle through accent colors to give each KB a distinct folder-tab color.
    private var accentColor: Color {
        let palette: [Color] = [DT.ribbon, DT.stamp, DT.green, DT.amber, DT.inkSoft]
        return palette[index % palette.count]
    }

    private var tabLabel: String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let letter = String(letters[letters.index(letters.startIndex, offsetBy: index % 26)])
        let prefix = String(kb.name.prefix(3)).uppercased()
        return "\(prefix) · \(letter)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder tab
            HStack {
                Text(tabLabel)
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Spacer()
            }
            .padding(.leading, DT.cardPadding)

            // Card body
            VStack(alignment: .leading, spacing: 8) {
                Text(kb.name)
                    .font(DT.serif(20, weight: .semibold))
                    .foregroundStyle(DT.ink)
                    .lineLimit(2)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DT.mono(10))
                        .foregroundStyle(DT.inkSoft)
                        .lineLimit(1)
                }

                Rectangle()
                    .fill(DT.rule.opacity(0.6))
                    .frame(height: 0.5)

                HStack(spacing: 8) {
                    statView(value: "\(docCount)", label: "DOCS")
                    Circle().fill(DT.inkFaint).frame(width: 3, height: 3)
                    statView(value: formattedChunks, label: "CHUNKS")
                    Spacer()
                    miniBarChart()
                }
                .padding(.top, 2)
            }
            .padding(DT.cardPadding)
            .background(DT.card)
            .overlay(
                Rectangle()
                    .stroke(isSelected ? DT.stamp : DT.rule, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
    }

    private var formattedChunks: String {
        chunkCount >= 1000
            ? String(format: "%.1fK", Double(chunkCount) / 1000)
            : "\(chunkCount)"
    }

    private func statView(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(DT.serif(14, weight: .semibold))
                .foregroundStyle(DT.ink)
            Text(label)
                .font(DT.mono(10))
                .tracking(0.8)
                .foregroundStyle(DT.inkFaint)
        }
    }

    private func miniBarChart() -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<12, id: \.self) { k in
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 2.5, height: CGFloat(3 + ((k * 7 + index * 3) % 11)))
            }
        }
        .frame(height: 14)
    }
}
