import Foundation
import GRDB

final class DatabaseService {
    static let shared = DatabaseService()

    private let dbQueue: DatabaseQueue

    /// For unit tests only — injects a pre-configured in-memory queue.
    init(queue: DatabaseQueue) {
        self.dbQueue = queue
    }

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

        migrator.registerMigration("v6") { db in
            try db.create(table: "chat_sessions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("kbId", .text).notNull()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            let msgCols = try db.columns(in: "messages").map { $0.name }
            if !msgCols.contains("sessionId") {
                try db.alter(table: "messages") { t in
                    t.add(column: "sessionId", .text)
                }
            }
            // Migrate existing messages: create one default session per KB
            let kbIds = try String.fetchAll(db, sql: "SELECT DISTINCT kbId FROM messages")
            for kbId in kbIds {
                let sessionId = UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO chat_sessions (id, kbId, name, createdAt)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [sessionId, kbId, "Chat", Date()])
                try db.execute(sql: "UPDATE messages SET sessionId = ? WHERE kbId = ?",
                               arguments: [sessionId, kbId])
            }
        }

        migrator.registerMigration("v7") { db in
            let cols = try db.columns(in: "knowledge_bases").map { $0.name }
            if !cols.contains("topK") {
                try db.alter(table: "knowledge_bases") { t in
                    t.add(column: "topK", .integer).notNull().defaults(to: 10)
                }
            }
        }

        migrator.registerMigration("v8") { db in
            // Per-KB RAG settings: retrieval + chunking
            let kbCols = try db.columns(in: "knowledge_bases").map { $0.name }
            if !kbCols.contains("topN") {
                try db.alter(table: "knowledge_bases") { t in
                    t.add(column: "topN", .integer).notNull().defaults(to: 50)
                    t.add(column: "chunkMethod", .text).notNull().defaults(to: "General")
                    t.add(column: "chunkSize", .integer).notNull().defaults(to: 512)
                    t.add(column: "chunkOverlap", .integer).notNull().defaults(to: 64)
                    t.add(column: "similarityThreshold", .double).notNull().defaults(to: 0.2)
                }
            }
            // Document metadata
            let bookCols = try db.columns(in: "books").map { $0.name }
            if !bookCols.contains("fileType") {
                try db.alter(table: "books") { t in
                    t.add(column: "fileType", .text).notNull().defaults(to: "")
                    t.add(column: "pageCount", .integer).notNull().defaults(to: 0)
                    t.add(column: "wordCount", .integer).notNull().defaults(to: 0)
                    t.add(column: "sourceURL", .text).notNull().defaults(to: "")
                }
            }
            // Store source document title in message_sources for citations
            let allTables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            if allTables.contains("message_sources") {
                let srcCols = try db.columns(in: "message_sources").map { $0.name }
                if !srcCols.contains("documentTitle") {
                    try db.alter(table: "message_sources") { t in
                        t.add(column: "documentTitle", .text).notNull().defaults(to: "")
                    }
                }
            }
        }

        migrator.registerMigration("v9") { _ in
            // WorkflowStep model gains new step types (variableAssigner, switchStep, categorize)
            // and new optional fields (nextStepId, defaultNextStepId, switchBranches, assignments,
            // categories, categoryPromptOverride, webSearchToolId) encoded in the stepsJSON TEXT blob.
            // No SQL column changes required — JSON is self-describing and Codable decodes nil for
            // missing keys, so existing workflows remain fully backward-compatible.
        }

        migrator.registerMigration("v10") { db in
            // Per-chat overrides: model, temperature, top-p, system prompt.
            let cols = try db.columns(in: "chat_sessions").map { $0.name }
            if !cols.contains("modelOverride") {
                try db.alter(table: "chat_sessions") { t in t.add(column: "modelOverride", .text) }
            }
            if !cols.contains("temperature") {
                try db.alter(table: "chat_sessions") { t in t.add(column: "temperature", .double) }
            }
            if !cols.contains("topP") {
                try db.alter(table: "chat_sessions") { t in t.add(column: "topP", .double) }
            }
            if !cols.contains("systemPrompt") {
                try db.alter(table: "chat_sessions") { t in t.add(column: "systemPrompt", .text) }
            }
        }

        migrator.registerMigration("v11") { db in
            // C4: Per-chat LLM history window (last N messages). NULL = unlimited.
            let cols = try db.columns(in: "chat_sessions").map { $0.name }
            if !cols.contains("historyWindow") {
                try db.alter(table: "chat_sessions") { t in t.add(column: "historyWindow", .integer) }
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
            try db.execute(sql: "DELETE FROM chat_sessions")
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

    func book(id: String) throws -> Book? {
        try dbQueue.read { db in try Book.fetchOne(db, key: id) }
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

    // MARK: - KB lookup

    func kb(id: String) throws -> KnowledgeBase? {
        try dbQueue.read { db in try KnowledgeBase.fetchOne(db, key: id) }
    }

    // MARK: - Search (KB-scoped)

    /// BM25 keyword search returning chunks with their ordinal BM25 rank (1 = most relevant).
    /// Used by hybrid RRF retrieval alongside vector similarity ranking.
    func keywordSearchRanked(query: String, kbId: String, limit: Int) throws -> [(Chunk, Int)] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try dbQueue.read { db in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: query) else { return [] }
            let rows = try Row.fetchAll(db, sql: """
                SELECT chunks.*
                FROM chunks
                JOIN books   ON books.id = chunks.bookId
                JOIN chunks_fts ON chunks_fts.chunk_id = chunks.id
                WHERE books.kbId = ? AND chunks_fts MATCH ?
                ORDER BY chunks_fts.rank
                LIMIT ?
                """, arguments: [kbId, pattern, limit])
            return rows.enumerated().map { idx, row in
                let chunk = Chunk(
                    id: row["id"], bookId: row["bookId"],
                    content: row["content"], chapterTitle: row["chapterTitle"],
                    position: row["position"]
                )
                return (chunk, idx + 1)   // rank 1-based
            }
        }
    }

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

    // MARK: - Chat Sessions

    func session(id: String) throws -> ChatSession? {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM chat_sessions WHERE id = ?", arguments: [id])
            return rows.first.map { Self.sessionFromRow($0) }
        }
    }

