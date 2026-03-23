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

            // Standalone FTS5 table — we insert manually on ingest
            try db.create(virtualTable: "chunks_fts", ifNotExists: true, using: FTS5()) { t in
                t.tokenizer = .porter()
                t.column("chunk_id")
                t.column("content")
                t.column("chapterTitle")
            }
        }

        try migrator.migrate(dbQueue)
    }

    func save(_ book: Book) throws {
        try dbQueue.write { db in try book.save(db) }
    }

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

    func allBooks() throws -> [Book] {
        try dbQueue.read { db in try Book.fetchAll(db) }
    }

    func deleteBook(_ id: String) throws {
        try dbQueue.write { db in
            // Clean up FTS entries for this book's chunks
            let chunkIds = try String.fetchAll(db, sql: "SELECT id FROM chunks WHERE bookId = ?", arguments: [id])
            for cid in chunkIds {
                try db.execute(sql: "DELETE FROM chunks_fts WHERE chunk_id = ?", arguments: [cid])
            }
            try Book.deleteOne(db, key: id)
        }
    }

    func search(query: String, limit: Int = 5) throws -> [Chunk] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try dbQueue.read { db in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else {
                // Fallback: return recent chunks if pattern is unformable
                return try Chunk.limit(limit).fetchAll(db)
            }
            return try Chunk.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                WHERE chunks.id IN (
                    SELECT chunk_id FROM chunks_fts
                    WHERE chunks_fts MATCH ?
                    LIMIT ?
                )
                """, arguments: [pattern, limit])
        }
    }
}
