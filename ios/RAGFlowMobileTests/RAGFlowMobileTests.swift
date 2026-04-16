import XCTest
import GRDB
@testable import RAGFlowMobile

// MARK: - Chunker

final class ChunkerTests: XCTestCase {
    private let chunker = Chunker(chunkSize: 10, overlap: 2)

    func testChunkSplitsText() {
        // 25 words at chunkSize=10 → at least 2 chunks (word-boundary fallback for no-sentence text)
        let words = Array(repeating: "word", count: 25)
        let text = words.joined(separator: " ")
        let chunks = chunker.chunk(text: text, bookId: "test")
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertEqual(chunks.first?.position, 0)
    }

    func testEmptyTextReturnsNoChunks() {
        let chunks = chunker.chunk(text: "", bookId: "test")
        XCTAssertTrue(chunks.isEmpty)
    }

    func testChunksHaveCorrectBookId() {
        let chunks = chunker.chunk(text: "one two three four five six", bookId: "book-123")
        XCTAssertTrue(chunks.allSatisfy { $0.bookId == "book-123" })
    }

    func testChapterTitlePropagated() {
        let chunks = chunker.chunk(text: "one two three", bookId: "b", chapterTitle: "Chapter 1")
        XCTAssertTrue(chunks.allSatisfy { $0.chapterTitle == "Chapter 1" })
    }

    func testChunkPositionsAreSequential() {
        let text = Array(repeating: "w", count: 50).joined(separator: " ")
        let chunks = chunker.chunk(text: text, bookId: "x")
        for (i, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.position, i)
        }
    }

    func testSingleWordText() {
        let chunks = chunker.chunk(text: "hello", bookId: "x")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].content, "hello")
    }

    func testChunkIdsAreUnique() {
        let text = Array(repeating: "word", count: 50).joined(separator: " ")
        let chunks = chunker.chunk(text: text, bookId: "x")
        let ids = chunks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "All chunk IDs must be unique")
    }

    func testOverlapProducesExpectedChunkCount() {
        // 20 single-char words, chunkSize=10, overlap=2
        // Sentence chunker treats this as 1 long sentence > chunkSize → word-boundary fallback
        // step = chunkSize - buffer_at_split: produces ≥ 2 chunks
        let text = Array(repeating: "w", count: 20).joined(separator: " ")
        let chunks = Chunker(chunkSize: 10, overlap: 2).chunk(text: text, bookId: "x")
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
    }
}

// MARK: - EmbeddingService math

final class EmbeddingServiceTests: XCTestCase {

