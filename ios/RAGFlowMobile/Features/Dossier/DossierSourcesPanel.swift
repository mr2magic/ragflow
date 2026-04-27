import SwiftUI

/// Right column in the iPad 3-column layout.
/// Displays sources from the last tapped MEMO bubble plus a retrieval trace.
struct DossierSourcesPanel: View {
    let message: Message?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            if let msg = message, !msg.sources.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(msg.sources.enumerated()), id: \.element.id) { i, src in
                            sourceCard(src, index: i + 1)
                        }
                        retrievalTrace
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, DT.pagePadding)
                    .padding(.vertical, 8)
                }
            } else {
                emptyState
            }
        }
        .background(DT.manilaDeep)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            let count = message?.sources.count ?? 0
            Text("SOURCES · \(count) ATTACHED")
                .font(DT.mono(10, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Source card

    private func sourceCard(_ src: ChunkSource, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("SRC · [\(index)]")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DT.ribbon)
                    .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                Spacer()
            }

            Text(src.documentTitle)
                .font(DT.mono(10, weight: .bold))
                .foregroundStyle(DT.ink)
                .lineLimit(1)

            if let chapter = src.chapterTitle, !chapter.isEmpty {
                Text(chapter)
                    .font(DT.mono(9))
                    .foregroundStyle(DT.inkSoft)
                    .lineLimit(1)
            }

            Text(src.preview)
                .font(DT.serif(12))
                .italic()
                .foregroundStyle(DT.inkSoft)
                .lineLimit(4)
                .lineSpacing(2)
        }
        .padding(10)
        .background(DT.card)
        .overlay(alignment: .leading) {
            Rectangle().fill(DT.ribbon).frame(width: 3)
        }
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    // MARK: - Retrieval trace

    private var retrievalTrace: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(DT.rule).frame(height: 0.5)
            Text("RETRIEVAL TRACE")
                .font(DT.mono(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
                .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(["EMBED", "BM25", "COS-SIM", "RRF-FUSE", "THRESHOLD"], id: \.self) { step in
                        Text(step)
                            .font(DT.mono(8))
                            .tracking(0.5)
                            .foregroundStyle(DT.inkSoft)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(DT.manila)
                            .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
                        if step != "THRESHOLD" {
                            Text("→")
                                .font(DT.mono(8))
                                .foregroundStyle(DT.inkFaint)
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            Text("TAP A MEMO")
                .font(DT.mono(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Tap any assistant response to view its source citations here.")
                .font(DT.serif(13))
                .italic()
                .foregroundStyle(DT.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }
}
