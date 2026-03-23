import Foundation
import GRDB

struct KnowledgeBase: Identifiable, Codable, FetchableRecord, PersistableRecord, Hashable {
    var id: String
    var name: String
    var createdAt: Date

    static let databaseTableName = "knowledge_bases"

    static let defaultID = "default"

    static func makeDefault() -> KnowledgeBase {
        KnowledgeBase(id: defaultID, name: "My Library", createdAt: Date())
    }

    public static func == (lhs: KnowledgeBase, rhs: KnowledgeBase) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
