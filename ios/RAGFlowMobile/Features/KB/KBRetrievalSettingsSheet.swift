import SwiftUI

/// Full per-KB RAG configuration sheet — mirrors RAGflow's Knowledge Base settings panel.
/// Controls both retrieval behaviour (topK, topN, threshold) and
/// chunking strategy (method, size, overlap) applied at ingest time.
struct KBRetrievalSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_theme") private var themeRaw: String = AppTheme.simple.rawValue
    private let kb: KnowledgeBase
    private let onSave: (KnowledgeBase) -> Void

    private var isDossier: Bool { AppTheme(rawValue: themeRaw) == .dossier }

    // Retrieval settings
    @State private var topK: Int
    @State private var topN: Int
    @State private var threshold: Double

    // Chunking settings
    @State private var chunkMethod: ChunkMethod
    @State private var chunkSize: Int
    @State private var chunkOverlap: Int

    // Re-index state
    @State private var isReindexing = false
    @State private var showReindexConfirm = false
    @State private var reindexMessage: String?
    @State private var showReindexResult = false

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
                reindexSection
                infoSection
            }
            .scrollContentBackground(.hidden)
            .background(isDossier ? DT.manila : Color(uiColor: .systemGroupedBackground))
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
            .confirmationDialog(
                "Re-index All Documents?",
                isPresented: $showReindexConfirm,
                titleVisibility: .visible
            ) {
                Button("Save & Re-index All", role: .destructive) {
                    save()
                    Task { await reindexAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will save your settings and re-chunk every document in this knowledge base using the new settings. Documents without their original file on disk will be skipped.")
            }
            .alert("Re-index Complete", isPresented: $showReindexResult) {
                Button("OK") {}
            } message: {
                Text(reindexMessage ?? "")
            }
        }
    }

    // MARK: - Retrieval

    private var retrievalSection: some View {
        Section {
            Stepper(value: $topK, in: 1...100) {
                labeledValue("Top-K (returned passages)", value: topK,
                             help: "Number of passages actually sent to the AI model. Lower = faster; higher = more context. Default: 10.")
            }
            .onChange(of: topK) { _, newK in
                if topN < newK { topN = newK }
            }

            Stepper(value: $topN, in: max(topK, 1)...500, step: 10) {
                labeledValue("Top-N (candidate pool)", value: topN,
                             help: "Wider candidate pool scored before selecting Top-K. Must be ≥ Top-K. Default: 50.")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Similarity Threshold")
                    SettingHelpButton(text: "Minimum relevance score a passage must reach to be included. 0 = accept all candidates; 1 = exact match only. Default: 0.2.")
                    Spacer()
                    Text(String(format: "%.2f", threshold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $threshold, in: 0...1, step: 0.05)
                    .accessibilityLabel("Similarity threshold")
            }
        } header: {
            Text("Retrieval")
        } footer: {
            Text("Top-K: passages sent to the model. Top-N: wider candidate pool before scoring. Threshold: minimum relevance score (0 = all candidates, 1 = exact matches only). Default: K=10, N=50, threshold=0.2.")
                .font(.footnote)
        }
    }

    // MARK: - Chunking

    private var chunkingSection: some View {
        Section {
            Picker(selection: $chunkMethod) {
                ForEach(ChunkMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Method")
                    SettingHelpButton(text: "Controls how documents are split into passages. General works for most content; other methods are optimised for specific formats.")
                }
            }

            Stepper(value: $chunkSize, in: 64...2048, step: 64) {
                labeledValue("Chunk Size (words)", value: chunkSize,
                             help: "Target word count per chunk. Smaller = more precise retrieval; larger = more context per passage. Default: 512.")
            }

            Stepper(value: $chunkOverlap, in: 0...min(chunkSize / 2, 256), step: 16) {
                labeledValue("Overlap (words)", value: chunkOverlap,
                             help: "Word overlap between adjacent chunks. Prevents context from being split across chunk boundaries. Default: 64.")
            }
        } header: {
            Text("Chunking")
        } footer: {
            Text("\(chunkMethod.rawValue): \(chunkMethod.detail)\n\nChunking settings apply to documents imported after saving. Re-import existing documents to apply new chunk settings.")
                .font(.footnote)
        }
    }

    // MARK: - Re-index

    private var reindexSection: some View {
        Section {
            Button {
                showReindexConfirm = true
            } label: {
                HStack {
                    if isReindexing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 4)
                        Text("Re-indexing…")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Re-index All Documents", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .disabled(isReindexing)
        } footer: {
            Text("Applies current chunking settings to every document already in this knowledge base. Useful after changing chunk size, overlap, or method.")
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
            Text("Retrieval uses Reciprocal Rank Fusion to merge BM25 keyword search with cosine vector similarity — the same hybrid strategy as Ragion's backend.")
                .font(.footnote)
        }
    }

    // MARK: - Helpers

    private func labeledValue(_ label: String, value: Int, help: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label)
            if let help {
                SettingHelpButton(text: help)
            }
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func reindexAll() async {
        let db = DatabaseService.shared
        let rag = RAGService.shared
        let books = (try? db.allBooks(kbId: kb.id)) ?? []
        guard !books.isEmpty else {
            reindexMessage = "No documents found in this knowledge base."
            showReindexResult = true
            return
        }
        isReindexing = true
        defer { isReindexing = false }
        var succeeded = 0
        var skipped = 0
        for book in books {
            guard FileManager.default.fileExists(atPath: book.filePath) else {
                skipped += 1
                continue
            }
            do {
                try db.deleteBook(book.id)
                let reindexed = try await rag.ingest(url: URL(fileURLWithPath: book.filePath), kbId: book.kbId)
                let chunks = (try? db.chunks(bookId: reindexed.id)) ?? []
                SpotlightIndexer.shared.index(book: reindexed, chunks: chunks)
                succeeded += 1
            } catch {
                try? db.save(book)
                skipped += 1
            }
        }
        SharedGroupDefaults.syncFromApp()
        reindexMessage = "\(succeeded) document\(succeeded == 1 ? "" : "s") re-indexed successfully" +
            (skipped > 0 ? ", \(skipped) skipped (file not found or error)." : ".")
        showReindexResult = true
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

// MARK: - Inline help button

/// Small ⓘ button that shows a brief explanation popover when tapped.
/// On iPhone the popover adapts to a compact floating card.
private struct SettingHelpButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(minWidth: 220, maxWidth: 280, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Help for this setting")
    }
}