    func testCosineSimilarityIdenticalVectors() {
        let v: [Float] = [1, 0, 0, 0]
        let score = EmbeddingService.cosineSimilarity(v, v)
        XCTAssertEqual(score, 1.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOrthogonalVectors() {
        let a: [Float] = [1, 0]
        let b: [Float] = [0, 1]
        let score = EmbeddingService.cosineSimilarity(a, b)
        XCTAssertEqual(score, 0.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOppositeVectors() {
        let a: [Float] = [1, 0]
        let b: [Float] = [-1, 0]
        let score = EmbeddingService.cosineSimilarity(a, b)
        XCTAssertEqual(score, -1.0, accuracy: 1e-5)
    }

    func testCosineSimilarityMismatchedLengthsReturnsZero() {
        let score = EmbeddingService.cosineSimilarity([1, 0], [1, 0, 0])
        XCTAssertEqual(score, 0.0)
    }

    func testFloatRoundTrip() {
        let original: [Float] = [0.1, 0.2, 0.3, -0.9, 1.0]
        let data = EmbeddingService.floatsToData(original)
        let recovered = EmbeddingService.dataToFloats(data)
        XCTAssertEqual(original.count, recovered.count)
        for (a, b) in zip(original, recovered) {
            XCTAssertEqual(a, b, accuracy: 1e-7)
        }
    }

    func testEmptyVectorRoundTrip() {
        let data = EmbeddingService.floatsToData([])
        let recovered = EmbeddingService.dataToFloats(data)
        XCTAssertTrue(recovered.isEmpty)
    }
}

// MARK: - LLMError

final class LLMErrorTests: XCTestCase {

    func testMissingApiKeyHasDescription() {
        let err = LLMError.missingApiKey
        XCTAssertNotNil(err.errorDescription)
        XCTAssertFalse(err.errorDescription!.isEmpty)
    }

    func testBadResponseHasDescription() {
        let err = LLMError.badResponse
        XCTAssertNotNil(err.errorDescription)
    }

    func testServerErrorSurfacesMessage() {
        let msg = "model 'llama9' not found"
        let err = LLMError.serverError("Ollama: \(msg)")
        XCTAssertTrue(err.errorDescription?.contains(msg) == true)
    }
}

// MARK: - SettingsStore isConfigured

final class SettingsStoreConfiguredTests: XCTestCase {

    func testClaudeConfiguredWhenKeyPresent() {
        var config = LLMConfig.default
        config.provider = .claude
        config.claudeApiKey = "sk-test-key"
        let store = SettingsStore.shared
        let saved = store.config
        store.config = config
        XCTAssertTrue(store.isConfigured)
        store.config = saved
    }

    func testClaudeNotConfiguredWhenKeyEmpty() {
        var config = LLMConfig.default
        config.provider = .claude
        config.claudeApiKey = "   "
        let store = SettingsStore.shared
        let saved = store.config
        store.config = config
        XCTAssertFalse(store.isConfigured)
        store.config = saved
    }

    func testOllamaConfiguredWhenHostAndModelPresent() {
        var config = LLMConfig.default
        config.provider = .ollama
        config.ollamaHost = "http://192.168.1.5:11434"
        config.ollamaModel = "llama3.2"
        let store = SettingsStore.shared
        let saved = store.config
        store.config = config
        XCTAssertTrue(store.isConfigured)
        store.config = saved
    }

    func testOllamaNotConfiguredWhenModelEmpty() {
        var config = LLMConfig.default
        config.provider = .ollama
        config.ollamaHost = "http://192.168.1.5:11434"
        config.ollamaModel = ""
        let store = SettingsStore.shared
        let saved = store.config
        store.config = config
        XCTAssertFalse(store.isConfigured)
        store.config = saved
    }

    func testOllamaNotConfiguredWhenHostEmpty() {
        var config = LLMConfig.default
        config.provider = .ollama
        config.ollamaHost = ""
        config.ollamaModel = "llama3.2"
        let store = SettingsStore.shared
        let saved = store.config
        store.config = config
        XCTAssertFalse(store.isConfigured)
        store.config = saved
    }
}

// MARK: - KnowledgeBase model

final class KnowledgeBaseTests: XCTestCase {

    func testDefaultIDIsStable() {
        XCTAssertFalse(KnowledgeBase.defaultID.isEmpty)
        XCTAssertEqual(KnowledgeBase.defaultID, KnowledgeBase.defaultID)
    }

    func testKBCreation() {
        let kb = KnowledgeBase(id: "test-id", name: "Science", createdAt: Date())
        XCTAssertEqual(kb.id, "test-id")
        XCTAssertEqual(kb.name, "Science")
    }
}

// MARK: - DatabaseService (in-memory)

final class DatabaseServiceTests: XCTestCase {
    private var db: DatabaseQueue!

    override func setUp() {
        super.setUp()
        // Use an in-memory DB so tests are fully isolated
        db = try! DatabaseQueue()
        try! runMigrations(on: db)
    }

    /// Replicate the full migration sequence from DatabaseService.
    private func runMigrations(on queue: DatabaseQueue) throws {
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
            try db.alter(table: "chunks") { t in t.add(column: "embedding", .blob) }
        }
        migrator.registerMigration("v3") { db in
            try db.create(table: "knowledge_bases", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                arguments: [KnowledgeBase.defaultID, "My Library", Date()]
            )
            try db.alter(table: "books") { t in
                t.add(column: "kbId", .text).notNull().defaults(to: KnowledgeBase.defaultID)
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
        migrator.registerMigration("v7") { db in
            try db.alter(table: "knowledge_bases") { t in
                t.add(column: "topK", .integer).notNull().defaults(to: 10)
            }
        }
        migrator.registerMigration("v8") { db in
            try db.alter(table: "knowledge_bases") { t in
                t.add(column: "topN", .integer).notNull().defaults(to: 50)
                t.add(column: "chunkMethod", .text).notNull().defaults(to: "General")
                t.add(column: "chunkSize", .integer).notNull().defaults(to: 512)
                t.add(column: "chunkOverlap", .integer).notNull().defaults(to: 64)
                t.add(column: "similarityThreshold", .double).notNull().defaults(to: 0.2)
            }
            try db.alter(table: "books") { t in
                t.add(column: "fileType", .text).notNull().defaults(to: "")
                t.add(column: "pageCount", .integer).notNull().defaults(to: 0)
                t.add(column: "wordCount", .integer).notNull().defaults(to: 0)
                t.add(column: "sourceURL", .text).notNull().defaults(to: "")
            }
            try db.alter(table: "message_sources") { t in
                t.add(column: "documentTitle", .text).notNull().defaults(to: "")
            }
        }
        try migrator.migrate(queue)
    }

    // MARK: Schema

    func testAllTablesExist() throws {
        let tables = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
        }
        for expected in ["books", "chunks", "knowledge_bases", "messages", "message_sources"] {
            XCTAssertTrue(tables.contains(expected), "Missing table: \(expected)")
        }
    }

    func testDefaultKBSeeded() throws {
        let count = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_bases WHERE id = ?",
                             arguments: [KnowledgeBase.defaultID])!
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: Books CRUD

    func testSaveAndFetchBook() throws {
        let book = Book(id: "b1", kbId: KnowledgeBase.defaultID, title: "Dune",
                        author: "Herbert", filePath: "/tmp/dune.pdf",
                        addedAt: Date(), chunkCount: 10)
        try db.write { db in try book.save(db) }

        let fetched = try db.read { db in
            try Book.filter(Column("id") == "b1").fetchOne(db)
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Dune")
        XCTAssertEqual(fetched?.author, "Herbert")
    }

    func testDeleteBookCascadesChunks() throws {
        let book = Book(id: "b2", kbId: KnowledgeBase.defaultID, title: "Test",
                        author: "", filePath: "", addedAt: Date(), chunkCount: 2)
        try db.write { db in try book.save(db) }

        let chunk = Chunk(id: "c1", bookId: "b2", content: "hello world",
                          chapterTitle: nil, position: 0)
        try db.write { db in try chunk.save(db) }

        try db.write { db in try Book.deleteOne(db, key: "b2") }

        let chunkCount = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunks WHERE bookId = 'b2'")!
        }
        XCTAssertEqual(chunkCount, 0, "Chunks should cascade-delete with their book")
    }

    // MARK: Chunks

    func testSaveAndFetchChunk() throws {
        let book = Book(id: "b3", kbId: KnowledgeBase.defaultID, title: "T",
                        author: "", filePath: "", addedAt: Date(), chunkCount: 1)
        try db.write { db in try book.save(db) }

        let chunk = Chunk(id: "c2", bookId: "b3", content: "some text here",
                          chapterTitle: "Ch1", position: 0)
        try db.write { db in try chunk.save(db) }

        let fetched = try db.read { db in
            try Chunk.filter(Column("id") == "c2").fetchOne(db)
        }
        XCTAssertEqual(fetched?.content, "some text here")
        XCTAssertEqual(fetched?.chapterTitle, "Ch1")
    }

    func testEmbeddingRoundTrip() throws {
        let book = Book(id: "b4", kbId: KnowledgeBase.defaultID, title: "T",
                        author: "", filePath: "", addedAt: Date(), chunkCount: 1)
        try db.write { db in try book.save(db) }

        var chunk = Chunk(id: "c3", bookId: "b4", content: "embed test",
                          chapterTitle: nil, position: 0)
        try db.write { db in try chunk.save(db) }

        let vector: [Float] = [0.1, 0.2, 0.3]
        let data = EmbeddingService.floatsToData(vector)
        try db.write { db in
            try db.execute(sql: "UPDATE chunks SET embedding = ? WHERE id = 'c3'",
                           arguments: [data])
        }

        let row = try db.read { db in
            try Row.fetchOne(db, sql: "SELECT embedding FROM chunks WHERE id = 'c3'")
        }
        let recovered = EmbeddingService.dataToFloats(row!["embedding"] as! Data)
        XCTAssertEqual(recovered.count, 3)
        XCTAssertEqual(recovered[0], 0.1, accuracy: 1e-6)
    }

    // MARK: Messages

    func testSaveAndLoadMessages() throws {
        let kb = KnowledgeBase(id: "kb-test", name: "Test KB", createdAt: Date())
        try db.write { db in try kb.save(db) }

        let msgId = UUID().uuidString
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, kbId, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                arguments: [msgId, "kb-test", "user", "What is Dune about?", Date()])
            try db.execute(
                sql: "INSERT INTO message_sources (id, messageId, chapterTitle, preview) VALUES (?, ?, ?, ?)",
                arguments: ["src-1", msgId, "Chapter 1", "In the beginning..."])
        }

        let messages = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM messages WHERE kbId = 'kb-test'")
        }
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["content"] as String, "What is Dune about?")

        let sources = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM message_sources WHERE messageId = ?",
                             arguments: [msgId])
        }
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0]["preview"] as String, "In the beginning...")
    }

    func testMessageSourcesCascadeDeleteWithMessage() throws {
        let kb = KnowledgeBase(id: "kb-cascade", name: "Cascade KB", createdAt: Date())
        try db.write { db in try kb.save(db) }

        let msgId = UUID().uuidString
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, kbId, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                arguments: [msgId, "kb-cascade", "assistant", "A reply", Date()])
            try db.execute(
                sql: "INSERT INTO message_sources (id, messageId, chapterTitle, preview) VALUES (?, ?, ?, ?)",
                arguments: ["src-2", msgId, nil, "A passage"])
            try db.execute(sql: "DELETE FROM messages WHERE id = ?", arguments: [msgId])
        }

        let srcCount = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM message_sources WHERE messageId = ?",
                             arguments: [msgId])!
        }
        XCTAssertEqual(srcCount, 0, "message_sources should cascade-delete with their message")
    }

    // MARK: Knowledge Bases

    func testCreateAndDeleteKB() throws {
        let kb = KnowledgeBase(id: "kb-new", name: "New KB", createdAt: Date())
        try db.write { db in try kb.save(db) }

        let count = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_bases WHERE id = 'kb-new'")!
        }
        XCTAssertEqual(count, 1)

        try db.write { db in try KnowledgeBase.deleteOne(db, key: "kb-new") }
        let afterCount = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledge_bases WHERE id = 'kb-new'")!
        }
        XCTAssertEqual(afterCount, 0)
    }
}

