import Foundation
import EPUBKit
import PDFKit

@MainActor
final class RAGService: ObservableObject {
    static let shared = RAGService()

    @Published var embedProgress: Double = 0   // 0.0 – 1.0
    @Published var ingestPhase: String = ""    // e.g. "Parsing PDF…", "Saving chunks…"

    private let db = DatabaseService.shared
    private let chunker = Chunker()
    private let pdfParser = PDFParser()

    // MARK: - Ingest

    func ingest(url: URL, kbId: String) async throws -> Book {
        switch url.pathExtension.lowercased() {
        case "epub":
            return try await ingestEPUB(url: url, kbId: kbId)
        case "pdf":
            return try await ingestPDF(url: url, kbId: kbId)
        case "txt", "md", "mdx", "markdown",
             "csv", "tsv",
             "json", "jsonl", "ldjson",
             "py", "js", "ts", "swift", "java", "c", "cpp", "h", "go",
             "sh", "sql", "yaml", "yml", "xml":
            return try await ingestText(url: url, kbId: kbId)
        case "htm", "html":
            return try await ingestHTML(url: url, kbId: kbId)
        case "rtf":
            return try await ingestRTF(url: url, kbId: kbId)
        default:
            throw IngestError.unsupportedFormat
        }
    }

    // PDF parse + chunk run on a background thread; only DB writes stay on main actor.
    private func ingestPDF(url: URL, kbId: String) async throws -> Book {
        ingestPhase = "Parsing PDF…"
        let parser = pdfParser
        let c = chunker
        let (book, allChunks): (Book, [Chunk]) = try await Task.detached(priority: .utility) {
            let sections = parser.parse(url: url)
            guard !sections.isEmpty else { throw IngestError.parseFailure }
            let bookId = UUID().uuidString
            let pdfDoc = PDFDocument(url: url)
            let title = (pdfDoc?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let author = (pdfDoc?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
            var chunks: [Chunk] = []
            for section in sections {
                chunks.append(contentsOf: c.chunk(text: section.text, bookId: bookId, chapterTitle: section.title))
            }
            let book = Book(id: bookId, kbId: kbId, title: title, author: author,
                            filePath: url.path, addedAt: Date(), chunkCount: chunks.count)
            return (book, chunks)
        }.value
        ingestPhase = "Saving chunks…"
        try db.save(book)
        try db.saveChunks(allChunks)
        ingestPhase = "Embedding…"
        await embedChunks(allChunks)
        ingestPhase = ""
        return book
    }

    // EPUB spine parse + chunk run on a background thread.
    private func ingestEPUB(url: URL, kbId: String) async throws -> Book {
        ingestPhase = "Parsing EPUB…"
        let c = chunker
        let (book, allChunks): (Book, [Chunk]) = try await Task.detached(priority: .utility) {
            guard let document = EPUBDocument(url: url) else { throw IngestError.parseFailure }
            let bookId = UUID().uuidString
            var chunks: [Chunk] = []
            for spineItem in document.spine.items {
                guard let manifestItem = document.manifest.items[spineItem.idref] else { continue }
                let fileURL = document.contentDirectory.appendingPathComponent(manifestItem.path)
                guard let html = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let text = RAGService.stripHTMLStatic(html)
                guard !text.isEmpty else { continue }
                let title = URL(fileURLWithPath: manifestItem.path).deletingPathExtension().lastPathComponent
                chunks.append(contentsOf: c.chunk(text: text, bookId: bookId, chapterTitle: title))
            }
            let book = Book(
                id: bookId, kbId: kbId,
                title: document.metadata.title ?? url.deletingPathExtension().lastPathComponent,
                author: document.metadata.creator?.name ?? "",
                filePath: url.path, addedAt: Date(), chunkCount: chunks.count
            )
            return (book, chunks)
        }.value
        ingestPhase = "Saving chunks…"
        try db.save(book)
        try db.saveChunks(allChunks)
        ingestPhase = "Embedding…"
        await embedChunks(allChunks)
        ingestPhase = ""
        return book
    }

    private func ingestText(url: URL, kbId: String) async throws -> Book {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestError.parseFailure
        }
        return try await ingestPlain(text: text, url: url, kbId: kbId)
    }

    private func ingestHTML(url: URL, kbId: String) async throws -> Book {
        let html = try String(contentsOf: url, encoding: .utf8)
        let text = RAGService.stripHTMLStatic(html)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestError.parseFailure
        }
        return try await ingestPlain(text: text, url: url, kbId: kbId)
    }

    private func ingestRTF(url: URL, kbId: String) async throws -> Book {
        let data = try Data(contentsOf: url)
        let attrString = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let text = attrString.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestError.parseFailure
        }
        return try await ingestPlain(text: text, url: url, kbId: kbId)
    }

    private func ingestPlain(text: String, url: URL, kbId: String) async throws -> Book {
        let bookId = UUID().uuidString
        let title = url.deletingPathExtension().lastPathComponent
        let allChunks = chunker.chunk(text: text, bookId: bookId, chapterTitle: nil)
        let book = Book(
            id: bookId, kbId: kbId, title: title, author: "",
            filePath: url.path, addedAt: Date(), chunkCount: allChunks.count
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

    nonisolated private static func stripHTMLStatic(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum IngestError: LocalizedError {
        case unsupportedFormat, parseFailure

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Unsupported format. Supported: PDF, ePub, TXT, MD, HTML, RTF, CSV, JSON, and common code files."
            case .parseFailure: return "Could not parse the document."
            }
        }
    }
}
