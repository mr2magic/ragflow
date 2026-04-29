import SwiftUI

/// KB overview card — shown on the KB tab of DossierKBDetailView.
struct DossierQueryView: View {
    let kb: KnowledgeBase
    var onSaveSettings: ((KnowledgeBase) -> Void)?

    @State private var docCount: Int = 0
    @State private var chunkCount: Int = 0
    @State private var showRetrievalSettings = false
    @ObservedObject private var settings = SettingsStore.shared

    private let db = DatabaseService.shared

    private var createdLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: kb.createdAt)
    }

    private var llmLabel: String {
        let p = settings.config.provider
        switch p {
        case .ollama:
            let m = settings.config.ollamaModel.isEmpty ? "—" : settings.config.ollamaModel
            return "\(p.rawValue) · \(m)"
        default:
            return "\(p.rawValue) · \(p.defaultModel)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerBar
                coverCard
                statsGrid
                retrievalCard
                Spacer()
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.top, 12)
        }
        .background(DT.manila)
        .onAppear { loadCounts() }
        .sheet(isPresented: $showRetrievalSettings) {
            KBRetrievalSettingsSheet(kb: kb) { updated in
                try? DatabaseService.shared.saveKB(updated)
                onSaveSettings?(updated)
                loadCounts()
            }
        }
    }

    private func loadCounts() {
        let books = (try? db.allBooks(kbId: kb.id)) ?? []
        docCount = books.count
        chunkCount = books.reduce(0) { $0 + $1.chunkCount }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("KNOWLEDGE BASE")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
    }

    // MARK: - Cover card

    private var coverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DOSSIER")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(DT.stamp)
                    .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                Spacer()
                Text("EST. \(createdLabel)")
                    .font(DT.mono(9))
                    .foregroundStyle(DT.inkFaint)
            }

            Text(kb.name)
                .font(DT.serif(24, weight: .semibold))
                .foregroundStyle(DT.ink)

            Rectangle().fill(DT.rule.opacity(0.6)).frame(height: 0.5)

            Text("Chunk method: \(kb.chunkMethod.rawValue.uppercased())")
                .font(DT.mono(10))
                .tracking(0.8)
                .foregroundStyle(DT.inkFaint)

            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundStyle(DT.inkFaint)
                    .accessibilityHidden(true)
                Text(llmLabel)
                    .font(DT.mono(10))
                    .tracking(0.8)
                    .foregroundStyle(settings.isConfigured ? DT.ink : DT.inkFaint)
            }
        }
        .padding(DT.cardPadding)
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        HStack(spacing: 8) {
            statCard(value: "\(docCount)", label: "DOCUMENTS", color: DT.ribbon)
            statCard(value: formattedChunks, label: "CHUNKS", color: DT.stamp)
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(DT.serif(28, weight: .semibold))
                .foregroundStyle(DT.ink)
            Text(label)
                .font(DT.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DT.cardPadding)
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    private var formattedChunks: String {
        chunkCount >= 1000
            ? String(format: "%.1fK", Double(chunkCount) / 1000)
            : "\(chunkCount)"
    }

    // MARK: - Retrieval settings card

    private var retrievalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RETRIEVAL")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                Button { showRetrievalSettings = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit retrieval settings")
            }

            Rectangle().fill(DT.rule.opacity(0.6)).frame(height: 0.5)

            metaRow(label: "TOP-K",      value: "\(kb.topK)")
            metaRow(label: "TOP-N",      value: "\(kb.topN)")
            metaRow(label: "SIMILARITY", value: String(format: "%.2f", kb.similarityThreshold))
            metaRow(label: "CHUNK SIZE", value: "\(kb.chunkSize)")
            metaRow(label: "OVERLAP",    value: "\(kb.chunkOverlap)")
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
