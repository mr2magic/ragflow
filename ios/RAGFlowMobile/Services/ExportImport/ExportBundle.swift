import Foundation

// MARK: - Workflow Export Bundle

struct WorkflowExportBundle: Codable {
    let version: Int          // = 1
    let exportedAt: Date
    let workflow: Workflow
    // stepsJSON is already inside Workflow — no extra field needed
}

// MARK: - KB Export Bundle

struct KBExportBundle: Codable {
    let version: Int          // = 1
    let exportedAt: Date
    let kb: KBExportRecord
    let documents: [DocumentExportRecord]
}

struct KBExportRecord: Codable {
    let id: String
    let name: String
    let chunkMethod: String
    let chunkSize: Int
    let chunkOverlap: Int
}

struct DocumentExportRecord: Codable {
    let id: String
    let title: String
    let author: String
    let fileType: String
    let sourceURL: String
    let chunks: [ChunkExportRecord]
}

struct ChunkExportRecord: Codable {
    let id: String
    let content: String
    let chapterTitle: String?
    let position: Int
    // Note: embeddings are NOT exported (model-specific).
    // Re-embed on import via RAGService.embedChunksForKB(kbId:).
}
