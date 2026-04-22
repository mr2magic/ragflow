import SwiftUI

struct DossierDocumentRow: View {
    let book: Book
    let index: Int
    let isSelected: Bool
    var isIndexing: Bool = false     // D-DOC13

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: book.addedAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            fileIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(DT.serif(14))
                    .foregroundStyle(DT.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    statusBadge      // D-DOC13 — dynamic badge
                    Text("\(dateLabel) · \(book.chunkCount) chunks")
                        .font(DT.mono(10))
                        .foregroundStyle(DT.inkFaint)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, DT.cardPadding)
        .background(isSelected ? DT.manila.opacity(0.5) : DT.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DT.rule.opacity(0.4)).frame(height: 0.5)
        }
    }

    // D-DOC13 — accurate index status badge
    @ViewBuilder
    private var statusBadge: some View {
        if isIndexing {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 20, height: 14)
                .tint(DT.stamp)
        } else if book.chunkCount > 0 {
            Text("INDEXED")
                .font(DT.mono(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DT.green)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                Text("0 CHUNKS")
                    .font(DT.mono(8, weight: .bold))
                    .tracking(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.orange)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private var fileIcon: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DT.card)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(DT.rule, lineWidth: 0.5))
                .frame(width: 36, height: 44)

            Path { p in
                p.move(to: CGPoint(x: 26, y: 0))
                p.addLine(to: CGPoint(x: 36, y: 10))
                p.addLine(to: CGPoint(x: 36, y: 0))
                p.closeSubpath()
            }
            .fill(DT.manila)

            Text("\(index + 1)")
                .font(DT.mono(9, weight: .bold))
                .foregroundStyle(DT.stamp)
                .frame(width: 36, height: 44, alignment: .bottomLeading)
                .padding(.leading, 4)
                .padding(.bottom, 4)

            Text(book.fileTypeLabel.prefix(4))
                .font(DT.mono(7, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(DT.inkFaint)
                .frame(width: 36, height: 44, alignment: .center)
        }
        .frame(width: 36, height: 44)
    }
}
