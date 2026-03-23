import Foundation

struct Message: Identifiable {
    var id = UUID()
    var role: Role
    var content: String
    var sources: [ChunkSource] = []
    var toolActivity: String? = nil   // e.g. "Searching Brave…"
    var timestamp = Date()

    enum Role {
        case user, assistant
    }

    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

struct ChunkSource: Identifiable {
    var id: String
    var chapterTitle: String?
    var preview: String

    init(from chunk: Chunk) {
        self.id = chunk.id
        self.chapterTitle = chunk.chapterTitle
        self.preview = String(chunk.content.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(id: String, chapterTitle: String?, preview: String) {
        self.id = id
        self.chapterTitle = chapterTitle
        self.preview = preview
    }
}
