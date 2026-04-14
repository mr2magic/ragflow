import Foundation
import EPUBKit
import PDFKit
import Zip

@MainActor
final class RAGService: ObservableObject {
    static let shared = RAGService()

    @Published var embedProgress: Double = 0   // 0.0 – 1.0
    @Published var ingestPhase: String = ""    // e.g. "Parsing PDF…", "Saving chunks…"

    private let db = DatabaseService.shared
    private let pdfParser = PDFParser()
    private let officeParser = OfficeParser()
    private let emlParser = EMLParser()

    // MARK: - Ingest

    /// Ingest a document that was downloaded from `sourceURL`.
    /// Sets the sourceURL metadata field on the resulting document record.
    func ingest(url: URL, kbId: String, sourceURL: String) async throws -> Book {
        var book = try await ingest(url: url, kbId: kbId)
        book.sourceURL = sourceURL
        try db.save(book)
        return book
    }

    func ingest(url: URL, kbId: String) async throws -> Book {
        // Load KB settings for per-KB chunking configuration
        let kb = (try? db.kb(id: kbId)) ?? KnowledgeBase(id: kbId, name: "", createdAt: Date())
        let c = Chunker(chunkSize: kb.chunkSize, overlap: kb.chunkOverlap)
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "epub":
            return try await ingestEPUB(url: url, kbId: kbId, chunker: c)
        case "pdf":
            return try await ingestPDF(url: url, kbId: kbId, chunker: c)
        case "txt", "md", "mdx", "markdown",
             "csv", "tsv",
             "json", "jsonl", "ldjson",
             "py", "js", "ts", "swift", "java", "c", "cpp", "h", "go",
             "sh", "sql", "yaml", "yml", "xml":
            return try await ingestText(url: url, kbId: kbId, chunker: c)
        case "htm", "html":
            return try await ingestHTML(url: url, kbId: kbId, chunker: c)
        case "rtf":
            return try await ingestRTF(url: url, kbId: kbId, chunker: c)
        case "docx":
            return try await ingestDOCX(url: url, kbId: kbId, chunker: c)
        case "xlsx":
            return try await ingestXLSX(url: url, kbId: kbId, chunker: c)
        case "pptx":
            return try await ingestPPTX(url: url, kbId: kbId, chunker: c)
        case "eml", "emlx":
            return try await ingestEML(url: url, kbId: kbId, chunker: c)
        case "odt":
            return try await ingestODT(url: url, kbId: kbId, chunker: c)
        default:
            throw IngestError.unsupportedFormat
        }
    }

    // PDFKit is not thread-safe — parse on @MainActor, only chunk on background thread.
    private func ingestPDF(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        ingestPhase = "Parsing PDF…"
        var sections = pdfParser.parse(url: url)

        // Scanned / image-only PDF — no text layer. Fall back to on-device Vision OCR.
        if sections.isEmpty {
            ingestPhase = "Scanning with OCR…"
            let pageTexts = await VisionOCRParser().extractText(fromPDFAt: url)
            sections = pageTexts.enumerated().map { i, text in
                PDFParser.PDFSection(title: "Page \(i + 1)", text: text)
            }
        }
        guard !sections.isEmpty else { throw IngestError.parseFailure }

        let pdfDoc = PDFDocument(url: url)
        let title = (pdfDoc?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let author = (pdfDoc?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
        let pageCount = pdfDoc?.pageCount ?? 0

        ingestPhase = "Chunking…"
        let bookId = UUID().uuidString
        let allChunks: [Chunk] = await Task.detached(priority: .utility) {
            var chunks: [Chunk] = []
            for section in sections {
                chunks.append(contentsOf: c.chunk(text: section.text, bookId: bookId, chapterTitle: section.title))
            }
            return chunks
        }.value

        let wordCount = allChunks.reduce(0) { $0 + $1.content.split(separator: " ").count }
        var book = Book(id: bookId, kbId: kbId, title: title, author: author,
                        filePath: url.path, addedAt: Date(), chunkCount: allChunks.count)
        book.fileType = "pdf"
        book.pageCount = pageCount
        book.wordCount = wordCount
        ingestPhase = "Saving chunks…"
        try db.save(book)
        try db.saveChunks(allChunks)
        ingestPhase = "Embedding…"
        await embedChunks(allChunks)
        ingestPhase = ""
        return book
    }

    // EPUB spine parse + chunk run on a background thread.
    private func ingestEPUB(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        ingestPhase = "Parsing EPUB…"
        let (book, allChunks): (Book, [Chunk]) = try await Task.detached(priority: .utility) {
            guard let document = EPUBDocument(url: url) else { throw IngestError.parseFailure }
            let bookId = UUID().uuidString
            var chunks: [Chunk] = []

            // Build TOC chapter title map: spine file path → chapter label
            // EPUBTableOfContents is a recursive struct; .item holds the manifest item id.
            var chapterTitles: [String: String] = [:]
            func collectTOC(_ node: EPUBTableOfContents) {
                if let manifestId = node.item,
                   let manifestItem = document.manifest.items[manifestId] {
                    let path = manifestItem.path.components(separatedBy: "/").last ?? manifestItem.path
                    let base = path.components(separatedBy: "#").first ?? path
                    chapterTitles[base] = node.label
                    chapterTitles[manifestItem.path] = node.label
                }
                node.subTable?.forEach { collectTOC($0) }
            }
            collectTOC(document.tableOfContents)

            for spineItem in document.spine.items {
                guard let manifestItem = document.manifest.items[spineItem.idref] else { continue }
                let fileURL = document.contentDirectory.appendingPathComponent(manifestItem.path)
                guard let html = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let text = RAGService.stripHTMLStatic(html)
                guard text.count > 150 else { continue }  // skip cover/nav/metadata pages

                // Use NCX title if available, fall back to filename-derived label
                let baseName = manifestItem.path.components(separatedBy: "/").last ?? manifestItem.path
                let chapterTitle = chapterTitles[baseName]
                    ?? chapterTitles[manifestItem.path]
                    ?? baseName.components(separatedBy: ".").first?.replacingOccurrences(of: "_", with: " ").capitalized

                chunks.append(contentsOf: c.chunk(text: text, bookId: bookId, chapterTitle: chapterTitle))
            }
            guard !chunks.isEmpty else { throw RAGService.IngestError.parseFailure }
            let wordCount = chunks.reduce(0) { $0 + $1.content.split(separator: " ").count }
            var book = Book(
                id: bookId, kbId: kbId,
                title: document.metadata.title ?? url.deletingPathExtension().lastPathComponent,
                author: document.metadata.creator?.name ?? "",
                filePath: url.path, addedAt: Date(), chunkCount: chunks.count
            )
            book.fileType = "epub"
            book.wordCount = wordCount
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

    private func ingestText(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestError.parseFailure
        }
        return try await ingestPlain(text: text, url: url, kbId: kbId, chunker: c,
                                      fileType: url.pathExtension.lowercased())
    }

    private func ingestHTML(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        let html = try String(contentsOf: url, encoding: .utf8)
        let text = RAGService.stripHTMLStatic(html)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestError.parseFailure
        }
        return try await ingestPlain(text: text, url: url, kbId: kbId, chunker: c, fileType: "html")
    }

    private func ingestRTF(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
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
        return try await ingestPlain(text: text, url: url, kbId: kbId, chunker: c, fileType: "rtf")
    }

    private func ingestOffice(url: URL, kbId: String, chunker c: Chunker,
                               sections: [OfficeParser.Section], ext: String) async throws -> Book {
        let bookId = UUID().uuidString
        let allChunks: [Chunk] = await Task.detached(priority: .utility) {
            sections.flatMap { c.chunk(text: $0.text, bookId: bookId, chapterTitle: $0.title) }
        }.value
        guard !allChunks.isEmpty else { throw IngestError.parseFailure }
        let wordCount = allChunks.reduce(0) { $0 + $1.content.split(separator: " ").count }
        var book = Book(id: bookId, kbId: kbId,
                        title: url.deletingPathExtension().lastPathComponent, author: "",
                        filePath: url.path, addedAt: Date(), chunkCount: allChunks.count)
        book.fileType = ext
        book.wordCount = wordCount
        try db.save(book)
        try db.saveChunks(allChunks)
        await embedChunks(allChunks)
        ingestPhase = ""
        return book
    }

    private func ingestDOCX(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        ingestPhase = "Parsing DOCX…"
        let sections = try await Task.detached(priority: .utility) { [officeParser] in
            try officeParser.parseDOCX(url: url)
        }.value
        return try await ingestOffice(url: url, kbId: kbId, chunker: c, sections: sections, ext: "docx")
    }

    private func ingestXLSX(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        ingestPhase = "Parsing XLSX…"
        let sections = try await Task.detached(priority: .utility) { [officeParser] in
            try officeParser.parseXLSX(url: url)
        }.value
        return try await ingestOffice(url: url, kbId: kbId, chunker: c, sections: sections, ext: "xlsx")
    }

    private func ingestPPTX(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        ingestPhase = "Parsing PPTX…"
        let sections = try await Task.detached(priority: .utility) { [officeParser] in
            try officeParser.parsePPTX(url: url)
        }.value
        return try await ingestOffice(url: url, kbId: kbId, chunker: c, sections: sections, ext: "pptx")
    }

    private func ingestODT(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        ingestPhase = "Parsing ODT…"
        let sections = try await Task.detached(priority: .utility) { [officeParser] in
            try officeParser.parseODT(url: url)
        }.value
        return try await ingestOffice(url: url, kbId: kbId, chunker: c, sections: sections, ext: "odt")
    }

    private func ingestEML(url: URL, kbId: String, chunker c: Chunker) async throws -> Book {
        ingestPhase = "Parsing EML…"
        let content = try await Task.detached(priority: .utility) { [emlParser] in
            try emlParser.parse(url: url)
        }.value
        let text = [content.subject, content.body]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestError.parseFailure
        }
        let title = content.subject.isEmpty ? url.deletingPathExtension().lastPathComponent : content.subject
        return try await ingestPlain(text: text, url: url, kbId: kbId, chunker: c,
                                      fileType: "eml", title: title)
    }

    private func ingestPlain(text: String, url: URL, kbId: String, chunker c: Chunker,
                              fileType: String = "", title: String? = nil) async throws -> Book {
        let bookId = UUID().uuidString
        let resolvedTitle = title ?? url.deletingPathExtension().lastPathComponent
        let allChunks = c.chunk(text: text, bookId: bookId, chapterTitle: nil)
        guard !allChunks.isEmpty else { throw IngestError.parseFailure }
        let wordCount = allChunks.reduce(0) { $0 + $1.content.split(separator: " ").count }
        var book = Book(id: bookId, kbId: kbId, title: resolvedTitle, author: "",
                        filePath: url.path, addedAt: Date(), chunkCount: allChunks.count)
        book.fileType = fileType
        book.wordCount = wordCount
        try db.save(book)
        try db.saveChunks(allChunks)
        await embedChunks(allChunks)
        return book
    }

    // MARK: - Embedding

    /// Re-embed all chunks for a KB. Called after KB import to build vector index.
    /// Keyword search works immediately even before this completes.
    func embedChunksForKB(kbId: String) async {
        let books = (try? db.allBooks(kbId: kbId)) ?? []
        let chunks = books.flatMap { (try? db.chunks(bookId: $0.id)) ?? [] }
        guard !chunks.isEmpty else { return }
        await embedChunks(chunks)
    }

    private func embedChunks(_ chunks: [Chunk]) async {
        let settings = SettingsStore.shared
        guard settings.config.provider == .ollama else { return }

        let host = settings.config.ollamaHost
        let db = self.db
        let total = chunks.count
        embedProgress = 0

        // Run entirely in background — network I/O + DB writes all off the main thread.
        await Task.detached(priority: .utility) { [weak self] in
            let service = EmbeddingService(host: host)
            let batchSize = 10
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
                let progress = Double(processed) / Double(total)
                let s = self
                await MainActor.run { s?.embedProgress = progress }
                i += batchSize
            }
            let s = self
            await MainActor.run { s?.embedProgress = 1.0 }
        }.value
    }

    // MARK: - Retrieve (Hybrid RRF, KB-scoped)

    /// Primary retrieval entry point — uses Reciprocal Rank Fusion to merge
    /// BM25 (FTS5) and vector cosine similarity rankings into a single scored list.
    /// Falls back to BM25-only when no embeddings are available.
    ///
    /// RRF formula: score(d) = Σ 1 / (k + rank_i(d))   where k=60 (standard constant)
    /// This is the same fusion strategy used by RAGflow's hybrid retrieval pipeline.
    func retrieve(query: String, kb: KnowledgeBase) throws -> [Chunk] {
        let topN = max(kb.topN, kb.topK * 3)
        let topK  = kb.topK
        let threshold = kb.similarityThreshold
        let kbId  = kb.id

        // --- BM25 via FTS5 ---
        let bm25Ranked = (try? db.keywordSearchRanked(query: query, kbId: kbId, limit: topN)) ?? []

        // Build a lookup table for fast access during fusion
        var chunkById: [String: Chunk] = [:]
        var rrfScores: [String: Double] = [:]

        let k = 60.0
        for (chunk, rank) in bm25Ranked {
            chunkById[chunk.id] = chunk
            rrfScores[chunk.id, default: 0] += 1.0 / (k + Double(rank))
        }

        // --- Vector cosine similarity (if embeddings exist) ---
        let allEmbedded = (try? db.allChunksWithEmbeddings(kbId: kbId)) ?? []
        if !allEmbedded.isEmpty,
           let queryVec = currentQueryEmbedding {
            // Score every embedded chunk by cosine similarity
            let scored = allEmbedded.map { (chunk, data) -> (String, Double) in
                let vec = EmbeddingService.dataToFloats(data)
                let sim = Double(EmbeddingService.cosineSimilarity(queryVec, vec))
                return (chunk.id, sim)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(topN)

            for (rank, (id, _)) in scored.enumerated() {
                // Populate chunkById for vector-only hits (may not be in BM25 results)
                if chunkById[id] == nil,
                   let hit = allEmbedded.first(where: { $0.0.id == id }) {
                    chunkById[id] = hit.0
                }
                rrfScores[id, default: 0] += 1.0 / (k + Double(rank + 1))
            }
        }

        // --- Fallback: no FTS or vector hits — spread across KB ---
        if rrfScores.isEmpty {
            return (try? db.keywordSearch(query: query, kbId: kbId, limit: topK)) ?? []
        }

        // --- Normalise scores, apply threshold, return top-K ---
        let maxScore = rrfScores.values.max() ?? 1.0
        return rrfScores
            .compactMap { id, score -> (Chunk, Double)? in
                guard let chunk = chunkById[id] else { return nil }
                let normalised = maxScore > 0 ? score / maxScore : score
                guard normalised >= threshold else { return nil }
                return (chunk, normalised)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map(\.0)
    }

    /// Transient storage for the query embedding used during a single retrieve() call.
    /// Set by ChatViewModel before calling retrieve(), cleared after.
    var currentQueryEmbedding: [Float]?

    // Retained for WorkflowRunner compatibility
    func retrieve(query: String, kbId: String, topK: Int = 5) throws -> [Chunk] {
        let kb = (try? db.kb(id: kbId)) ?? KnowledgeBase(id: kbId, name: "", createdAt: Date())
        var kbOverride = kb
        kbOverride.topK = topK
        return (try? retrieve(query: query, kb: kbOverride)) ?? []
    }

    func retrieveWithEmbedding(query: String, queryEmbedding: [Float], kbId: String, topK: Int = 5) throws -> [Chunk] {
        currentQueryEmbedding = queryEmbedding
        defer { currentQueryEmbedding = nil }
        return (try? retrieve(query: query, kbId: kbId, topK: topK)) ?? []
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
            case .unsupportedFormat: return "Unsupported format. Supported: PDF, ePub, DOCX, XLSX, PPTX, EML, TXT, MD, HTML, RTF, CSV, JSON, and common code files."
            case .parseFailure: return "Could not parse the document."
            }
        }
    }
}