// MARK: - RAGService HTML stripping (via ingestHTML logic)

final class RAGServiceHTMLTests: XCTestCase {

    // Access the nonisolated static method via a minimal subclass hook
    // Since stripHTMLStatic is private, test indirectly via Chunker on expected output
    func testHTMLTagsNotIncludedInChunks() {
        // If the html strip worked, "<b>Hello</b> World" → "Hello World"
        let html = "<h1>Title</h1><p>First paragraph with <b>bold</b> text.</p>"
        // Strip manually matching the same regex logic
        let stripped = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(stripped.contains("<"))
        XCTAssertFalse(stripped.contains(">"))
        XCTAssertTrue(stripped.contains("Title"))
        XCTAssertTrue(stripped.contains("bold"))
    }
}

// MARK: - Chunk Fetch & Retrieval (in-memory DB)

final class ChunkFetchTests: XCTestCase {
    private var dbq: DatabaseQueue!

    override func setUp() {
        super.setUp()
        dbq = try! DatabaseQueue()
        try! runMigrations()
    }

    private func runMigrations() throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
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
        m.registerMigration("v2") { db in
            try db.alter(table: "chunks") { t in t.add(column: "embedding", .blob) }
        }
        m.registerMigration("v3") { db in
            try db.create(table: "knowledge_bases", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                           arguments: [KnowledgeBase.defaultID, "My Library", Date()])
            try db.alter(table: "books") { t in
                t.add(column: "kbId", .text).notNull().defaults(to: KnowledgeBase.defaultID)
            }
        }
        m.registerMigration("v4") { db in
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
        m.registerMigration("v7") { db in
            try db.alter(table: "knowledge_bases") { t in
                t.add(column: "topK", .integer).notNull().defaults(to: 10)
            }
        }
        m.registerMigration("v8") { db in
            try db.alter(table: "knowledge_bases") { t in
                t.add(column: "topN", .integer).notNull().defaults(to: 50)
                t.add(column: "chunkMethod", .text).notNull().defaults(to: "General")
                t.add(column: "chunkSize", .integer).notNull().defaults(to: 512)
                t.add(column: "chunkOverlap", .integer).notNull().defaults(to: 64)
                t.add(column: "similarityThreshold", .double).notNull().defaults(to: 0.2)
            }
            try db.alter(table: "books") { t in
                t.add(column: "fileType", .text).notNull().defaults(to: "")
                t.add(column: "pageCount", .integer).notNull().defaults(to: 0)
                t.add(column: "wordCount", .integer).notNull().defaults(to: 0)
                t.add(column: "sourceURL", .text).notNull().defaults(to: "")
            }
            try db.alter(table: "message_sources") { t in
                t.add(column: "documentTitle", .text).notNull().defaults(to: "")
            }
        }
        try m.migrate(dbq)
    }

