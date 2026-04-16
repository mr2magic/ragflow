import SwiftUI

/// Full per-KB RAG configuration sheet — mirrors RAGflow's Knowledge Base settings panel.
/// Controls both retrieval behaviour (topK, topN, threshold) and
/// chunking strategy (method, size, overlap) applied at ingest time.
struct KBRetrievalSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let kb: KnowledgeBase
    private let onSave: (KnowledgeBase) -> Void

    // Retrieval settings
    @State private var topK: Int
    @State private var topN: Int
    @State private var threshold: Double

    // Chunking settings
    @State private var chunkMethod: ChunkMethod
    @State private var chunkSize: Int
    @State private var chunkOverlap: Int

    init(kb: KnowledgeBase, onSave: @escaping (KnowledgeBase) -> Void) {
        self.kb = kb
        self.onSave = onSave
        _topK         = State(initialValue: kb.topK)
        _topN         = State(initialValue: kb.topN)
        _threshold    = State(initialValue: kb.similarityThreshold)
        _chunkMethod  = State(initialValue: kb.chunkMethod)
        _chunkSize    = State(initialValue: kb.chunkSize)
        _chunkOverlap = State(initialValue: kb.chunkOverlap)
    }

    var body: some View {
        NavigationStack {
            Form {
                retrievalSection
                chunkingSection
                infoSection
            }
            .navigationTitle(kb.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Retrieval

    private var retrievalSection: some View {
        Section {
            Stepper(value: $topK, in: 1...100) {
                labeledValue("Top-K (returned passages)", value: topK)
            }
            .help("Number of passages actually sent to the AI model. Lower = faster; higher = more context. RAGflow default: 10.")
            .onChange(of: topK) { _, newK in
                if topN < newK { topN = newK }
            }

            Stepper(value: $topN, in: max(topK, 1)...500, step: 10) {
                labeledValue("Top-N (candidate pool)", value: topN)
            }
            .help("Wider candidate pool scored before selecting Top-K. Must be ≥ Top-K. RAGflow default: 50.")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Similarity Threshold")
                    Spacer()
                    Text(String(format: "%.2f", threshold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $threshold, in: 0...1, step: 0.05)
                    .accessibilityLabel("Similarity threshold")
                    .help("Minimum relevance score a passage must reach to be included. 0 = accept all candidates; 1 = exact match only. RAGflow default: 0.2.")
            }
        } header: {
            Text("Retrieval")
        } footer: {
            Text("Top-K: passages sent to the model. Top-N: wider candidate pool before scoring. Threshold: minimum relevance score (0 = all candidates, 1 = exact matches only). RAGflow default: K=10, N=50, threshold=0.2.")
                .font(.footnote)
        }
    }

    // MARK: - Chunking

    private var chunkingSection: some View {
        Section {
            Picker("Method", selection: $chunkMethod) {
                ForEach(ChunkMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .help("Controls how documents are split into passages. General works for most content; other methods are optimised for specific formats.")

            Stepper(value: $chunkSize, in: 64...2048, step: 64) {
                labeledValue("Chunk Size (words)", value: chunkSize)
            }
            .help("Target word count per chunk. Smaller = more precise retrieval; larger = more context per passage. Default: 512.")

            Stepper(value: $chunkOverlap, in: 0...min(chunkSize / 2, 256), step: 16) {
                labeledValue("Overlap (words)", value: chunkOverlap)
            }
            .help("Word overlap between adjacent chunks. Prevents context from being split across chunk boundaries. Default: 64.")
        } header: {
            Text("Chunking")
        } footer: {
            Text("\(chunkMethod.rawValue): \(chunkMethod.detail)\n\nChunking settings apply to documents imported after saving. Re-import existing documents to apply new chunk settings.")
                .font(.footnote)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        let embeddingSource = SettingsStore.shared.config.provider == .ollama
            ? "Ollama (network)"
            : "BM25 keyword only"
        return Section {
            LabeledContent("Hybrid Retrieval", value: "BM25 + Vector (RRF)")
            LabeledContent("Chunking Engine", value: "Sentence-boundary (NLTokenizer)")
            LabeledContent("Embeddings", value: embeddingSource)
        } header: {
            Text("Pipeline")
        } footer: {
            Text("Retrieval uses Reciprocal Rank Fusion to merge BM25 keyword search with cosine vector similarity — the same hybrid strategy as RAGflow's backend.")
                .font(.footnote)
        }
    }

    // MARK: - Helpers

    private func labeledValue(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func save() {
        var updated = kb
        updated.topK = topK
        updated.topN = max(topN, topK)
        updated.similarityThreshold = threshold
        updated.chunkMethod = chunkMethod
        updated.chunkSize = chunkSize
        updated.chunkOverlap = min(chunkOverlap, chunkSize / 2)
        onSave(updated)
        dismiss()
    }
}
