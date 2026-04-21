import SwiftUI

/// Architecture / metadata view — shown on the ARCH tab of DossierKBDetailView.
struct DossierArchView: View {
    let kb: KnowledgeBase
    let docCount: Int
    let chunkCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerBar
                metaCard
                Spacer()
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.top, 12)
        }
        .background(DT.manila)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ARCHITECTURE")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
    }

    // MARK: - Meta card

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            metaRow(label: "TOP-K",       value: "\(kb.topK)")
            metaRow(label: "TOP-N",       value: "\(kb.topN)")
            metaRow(label: "SIMILARITY",  value: String(format: "%.2f", kb.similarityThreshold))
            metaRow(label: "CHUNK SIZE",  value: "\(kb.chunkSize)")
            metaRow(label: "OVERLAP",     value: "\(kb.chunkOverlap)")
            metaRow(label: "METHOD",      value: kb.chunkMethod.rawValue.uppercased())

            Rectangle().fill(DT.rule.opacity(0.6)).frame(height: 0.5)

            metaRow(label: "DOCUMENTS",   value: "\(docCount)")
            metaRow(label: "CHUNKS",      value: "\(chunkCount)")
        }
        .padding(DT.cardPadding)
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DT.mono(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(DT.inkFaint)
            Spacer()
            Text(value)
                .font(DT.serif(14))
                .foregroundStyle(DT.ink)
        }
    }
}