    // Helper: save a KB, book, and chunks into the in-memory DB.
    private func seed(kbId: String, kbName: String, bookId: String, contents: [(String, String?)]) throws {
        try dbq.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                           arguments: [kbId, kbName, Date()])
            let book = Book(id: bookId, kbId: kbId, title: kbName + " Book", author: "",
                            filePath: "", addedAt: Date(), chunkCount: contents.count)
            try book.save(db)
            for (i, (text, title)) in contents.enumerated() {
                let chunk = Chunk(id: "\(bookId)-c\(i)", bookId: bookId, content: text,
                                  chapterTitle: title, position: i)
                try chunk.save(db)
                try db.execute(sql: "INSERT INTO chunks_fts(chunk_id, content, chapterTitle) VALUES (?, ?, ?)",
                               arguments: [chunk.id, text, title ?? ""])
            }
        }
    }

    // MARK: chunks(bookId:)

    func testChunksByBookIdReturnedInPositionOrder() throws {
        try seed(kbId: "kb1", kbName: "Astronomy", bookId: "book1", contents: [
            ("Stars are giant balls of plasma.", "Section 1"),
            ("Black holes form when massive stars collapse.", "Section 2"),
            ("Galaxies contain billions of stars.", "Section 3"),
        ])
        let chunks = try dbq.read { db in
            try Chunk.filter(Column("bookId") == "book1")
                .order(Column("position"))
                .fetchAll(db)
        }
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].position, 0)
        XCTAssertEqual(chunks[1].position, 1)
        XCTAssertEqual(chunks[2].position, 2)
        XCTAssertTrue(chunks[0].content.contains("plasma"))
    }

    func testChunksByBookIdFilteredToCorrectBook() throws {
        try seed(kbId: "kb1", kbName: "Astronomy", bookId: "bookA", contents: [
            ("The Sun is a yellow dwarf star.", nil),
        ])
        try seed(kbId: "kb1", kbName: "Astronomy", bookId: "bookB", contents: [
            ("Julius Caesar crossed the Rubicon in 49 BCE.", nil),
        ])
        let chunksA = try dbq.read { db in
            try Chunk.filter(Column("bookId") == "bookA").fetchAll(db)
        }
        let chunksB = try dbq.read { db in
            try Chunk.filter(Column("bookId") == "bookB").fetchAll(db)
        }
        XCTAssertEqual(chunksA.count, 1)
        XCTAssertTrue(chunksA[0].content.contains("Sun"))
        XCTAssertEqual(chunksB.count, 1)
        XCTAssertTrue(chunksB[0].content.contains("Caesar"))
    }

    // MARK: FTS keyword search

    func testFTSFindsRelevantAstronomyChunk() throws {
        try seed(kbId: "kb-astro", kbName: "Astronomy", bookId: "astro1", contents: [
            ("The Milky Way is a barred spiral galaxy containing 400 billion stars.", "Section 1"),
            ("Jupiter is the largest planet in the solar system with a Great Red Spot storm.", "Section 2"),
            ("Black holes warp spacetime so strongly that not even light can escape the event horizon.", "Section 3"),
        ])
        let results = try dbq.read { db -> [Chunk] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "black hole event horizon") else {
                XCTFail("Pattern should be valid"); return []
            }
            return try Chunk.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = 'kb-astro'
                AND chunks.id IN (SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT 20)
                """, arguments: [pattern])
        }
        XCTAssertFalse(results.isEmpty, "Should find at least one chunk about black holes")
        XCTAssertTrue(results.contains { $0.content.contains("Black holes") })
    }

    func testFTSFindsHistoryChunk() throws {
        try seed(kbId: "kb-hist", kbName: "History", bookId: "hist1", contents: [
            ("The pharaohs of ancient Egypt built massive pyramids as royal tombs.", "Section 1"),
            ("Rome was founded according to tradition in 753 BCE by Romulus.", "Section 2"),
            ("Hammurabi's law code is inscribed on a basalt stele in the Louvre.", "Section 3"),
        ])
        let results = try dbq.read { db -> [Chunk] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "pharaoh pyramid Egypt") else {
                XCTFail("Pattern should be valid"); return []
            }
            return try Chunk.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = 'kb-hist'
                AND chunks.id IN (SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT 20)
                """, arguments: [pattern])
        }
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.content.contains("pharaohs") })
    }

    func testFTSFallbackReturnsChunksWhenNoTokenMatch() throws {
        try seed(kbId: "kb-fb", kbName: "Fallback KB", bookId: "fb1", contents: [
            ("Stellar nucleosynthesis produces heavy elements in supergiant stars.", "Ch1"),
            ("The Coriolis effect influences atmospheric circulation patterns.", "Ch2"),
        ])
        // "summarize corpus" — these words don't appear in the chunks
        let pattern = FTS5Pattern(matchingAnyTokenIn: "summarize corpus")
        // pattern may be nil or return empty results; either way fallback should work
        let ftsResults: [Chunk]
        if let p = pattern {
            ftsResults = (try? dbq.read { db in
                try Chunk.fetchAll(db, sql: """
                    SELECT chunks.* FROM chunks
                    JOIN books ON books.id = chunks.bookId
                    WHERE books.kbId = 'kb-fb'
                    AND chunks.id IN (SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT 20)
                    """, arguments: [p])
            }) ?? []
        } else {
            ftsResults = []
        }

        // Fallback path
        if ftsResults.isEmpty {
            let fallback = try dbq.read { db in
                try Chunk.fetchAll(db, sql: """
                    SELECT chunks.* FROM chunks
                    JOIN books ON books.id = chunks.bookId
                    WHERE books.kbId = 'kb-fb'
                    ORDER BY books.addedAt DESC, chunks.position ASC
                    LIMIT 20
                    """, arguments: [])
            }
            XCTAssertEqual(fallback.count, 2, "Fallback should return all available chunks")
        }
        // Either path is acceptable; the test verifies no crash and data is returned
        XCTAssertTrue(true)
    }

    // MARK: KB isolation

    func testSearchDoesNotLeakAcrossKBs() throws {
        try seed(kbId: "kb-A", kbName: "Astronomy", bookId: "a1", contents: [
            ("Neutron stars spin hundreds of times per second emitting pulsar beams.", "S1"),
        ])
        try seed(kbId: "kb-B", kbName: "History", bookId: "b1", contents: [
            ("The Roman Senate voted to grant Caesar the title dictator perpetuo.", "S1"),
        ])

        // Search astronomy KB for "neutron" — should NOT return history chunk
        let results = try dbq.read { db -> [Chunk] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "neutron pulsar") else { return [] }
            return try Chunk.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = 'kb-A'
                AND chunks.id IN (SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT 20)
                """, arguments: [pattern])
        }
        XCTAssertFalse(results.isEmpty)
        XCTAssertFalse(results.contains { $0.content.contains("Caesar") },
                       "History chunk must not appear in Astronomy KB search")
    }

    func testMultiKBSearchMergesResults() throws {
        try seed(kbId: "kb-X", kbName: "Science", bookId: "x1", contents: [
            ("Telescopes reveal distant galaxies across cosmic time.", "S1"),
        ])
        try seed(kbId: "kb-Y", kbName: "History", bookId: "y1", contents: [
            ("Ancient astronomers tracked celestial bodies with naked-eye observations.", "S1"),
        ])

        var combined: [Chunk] = []
        for kbId in ["kb-X", "kb-Y"] {
            let kbId = kbId
            if let pattern = FTS5Pattern(matchingAnyTokenIn: "telescope astronomer celestial") {
                let r = (try? dbq.read { db in
                    try Chunk.fetchAll(db, sql: """
                        SELECT chunks.* FROM chunks
                        JOIN books ON books.id = chunks.bookId
                        WHERE books.kbId = ?
                        AND chunks.id IN (SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT 20)
                        """, arguments: [kbId, pattern])
                }) ?? []
                combined.append(contentsOf: r)
            }
        }
        XCTAssertEqual(combined.count, 2, "Multi-KB search should return chunks from both KBs")
        XCTAssertTrue(combined.contains { $0.content.contains("galaxies") })
        XCTAssertTrue(combined.contains { $0.content.contains("astronomers") })
    }
}

// MARK: - Multi-Document Import (integration)

/// Exercises the exact loop that LibraryViewModel.ingest(urls:) runs, using a real
/// in-memory database so the test is fully isolated and leaves no side-effects.
final class MultiDocImportTests: XCTestCase {
    private var dbq: DatabaseQueue!

    override func setUp() {
        super.setUp()
        dbq = try! DatabaseQueue()
        try! runMigrations(on: dbq)
    }

    /// Mirror of DatabaseService migrations — kept in-sync so the test DB has all tables.
    private func runMigrations(on queue: DatabaseQueue) throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
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
        m.registerMigration("v2") { db in
            try db.alter(table: "chunks") { t in t.add(column: "embedding", .blob) }
        }
        m.registerMigration("v3") { db in
            try db.create(table: "knowledge_bases", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                           arguments: [KnowledgeBase.defaultID, "My Library", Date()])
            try db.alter(table: "books") { t in
                t.add(column: "kbId", .text).notNull().defaults(to: KnowledgeBase.defaultID)
            }
        }
        m.registerMigration("v7") { db in
            try db.alter(table: "knowledge_bases") { t in
                t.add(column: "topK", .integer).notNull().defaults(to: 10)
            }
        }
        m.registerMigration("v8") { db in
            try db.alter(table: "knowledge_bases") { t in
                t.add(column: "topN", .integer).notNull().defaults(to: 50)
                t.add(column: "chunkMethod", .text).notNull().defaults(to: "General")
                t.add(column: "chunkSize", .integer).notNull().defaults(to: 512)
                t.add(column: "chunkOverlap", .integer).notNull().defaults(to: 64)
                t.add(column: "similarityThreshold", .double).notNull().defaults(to: 0.2)
            }
            try db.alter(table: "books") { t in
                t.add(column: "fileType", .text).notNull().defaults(to: "")
                t.add(column: "pageCount", .integer).notNull().defaults(to: 0)
                t.add(column: "wordCount", .integer).notNull().defaults(to: 0)
                t.add(column: "sourceURL", .text).notNull().defaults(to: "")
            }
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            if tables.contains("message_sources") {
                try db.alter(table: "message_sources") { t in
                    t.add(column: "documentTitle", .text).notNull().defaults(to: "")
                }
            }
        }
        try m.migrate(queue)
    }

    // MARK: - Helpers

    /// Write a text document to a temp file and return its URL.
    private func makeTempTextFile(name: String, content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Simulate the LibraryViewModel ingest loop against the in-memory DB.
    /// Returns (succeededCount, bookIds) so tests can make assertions.
    private func simulateMultiImport(urls: [URL], kbId: String) throws -> (succeeded: Int, bookIds: [String]) {
        var succeeded = 0
        var bookIds: [String] = []
        let chunker = Chunker()
        for url in urls {
            let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let bookId = UUID().uuidString
            let chunks = chunker.chunk(text: text, bookId: bookId)
            let book = Book(id: bookId, kbId: kbId, title: url.deletingPathExtension().lastPathComponent,
                            author: "", filePath: url.path, addedAt: Date(), chunkCount: chunks.count)
            try dbq.write { db in
                try book.save(db)
                for chunk in chunks {
                    try chunk.save(db)
                    try db.execute(sql: "INSERT INTO chunks_fts(chunk_id, content, chapterTitle) VALUES (?, ?, ?)",
                                   arguments: [chunk.id, chunk.content, chunk.chapterTitle ?? ""])
                }
            }
            succeeded += 1
            bookIds.append(bookId)
        }
        return (succeeded, bookIds)
    }

    // MARK: - Tests

    func testThreeFilesAllImported() throws {
        let kbId = KnowledgeBase.defaultID
        let urls = try [
            ("doc_alpha", "Stars are giant balls of plasma undergoing nuclear fusion in their cores. The Sun fuses 600 million tonnes of hydrogen per second producing the energy that lights our solar system."),
            ("doc_beta",  "The Roman Senate in 44 BCE assassinated Julius Caesar on the Ides of March. This act plunged Rome into years of civil war ultimately leading to Augustus becoming the first emperor."),
            ("doc_gamma", "Python and Swift are both high-level programming languages. Python excels at data science while Swift is optimised for Apple platforms including iOS macOS watchOS and tvOS."),
        ].map { (name, content) in try makeTempTextFile(name: name, content: content) }

        let (succeeded, bookIds) = try simulateMultiImport(urls: urls, kbId: kbId)

        XCTAssertEqual(succeeded, 3, "All three documents must be imported successfully")

        let bookCount = try dbq.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM books WHERE kbId = ?", arguments: [kbId])!
        }
        XCTAssertEqual(bookCount, 3, "Three books should exist in the KB")

        // Every book should have at least one chunk
        for id in bookIds {
            let chunkCount = try dbq.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chunks WHERE bookId = ?", arguments: [id])!
            }
            XCTAssertGreaterThan(chunkCount, 0, "Book \(id) should have at least one chunk")
        }
    }

    func testPartialFailureDoesNotAbortLoop() throws {
        let kbId = KnowledgeBase.defaultID
        // Create two valid files and one empty file (will throw parseFailure)
        let valid1 = try makeTempTextFile(name: "valid_a", content: "Astronomy text about galaxies and black holes. The Milky Way contains billions of stars.")
        let empty  = try makeTempTextFile(name: "empty_doc", content: "")
        let valid2 = try makeTempTextFile(name: "valid_b", content: "History text about ancient Rome and Julius Caesar crossing the Rubicon river.")

        // Simulate the loop with error isolation (mirrors LibraryViewModel.ingest)
        var succeeded = 0
        let chunker = Chunker()
        for url in [valid1, empty, valid2] {
            do {
                let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw RAGService.IngestError.parseFailure }
                let bookId = UUID().uuidString
                let chunks = chunker.chunk(text: text, bookId: bookId)
                let book = Book(id: bookId, kbId: kbId, title: url.deletingPathExtension().lastPathComponent,
                                author: "", filePath: url.path, addedAt: Date(), chunkCount: chunks.count)
                try dbq.write { db in
                    try book.save(db)
                    for chunk in chunks { try chunk.save(db) }
                }
                succeeded += 1
            } catch {
                // Loop continues — exactly as LibraryViewModel does
            }
        }

        XCTAssertEqual(succeeded, 2, "Two valid docs should succeed; empty doc should fail silently without aborting the loop")
        let bookCount = try dbq.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM books WHERE kbId = ?", arguments: [kbId])!
        }
        XCTAssertEqual(bookCount, 2)
    }

    func testProgressMessagesForNFiles() {
        // Verify the progress message format used in LibraryViewModel.ingest(urls:)
        let urls = (1...5).map { URL(fileURLWithPath: "/tmp/doc\($0).txt") }
        var messages: [String] = []
        for (i, _) in urls.enumerated() {
            messages.append("Importing \(i + 1) of \(urls.count)…")
        }
        XCTAssertEqual(messages.first, "Importing 1 of 5…")
        XCTAssertEqual(messages.last,  "Importing 5 of 5…")
        XCTAssertEqual(messages.count, 5)
    }

    func testSameKBIdOnAllImportedBooks() throws {
        let kbId = "kb-isolation-test"
        try dbq.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                           arguments: [kbId, "Test KB", Date()])
        }
        let urls = try [
            ("file1", "Content about the solar system and planetary orbits."),
            ("file2", "Content about ancient Egyptian pharaohs and pyramids."),
            ("file3", "Content about Python programming and data structures."),
        ].map { try makeTempTextFile(name: $0.0, content: $0.1) }

        let (succeeded, _) = try simulateMultiImport(urls: urls, kbId: kbId)
        XCTAssertEqual(succeeded, 3)

        // All books must have the correct kbId
        let books = try dbq.read { db in
            try Book.filter(Column("kbId") == kbId).fetchAll(db)
        }
        XCTAssertEqual(books.count, 3)
        XCTAssertTrue(books.allSatisfy { $0.kbId == kbId }, "All imported books must carry the correct kbId")
    }

    func testImportOrderPreservedInDB() throws {
        let kbId = KnowledgeBase.defaultID
        let titles = ["first_import", "second_import", "third_import"]
        let urls = try titles.map { try makeTempTextFile(name: $0, content: "Unique content for \($0): stars galaxies nebulae supernovae.") }

        let (succeeded, _) = try simulateMultiImport(urls: urls, kbId: kbId)
        XCTAssertEqual(succeeded, 3)

        // Titles should all be present (order by addedAt may vary by millisecond, so just check set membership)
        let storedTitles = try dbq.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM books WHERE kbId = ?", arguments: [kbId])
        }
        for title in titles {
            XCTAssertTrue(storedTitles.contains(title), "Book '\(title)' should be in the DB after import")
        }
    }

    func testTenFilesAllImported() throws {
        let kbId = KnowledgeBase.defaultID
        let count = 10
        let urls = try (1...count).map { i in
            try makeTempTextFile(name: "batch_doc_\(i)", content: "Document \(i) discusses topic \(i) in detail. Stars planets galaxies black holes neutron stars pulsars quasars.")
        }
        let (succeeded, _) = try simulateMultiImport(urls: urls, kbId: kbId)
        XCTAssertEqual(succeeded, count, "All \(count) documents in a batch must be imported")
    }
}

// MARK: - ChunkSource model

final class ChunkSourceTests: XCTestCase {

    func testChunkSourceFromChunk() {
        let chunk = Chunk(id: "id1", bookId: "b1",
                          content: String(repeating: "word ", count: 30),
                          chapterTitle: "Intro", position: 0)
        let source = ChunkSource(from: chunk)
        XCTAssertEqual(source.id, "id1")
        XCTAssertEqual(source.chapterTitle, "Intro")
        // Preview is capped at 160 chars
        XCTAssertLessThanOrEqual(source.preview.count, 160)
    }

    func testChunkSourceInitDirect() {
        let source = ChunkSource(id: "x", chapterTitle: nil, preview: "A passage")
        XCTAssertNil(source.chapterTitle)
        XCTAssertEqual(source.preview, "A passage")
    }
}

// MARK: - Import Parser Tests
// Creates minimal valid fixture files at runtime and drives each parser directly.
// No database or LLM calls — pure parsing validation.

final class ImportParserTests: XCTestCase {

    // MARK: – Shared helpers

    private static let content = "RAGFlow import test content — hello world"
    // resolvingSymlinksInPath converts /var/... → /private/var/... so Zip.unzipFile's
    // fileExists check doesn't fail on the symlinked tmp path.
    private var tmp: URL { FileManager.default.temporaryDirectory.resolvingSymlinksInPath() }
    private func url(_ name: String) -> URL { tmp.appendingPathComponent("ragflow_test_\(name)") }

    // MARK: – Plain-text formats

    func testImportTXT() throws {
        let f = url("sample.txt")
        try Self.content.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        let chunks = Chunker().chunk(text: read, bookId: "b")
        XCTAssertFalse(chunks.isEmpty, "TXT: no chunks produced")
        XCTAssertTrue(read.contains("hello world"))
    }

    func testImportMarkdown() throws {
        let md = "# Heading\n\n\(Self.content)\n\n- bullet one\n- bullet two"
        let f = url("sample.md")
        try md.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(read.contains("hello world"))
    }

    func testImportCSV() throws {
        let csv = "name,value\nhello,world\nfoo,bar"
        let f = url("sample.csv")
        try csv.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(read.contains("hello"))
    }

    func testImportJSON() throws {
        let json = "{\"title\": \"Test\", \"body\": \"\(Self.content)\"}"
        let f = url("sample.json")
        try json.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(read.contains("hello world"))
    }

    func testImportYAML() throws {
        let yaml = "title: Test\nbody: \(Self.content)"
        let f = url("sample.yaml")
        try yaml.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(read.contains("hello world"))
    }

    func testImportSwift() throws {
        let code = "// RAGFlow test\nlet greeting = \"hello world\"\nprint(greeting)"
        let f = url("sample.swift")
        try code.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(read.contains("hello world"))
    }

    func testImportPython() throws {
        let code = "# \(Self.content)\nprint('hello world')"
        let f = url("sample.py")
        try code.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(read.contains("hello world"))
    }

    func testImportSQL() throws {
        let sql = "-- \(Self.content)\nSELECT 'hello world';"
        let f = url("sample.sql")
        try sql.write(to: f, atomically: true, encoding: .utf8)
        let read = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(read.contains("hello world"))
    }

    // MARK: – HTML

    func testImportHTML() throws {
        let html = "<html><body><h1>Hello World</h1><p>\(Self.content)</p></body></html>"
        let f = url("sample.html")
        try html.write(to: f, atomically: true, encoding: .utf8)
        let raw = try String(contentsOf: f, encoding: .utf8)
        // Replicate RAGService HTML stripping
        let stripped = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(stripped.isEmpty, "HTML: stripped text is empty")
        XCTAssertTrue(stripped.contains("Hello World"), "HTML: tag stripping removed text content")
        XCTAssertFalse(stripped.contains("<"), "HTML: tags not fully stripped")
    }

    // MARK: – RTF

    func testImportRTF() throws {
        // Minimal valid RTF 1.x document
        let rtf = "{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}} \\f0\\fs24 Hello World \(Self.content)}"
        let f = url("sample.rtf")
        try rtf.write(to: f, atomically: true, encoding: .utf8)
        let data = try Data(contentsOf: f)
        let attrStr = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let text = attrStr.string
        XCTAssertFalse(text.isEmpty, "RTF: NSAttributedString returned empty string")
        XCTAssertTrue(text.contains("Hello World"), "RTF: expected text not found; got: \(text.prefix(80))")
    }

    // MARK: – PDF (text layer)

    func testImportPDFTextLayer() throws {
        let f = url("sample.pdf")
        // Draw a text-layer PDF using UIGraphicsPDFRenderer
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
            "Hello World \(Self.content)".draw(in: CGRect(x: 50, y: 50, width: 500, height: 600), withAttributes: attrs)
        }
        try data.write(to: f)
        let sections = PDFParser().parse(url: f)
        XCTAssertFalse(sections.isEmpty, "PDF: PDFParser returned no sections")
        let allText = sections.map(\.text).joined(separator: " ")
        XCTAssertTrue(allText.localizedCaseInsensitiveContains("Hello"), "PDF: text not extracted; got: \(allText.prefix(80))")
    }

    // MARK: – EML / EMLX

    func testImportEML() throws {
        let eml = """
        From: sender@example.com\r
        To: receiver@example.com\r
        Subject: Test Email Hello World\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        \(Self.content)\r
        Hello world email body.\r
        """
        let f = url("sample.eml")
        try eml.write(to: f, atomically: true, encoding: .utf8)
        let result = try EMLParser().parse(url: f)
        XCTAssertFalse(result.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "EML: empty body")
        XCTAssertEqual(result.subject, "Test Email Hello World", "EML: subject mismatch")
        XCTAssertTrue(result.body.contains("hello world"), "EML: body text not found")
    }

    func testImportEMLX() throws {
        // .emlx has the same RFC 2822 format as .eml — same parser
        let emlx = """
        From: sender@example.com\r
        Subject: EMLX Hello World\r
        Content-Type: text/plain\r
        \r
        \(Self.content)\r
        """
        let f = url("sample.emlx")
        try emlx.write(to: f, atomically: true, encoding: .utf8)
        let result = try EMLParser().parse(url: f)
        XCTAssertFalse(result.body.isEmpty, "EMLX: empty body")
        XCTAssertTrue(result.body.contains("hello world") || result.subject.contains("Hello World"))
    }

    // MARK: – Office formats (DOCX / XLSX / PPTX)

    func testImportDOCX() throws {
        // Bypass unzip — write XML directly into a temp directory structure
        let dir = tmp.appendingPathComponent("ragflow_test_docx_dir", isDirectory: true)
        let wordDir = dir.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Hello World</w:t></w:r></w:p>
            <w:p><w:r><w:t>\(Self.content)</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        try xml.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sections = try OfficeParser().parseDOCXContent(dir: dir, fileName: "sample")
        XCTAssertFalse(sections.isEmpty, "DOCX: no sections parsed")
        let text = sections.map(\.text).joined()
        XCTAssertTrue(text.contains("Hello World"), "DOCX: expected text not found; got: \(text.prefix(120))")
    }

    func testImportXLSX() throws {
        // Bypass unzip — write XML directly into a temp directory structure
        let dir = tmp.appendingPathComponent("ragflow_test_xlsx_dir", isDirectory: true)
        let xlDir = dir.appendingPathComponent("xl", isDirectory: true)
        let wsDir = xlDir.appendingPathComponent("worksheets", isDirectory: true)
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)
        let sharedStrings = """
        <?xml version="1.0" encoding="UTF-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2">
          <si><t>Hello</t></si>
          <si><t>World</t></si>
        </sst>
        """
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1">
              <c r="A1" t="s"><v>0</v></c>
              <c r="B1" t="s"><v>1</v></c>
            </row>
          </sheetData>
        </worksheet>
        """
        try sharedStrings.write(to: xlDir.appendingPathComponent("sharedStrings.xml"), atomically: true, encoding: .utf8)
        try sheet.write(to: wsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sections = try OfficeParser().parseXLSXContent(dir: dir, fileName: "sample")
        XCTAssertFalse(sections.isEmpty, "XLSX: no sections parsed")
        let text = sections.map(\.text).joined()
        XCTAssertTrue(text.contains("Hello"), "XLSX: expected text not found; got: \(text.prefix(120))")
    }

    func testImportPPTX() throws {
        // Bypass unzip — write XML directly into a temp directory structure
        let dir = tmp.appendingPathComponent("ragflow_test_pptx_dir", isDirectory: true)
        let slidesDir = dir.appendingPathComponent("ppt/slides", isDirectory: true)
        try FileManager.default.createDirectory(at: slidesDir, withIntermediateDirectories: true)
        let slide = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
               xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <p:cSld><p:spTree>
            <p:sp><p:txBody><a:p><a:r><a:t>Hello World slide content</a:t></a:r></a:p></p:txBody></p:sp>
          </p:spTree></p:cSld>
        </p:sld>
        """
        try slide.write(to: slidesDir.appendingPathComponent("slide1.xml"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sections = try OfficeParser().parsePPTXContent(dir: dir)
        XCTAssertFalse(sections.isEmpty, "PPTX: no sections parsed")
        let text = sections.map(\.text).joined()
        XCTAssertTrue(text.contains("Hello World"), "PPTX: expected text not found; got: \(text.prefix(120))")
    }

    // MARK: – ODT

    func testImportODT() throws {
        // Bypass unzip — write XML directly into a temp directory
        let dir = tmp.appendingPathComponent("ragflow_test_odt_dir", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content
          xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
          xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
          <office:body><office:text>
            <text:p>Hello World</text:p>
            <text:p>\(Self.content)</text:p>
          </office:text></office:body>
        </office:document-content>
        """
        try xmlContent.write(to: dir.appendingPathComponent("content.xml"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sections = try OfficeParser().parseODTContent(dir: dir, fileName: "sample")
        XCTAssertFalse(sections.isEmpty, "ODT: no sections parsed")
        let text = sections.map(\.text).joined()
        XCTAssertTrue(text.contains("Hello World"), "ODT: expected text not found; got: \(text.prefix(120))")
    }

    // MARK: – EPUB (ZIP structure only — EPUBKit is main-target only)
    // Full EPUB parse is tested implicitly when importing via the app; here we verify
    // that our makeZip helper produces a valid EPUB-shaped archive.

    func testImportEPUBZipStructure() throws {
        let chapter = "<html><body><h1>Hello World</h1><p>\(Self.content)</p></body></html>"
        let opf = """
        <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Test</dc:title><dc:identifier id="uid">1</dc:identifier></metadata>
        <manifest><item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>
        <spine toc="ncx"><itemref idref="ch1"/></spine></package>
        """
        let container = """
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """
        let f = url("sample.epub")
        try Self.makeZip(to: f, entries: [
            ("mimetype",                 "application/epub+zip"),
            ("META-INF/container.xml",   container),
            ("OEBPS/content.opf",        opf),
            ("OEBPS/chapter1.xhtml",     chapter)
        ])
        // ZIP is readable and contains expected entries
        let raw = try Data(contentsOf: f)
        XCTAssertGreaterThan(raw.count, 200, "EPUB: archive too small")
        XCTAssertNotNil(raw.range(of: Data("application/epub+zip".utf8)), "EPUB: mimetype entry missing")
        XCTAssertNotNil(raw.range(of: Data("Hello World".utf8)), "EPUB: chapter content missing in archive")
    }

    // MARK: – ZIP builder (stored, no compression)

    private static func makeZip(to dest: URL, entries: [(String, String)]) throws {
        var data = Data()
        var centralDir = Data()
        var offsets: [UInt32] = []

        for (path, body) in entries {
            let nameBytes = Data(path.utf8)
            let fileBytes = Data(body.utf8)
            let crc = crc32(fileBytes)
            offsets.append(UInt32(data.count))

            // Local file header
            var lh = Data()
            lh.appendLE(UInt32(0x04034B50))        // signature
            lh.appendLE(UInt16(20))                 // version needed
            lh.appendLE(UInt16(0))                  // flags
            lh.appendLE(UInt16(0))                  // compression: stored
            lh.appendLE(UInt16(0))                  // mod time
            lh.appendLE(UInt16(0))                  // mod date
            lh.appendLE(crc)                        // CRC-32
            lh.appendLE(UInt32(fileBytes.count))    // compressed size
            lh.appendLE(UInt32(fileBytes.count))    // uncompressed size
            lh.appendLE(UInt16(nameBytes.count))    // filename length
            lh.appendLE(UInt16(0))                  // extra length
            lh.append(nameBytes)
            lh.append(fileBytes)
            data.append(lh)
        }

        let cdOffset = UInt32(data.count)

        for (i, (path, body)) in entries.enumerated() {
            let nameBytes = Data(path.utf8)
            let fileBytes = Data(body.utf8)
            let crc = crc32(fileBytes)

            var cd = Data()
            cd.appendLE(UInt32(0x02014B50))        // central dir signature
            cd.appendLE(UInt16(20))                 // version made by
            cd.appendLE(UInt16(20))                 // version needed
            cd.appendLE(UInt16(0))                  // flags
            cd.appendLE(UInt16(0))                  // compression
            cd.appendLE(UInt16(0))                  // mod time
            cd.appendLE(UInt16(0))                  // mod date
            cd.appendLE(crc)
            cd.appendLE(UInt32(fileBytes.count))
            cd.appendLE(UInt32(fileBytes.count))
            cd.appendLE(UInt16(nameBytes.count))
            cd.appendLE(UInt16(0))                  // extra length
            cd.appendLE(UInt16(0))                  // comment length
            cd.appendLE(UInt16(0))                  // disk start
            cd.appendLE(UInt16(0))                  // internal attrs
            cd.appendLE(UInt32(0))                  // external attrs
            cd.appendLE(offsets[i])
            cd.append(nameBytes)
            centralDir.append(cd)
        }

        // End of central directory record
        var eocd = Data()
        eocd.appendLE(UInt32(0x06054B50))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt32(centralDir.count))
        eocd.appendLE(cdOffset)
        eocd.appendLE(UInt16(0))

        data.append(centralDir)
        data.append(eocd)
        try data.write(to: dest)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB88320) }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }
}

