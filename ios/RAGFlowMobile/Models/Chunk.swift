import Foundation
import GRDB

struct Chunk: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var bookId: String
    var content: String
    var chapterTitle: String?
    var position: Int

    static let databaseTableName = "chunks"
}
