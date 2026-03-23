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

        try migrator.migrate(dbQueue)
    }

    // MARK: - Books

    func save(_ book: Book) throws {
        try dbQueue.write { db in try book.save(db) }
    }

    func allBooks() throws -> [Book] {
        try dbQueue.read { db in try Book.fetchAll(db) }
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

    func updateEmbedding(chunkId: String, embedding: Data) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE chunks SET embedding = ? WHERE id = ?",
                arguments: [embedding, chunkId]
            )
        }
    }

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

    // MARK: - Search

    func keywordSearch(query: String, limit: Int = 20) throws -> [Chunk] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try dbQueue.read { db in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else {
                return try Chunk.limit(limit).fetchAll(db)
            }
            return try Chunk.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                WHERE chunks.id IN (
                    SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT ?
                )
                """, arguments: [pattern, limit])
        }
    }

    func allChunksWithEmbeddings(bookId: String? = nil) throws -> [(Chunk, Data)] {
        try dbQueue.read { db in
            let sql = bookId != nil
                ? "SELECT * FROM chunks WHERE bookId = ? AND embedding IS NOT NULL"
                : "SELECT * FROM chunks WHERE embedding IS NOT NULL"
            let args: StatementArguments = bookId != nil ? [bookId!] : []
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
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

    func chunksWithoutEmbeddings(bookId: String) throws -> [Chunk] {
        try dbQueue.read { db in
            try Chunk.fetchAll(db, sql: "SELECT * FROM chunks WHERE bookId = ? AND embedding IS NULL", arguments: [bookId])
        }
    }
}