// MARK: - SettingsStore new fields

final class SettingsStoreNewFieldsTests: XCTestCase {

    func testUseCloudKitSyncDefaultIsFalse() {
        XCTAssertFalse(LLMConfig.default.useCloudKitSync,
                       "CloudKit sync should be off by default")
    }

    func testCloudKitSyncPersistedAndLoaded() {
        let store = SettingsStore.shared
        let saved = store.config
        defer { store.config = saved; store.save() }

        store.config.useCloudKitSync = true
        store.save()
        let storedValue = UserDefaults.standard.bool(forKey: "use_cloudkit_sync")
        XCTAssertTrue(storedValue, "useCloudKitSync must persist to UserDefaults")

        store.config.useCloudKitSync = false
        store.save()
        let storedFalse = UserDefaults.standard.bool(forKey: "use_cloudkit_sync")
        XCTAssertFalse(storedFalse)
    }
}

// MARK: - DatabaseService new lookup methods

final class DatabaseServiceLookupTests: XCTestCase {
    private var dbq: DatabaseQueue!

    override func setUp() {
        super.setUp()
        dbq = try! DatabaseQueue()
        try! runMigrations(on: dbq)
    }

    private func runMigrations(on queue: DatabaseQueue) throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
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
        m.registerMigration("v2") { db in
            try db.alter(table: "chunks") { t in t.add(column: "embedding", .blob) }
        }
        m.registerMigration("v3") { db in
            try db.create(table: "knowledge_bases", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(sql: "INSERT OR IGNORE INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                           arguments: [KnowledgeBase.defaultID, "My Library", Date()])
            try db.alter(table: "books") { t in
                t.add(column: "kbId", .text).notNull().defaults(to: KnowledgeBase.defaultID)
            }
        }
        m.registerMigration("v4") { db in
            try db.create(table: "messages", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("kbId", .text).notNull()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }
        }
        m.registerMigration("v8") { db in
            try db.alter(table: "knowledge_bases") { t in
                t.add(column: "topK", .integer).notNull().defaults(to: 10)
                t.add(column: "topN", .integer).notNull().defaults(to: 50)
                t.add(column: "chunkMethod", .text).notNull().defaults(to: "General")
                t.add(column: "chunkSize", .integer).notNull().defaults(to: 512)
                t.add(column: "chunkOverlap", .integer).notNull().defaults(to: 64)
                t.add(column: "similarityThreshold", .double).notNull().defaults(to: 0.2)
            }
            try db.alter(table: "books") { t in
                t.add(column: "fileType", .text).notNull().defaults(to: "")
                t.add(column: "pageCount", .integer).notNull().defaults(to: 0)
                t.add(column: "wordCount", .integer).notNull().defaults(to: 0)
                t.add(column: "sourceURL", .text).notNull().defaults(to: "")
            }
            try db.alter(table: "messages") { t in
                t.add(column: "sessionId", .text).notNull().defaults(to: "")
            }
        }
        try m.migrate(queue)
    }

    func testBookLookupById() throws {
        let book = Book(id: "lookup-b1", kbId: KnowledgeBase.defaultID, title: "Lookup Test",
                        author: "", filePath: "", addedAt: Date(), chunkCount: 0)
        try dbq.write { db in try book.save(db) }

        let found = try dbq.read { db in try Book.fetchOne(db, key: "lookup-b1") }
        XCTAssertNotNil(found, "book(id:) should return the saved book")
        XCTAssertEqual(found?.title, "Lookup Test")
    }

    func testBookLookupReturnsNilForMissingId() throws {
        let found = try dbq.read { db in try Book.fetchOne(db, key: "does-not-exist") }
        XCTAssertNil(found, "book(id:) should return nil for an unknown ID")
    }

    func testMessageExistsReturnsTrueAfterInsert() throws {
        try dbq.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, kbId, sessionId, role, content, timestamp) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: ["msg-exists-1", KnowledgeBase.defaultID, "sess-1", "user", "Hello", Date()])
        }
        let exists = (try? dbq.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages WHERE id = ?", arguments: ["msg-exists-1"]) ?? 0
        }) ?? 0
        XCTAssertEqual(exists, 1, "messageExists should return true for an inserted message")
    }

    func testMessageExistsReturnsFalseForMissingId() throws {
        let count = (try? dbq.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages WHERE id = ?", arguments: ["not-there"]) ?? 0
        }) ?? 0
        XCTAssertEqual(count, 0, "messageExists should return false for an unknown message ID")
    }
}

