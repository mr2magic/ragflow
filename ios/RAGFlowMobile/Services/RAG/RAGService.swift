import Foundation
import EPUBKit
import PDFKit

@MainActor
final class RAGService: ObservableObject {
    static let shared = RAGService()

    @Published var embedProgress: Double = 0   // 0.0 – 1.0

    private let db = DatabaseService.shared
    private let chunker = Chunker()
    private let pdfParser = PDFParser()

    // MARK: - Ingest

    func ingest(url: URL, kbId: String) async throws -> Book {
        switch url.pathExtension.lowercased() {
        case "epub": return try await ingestEPUB(url: url, kbId: kbId)
        case "pdf":  return try await ingestPDF(url: url, kbId: kbId)
        default:     throw IngestError.unsupportedFormat
        }
    }

    private func ingestEPUB(url: URL, kbId: String) async throws -> Book {
        guard let document = EPUBDocument(url: url) else { throw IngestError.parseFailure }

        let bookId = UUID().uuidString
        var allChunks: [Chunk] = []

        for spineItem in document.spine.items {
            guard let manifestItem = document.manifest.items[spineItem.idref] else { continue }
            let fileURL = document.contentDirectory.appendingPathComponent(manifestItem.path)
            guard let html = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let text = stripHTML(html)
            guard !text.isEmpty else { continue }
            let title = URL(fileURLWithPath: manifestItem.path).deletingPathExtension().lastPathComponent
            allChunks.append(contentsOf: chunker.chunk(text: text, bookId: bookId, chapterTitle: title))
        }

        let book = Book(
            id: bookId,
            kbId: kbId,
            title: document.metadata.title ?? url.deletingPathExtension().lastPathComponent,
            author: document.metadata.creator?.name ?? "",
            filePath: url.path,
            addedAt: Date(),
            chunkCount: allChunks.count
        )

        try db.save(book)
        try db.saveChunks(allChunks)
        await embedChunks(allChunks)
        return book
    }

    private func ingestPDF(url: URL, kbId: String) async throws -> Book {
        let sections = pdfParser.parse(url: url)
        guard !sections.isEmpty else { throw IngestError.parseFailure }

        let bookId = UUID().uuidString
        var allChunks: [Chunk] = []

        let pdfDoc = PDFDocument(url: url)
        let title = (pdfDoc?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let author = (pdfDoc?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""

        for section in sections {
            allChunks.append(contentsOf: chunker.chunk(
                text: section.text,
                bookId: bookId,
                chapterTitle: section.title
            ))
        }

        let book = Book(
            id: bookId,
            kbId: kbId,
            title: title,
            author: author,
            filePath: url.path,
            addedAt: Date(),
            chunkCount: allChunks.count
        )

        try db.save(book)
        try db.saveChunks(allChunks)
        await embedChunks(allChunks)
        return book
    }

    // MARK: - Embedding

    private func embedChunks(_ chunks: [Chunk]) async {
        let settings = SettingsStore.shared
        guard settings.config.provider == .ollama else { return }

        let service = EmbeddingService(host: settings.config.ollamaHost)
        let batchSize = 10
        embedProgress = 0

        var processed = 0
        var i = 0
        while i < chunks.count {
            let batch = Array(chunks[i..<min(i + batchSize, chunks.count)])
            let texts = batch.map(\.content)

            if let embeddings = try? await service.embed(texts: texts) {
                let updates = zip(batch, embeddings).map { (chunk, vector) in
                    (id: chunk.id, embedding: EmbeddingService.floatsToData(vector))
                }
                try? db.updateEmbeddingsBatch(updates)
            }

            processed += batch.count
            embedProgress = Double(processed) / Double(chunks.count)
            i += batchSize
        }

        embedProgress = 1.0
    }

    // MARK: - Retrieve (Hybrid, KB-scoped)

    func retrieve(query: String, kbId: String, topK: Int = 5) throws -> [Chunk] {
        let candidates = (try? db.keywordSearch(query: query, kbId: kbId, limit: 20)) ?? []
        return Array(candidates.prefix(topK))
    }

    func retrieveWithEmbedding(query: String, queryEmbedding: [Float], kbId: String, topK: Int = 5) throws -> [Chunk] {
        let chunksWithVectors = (try? db.allChunksWithEmbeddings(kbId: kbId)) ?? []

        guard !chunksWithVectors.isEmpty else {
            return (try? db.keywordSearch(query: query, kbId: kbId, limit: topK)) ?? []
        }

        let scored = chunksWithVectors.map { (chunk, data) -> (Chunk, Float) in
            let vector = EmbeddingService.dataToFloats(data)
            let score = EmbeddingService.cosineSimilarity(queryEmbedding, vector)
            return (chunk, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map(\.0)
    }

    // MARK: - Helpers

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum IngestError: LocalizedError {
        case unsupportedFormat, parseFailure

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Only ePub and PDF files are supported."
            case .parseFailure: return "Could not parse the document."
            }
        }
    }
}
