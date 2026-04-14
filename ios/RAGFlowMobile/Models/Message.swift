import Foundation

struct Message: Identifiable {
    var id = UUID()
    var role: Role
    var content: String
    var sources: [ChunkSource] = []
    var toolActivity: String? = nil
    var timestamp = Date()
    var tokenUsage: TokenUsage? = nil

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
    var documentTitle: String         // source document name for citations
    var chapterTitle: String?
    var preview: String

    init(from chunk: Chunk, documentTitle: String = "") {
        self.id = chunk.id
        self.documentTitle = documentTitle
        self.chapterTitle = chunk.chapterTitle
        self.preview = String(chunk.content.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(id: String, chapterTitle: String?, documentTitle: String = "", preview: String) {
        self.id = id
        self.documentTitle = documentTitle
        self.chapterTitle = chapterTitle
        self.preview = preview
    }
}
