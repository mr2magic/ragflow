import Foundation

/// Handles export and import of Workflows and Knowledge Bases.
@MainActor
final class ExportImportService {
    static let shared = ExportImportService()
    private let db = DatabaseService.shared

    private init() {}

    // MARK: - JSON Encoder / Decoder

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Workflow Export

    /// Encodes a workflow to a temporary `.ragflow-workflow` file and returns its URL.
    func workflowExportURL(for workflow: Workflow) throws -> URL {
        let bundle = WorkflowExportBundle(version: 1, exportedAt: Date(), workflow: workflow)
        let data = try encoder.encode(bundle)
        let safeName = sanitizeFilename(workflow.name)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension("ragflow-workflow")
        try data.write(to: url)
        return url
    }

    // MARK: - Workflow Import

    /// Decodes a workflow bundle from a file URL, assigns a new UUID, and returns the workflow.
    /// Caller is responsible for saving it to the database.
    func importWorkflow(from url: URL) throws -> Workflow {
        let data = try Data(contentsOf: url)
        let bundle = try decoder.decode(WorkflowExportBundle.self, from: data)
        var workflow = bundle.workflow
        workflow.id = UUID().uuidString
        workflow.createdAt = Date()
        return workflow
    }

    // MARK: - KB Export

    /// Encodes a KB (metadata + all documents + all chunks) to a temporary `.ragflow-kb` file.
    func kbExportURL(for kbId: String, kbName: String) throws -> URL {
        let data = try buildKBExportData(kbId: kbId, kbName: kbName)
        let safeName = sanitizeFilename(kbName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension("ragflow-kb")
        try data.write(to: url)
        return url
    }

    private func buildKBExportData(kbId: String, kbName: String) throws -> Data {
        guard let kb = try db.kb(id: kbId) else {
            throw ExportImportError.kbNotFound
        }
        let books = try db.allBooks(kbId: kbId)
        let documents: [DocumentExportRecord] = try books.map { book in
            let chunks = try db.chunks(bookId: book.id)
            let chunkRecords = chunks.map { c in
                ChunkExportRecord(
                    id: c.id,
                    content: c.content,
                    chapterTitle: c.chapterTitle,
                    position: c.position
                )
            }
            return DocumentExportRecord(
                id: book.id,
                title: book.title,
                author: book.author,
                fileType: book.fileType,
                sourceURL: book.sourceURL,
                chunks: chunkRecords
            )
        }
        let record = KBExportRecord(
            id: kb.id,
            name: kb.name,
            chunkMethod: kb.chunkMethod.rawValue,
            chunkSize: kb.chunkSize,
            chunkOverlap: kb.chunkOverlap
        )
        let bundle = KBExportBundle(version: 1, exportedAt: Date(), kb: record, documents: documents)
        return try encoder.encode(bundle)
    }

    // MARK: - KB Import

    /// Imports a KB bundle from a file URL.
    /// - Returns the imported KnowledgeBase.
    /// - Embeddings are rebuilt asynchronously after this returns — keyword search works immediately.
    func importKB(from url: URL) async throws -> KnowledgeBase {
        let data = try Data(contentsOf: url)
        let bundle = try decoder.decode(KBExportBundle.self, from: data)

        let kbId = UUID().uuidString
        let method = ChunkMethod(rawValue: bundle.kb.chunkMethod) ?? .general
        let kb = KnowledgeBase(
            id: kbId,
            name: bundle.kb.name,
            createdAt: Date(),
            chunkMethod: method,
            chunkSize: bundle.kb.chunkSize,
            chunkOverlap: bundle.kb.chunkOverlap
        )
        try db.saveKB(kb)

        for doc in bundle.documents {
            let book = Book(
                id: UUID().uuidString,
                kbId: kbId,
                title: doc.title,
                author: doc.author,
                filePath: "",            // no source file — restored from chunks
                addedAt: Date(),
                chunkCount: doc.chunks.count,
                fileType: doc.fileType,
                sourceURL: doc.sourceURL
            )
            try db.save(book)
            let chunks = doc.chunks.map { c in
                Chunk(
                    id: UUID().uuidString,
                    bookId: book.id,
                    content: c.content,
                    chapterTitle: c.chapterTitle,
                    position: c.position
                )
            }
            try db.saveChunks(chunks)
        }

        // Rebuild vector embeddings in the background.
        // FTS keyword search is already functional for the imported chunks.
        Task.detached(priority: .utility) { [kbId] in
            await RAGService.shared.embedChunksForKB(kbId: kbId)
        }

        return kb
    }

    // MARK: - Helpers

    private func sanitizeFilename(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
            .prefix(64)
            .description
    }
}

// MARK: - Errors

enum ExportImportError: LocalizedError {
    case kbNotFound
    case invalidFileFormat

    var errorDescription: String? {
        switch self {
        case .kbNotFound:       return "Knowledge base not found."
        case .invalidFileFormat: return "The file is not a valid RAGFlow export."
        }
    }
}
