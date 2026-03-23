import Foundation
import GRDB

struct Book: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var kbId: String
    var title: String
    var author: String
    var filePath: String
    var addedAt: Date
    var chunkCount: Int

    static let databaseTableName = "books"
}
