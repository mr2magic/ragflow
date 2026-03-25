import Foundation
import GRDB

final class DatabaseService {
    static let shared = DatabaseService()

    private let dbQueue: DatabaseQueue

    private init() {
        do {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let url = dir.appendingPathComponent("ragflow.sqlite")
            dbQueue = try DatabaseQueue(path: url.path)
        } catch {
            fatalError("RAGFlow: cannot open database — \(error)")
        }
        do {
            try migrate()
        } catch {
            fatalError("RAGFlow: database migration failed — \(error)")
        }
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

        migrator.registerMigration("v4") { db in
            try db.create(table: "messages", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("kbId", .text).notNull()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }
            try db.create(table: "message_sources", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("messageId", .text).notNull().references("messages", onDelete: .cascade)
                t.column("chapterTitle", .text)
                t.column("preview", .text).notNull()
            }
        }

        migrator.registerMigration("v5") { db in
            try db.create(table: "workflows", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("templateId", .text).notNull()
                t.column("kbId", .text).notNull()
                t.column("stepsJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "workflow_runs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("workflowId", .text).notNull().references("workflows", onDelete: .cascade)
                t.column("input", .text).notNull()
                t.column("output", .text).notNull()
                t.column("status", .text).notNull()
                t.column("stepLogJSON", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Debug helpers

    #if DEBUG
    func wipeAllData() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM message_sources")
            try db.execute(sql: "DELETE FROM messages")
            try db.execute(sql: "DELETE FROM workflow_runs")
            try db.execute(sql: "DELETE FROM workflows")
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
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
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
            // Try broad match first (any token) — better recall for natural-language questions.
            // Fall back to first N chunks by position when no FTS tokens match (e.g. meta-queries
            // like "summarize this corpus" where the words don't appear in the documents).
            let ftsResults: [Chunk]
            if let pattern = FTS5Pattern(matchingAnyTokenIn: query) {
                ftsResults = try Chunk.fetchAll(db, sql: """
                    SELECT chunks.* FROM chunks
                    JOIN books ON books.id = chunks.bookId
                    WHERE books.kbId = ?
                    AND chunks.id IN (
                        SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT ?
                    )
                    """, arguments: [kbId, pattern, limit])
            } else {
                ftsResults = []
            }

            if !ftsResults.isEmpty { return ftsResults }

            // Fallback: return a spread of chunks across the KB so the LLM always has context.
            return try Chunk.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = ?
                ORDER BY books.addedAt DESC, chunks.position ASC
                LIMIT ?
                """, arguments: [kbId, limit])
        }
    }

    // MARK: - Messages

    func saveMessages(_ messages: [Message], kbId: String) throws {
        try dbQueue.write { db in
            for msg in messages {
                let roleStr = msg.role == .user ? "user" : "assistant"
                try db.execute(sql: """
                    INSERT OR REPLACE INTO messages (id, kbId, role, content, timestamp)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [msg.id.uuidString, kbId, roleStr, msg.content, msg.timestamp])
                try db.execute(sql: "DELETE FROM message_sources WHERE messageId = ?",
                               arguments: [msg.id.uuidString])
                for src in msg.sources {
                    try db.execute(sql: """
                        INSERT INTO message_sources (id, messageId, chapterTitle, preview)
                        VALUES (?, ?, ?, ?)
                        """, arguments: [src.id, msg.id.uuidString, src.chapterTitle, src.preview])
                }
            }
        }
    }

    func loadMessages(kbId: String) throws -> [Message] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM messages WHERE kbId = ? ORDER BY timestamp ASC
                """, arguments: [kbId])
            return try rows.map { row -> Message in
                let msgId: String = row["id"]
                let srcRows = try Row.fetchAll(db, sql: """
                    SELECT * FROM message_sources WHERE messageId = ?
                    """, arguments: [msgId])
                let sources = srcRows.map { r in
                    ChunkSource(id: r["id"], chapterTitle: r["chapterTitle"], preview: r["preview"])
                }
                var msg = Message(
                    role: (row["role"] as String) == "user" ? .user : .assistant,
                    content: row["content"]
                )
                msg.id = UUID(uuidString: msgId) ?? UUID()
                msg.sources = sources
                msg.timestamp = row["timestamp"]
                return msg
            }
        }
    }

    func deleteMessages(kbId: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE kbId = ?", arguments: [kbId])
        }
    }

    // MARK: - Workflows

    func allWorkflows() throws -> [Workflow] {
        try dbQueue.read { db in
            try Workflow.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func saveWorkflow(_ workflow: Workflow) throws {
        var w = workflow
        try dbQueue.write { db in try w.save(db) }
    }

    func deleteWorkflow(_ id: String) throws {
        _ = try dbQueue.write { db in try Workflow.deleteOne(db, key: id) }
    }

    func runsForWorkflow(_ workflowId: String, limit: Int = 20) throws -> [WorkflowRun] {
        try dbQueue.read { db in
            try WorkflowRun
                .filter(Column("workflowId") == workflowId)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func saveWorkflowRun(_ run: WorkflowRun) throws {
        var r = run
        try dbQueue.write { db in try r.save(db) }
    }

    func deleteRunsForWorkflow(_ workflowId: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM workflow_runs WHERE workflowId = ?", arguments: [workflowId])
        }
    }

    // MARK: - Chunks (by book)

    func chunks(bookId: String) throws -> [Chunk] {
        try dbQueue.read { db in
            try Chunk.filter(Column("bookId") == bookId)
                .order(Column("position"))
                .fetchAll(db)
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
