import Foundation
import GRDB

final class DatabaseService {
    static let shared = DatabaseService()

    private let dbQueue: DatabaseQueue

    private init() {
        let dir = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = dir.appendingPathComponent("ragflow.sqlite")
        dbQueue = try! DatabaseQueue(path: url.path)
        try! migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "books", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("author", .text).notNull().defaults(to: "")
                t.column("filePath", .text).notNull()
                t.column("addedAt", .datetime).notNull()
                t.column("chunkCount", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "chunks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("bookId", .text).notNull().references("books", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("chapterTitle", .text)
                t.column("position", .integer).notNull()
            }
            try db.create(virtualTable: "chunks_fts", ifNotExists: true, using: FTS5()) { t in
                t.tokenizer = .porter()
                t.column("chunk_id")
                t.column("content")
                t.column("chapterTitle")
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "chunks") { t in
                t.add(column: "embedding", .blob)
            }
        }

        migrator.registerMigration("v3") { db in
            try db.create(table: "knowledge_bases", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            // Seed the default KB
            try db.execute(
                sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                arguments: [KnowledgeBase.defaultID, "My Library", Date()]
            )
            // Add kbId to books, defaulting all existing books to "My Library"
            let columns = try db.columns(in: "books").map { $0.name }
            if !columns.contains("kbId") {
                try db.alter(table: "books") { t in
                    t.add(column: "kbId", .text).notNull().defaults(to: KnowledgeBase.defaultID)
                }
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Debug helpers

    #if DEBUG
    func wipeAllData() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM chunks_fts")
            try db.execute(sql: "DELETE FROM chunks")
            try db.execute(sql: "DELETE FROM books")
            try db.execute(sql: "DELETE FROM knowledge_bases")
            // Re-seed default KB
            try db.execute(
                sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                arguments: [KnowledgeBase.defaultID, "My Library", Date()]
            )
        }
    }
    #endif

    // MARK: - Knowledge Bases

    func allKBs() throws -> [KnowledgeBase] {
        try dbQueue.read { db in
            try KnowledgeBase.order(Column("createdAt")).fetchAll(db)
        }
    }

    func saveKB(_ kb: KnowledgeBase) throws {
        try dbQueue.write { db in try kb.save(db) }
    }

    func deleteKB(_ id: String) throws {
        guard id != KnowledgeBase.defaultID else { return } // protect default KB
        try dbQueue.write { db in
            // Books in this KB will cascade-delete their chunks via FK
            try db.execute(sql: "DELETE FROM books WHERE kbId = ?", arguments: [id])
            try KnowledgeBase.deleteOne(db, key: id)
        }
    }

    // MARK: - Books (Documents)

    func save(_ book: Book) throws {
        try dbQueue.write { db in try book.save(db) }
    }

    func allBooks(kbId: String) throws -> [Book] {
        try dbQueue.read { db in
            try Book.filter(Column("kbId") == kbId)
                .order(Column("addedAt").desc)
                .fetchAll(db)
        }
    }

    func deleteBook(_ id: String) throws {
        try dbQueue.write { db in
            let chunkIds = try String.fetchAll(db, sql: "SELECT id FROM chunks WHERE bookId = ?", arguments: [id])
            for cid in chunkIds {
                try db.execute(sql: "DELETE FROM chunks_fts WHERE chunk_id = ?", arguments: [cid])
            }
            try Book.deleteOne(db, key: id)
        }
    }

    // MARK: - Chunks

    func saveChunks(_ chunks: [Chunk]) throws {
        try dbQueue.write { db in
            for chunk in chunks {
                try chunk.save(db)
                try db.execute(
                    sql: "INSERT INTO chunks_fts(chunk_id, content, chapterTitle) VALUES (?, ?, ?)",
                    arguments: [chunk.id, chunk.content, chunk.chapterTitle ?? ""]
                )
            }
        }
    }

    #if DEBUG
    func seedDummyData() throws {
        let existing = (try? allKBs()) ?? []
        guard existing.count <= 1 else { return } // only seed once

        let scifi = KnowledgeBase(id: UUID().uuidString, name: "Sci-Fi Classics", createdAt: Date().addingTimeInterval(-86400 * 14))
        let philosophy = KnowledgeBase(id: UUID().uuidString, name: "Philosophy", createdAt: Date().addingTimeInterval(-86400 * 7))
        try saveKB(scifi)
        try saveKB(philosophy)

        let dummyBooks: [Book] = [
            // My Library
            Book(id: UUID().uuidString, kbId: KnowledgeBase.defaultID, title: "Pride and Prejudice", author: "Jane Austen", filePath: "", addedAt: Date().addingTimeInterval(-86400 * 10), chunkCount: 312),
            Book(id: UUID().uuidString, kbId: KnowledgeBase.defaultID, title: "Sherlock Holmes", author: "Arthur Conan Doyle", filePath: "", addedAt: Date().addingTimeInterval(-86400 * 5), chunkCount: 47),
            // Sci-Fi Classics
            Book(id: UUID().uuidString, kbId: scifi.id, title: "Dune", author: "Frank Herbert", filePath: "", addedAt: Date().addingTimeInterval(-86400 * 12), chunkCount: 892),
            Book(id: UUID().uuidString, kbId: scifi.id, title: "Foundation", author: "Isaac Asimov", filePath: "", addedAt: Date().addingTimeInterval(-86400 * 8), chunkCount: 445),
            Book(id: UUID().uuidString, kbId: scifi.id, title: "Neuromancer", author: "William Gibson", filePath: "", addedAt: Date().addingTimeInterval(-86400 * 3), chunkCount: 267),
            // Philosophy
            Book(id: UUID().uuidString, kbId: philosophy.id, title: "Meditations", author: "Marcus Aurelius", filePath: "", addedAt: Date().addingTimeInterval(-86400 * 6), chunkCount: 198),
            Book(id: UUID().uuidString, kbId: philosophy.id, title: "Nicomachean Ethics", author: "Aristotle", filePath: "", addedAt: Date().addingTimeInterval(-86400 * 2), chunkCount: 341),
        ]
        for book in dummyBooks { try save(book) }
    }
    #endif

    func updateEmbeddingsBatch(_ updates: [(id: String, embedding: Data)]) throws {
        try dbQueue.write { db in
            for (id, data) in updates {
                try db.execute(
                    sql: "UPDATE chunks SET embedding = ? WHERE id = ?",
                    arguments: [data, id]
                )
            }
        }
    }

    // MARK: - Search (KB-scoped)

    func keywordSearch(query: String, kbId: String, limit: Int = 20) throws -> [Chunk] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try dbQueue.read { db in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else {
                return try Chunk.limit(limit).fetchAll(db)
            }
            return try Chunk.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = ?
                AND chunks.id IN (
                    SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT ?
                )
                """, arguments: [kbId, pattern, limit])
        }
    }

    func allChunksWithEmbeddings(kbId: String) throws -> [(Chunk, Data)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = ? AND chunks.embedding IS NOT NULL
                """, arguments: [kbId])
            return rows.compactMap { row -> (Chunk, Data)? in
                guard let embedding = row["embedding"] as? Data else { return nil }
                let chunk = Chunk(
                    id: row["id"],
                    bookId: row["bookId"],
                    content: row["content"],
                    chapterTitle: row["chapterTitle"],
                    position: row["position"]
                )
                return (chunk, embedding)
            }
        }
    }
}