    func messageExists(id: String) -> Bool {
        (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages WHERE id = ?", arguments: [id]) ?? 0
        }) ?? 0 > 0
    }

    func allSessions(kbId: String) throws -> [ChatSession] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_sessions WHERE kbId = ? ORDER BY createdAt DESC
                """, arguments: [kbId])
            return rows.map { Self.sessionFromRow($0) }
        }
    }

    func saveSession(_ session: ChatSession) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO chat_sessions
                    (id, kbId, name, createdAt, modelOverride, temperature, topP, systemPrompt, historyWindow)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    session.id, session.kbId, session.name, session.createdAt,
                    session.modelOverride, session.temperature, session.topP,
                    session.systemPrompt, session.historyWindow
                ])
        }
    }

    func updateSessionParams(id: String, modelOverride: String?, temperature: Double?,
                             topP: Double?, systemPrompt: String?, historyWindow: Int?) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE chat_sessions
                SET modelOverride = ?, temperature = ?, topP = ?, systemPrompt = ?, historyWindow = ?
                WHERE id = ?
                """, arguments: [modelOverride, temperature, topP, systemPrompt, historyWindow, id])
        }
    }

    private static func sessionFromRow(_ row: Row) -> ChatSession {
        ChatSession(
            id: row["id"], kbId: row["kbId"], name: row["name"], createdAt: row["createdAt"],
            modelOverride: row["modelOverride"], temperature: row["temperature"],
            topP: row["topP"], systemPrompt: row["systemPrompt"],
            historyWindow: row["historyWindow"]
        )
    }

    func deleteSession(_ id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM chat_sessions WHERE id = ?", arguments: [id])
        }
    }

    func deleteSessions(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM messages WHERE sessionId = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM chat_sessions WHERE id = ?", arguments: [id])
            }
        }
    }

    func renameSession(id: String, name: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE chat_sessions SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    // MARK: - Messages

    func saveMessages(_ messages: [Message], sessionId: String, kbId: String) throws {
        try dbQueue.write { db in
            for msg in messages {
                let roleStr = msg.role == .user ? "user" : "assistant"
                try db.execute(sql: """
                    INSERT OR REPLACE INTO messages (id, kbId, sessionId, role, content, timestamp)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [msg.id.uuidString, kbId, sessionId, roleStr, msg.content, msg.timestamp])
                try db.execute(sql: "DELETE FROM message_sources WHERE messageId = ?",
                               arguments: [msg.id.uuidString])
                for src in msg.sources {
                    try db.execute(sql: """
                        INSERT INTO message_sources (id, messageId, chapterTitle, documentTitle, preview)
                        VALUES (?, ?, ?, ?, ?)
                        """, arguments: [src.id, msg.id.uuidString, src.chapterTitle, src.documentTitle, src.preview])
                }
            }
        }
    }

    func loadMessages(sessionId: String) throws -> [Message] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM messages WHERE sessionId = ? ORDER BY timestamp ASC
                """, arguments: [sessionId])
            return try rows.map { row -> Message in
                let msgId: String = row["id"]
                let srcRows = try Row.fetchAll(db, sql: """
                    SELECT * FROM message_sources WHERE messageId = ?
                    """, arguments: [msgId])
                let sources = srcRows.map { r in
                    ChunkSource(id: r["id"], chapterTitle: r["chapterTitle"],
                                documentTitle: r["documentTitle"] ?? "", preview: r["preview"])
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

    func countMessages(sessionId: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages WHERE sessionId = ?",
                             arguments: [sessionId]) ?? 0
        }
    }

    /// Returns up to `limit` messages ending at `offset` from the newest, in chronological order.
    /// Fetch newest-first, then reverse so callers receive oldest→newest slice.
    func loadMessages(sessionId: String, limit: Int, offset: Int) throws -> [Message] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM messages WHERE sessionId = ?
                ORDER BY timestamp DESC LIMIT ? OFFSET ?
                """, arguments: [sessionId, limit, offset])
            let messages = try rows.map { row -> Message in
                let msgId: String = row["id"]
                let srcRows = try Row.fetchAll(db, sql: """
                    SELECT * FROM message_sources WHERE messageId = ?
                    """, arguments: [msgId])
                let sources = srcRows.map { r in
                    ChunkSource(id: r["id"], chapterTitle: r["chapterTitle"],
                                documentTitle: r["documentTitle"] ?? "", preview: r["preview"])
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
            return messages.reversed()
        }
    }

    func deleteMessages(kbId: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE kbId = ?", arguments: [kbId])
        }
    }

    func deleteMessage(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE id = ?", arguments: [id])
        }
    }

    func firstUserMessage(sessionId: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT content FROM messages
                WHERE sessionId = ? AND role = 'user'
                ORDER BY timestamp ASC LIMIT 1
                """, arguments: [sessionId])
        }
    }

    func sourceCount(sessionId: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM message_sources
                JOIN messages ON messages.id = message_sources.messageId
                WHERE messages.sessionId = ?
                """, arguments: [sessionId]) ?? 0
        }
    }

    func bookTitles(kbId: String, limit: Int = 3) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT title FROM books WHERE kbId = ?
                ORDER BY addedAt DESC LIMIT ?
                """, arguments: [kbId, limit])
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
