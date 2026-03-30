import Foundation
import GRDB

/// Represents an ingested document in a Knowledge Base.
/// Called "Book" for historical DB-schema compatibility; represents any document type.
struct Book: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var kbId: String
    var title: String
    var author: String
    var filePath: String
    var addedAt: Date
    var chunkCount: Int

    // Document metadata (migration v8)
    var fileType: String = ""      // "epub", "pdf", "docx", "xlsx", "pptx", "eml", "txt", etc.
    var pageCount: Int = 0         // pages for PDF/EPUB; rows for spreadsheets; 0 if unknown
    var wordCount: Int = 0         // approximate word count of extracted text
    var sourceURL: String = ""     // original URL if imported from the web

    static let databaseTableName = "books"

    var fileTypeLabel: String {
        fileType.isEmpty ? "Document" : fileType.uppercased()
    }
}