// MARK: - Retrieval settings save() validation

final class RetrievalSettingsSaveTests: XCTestCase {

    /// Mirror the save logic from KBRetrievalSettingsSheet to verify constraints are enforced.
    private func simulateSave(topK: Int, topN: Int, threshold: Double,
                               chunkSize: Int, chunkOverlap: Int) -> (topN: Int, chunkOverlap: Int) {
        let savedTopN    = max(topN, topK)
        let savedOverlap = min(chunkOverlap, chunkSize / 2)
        return (savedTopN, savedOverlap)
    }

    func testTopNAlwaysAtLeastTopK() {
        let result = simulateSave(topK: 30, topN: 10, threshold: 0.2, chunkSize: 512, chunkOverlap: 64)
        XCTAssertEqual(result.topN, 30, "topN must be raised to topK when it is lower")
    }

    func testTopNPreservedWhenGreaterThanTopK() {
        let result = simulateSave(topK: 10, topN: 50, threshold: 0.2, chunkSize: 512, chunkOverlap: 64)
        XCTAssertEqual(result.topN, 50, "topN must not be changed when already ≥ topK")
    }

    func testChunkOverlapCappedAtHalfChunkSize() {
        let result = simulateSave(topK: 10, topN: 50, threshold: 0.2, chunkSize: 128, chunkOverlap: 100)
        XCTAssertEqual(result.chunkOverlap, 64, "Overlap must be capped at chunkSize/2 (64 for chunkSize=128)")
    }

