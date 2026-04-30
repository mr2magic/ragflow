import Foundation
import GRDB

enum ChunkMethod: String, Codable, CaseIterable, Identifiable {
    case general = "General"
    case qa      = "Q&A"
    case paper   = "Paper"
    case table   = "Table"

    var id: String { rawValue }
}

extension ChunkMethod: DatabaseValueConvertible {}

extension ChunkMethod {
    var detail: String {
        switch self {
        case .general: return "Sentence-boundary paragraphs — best for prose, reports, books"
        case .qa:      return "Q&A pair extraction — best for FAQs and support docs"
        case .paper:   return "Academic structure (abstract, sections, conclusions)"
        case .table:   return "Row-level chunking — best for CSV, spreadsheets, structured data"
        }
    }
}

struct KnowledgeBase: Identifiable, Codable, FetchableRecord, PersistableRecord, Hashable {
    var id: String
    var name: String
    var createdAt: Date

    // Retrieval settings
    var topK: Int = 10             // passages returned to the LLM per query
    var topN: Int = 50             // candidate pool before scoring/threshold
    var similarityThreshold: Double = 0.2  // minimum relevance score (RRF-normalised, 0–1)

    // Chunking settings (applied at ingest time)
    var chunkMethod: ChunkMethod = .general
    var chunkSize: Int = 512       // words per chunk
    var chunkOverlap: Int = 64     // overlapping words between adjacent chunks

    static let databaseTableName = "knowledge_bases"
    static let defaultID = "default"

    static func makeDefault() -> KnowledgeBase {
        KnowledgeBase(id: defaultID, name: "My Library", createdAt: Date())
    }

    public static func == (lhs: KnowledgeBase, rhs: KnowledgeBase) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
