import Foundation

struct ChatSession: Identifiable, Hashable {
    var id: String
    var kbId: String
    var name: String
    var createdAt: Date
}