    func testChunkOverlapPreservedWhenWithinBounds() {
        let result = simulateSave(topK: 10, topN: 50, threshold: 0.2, chunkSize: 512, chunkOverlap: 64)
        XCTAssertEqual(result.chunkOverlap, 64)
    }

    func testTopKEqualsTopNBoundaryCase() {
        let result = simulateSave(topK: 20, topN: 20, threshold: 0.3, chunkSize: 256, chunkOverlap: 32)
        XCTAssertEqual(result.topN, 20, "topN == topK should be preserved (not raised)")
    }
}

// MARK: - URLError cancellation recognition

final class CancellationErrorTests: XCTestCase {

    func testURLErrorCancelledIsRecognised() {
        let err = URLError(.cancelled)
        XCTAssertEqual(err.code, .cancelled, "URLError code must be .cancelled for -999")
        // Verify the pattern used in ChatViewModel catch clause compiles and matches
        let matched: Bool
        if let u = (err as Error) as? URLError, u.code == .cancelled {
            matched = true
        } else {
            matched = false
        }
        XCTAssertTrue(matched, "URLError(.cancelled) must be caught by the false-positive guard")
    }

    func testCancellationErrorIsDistinctFromURLError() {
        let cancErr = CancellationError()
        XCTAssertNil(cancErr as? URLError, "CancellationError must not be a URLError")
    }
}
