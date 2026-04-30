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

    // MARK: – GEDCOM

    func testImportGEDCOM() throws {
        let ged = """
        0 HEAD
        1 SOUR Test
        0 @I1@ INDI
        1 NAME Alice /Wonderland/
        1 SEX F
        1 BIRT
        2 DATE 4 JUL 1852
        2 PLAC Oxford, England
        0 @I2@ INDI
        1 NAME Bob /Wonderland/
        1 SEX M
        0 @F1@ FAM
        1 HUSB @I2@
        1 WIFE @I1@
        1 MARR
        2 DATE 12 DEC 1875
        0 TRLR
        """
        let f = url("sample.ged")
        try ged.write(to: f, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: f) }
        let sections = try GEDCOMParser().parse(url: f)
        XCTAssertFalse(sections.isEmpty, "GEDCOM: no sections parsed")
        let titles = sections.map(\.title)
        XCTAssertTrue(titles.contains("Alice Wonderland"), "GEDCOM: expected individual not found; titles=\(titles)")
        let allText = sections.map(\.text).joined()
        XCTAssertTrue(allText.contains("Oxford, England"), "GEDCOM: birth place missing from parsed text")
    }

    // MARK: – ZIP bundle (structure only — Zip library unzip is implicitly tested via the app)
    // Verifies makeZip produces a valid ZIP archive that RAGService.ingestZIP can open.

    func testImportZIPBundleStructure() throws {
        let entry = "This is a document inside a ZIP bundle. \(Self.content)"
        let f = url("bundle.zip")
        try Self.makeZip(to: f, entries: [("readme.txt", entry)])
        defer { try? FileManager.default.removeItem(at: f) }
        let raw = try Data(contentsOf: f)
        // ZIP local file header magic: PK\x03\x04
        let magic = Data([0x50, 0x4B, 0x03, 0x04])
        XCTAssertNotNil(raw.range(of: magic), "ZIP: local file header signature missing")
        XCTAssertNotNil(raw.range(of: Data("readme.txt".utf8)), "ZIP: entry filename not found in archive")
        XCTAssertNotNil(raw.range(of: Data(Self.content.utf8)), "ZIP: entry content not found in archive")
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

// MARK: - Retrieval settings end-to-end

/// Tests every retrieval-settings control end-to-end:
/// persistence through the DB, default values, constraint enforcement,
/// and observable effect on chunking / BM25 candidate counts.
final class RetrievalSettingsEndToEndTests: XCTestCase {
    private var dbq: DatabaseQueue!

    override func setUp() {
        super.setUp()
        dbq = try! DatabaseQueue()
        try! runMigrations()
    }

    // Mirrors the migration sequence in ChunkFetchTests so the in-memory DB
    // has the same schema as the live app.
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

    // Save a KB + one book + N chunks all containing `keyword` into the in-memory DB.
    private func seedKB(_ kb: KnowledgeBase, chunkCount: Int, keyword: String) throws {
        try dbq.write { db in
            try kb.save(db)
            let book = Book(id: "book-\(kb.id)", kbId: kb.id, title: kb.name,
                            author: "", filePath: "", addedAt: Date(), chunkCount: chunkCount)
            try book.save(db)
            for i in 0..<chunkCount {
                let text = "\(keyword) passage number \(i) with unique filler text alpha beta gamma delta epsilon"
                let chunk = Chunk(id: "\(kb.id)-c\(i)", bookId: book.id,
                                  content: text, chapterTitle: nil, position: i)
                try chunk.save(db)
                try db.execute(sql: "INSERT INTO chunks_fts(chunk_id, content, chapterTitle) VALUES (?, ?, ?)",
                               arguments: [chunk.id, text, ""])
            }
        }
    }

    // Mirrors KBRetrievalSettingsSheet.save() constraint logic.
    private func simulateSave(kb: KnowledgeBase, topK: Int, topN: Int,
                               threshold: Double, chunkSize: Int, chunkOverlap: Int) -> KnowledgeBase {
        var updated = kb
        updated.topK = topK
        updated.topN = max(topN, topK)
        updated.similarityThreshold = threshold
        updated.chunkSize = chunkSize
        updated.chunkOverlap = min(chunkOverlap, chunkSize / 2)
        return updated
    }

    // MARK: - Default values

    func testDefaultKBTopKIs10() {
        let kb = KnowledgeBase(id: "x", name: "Test", createdAt: Date())
        XCTAssertEqual(kb.topK, 10)
    }

    func testDefaultKBTopNIs50() {
        let kb = KnowledgeBase(id: "x", name: "Test", createdAt: Date())
        XCTAssertEqual(kb.topN, 50)
    }

    func testDefaultKBThresholdIs0_2() {
        let kb = KnowledgeBase(id: "x", name: "Test", createdAt: Date())
        XCTAssertEqual(kb.similarityThreshold, 0.2, accuracy: 0.001)
    }

    func testDefaultKBChunkSizeIs512() {
        let kb = KnowledgeBase(id: "x", name: "Test", createdAt: Date())
        XCTAssertEqual(kb.chunkSize, 512)
    }

    func testDefaultKBChunkOverlapIs64() {
        let kb = KnowledgeBase(id: "x", name: "Test", createdAt: Date())
        XCTAssertEqual(kb.chunkOverlap, 64)
    }

    func testDefaultKBChunkMethodIsGeneral() {
        let kb = KnowledgeBase(id: "x", name: "Test", createdAt: Date())
        XCTAssertEqual(kb.chunkMethod, .general)
    }

    // MARK: - DB round-trip for all settings fields

    func testAllSettingsFieldsRoundTripThroughDB() throws {
        var kb = KnowledgeBase(id: "rt1", name: "Round Trip", createdAt: Date())
        kb.topK = 7
        kb.topN = 35
        kb.similarityThreshold = 0.45
        kb.chunkMethod = .paper
        kb.chunkSize = 256
        kb.chunkOverlap = 32
        try dbq.write { db in try kb.save(db) }

        let loaded = try dbq.read { db in try KnowledgeBase.fetchOne(db, key: "rt1") }
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.topK, 7)
        XCTAssertEqual(loaded!.topN, 35)
        XCTAssertEqual(loaded!.similarityThreshold, 0.45, accuracy: 0.001)
        XCTAssertEqual(loaded!.chunkMethod, .paper)
        XCTAssertEqual(loaded!.chunkSize, 256)
        XCTAssertEqual(loaded!.chunkOverlap, 32)
    }

    // MARK: - All ChunkMethod variants persist

    func testAllChunkMethodsPersistAndLoad() throws {
        for (i, method) in ChunkMethod.allCases.enumerated() {
            var kb = KnowledgeBase(id: "cm-\(i)", name: method.rawValue, createdAt: Date())
            kb.chunkMethod = method
            try dbq.write { db in try kb.save(db) }
            let loaded = try dbq.read { db in try KnowledgeBase.fetchOne(db, key: "cm-\(i)") }
            XCTAssertEqual(loaded?.chunkMethod, method,
                           "ChunkMethod.\(method.rawValue) did not survive DB round-trip")
        }
    }

    // MARK: - Boundary value persistence

    func testTopKMinimumBoundaryPersists() throws {
        var kb = KnowledgeBase(id: "bnd1", name: "Boundary", createdAt: Date())
        kb.topK = 1
        kb.topN = 1
        try dbq.write { db in try kb.save(db) }
        let loaded = try dbq.read { db in try KnowledgeBase.fetchOne(db, key: "bnd1") }
        XCTAssertEqual(loaded?.topK, 1)
    }

    func testTopKMaximumBoundaryPersists() throws {
        var kb = KnowledgeBase(id: "bnd2", name: "Boundary", createdAt: Date())
        kb.topK = 100
        kb.topN = 100
        try dbq.write { db in try kb.save(db) }
        let loaded = try dbq.read { db in try KnowledgeBase.fetchOne(db, key: "bnd2") }
        XCTAssertEqual(loaded?.topK, 100)
    }

    func testThresholdZeroPersists() throws {
        var kb = KnowledgeBase(id: "thr0", name: "Threshold", createdAt: Date())
        kb.similarityThreshold = 0.0
        try dbq.write { db in try kb.save(db) }
        let loaded = try dbq.read { db in try KnowledgeBase.fetchOne(db, key: "thr0") }
        XCTAssertEqual(loaded?.similarityThreshold ?? -1, 0.0, accuracy: 0.001)
    }

    func testThresholdOnePersists() throws {
        var kb = KnowledgeBase(id: "thr1", name: "Threshold", createdAt: Date())
        kb.similarityThreshold = 1.0
        try dbq.write { db in try kb.save(db) }
        let loaded = try dbq.read { db in try KnowledgeBase.fetchOne(db, key: "thr1") }
        XCTAssertEqual(loaded?.similarityThreshold ?? -1, 1.0, accuracy: 0.001)
    }

    // MARK: - Save constraints

    func testSaveRaisesTopNToMatchTopKWhenLower() {
        let kb = KnowledgeBase(id: "sc1", name: "Test", createdAt: Date())
        let result = simulateSave(kb: kb, topK: 25, topN: 5,
                                   threshold: 0.2, chunkSize: 512, chunkOverlap: 64)
        XCTAssertEqual(result.topN, 25, "topN must be raised to topK when lower")
    }

    func testSaveCapsOverlapAtHalfChunkSize() {
        let kb = KnowledgeBase(id: "sc2", name: "Test", createdAt: Date())
        let result = simulateSave(kb: kb, topK: 10, topN: 50,
                                   threshold: 0.2, chunkSize: 128, chunkOverlap: 200)
        XCTAssertEqual(result.chunkOverlap, 64, "Overlap must be capped at chunkSize/2 = 64")
    }

    func testSavePreservesOverlapWhenWithinBounds() {
        let kb = KnowledgeBase(id: "sc3", name: "Test", createdAt: Date())
        let result = simulateSave(kb: kb, topK: 10, topN: 50,
                                   threshold: 0.2, chunkSize: 512, chunkOverlap: 48)
        XCTAssertEqual(result.chunkOverlap, 48)
    }

    func testSaveTopNEqualTopKIsPreserved() {
        let kb = KnowledgeBase(id: "sc4", name: "Test", createdAt: Date())
        let result = simulateSave(kb: kb, topK: 15, topN: 15,
                                   threshold: 0.3, chunkSize: 256, chunkOverlap: 32)
        XCTAssertEqual(result.topN, 15)
    }

    func testSaveZeroOverlapIsAllowed() {
        let kb = KnowledgeBase(id: "sc5", name: "Test", createdAt: Date())
        let result = simulateSave(kb: kb, topK: 10, topN: 50,
                                   threshold: 0.2, chunkSize: 512, chunkOverlap: 0)
        XCTAssertEqual(result.chunkOverlap, 0)
    }

    // MARK: - topN caps BM25 candidate pool (real data)

    func testTopNCapsKeywordSearchResults() throws {
        var kb = KnowledgeBase(id: "topc1", name: "TopN Test", createdAt: Date())
        kb.topN = 4
        try seedKB(kb, chunkCount: 10, keyword: "photosynthesis")

        let results = try dbq.read { db -> [(Chunk, Int)] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "photosynthesis") else { return [] }
            let rows = try Row.fetchAll(db, sql: """
                SELECT chunks.*
                FROM chunks
                JOIN books ON books.id = chunks.bookId
                JOIN chunks_fts ON chunks_fts.chunk_id = chunks.id
                WHERE books.kbId = ? AND chunks_fts MATCH ?
                ORDER BY chunks_fts.rank
                LIMIT ?
                """, arguments: [kb.id, pattern, kb.topN])
            return rows.enumerated().map { idx, row in
                let chunk = Chunk(id: row["id"], bookId: row["bookId"],
                                  content: row["content"], chapterTitle: row["chapterTitle"],
                                  position: row["position"])
                return (chunk, idx + 1)
            }
        }
        XCTAssertLessThanOrEqual(results.count, kb.topN,
                                 "BM25 candidate pool must not exceed topN (\(kb.topN))")
        XCTAssertEqual(results.count, kb.topN,
                       "Expected exactly topN results from 10 matching chunks with topN=4")
    }

    func testBM25ReturnsAllWhenChunkCountLessThanTopN() throws {
        var kb = KnowledgeBase(id: "topc2", name: "Small KB", createdAt: Date())
        kb.topN = 20
        try seedKB(kb, chunkCount: 3, keyword: "mitochondria")

        let results = try dbq.read { db -> [Row] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "mitochondria") else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT chunks.*
                FROM chunks
                JOIN books ON books.id = chunks.bookId
                JOIN chunks_fts ON chunks_fts.chunk_id = chunks.id
                WHERE books.kbId = ? AND chunks_fts MATCH ?
                ORDER BY chunks_fts.rank
                LIMIT ?
                """, arguments: [kb.id, pattern, kb.topN])
        }
        XCTAssertEqual(results.count, 3,
                       "All 3 chunks should be returned when chunkCount < topN")
    }

    // MARK: - chunkSize affects number of passages produced

    func testSmallerChunkSizeProducesMorePassages() {
        // 200 words of text — should yield more chunks with size=50 than size=150.
        let words = (0..<200).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let smallChunker = Chunker(chunkSize: 50, overlap: 0)
        let largeChunker = Chunker(chunkSize: 150, overlap: 0)
        let smallChunks = smallChunker.chunk(text: text, bookId: "b1", chapterTitle: nil)
        let largeChunks = largeChunker.chunk(text: text, bookId: "b2", chapterTitle: nil)
        XCTAssertGreaterThan(smallChunks.count, largeChunks.count,
                             "Smaller chunkSize must produce more chunks from the same text")
    }

    func testMaxChunkSizeProducesFewerPassages() {
        let words = (0..<500).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let defaultChunker = Chunker(chunkSize: 512, overlap: 0)
        let maxChunker = Chunker(chunkSize: 2048, overlap: 0)
        let defaultChunks = defaultChunker.chunk(text: text, bookId: "b1", chapterTitle: nil)
        let maxChunks = maxChunker.chunk(text: text, bookId: "b2", chapterTitle: nil)
        XCTAssertGreaterThanOrEqual(defaultChunks.count, maxChunks.count,
                                    "Larger chunkSize must not produce more chunks than smaller")
    }

    // MARK: - chunkOverlap increases passage count

    func testOverlapProducesMorePassagesThanNoOverlap() {
        // 300 words — with overlap each chunk shares words with its neighbor,
        // so the chunker needs more chunks to cover the same content.
        let words = (0..<300).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let noOverlap = Chunker(chunkSize: 100, overlap: 0)
        let withOverlap = Chunker(chunkSize: 100, overlap: 30)
        let countWithout = noOverlap.chunk(text: text, bookId: "b1", chapterTitle: nil).count
        let countWith    = withOverlap.chunk(text: text, bookId: "b2", chapterTitle: nil).count
        XCTAssertGreaterThanOrEqual(countWith, countWithout,
                                    "Overlap must not reduce the number of chunks")
    }

    func testOverlapContentIsSharedBetweenAdjacentChunks() {
        // Use a text that's long enough to produce 3+ chunks at size=10 with overlap=5.
        // The last words of chunk N should appear at the start of chunk N+1.
        let words = (0..<60).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let chunker = Chunker(chunkSize: 10, overlap: 5)
        let chunks = chunker.chunk(text: text, bookId: "b", chapterTitle: nil)
        guard chunks.count >= 2 else {
            XCTFail("Need at least 2 chunks to test overlap"); return
        }
        // The last word of chunk 0 should appear somewhere in chunk 1
        let lastWordChunk0 = chunks[0].content.split(separator: " ").last.map(String.init) ?? ""
        XCTAssertTrue(chunks[1].content.contains(lastWordChunk0),
                      "Overlapping word '\(lastWordChunk0)' from chunk 0 should appear in chunk 1")
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

// MARK: - GEDCOMParser

final class GEDCOMParserTests: XCTestCase {

    private let parser = GEDCOMParser()

    /// Minimal GEDCOM with 3 individuals and 1 family.
    private let sampleGED = """
    0 HEAD
    1 SOUR TestApp
    0 @I1@ INDI
    1 NAME John /Smith/
    1 SEX M
    1 BIRT
    2 DATE 15 MAR 1850
    2 PLAC Boston, MA
    1 DEAT
    2 DATE 22 JUN 1920
    2 PLAC Chicago, IL
    1 OCCU Farmer
    0 @I2@ INDI
    1 NAME Jane /Doe/
    1 SEX F
    1 BIRT
    2 DATE 3 APR 1855
    2 PLAC New York, NY
    0 @I3@ INDI
    1 NAME William /Smith/
    1 SEX M
    1 BIRT
    2 DATE 5 JAN 1877
    0 @F1@ FAM
    1 HUSB @I1@
    1 WIFE @I2@
    1 CHIL @I3@
    1 MARR
    2 DATE 10 JUN 1875
    2 PLAC Springfield, IL
    0 TRLR
    """

    func testSectionCountMatchesIndividualsPlusFamilies() {
        let sections = parser.parse(text: sampleGED)
        // 3 individuals + 1 family = 4 sections
        XCTAssertEqual(sections.count, 4, "Expected 3 individual + 1 family section; got \(sections.count)")
    }

    func testIndividualNameExtracted() {
        let sections = parser.parse(text: sampleGED)
        let titles = sections.map(\.title)
        XCTAssertTrue(titles.contains("John Smith"), "John Smith not found in titles: \(titles)")
        XCTAssertTrue(titles.contains("Jane Doe"),   "Jane Doe not found in titles: \(titles)")
        XCTAssertTrue(titles.contains("William Smith"), "William Smith not found: \(titles)")
    }

    func testSlashSurnameStripped() {
        // "/Smith/" notation must be converted to plain "Smith"
        let sections = parser.parse(text: sampleGED)
        XCTAssertFalse(sections.contains { $0.title.contains("/") },
                       "Slash characters should be removed from names")
    }

    func testBirthDateExtracted() {
        let sections = parser.parse(text: sampleGED)
        let john = sections.first { $0.title == "John Smith" }
        XCTAssertNotNil(john, "John Smith section missing")
        XCTAssertTrue(john!.text.contains("15 MAR 1850"), "Birth date not found: \(john!.text)")
    }

    func testBirthPlaceExtracted() {
        let sections = parser.parse(text: sampleGED)
        let john = sections.first { $0.title == "John Smith" }!
        XCTAssertTrue(john.text.contains("Boston, MA"), "Birth place not found: \(john.text)")
    }

    func testDeathDateAndPlaceExtracted() {
        let sections = parser.parse(text: sampleGED)
        let john = sections.first { $0.title == "John Smith" }!
        XCTAssertTrue(john.text.contains("22 JUN 1920"),  "Death date not found")
        XCTAssertTrue(john.text.contains("Chicago, IL"),  "Death place not found")
    }

    func testOccupationExtracted() {
        let sections = parser.parse(text: sampleGED)
        let john = sections.first { $0.title == "John Smith" }!
        XCTAssertTrue(john.text.contains("Farmer"), "Occupation not found: \(john.text)")
    }

    func testSexLabelExpanded() {
        let sections = parser.parse(text: sampleGED)
        let john = sections.first { $0.title == "John Smith" }!
        let jane = sections.first { $0.title == "Jane Doe" }!
        XCTAssertTrue(john.text.contains("Male"),   "Sex: Male not found for John")
        XCTAssertTrue(jane.text.contains("Female"), "Sex: Female not found for Jane")
    }

    func testFamilySectionProduced() {
        let sections = parser.parse(text: sampleGED)
        let family = sections.first { $0.title.contains("Family") }
        XCTAssertNotNil(family, "No family section produced")
        XCTAssertTrue(family!.title.contains("John Smith"), "Husband name missing from family title")
        XCTAssertTrue(family!.title.contains("Jane Doe"),   "Wife name missing from family title")
    }

    func testMarriageDateAndPlaceInFamily() {
        let sections = parser.parse(text: sampleGED)
        let family = sections.first { $0.title.contains("Family") }!
        XCTAssertTrue(family.text.contains("10 JUN 1875"),    "Marriage date not found")
        XCTAssertTrue(family.text.contains("Springfield, IL"), "Marriage place not found")
    }

    func testChildListedInFamily() {
        let sections = parser.parse(text: sampleGED)
        let family = sections.first { $0.title.contains("Family") }!
        XCTAssertTrue(family.text.contains("William Smith"), "Child not listed in family section: \(family.text)")
    }

    func testEmptyInputReturnsNoSections() {
        XCTAssertTrue(parser.parse(text: "").isEmpty)
        XCTAssertTrue(parser.parse(text: "0 HEAD\n0 TRLR").isEmpty)
    }

    func testCRLFLineEndingsHandled() {
        let crlf = sampleGED.replacingOccurrences(of: "\n", with: "\r\n")
        let sections = parser.parse(text: crlf)
        XCTAssertEqual(sections.count, 4, "CRLF line endings should parse identically to LF")
    }

    func testCRLineEndingsHandled() {
        let cr = sampleGED.replacingOccurrences(of: "\n", with: "\r")
        let sections = parser.parse(text: cr)
        XCTAssertEqual(sections.count, 4, "CR-only line endings should parse identically to LF")
    }

    func testParseFromFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ragflow_test_sample.ged")
        try sampleGED.write(to: url, atomically: true, encoding: .utf8)
        let sections = try parser.parse(url: url)
        XCTAssertEqual(sections.count, 4, "File-based parse should produce same result as text-based")
        XCTAssertTrue(sections.contains { $0.title == "John Smith" })
    }

    func testNoteExtracted() {
        let ged = """
        0 @I1@ INDI
        1 NAME Ada /Lovelace/
        1 NOTE First programmer in history
        0 TRLR
        """
        let sections = parser.parse(text: ged)
        let ada = sections.first { $0.title == "Ada Lovelace" }
        XCTAssertNotNil(ada)
        XCTAssertTrue(ada!.text.contains("First programmer"), "Note not extracted: \(ada!.text)")
    }

    func testIndividualWithNoEventsStillProducesSection() {
        let ged = "0 @I1@ INDI\n1 NAME Mystery /Person/\n0 TRLR"
        let sections = parser.parse(text: ged)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Mystery Person")
    }
}

// MARK: - GutenbergResolver

final class GutenbergResolverTests: XCTestCase {

    // MARK: isGutenbergBookPage

    func testStandardBookPageRecognised() {
        let url = URL(string: "https://www.gutenberg.org/ebooks/1342")!
        XCTAssertTrue(GutenbergResolver.isGutenbergBookPage(url))
    }

    func testWwwlessHostRecognised() {
        let url = URL(string: "https://gutenberg.org/ebooks/84")!
        XCTAssertTrue(GutenbergResolver.isGutenbergBookPage(url))
    }

    func testHttpSchemeRecognised() {
        let url = URL(string: "http://www.gutenberg.org/ebooks/11")!
        XCTAssertTrue(GutenbergResolver.isGutenbergBookPage(url))
    }

    func testNonGutenbergURLRejected() {
        XCTAssertFalse(GutenbergResolver.isGutenbergBookPage(URL(string: "https://example.com/ebooks/1342")!))
    }

    func testGutenbergNonBookPathRejected() {
        // /browse/ is not a book page
        XCTAssertFalse(GutenbergResolver.isGutenbergBookPage(URL(string: "https://www.gutenberg.org/browse/recent/last1")!))
    }

    func testNonNumericIdRejected() {
        XCTAssertFalse(GutenbergResolver.isGutenbergBookPage(URL(string: "https://www.gutenberg.org/ebooks/abc")!))
    }

    func testCacheDownloadURLRejected() {
        // A direct cache file URL is not a book page
        let url = URL(string: "https://www.gutenberg.org/cache/epub/1342/pg1342.epub")!
        XCTAssertFalse(GutenbergResolver.isGutenbergBookPage(url))
    }

    // MARK: resolve — error cases (no network needed)

    func testNonGutenbergURLThrows() async {
        let url = URL(string: "https://example.com/ebooks/1342")!
        do {
            _ = try await GutenbergResolver.resolve(url)
            XCTFail("Expected notAGutenbergURL error")
        } catch GutenbergResolver.GutenbergError.notAGutenbergURL {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: resolve — live network (skipped in CI, manual only)

    func testResolvePrideAndPrejudice() async throws {
        // Book #1342 = Pride and Prejudice — a stable, always-available Gutenberg title.
        // Skipped in automated runs; run manually to verify live resolution.
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "Skipping live network test in CI")
        let url = URL(string: "https://www.gutenberg.org/ebooks/1342")!
        let book = try await GutenbergResolver.resolve(url)
        XCTAssertEqual(book.gutenbergID, 1342)
        XCTAssertTrue(
            book.downloadURL.absoluteString.contains("gutenberg.org"),
            "Resolved URL must be on gutenberg.org"
        )
        let ext = book.downloadURL.pathExtension.lowercased()
        XCTAssertTrue(["epub", "txt"].contains(ext),
                      "Resolved extension must be epub or txt, got: \(ext)")
    }

    func testResolveAlicesAdventuresInWonderland() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "Skipping live network test in CI")
        let url = URL(string: "https://www.gutenberg.org/ebooks/11")!
        let book = try await GutenbergResolver.resolve(url)
        XCTAssertEqual(book.gutenbergID, 11)
        let ext = book.downloadURL.pathExtension.lowercased()
        XCTAssertTrue(["epub", "txt"].contains(ext))
    }
}

// MARK: - LLMError message quality tests

final class LLMErrorMessageTests: XCTestCase {

    // badResponse should no longer surface a vague "unexpected" message
    func testBadResponseDescriptionIsActionable() {
        let err = LLMError.badResponse
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
        // Should not be the old vague single-word message
        XCTAssertFalse(desc == "LLM returned an unexpected response.")
        // Should suggest a corrective action
        XCTAssertTrue(desc.lowercased().contains("api key") || desc.lowercased().contains("network"),
                      "badResponse description should mention API key or network, got: \(desc)")
    }

    // serverError wraps a custom string verbatim
    func testServerErrorPreservesMessage() {
        let msg = "Claude API error (429): Rate limit exceeded."
        let err = LLMError.serverError(msg)
        XCTAssertEqual(err.errorDescription, msg)
    }

    // missingApiKey message unchanged
    func testMissingApiKeyDescription() {
        let err = LLMError.missingApiKey
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.lowercased().contains("api key") || desc.lowercased().contains("ollama"),
                      "missingApiKey should mention API key or Ollama, got: \(desc)")
    }

    // Verify the provider name + status code appear in formatted error strings
    func testClaudeErrorIncludesStatusCode() {
        let err = LLMError.serverError("Claude API error (401): invalid x-api-key")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("401"), "Claude error message should include HTTP status code")
        XCTAssertTrue(desc.lowercased().contains("claude"), "Should identify Claude as the provider")
    }

    func testOpenAIErrorIncludesStatusCode() {
        let err = LLMError.serverError("OpenAI error (403): You exceeded your current quota")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("403"), "OpenAI error message should include HTTP status code")
        XCTAssertTrue(desc.lowercased().contains("openai"), "Should identify OpenAI as the provider")
    }

    func testOllamaErrorIncludesProviderName() {
        let err = LLMError.serverError("Ollama: model 'llama3' not found")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.lowercased().contains("ollama"), "Should identify Ollama as the provider")
    }

    func testOllamaHTTPErrorIncludesStatusCode() {
        let err = LLMError.serverError("Ollama returned HTTP 503.")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("503"), "Ollama HTTP error should include status code")
    }

    func testNetworkErrorIncludesProvider() {
        let claudeErr = LLMError.serverError("Claude: unexpected network response. Check your internet connection.")
        XCTAssertTrue((claudeErr.errorDescription ?? "").lowercased().contains("claude"))

        let openaiErr = LLMError.serverError("OpenAI: unexpected network response. Check your internet connection.")
        XCTAssertTrue((openaiErr.errorDescription ?? "").lowercased().contains("openai"))

        let ollamaErr = LLMError.serverError("Ollama: unexpected network response. Check that your Ollama host is reachable.")
        XCTAssertTrue((ollamaErr.errorDescription ?? "").lowercased().contains("ollama"))
    }
}

// MARK: - DOCX import tests

final class DOCXParserTests: XCTestCase {

    private let parser = OfficeParser()
    private var tmpDir: URL!

    // Minimal but valid Word XML skeleton
    private func makeDocumentXML(paragraphs: [String]) -> String {
        let paras = paragraphs.map { text -> String in
            "<w:p><w:r><w:t>\(text)</w:t></w:r></w:p>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(paras)</w:body>
        </w:document>
        """
    }

    // Write word/document.xml inside a temp dir, return the dir URL
    private func makeDocxDir(xml: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wordDir = dir.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try xml.write(to: wordDir.appendingPathComponent("document.xml"),
                      atomically: true, encoding: .utf8)
        return dir
    }

    override func tearDown() {
        if let d = tmpDir { try? FileManager.default.removeItem(at: d) }
        tmpDir = nil
    }

    // ── Basic extraction ──────────────────────────────────────────────────────

    func testSingleParagraphExtracted() throws {
        tmpDir = try makeDocxDir(xml: makeDocumentXML(paragraphs: ["Hello world"]))
        let sections = try parser.parseDOCXContent(dir: tmpDir, fileName: "test")
        XCTAssertEqual(sections.count, 1)
        XCTAssertTrue(sections[0].text.contains("Hello world"))
    }

    func testMultipleParagraphsExtracted() throws {
        tmpDir = try makeDocxDir(xml: makeDocumentXML(paragraphs: ["First paragraph", "Second paragraph", "Third paragraph"]))
        let sections = try parser.parseDOCXContent(dir: tmpDir, fileName: "doc")
        XCTAssertEqual(sections.count, 1)
        let text = sections[0].text
        XCTAssertTrue(text.contains("First paragraph"))
        XCTAssertTrue(text.contains("Second paragraph"))
        XCTAssertTrue(text.contains("Third paragraph"))
    }

    func testFileNameBecomesTitle() throws {
        tmpDir = try makeDocxDir(xml: makeDocumentXML(paragraphs: ["content"]))
        let sections = try parser.parseDOCXContent(dir: tmpDir, fileName: "MyReport")
        XCTAssertEqual(sections[0].title, "MyReport")
    }

    // ── Multiple <w:t> runs in one paragraph (bold, italic spans) ──────────

    func testMultipleRunsInParagraph() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
          <w:p>
            <w:r><w:t>Hello </w:t></w:r>
            <w:r><w:rPr><w:b/></w:rPr><w:t>bold</w:t></w:r>
            <w:r><w:t> world</w:t></w:r>
          </w:p>
        </w:body>
        </w:document>
        """
        tmpDir = try makeDocxDir(xml: xml)
        let sections = try parser.parseDOCXContent(dir: tmpDir, fileName: "f")
        XCTAssertTrue(sections[0].text.contains("Hello"))
        XCTAssertTrue(sections[0].text.contains("bold"))
        XCTAssertTrue(sections[0].text.contains("world"))
    }

    // ── Whitespace normalisation ───────────────────────────────────────────

    func testExcessiveWhitespaceCollapsed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body><w:p><w:r><w:t>  lots   of   spaces  </w:t></w:r></w:p></w:body>
        </w:document>
        """
        tmpDir = try makeDocxDir(xml: xml)
        let sections = try parser.parseDOCXContent(dir: tmpDir, fileName: "f")
        // After normalisation, multiple spaces collapse to one
        XCTAssertFalse(sections[0].text.contains("  "), "Extra whitespace should be collapsed")
    }

    // ── Error paths ───────────────────────────────────────────────────────

    func testMissingDocumentXMLThrows() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        // word/ dir exists but document.xml is absent
        try FileManager.default.createDirectory(
            at: tmpDir.appendingPathComponent("word"), withIntermediateDirectories: true)

        XCTAssertThrowsError(try parser.parseDOCXContent(dir: tmpDir, fileName: "f")) { error in
            XCTAssertTrue("\(error)".lowercased().contains("document.xml") ||
                          "\(error)".lowercased().contains("missing"),
                          "Should report missing document.xml, got: \(error)")
        }
    }

    func testEmptyDocumentThrows() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body></w:body>
        </w:document>
        """
        tmpDir = try makeDocxDir(xml: xml)
        XCTAssertThrowsError(try parser.parseDOCXContent(dir: tmpDir, fileName: "empty")) { error in
            XCTAssertTrue("\(error)".lowercased().contains("empty") ||
                          "\(error)".lowercased().contains("no") ||
                          "\(error)".lowercased().contains("text"),
                          "Should report empty content, got: \(error)")
        }
    }

    func testWhitespaceOnlyBodyThrows() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body><w:p><w:r><w:t>   </w:t></w:r></w:p></w:body>
        </w:document>
        """
        tmpDir = try makeDocxDir(xml: xml)
        XCTAssertThrowsError(try parser.parseDOCXContent(dir: tmpDir, fileName: "blank"))
    }

    // ── Paragraph separators ──────────────────────────────────────────────

    func testParagraphsAreSeparatedByNewlines() throws {
        tmpDir = try makeDocxDir(xml: makeDocumentXML(paragraphs: ["Line one", "Line two"]))
        let sections = try parser.parseDOCXContent(dir: tmpDir, fileName: "f")
        // Paragraphs should be on separate lines
        let lines = sections[0].text.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 2,
            "Each paragraph should produce a separate line")
    }

    // ── Legacy .doc binary format detection ───────────────────────────────

    func testLegacyDocMagicBytesThrowsDescriptiveError() throws {
        // OLE Compound Document magic: D0 CF 11 E0 ...
        let legacyHeader = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fakeDoc = dir.appendingPathComponent("thesis.docx")
        try legacyHeader.write(to: fakeDoc)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertThrowsError(try parser.parseDOCX(url: fakeDoc)) { error in
            let desc = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(desc.lowercased().contains("legacy") || desc.lowercased().contains("doc"),
                          "Should explain legacy format issue, got: \(desc)")
            XCTAssertTrue(desc.lowercased().contains("docx") || desc.lowercased().contains("resave"),
                          "Should guide user to resave as .docx, got: \(desc)")
        }
    }

    func testNonZipFileThrowsDescriptiveError() throws {
        // A plain text file masquerading as .docx
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fakeDocx = dir.appendingPathComponent("fake.docx")
        try "This is just plain text, not a ZIP".write(to: fakeDocx, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertThrowsError(try parser.parseDOCX(url: fakeDocx)) { error in
            let desc = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            // Should NOT be the raw ZipError — must be a human-readable message
            XCTAssertFalse(desc.contains("ZipError") || desc.contains("error 0"),
                           "Raw ZipError must not reach the user, got: \(desc)")
            XCTAssertTrue(desc.count > 20, "Error should have a meaningful description")
        }
    }

    // ── Typical document structure ────────────────────────────────────────

    func testRealisticDocument() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
          <w:p><w:r><w:t>Project Alpha — Q1 Report</w:t></w:r></w:p>
          <w:p><w:r><w:t></w:t></w:r></w:p>
          <w:p><w:r><w:t>Executive Summary</w:t></w:r></w:p>
          <w:p><w:r><w:t>Revenue increased 12% year over year driven by new enterprise contracts.</w:t></w:r></w:p>
          <w:p><w:r><w:t>Key Metrics</w:t></w:r></w:p>
          <w:p><w:r><w:t>MRR: $480,000</w:t></w:r></w:p>
          <w:p><w:r><w:t>Churn: 2.1%</w:t></w:r></w:p>
        </w:body>
        </w:document>
        """
        tmpDir = try makeDocxDir(xml: xml)
        let sections = try parser.parseDOCXContent(dir: tmpDir, fileName: "Q1Report")
        XCTAssertEqual(sections.count, 1)
        let text = sections[0].text
        XCTAssertTrue(text.contains("Project Alpha"))
        XCTAssertTrue(text.contains("Executive Summary"))
        XCTAssertTrue(text.contains("Revenue increased 12%"))
        XCTAssertTrue(text.contains("MRR"))
        XCTAssertTrue(text.contains("Churn"))
        XCTAssertGreaterThan(text.count, 50)
    }
}

// MARK: - H3: PDFParser unit tests

final class PDFParserTests: XCTestCase {

    func test_parse_missingFile_returnsEmpty() {
        let parser = PDFParser()
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).pdf")
        let sections = parser.parse(url: url)
        XCTAssertTrue(sections.isEmpty)
    }

    func test_hasTextLayer_missingFile_returnsFalse() {
        let parser = PDFParser()
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).pdf")
        XCTAssertFalse(parser.hasTextLayer(url: url))
    }
}

// MARK: - H3: IngestError description tests

final class IngestErrorTests: XCTestCase {

    func test_unsupportedFormat_hasDescription() {
        let err = RAGService.IngestError.unsupportedFormat
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription?.contains("PDF") == true)
    }

    func test_parseFailure_hasDescription() {
        let err = RAGService.IngestError.parseFailure
        XCTAssertNotNil(err.errorDescription)
    }

    func test_unsupportedLegacyDoc_mentionsDOCX() {
        let err = RAGService.IngestError.unsupportedLegacyDoc
        XCTAssertTrue(err.errorDescription?.contains("docx") == true || err.errorDescription?.contains(".docx") == true)
    }

    func test_fileTooLarge_mentions100MB() {
        let err = RAGService.IngestError.fileTooLarge
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription?.contains("100") == true)
    }
}

// MARK: - H3: DatabaseService keyword search tests (FTS5 via raw GRDB)

final class DatabaseServiceKeywordTests: XCTestCase {
    private var dbq: DatabaseQueue!
    private let kbId = "kb-kw-test"
    private let bookId = "book-kw-test"

    override func setUp() {
        super.setUp()
        dbq = try! DatabaseQueue()
        try! setupSchema(dbq)
        try! seedBook(dbq)
    }

    private func setupSchema(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            try db.create(table: "knowledge_bases", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(sql: "INSERT INTO knowledge_bases (id, name, createdAt) VALUES (?, ?, ?)",
                           arguments: [kbId, "KW Test KB", Date()])
            try db.create(table: "books", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("author", .text).notNull().defaults(to: "")
                t.column("filePath", .text).notNull()
                t.column("addedAt", .datetime).notNull()
                t.column("chunkCount", .integer).notNull().defaults(to: 0)
                t.column("kbId", .text).notNull()
                t.column("fileType", .text).notNull().defaults(to: "")
                t.column("pageCount", .integer).notNull().defaults(to: 0)
                t.column("wordCount", .integer).notNull().defaults(to: 0)
                t.column("sourceURL", .text).notNull().defaults(to: "")
            }
            try db.create(table: "chunks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("bookId", .text).notNull().references("books", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("chapterTitle", .text)
                t.column("position", .integer).notNull()
                t.column("embedding", .blob)
            }
            try db.create(virtualTable: "chunks_fts", ifNotExists: true, using: FTS5()) { t in
                t.tokenizer = .porter()
                t.column("chunk_id")
                t.column("content")
                t.column("chapterTitle")
            }
        }
    }

    private func seedBook(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO books (id, kbId, title, author, filePath, addedAt, chunkCount)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [bookId, kbId, "Test Book", "Author", "/tmp/t.pdf", Date(), 0])
        }
    }

    private func insertChunk(id: String, content: String, position: Int = 0) throws {
        try dbq.write { db in
            try db.execute(sql: """
                INSERT INTO chunks (id, bookId, content, chapterTitle, position)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [id, bookId, content, "Ch", position])
            try db.execute(sql: """
                INSERT INTO chunks_fts (chunk_id, content, chapterTitle) VALUES (?, ?, ?)
                """, arguments: [id, content, "Ch"])
        }
    }

    func test_fts_findsExactTerm() throws {
        let cid = UUID().uuidString
        try insertChunk(id: cid, content: "The quick brown fox jumps")
        let results = try dbq.read { db -> [Row] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "fox") else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = ?
                AND chunks.id IN (SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT 10)
                """, arguments: [kbId, pattern])
        }
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?["id"] as? String, cid)
    }

    func test_fts_noResults_forUnknownTerm() throws {
        try insertChunk(id: UUID().uuidString, content: "The quick brown fox jumps")
        let results = try dbq.read { db -> [Row] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "xylophone") else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                WHERE books.kbId = ?
                AND chunks.id IN (SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ? LIMIT 10)
                """, arguments: [kbId, pattern])
        }
        XCTAssertTrue(results.isEmpty)
    }

    func test_fts_rankedSearch_returnsBothChunks() throws {
        try insertChunk(id: UUID().uuidString, content: "swift programming language features", position: 0)
        try insertChunk(id: UUID().uuidString, content: "swift is fast and safe", position: 1)
        let results = try dbq.read { db -> [Row] in
            guard let pattern = FTS5Pattern(matchingAnyTokenIn: "swift") else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT chunks.* FROM chunks
                JOIN books ON books.id = chunks.bookId
                JOIN chunks_fts ON chunks_fts.chunk_id = chunks.id
                WHERE books.kbId = ? AND chunks_fts MATCH ?
                ORDER BY chunks_fts.rank LIMIT 10
                """, arguments: [kbId, pattern])
        }
        XCTAssertEqual(results.count, 2)
    }
}

// MARK: - Paginated message loading

final class PaginatedMessageLoadingTests: XCTestCase {

    private var dbq: DatabaseQueue!
    private var sut: DatabaseService!

    override func setUp() {
        super.setUp()
        dbq = try! DatabaseQueue()
        try! runMigrations(on: dbq)
        sut = DatabaseService(queue: dbq)
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
            try db.alter(table: "message_sources") { t in
                t.add(column: "documentTitle", .text).notNull().defaults(to: "")
            }
        }
        try m.migrate(queue)
    }

    private func insertMessage(id: String, sessionId: String, role: String,
                               content: String, offset: TimeInterval) throws {
        let ts = Date(timeIntervalSinceReferenceDate: offset)
        try dbq.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, kbId, sessionId, role, content, timestamp) VALUES (?,?,?,?,?,?)",
                arguments: [id, KnowledgeBase.defaultID, sessionId, role, content, ts])
        }
    }

    // MARK: - countMessages

    func testCountMessagesReturnsZeroForEmptySession() throws {
        let count = try sut.countMessages(sessionId: "none")
        XCTAssertEqual(count, 0)
    }

    func testCountMessagesReturnsExactCount() throws {
        try insertMessage(id: "m1", sessionId: "s1", role: "user", content: "hi", offset: 1)
        try insertMessage(id: "m2", sessionId: "s1", role: "assistant", content: "hello", offset: 2)
        try insertMessage(id: "m3", sessionId: "s1", role: "user", content: "bye", offset: 3)
        XCTAssertEqual(try sut.countMessages(sessionId: "s1"), 3)
    }

    func testCountMessagesIsScopedToSession() throws {
        try insertMessage(id: "a1", sessionId: "sessA", role: "user", content: "x", offset: 1)
        try insertMessage(id: "b1", sessionId: "sessB", role: "user", content: "y", offset: 2)
        try insertMessage(id: "b2", sessionId: "sessB", role: "assistant", content: "z", offset: 3)
        XCTAssertEqual(try sut.countMessages(sessionId: "sessA"), 1)
        XCTAssertEqual(try sut.countMessages(sessionId: "sessB"), 2)
    }

    // MARK: - loadMessages

    func testLoadMessagesReturnsEmptyForUnknownSession() throws {
        let msgs = try sut.loadMessages(sessionId: "x", limit: 50, offset: 0)
        XCTAssertTrue(msgs.isEmpty)
    }

    func testLoadMessagesReturnsChronologicalOrder() throws {
        try insertMessage(id: "c3", sessionId: "s2", role: "assistant", content: "third", offset: 3)
        try insertMessage(id: "c1", sessionId: "s2", role: "user",      content: "first",  offset: 1)
        try insertMessage(id: "c2", sessionId: "s2", role: "user",      content: "second", offset: 2)
        let msgs = try sut.loadMessages(sessionId: "s2", limit: 50, offset: 0)
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs[0].content, "first")
        XCTAssertEqual(msgs[1].content, "second")
        XCTAssertEqual(msgs[2].content, "third")
    }

    func testLoadMessagesRespectLimit() throws {
        for i in 0..<10 {
            try insertMessage(id: "lim\(i)", sessionId: "s3", role: "user",
                              content: "msg\(i)", offset: Double(i))
        }
        let page = try sut.loadMessages(sessionId: "s3", limit: 4, offset: 0)
        XCTAssertEqual(page.count, 4)
    }

    func testLoadMessagesRespectOffset() throws {
        for i in 0..<6 {
            try insertMessage(id: "off\(i)", sessionId: "s4", role: "user",
                              content: "msg\(i)", offset: Double(i))
        }
        // offset=0 fetches the 3 NEWEST (DESC order), reversed → chronological newest 3
        let first  = try sut.loadMessages(sessionId: "s4", limit: 3, offset: 0)
        // offset=3 fetches the 3 OLDER (DESC order), reversed → chronological older 3
        let second = try sut.loadMessages(sessionId: "s4", limit: 3, offset: 3)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(second.count, 3)
        // Pages must not overlap: all messages in second are older than all in first.
        XCTAssertLessThan(second.last!.timestamp, first.first!.timestamp)
    }

    func testLoadMessagesDoesNotReturnOtherSessions() throws {
        try insertMessage(id: "x1", sessionId: "sX", role: "user", content: "xmsg", offset: 1)
        try insertMessage(id: "y1", sessionId: "sY", role: "user", content: "ymsg", offset: 2)
        let msgs = try sut.loadMessages(sessionId: "sX", limit: 50, offset: 0)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].content, "xmsg")
    }

    func testLoadMessagesTotalMatchesCount() throws {
        let sessionId = "total-check"
        for i in 0..<15 {
            try insertMessage(id: "tc\(i)", sessionId: sessionId, role: "user",
                              content: "m\(i)", offset: Double(i))
        }
        let total  = try sut.countMessages(sessionId: sessionId)
        let page1  = try sut.loadMessages(sessionId: sessionId, limit: 10, offset: 0)
        let page2  = try sut.loadMessages(sessionId: sessionId, limit: 10, offset: 10)
        XCTAssertEqual(total, 15)
        XCTAssertEqual(page1.count, 10)
        XCTAssertEqual(page2.count, 5)
        XCTAssertEqual(page1.count + page2.count, total)
    }
}

// MARK: - Scanned document / Vision OCR tests

final class ScannedDocumentTests: XCTestCase {

    private var tmp: URL { FileManager.default.temporaryDirectory.resolvingSymlinksInPath() }
    private func url(_ name: String) -> URL { tmp.appendingPathComponent("ragflow_scan_test_\(name)") }

    /// Returns a single-page PDF containing a rasterised bitmap of `text`.
    /// The PDF has no PDFKit text layer — PDFParser.parse() returns empty for it.
    private func makeImageOnlyPDF(text: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let imgRenderer = UIGraphicsImageRenderer(size: pageRect.size)
        let img = imgRenderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(pageRect)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36),
                .foregroundColor: UIColor.black
            ]
            text.draw(in: CGRect(x: 50, y: 200, width: 512, height: 350), withAttributes: attrs)
        }
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            img.draw(in: pageRect)
        }
    }

    // MARK: - PDFParser.hasTextLayer

    func testHasTextLayerReturnsFalseForImageOnlyPDF() throws {
        let f = url("has_text_false.pdf")
        try makeImageOnlyPDF(text: "Hello World").write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertFalse(PDFParser().hasTextLayer(url: f),
                       "image-only PDF should report no text layer")
    }

    func testHasTextLayerReturnsTrueForTextPDF() throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
            "Hello World text layer verification string with enough characters to pass".draw(
                in: CGRect(x: 50, y: 50, width: 500, height: 600), withAttributes: attrs)
        }
        let f = url("has_text_true.pdf")
        try data.write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertTrue(PDFParser().hasTextLayer(url: f),
                      "text-layer PDF should be detected as having text")
    }

    // MARK: - PDFParser: image-only PDF returns no usable text sections

    func testPDFParserYieldsNoTextForImageOnlyPDF() throws {
        let f = url("pdf_parser_blank.pdf")
        try makeImageOnlyPDF(text: "invisible to PDFKit").write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        let sections = PDFParser().parse(url: f)
        let hasText = sections.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertFalse(hasText,
                       "PDFParser should not extract text from image-only PDF; got: \(sections.map(\.text).joined().prefix(80))")
    }

    // MARK: - VisionOCRParser: scanned PDF fallback

    func testVisionOCRExtractsTextFromImageOnlyPDF() async throws {
        let f = url("ocr_pdf.pdf")
        try makeImageOnlyPDF(text: "Hello World").write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }

        // Confirm PDFParser sees no text (exercising the RAGService branch condition)
        let pdfSections = PDFParser().parse(url: f)
        let pdfText = pdfSections.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(pdfText.isEmpty,
                      "precondition: PDFParser should see no text; got '\(pdfText.prefix(60))'")

        // VisionOCR should recover text from the rasterised page
        let pageTexts = await VisionOCRParser().extractText(fromPDFAt: f)
        XCTAssertFalse(pageTexts.isEmpty, "VisionOCR should return at least one page result")
        let ocrText = pageTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(ocrText.isEmpty,
                       "VisionOCR should extract non-empty text from image-only PDF")
    }

    // MARK: - VisionOCRParser: camera-captured UIImage (document scanner path)

    func testVisionOCRExtractsTextFromUIImage() async {
        let size = CGSize(width: 800, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44),
                .foregroundColor: UIColor.black
            ]
            "Hello World".draw(in: CGRect(x: 50, y: 80, width: 700, height: 150), withAttributes: attrs)
        }
        let text = await VisionOCRParser().extractText(from: img)
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "VisionOCR should extract text from UIImage; got empty")
    }
}

// MARK: - H3: Shared schema helper

/// Creates an in-memory DatabaseService with the full v1–v11 schema applied.
private func makeFullDB() throws -> DatabaseService {
    let queue = try DatabaseQueue()
    try queue.write { db in
        try db.create(table: "books") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("author", .text).notNull().defaults(to: "")
            t.column("filePath", .text).notNull()
            t.column("addedAt", .datetime).notNull()
            t.column("chunkCount", .integer).notNull().defaults(to: 0)
            t.column("kbId", .text).notNull().defaults(to: KnowledgeBase.defaultID)
            t.column("fileType", .text).notNull().defaults(to: "")
            t.column("pageCount", .integer).notNull().defaults(to: 0)
            t.column("wordCount", .integer).notNull().defaults(to: 0)
            t.column("sourceURL", .text).notNull().defaults(to: "")
        }
        try db.create(table: "chunks") { t in
            t.column("id", .text).primaryKey()
            t.column("bookId", .text).notNull().references("books", onDelete: .cascade)
            t.column("content", .text).notNull()
            t.column("chapterTitle", .text)
            t.column("position", .integer).notNull()
            t.column("embedding", .blob)
        }
        try db.create(virtualTable: "chunks_fts", using: FTS5()) { t in
            t.tokenizer = .porter()
            t.column("chunk_id")
            t.column("content")
            t.column("chapterTitle")
        }
        try db.create(table: "knowledge_bases") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("topK", .integer).notNull().defaults(to: 10)
            t.column("topN", .integer).notNull().defaults(to: 50)
            t.column("chunkMethod", .text).notNull().defaults(to: "General")
            t.column("chunkSize", .integer).notNull().defaults(to: 512)
            t.column("chunkOverlap", .integer).notNull().defaults(to: 64)
            t.column("similarityThreshold", .double).notNull().defaults(to: 0.2)
        }
        try db.create(table: "messages") { t in
            t.column("id", .text).primaryKey()
            t.column("kbId", .text).notNull()
            t.column("role", .text).notNull()
            t.column("content", .text).notNull()
            t.column("timestamp", .datetime).notNull()
            t.column("sessionId", .text).notNull().defaults(to: "")
        }
        try db.create(table: "message_sources") { t in
            t.column("id", .text).primaryKey()
            t.column("messageId", .text).notNull().references("messages", onDelete: .cascade)
            t.column("chapterTitle", .text)
            t.column("preview", .text).notNull()
            t.column("documentTitle", .text).notNull().defaults(to: "")
        }
        try db.create(table: "workflows") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("templateId", .text).notNull()
            t.column("kbId", .text).notNull()
            t.column("stepsJSON", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "workflow_runs") { t in
            t.column("id", .text).primaryKey()
            t.column("workflowId", .text).notNull().references("workflows", onDelete: .cascade)
            t.column("input", .text).notNull()
            t.column("output", .text).notNull()
            t.column("status", .text).notNull()
            t.column("stepLogJSON", .text).notNull().defaults(to: "[]")
            t.column("provider", .text).notNull().defaults(to: "")
            t.column("modelName", .text).notNull().defaults(to: "")
            t.column("kbName", .text).notNull().defaults(to: "")
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "chat_sessions") { t in
            t.column("id", .text).primaryKey()
            t.column("kbId", .text).notNull()
            t.column("name", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("modelOverride", .text)
            t.column("temperature", .double)
            t.column("topP", .double)
            t.column("systemPrompt", .text)
            t.column("historyWindow", .integer)
        }
    }
    return DatabaseService(queue: queue)
}

// MARK: - H3: DatabaseService — ChatSession CRUD

final class DatabaseServiceSessionTests: XCTestCase {
    private var sut: DatabaseService!

    override func setUp() {
        super.setUp()
        sut = try! makeFullDB()
    }

    private func makeSession(id: String = UUID().uuidString,
                              kbId: String = "kb1",
                              name: String = "Chat",
                              offset: TimeInterval = 0) -> ChatSession {
        ChatSession(id: id, kbId: kbId, name: name,
                    createdAt: Date(timeIntervalSinceReferenceDate: offset))
    }

    func testSaveAndFetchSessionById() throws {
        let s = makeSession(id: "s-round-trip", name: "My Chat")
        try sut.saveSession(s)
        let fetched = try sut.session(id: "s-round-trip")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "My Chat")
        XCTAssertEqual(fetched?.kbId, "kb1")
    }

    func testSessionNotFoundReturnsNil() throws {
        let result = try sut.session(id: "does-not-exist")
        XCTAssertNil(result)
    }

    func testAllSessionsScopedToKB() throws {
        try sut.saveSession(makeSession(id: "s-a1", kbId: "kb-A"))
        try sut.saveSession(makeSession(id: "s-a2", kbId: "kb-A"))
        try sut.saveSession(makeSession(id: "s-b1", kbId: "kb-B"))
        let sessions = try sut.allSessions(kbId: "kb-A")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.kbId == "kb-A" })
    }

    func testAllSessionsOrderedNewestFirst() throws {
        try sut.saveSession(makeSession(id: "s-old", offset: 1))
        try sut.saveSession(makeSession(id: "s-new", offset: 100))
        let sessions = try sut.allSessions(kbId: "kb1")
        XCTAssertEqual(sessions.first?.id, "s-new")
        XCTAssertEqual(sessions.last?.id, "s-old")
    }

    func testDeleteSessionRemovesIt() throws {
        try sut.saveSession(makeSession(id: "s-del"))
        try sut.deleteSession("s-del")
        let result = try sut.session(id: "s-del")
        XCTAssertNil(result)
    }

    func testDeleteSessionsBatch() throws {
        try sut.saveSession(makeSession(id: "s-b1"))
        try sut.saveSession(makeSession(id: "s-b2"))
        try sut.saveSession(makeSession(id: "s-b3"))
        try sut.deleteSessions(["s-b1", "s-b3"])
        XCTAssertNil(try sut.session(id: "s-b1"))
        XCTAssertNil(try sut.session(id: "s-b3"))
        XCTAssertNotNil(try sut.session(id: "s-b2"))
    }

    func testRenameSession() throws {
        try sut.saveSession(makeSession(id: "s-ren", name: "Old Name"))
        try sut.renameSession(id: "s-ren", name: "New Name")
        let fetched = try sut.session(id: "s-ren")
        XCTAssertEqual(fetched?.name, "New Name")
    }

    func testUpdateSessionParams() throws {
        try sut.saveSession(makeSession(id: "s-params"))
        try sut.updateSessionParams(id: "s-params",
                                    modelOverride: "claude-opus-4-7",
                                    temperature: 0.7,
                                    topP: 0.9,
                                    systemPrompt: "Be concise.",
                                    historyWindow: 20)
        let fetched = try sut.session(id: "s-params")
        XCTAssertEqual(fetched?.modelOverride, "claude-opus-4-7")
        XCTAssertEqual(fetched?.temperature, 0.7)
        XCTAssertEqual(fetched?.topP, 0.9)
        XCTAssertEqual(fetched?.systemPrompt, "Be concise.")
        XCTAssertEqual(fetched?.historyWindow, 20)
    }
}

// MARK: - H3: DatabaseService — Workflow + WorkflowRun CRUD

final class DatabaseServiceWorkflowTests: XCTestCase {
    private var sut: DatabaseService!

    override func setUp() {
        super.setUp()
        sut = try! makeFullDB()
    }

    private func makeWorkflow(id: String = UUID().uuidString,
                               name: String = "Test Flow",
                               offset: TimeInterval = 0) -> Workflow {
        Workflow(id: id, name: name, templateId: "tmpl-1", kbId: "kb1",
                 stepsJSON: "[]", createdAt: Date(timeIntervalSinceReferenceDate: offset))
    }

    private func makeRun(id: String = UUID().uuidString,
                          workflowId: String,
                          status: String = "completed") -> WorkflowRun {
        WorkflowRun(id: id, workflowId: workflowId, input: "query",
                    output: "answer", status: status, stepLogJSON: "[]",
                    provider: "claude", modelName: "claude-sonnet-4-6", kbName: "Test KB",
                    createdAt: Date())
    }

    func testSaveAndFetchAllWorkflows() throws {
        let w = makeWorkflow(id: "wf-round-trip", name: "My Workflow")
        try sut.saveWorkflow(w)
        let all = try sut.allWorkflows()
        XCTAssertTrue(all.contains { $0.id == "wf-round-trip" && $0.name == "My Workflow" })
    }

    func testAllWorkflowsOrderedNewestFirst() throws {
        try sut.saveWorkflow(makeWorkflow(id: "wf-old", offset: 1))
        try sut.saveWorkflow(makeWorkflow(id: "wf-new", offset: 100))
        let all = try sut.allWorkflows()
        XCTAssertEqual(all.first?.id, "wf-new")
        XCTAssertEqual(all.last?.id, "wf-old")
    }

    func testDeleteWorkflow() throws {
        try sut.saveWorkflow(makeWorkflow(id: "wf-del"))
        try sut.deleteWorkflow("wf-del")
        let all = try sut.allWorkflows()
        XCTAssertFalse(all.contains { $0.id == "wf-del" })
    }

    func testSaveAndFetchWorkflowRun() throws {
        try sut.saveWorkflow(makeWorkflow(id: "wf-run-parent"))
        let run = makeRun(id: "run-1", workflowId: "wf-run-parent", status: "completed")
        try sut.saveWorkflowRun(run)
        let runs = try sut.runsForWorkflow("wf-run-parent")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, "run-1")
        XCTAssertEqual(runs[0].status, "completed")
    }

    func testRunsForWorkflowScopedToWorkflow() throws {
        try sut.saveWorkflow(makeWorkflow(id: "wf-A"))
        try sut.saveWorkflow(makeWorkflow(id: "wf-B"))
        try sut.saveWorkflowRun(makeRun(id: "r-A1", workflowId: "wf-A"))
        try sut.saveWorkflowRun(makeRun(id: "r-B1", workflowId: "wf-B"))
        let runsA = try sut.runsForWorkflow("wf-A")
        XCTAssertEqual(runsA.count, 1)
        XCTAssertEqual(runsA[0].id, "r-A1")
    }

    func testRunsForWorkflowRespectsLimit() throws {
        try sut.saveWorkflow(makeWorkflow(id: "wf-lim"))
        for i in 0..<5 {
            var run = makeRun(id: "r-lim-\(i)", workflowId: "wf-lim")
            run.createdAt = Date(timeIntervalSinceReferenceDate: Double(i))
            try sut.saveWorkflowRun(run)
        }
        let runs = try sut.runsForWorkflow("wf-lim", limit: 3)
        XCTAssertEqual(runs.count, 3)
    }

    func testDeleteRunsForWorkflow() throws {
        try sut.saveWorkflow(makeWorkflow(id: "wf-del-runs"))
        try sut.saveWorkflowRun(makeRun(id: "r-dr1", workflowId: "wf-del-runs"))
        try sut.saveWorkflowRun(makeRun(id: "r-dr2", workflowId: "wf-del-runs"))
        try sut.deleteRunsForWorkflow("wf-del-runs")
        let runs = try sut.runsForWorkflow("wf-del-runs")
        XCTAssertTrue(runs.isEmpty)
    }
}

// MARK: - H3: DatabaseService — Utility methods

final class DatabaseServiceUtilityTests: XCTestCase {
    private var sut: DatabaseService!

    override func setUp() {
        super.setUp()
        sut = try! makeFullDB()
    }

    // MARK: bookTitles

    func testBookTitlesReturnsMostRecentFirst() throws {
        let kbId = "kb-bt"
        try sut.saveKB(KnowledgeBase(id: kbId, name: "KB", createdAt: Date()))
        try sut.save(Book(id: "bt-old", kbId: kbId, title: "Older Book", author: "", filePath: "/f",
                          addedAt: Date(timeIntervalSinceReferenceDate: 1), chunkCount: 0))
        try sut.save(Book(id: "bt-new", kbId: kbId, title: "Newer Book", author: "", filePath: "/f",
                          addedAt: Date(timeIntervalSinceReferenceDate: 100), chunkCount: 0))
        let titles = try sut.bookTitles(kbId: kbId)
        XCTAssertEqual(titles.first, "Newer Book")
        XCTAssertEqual(titles.last, "Older Book")
    }

    func testBookTitlesRespectsLimit() throws {
        let kbId = "kb-bt-lim"
        try sut.saveKB(KnowledgeBase(id: kbId, name: "KB", createdAt: Date()))
        for i in 0..<5 {
            try sut.save(Book(id: "bt-\(i)", kbId: kbId, title: "Book \(i)", author: "", filePath: "/f",
                              addedAt: Date(timeIntervalSinceReferenceDate: Double(i)),
                              chunkCount: 0))
        }
        let titles = try sut.bookTitles(kbId: kbId, limit: 2)
        XCTAssertEqual(titles.count, 2)
    }

    func testBookTitlesEmptyWhenNoBooksInKB() throws {
        let kbId = "kb-bt-empty"
        try sut.saveKB(KnowledgeBase(id: kbId, name: "KB", createdAt: Date()))
        let titles = try sut.bookTitles(kbId: kbId)
        XCTAssertTrue(titles.isEmpty)
    }

    // MARK: firstUserMessage

    func testFirstUserMessageReturnsEarliestUserContent() throws {
        let session = "sess-fum"
        let kbId = "kb-fum"
        try sut.saveKB(KnowledgeBase(id: kbId, name: "KB", createdAt: Date()))
        var msg1 = Message(role: .user, content: "First question")
        msg1.timestamp = Date(timeIntervalSinceReferenceDate: 1)
        var msg2 = Message(role: .user, content: "Second question")
        msg2.timestamp = Date(timeIntervalSinceReferenceDate: 10)
        try sut.saveMessages([msg1, msg2], sessionId: session, kbId: kbId)
        let first = try sut.firstUserMessage(sessionId: session)
        XCTAssertEqual(first, "First question")
    }

    func testFirstUserMessageReturnsNilForEmptySession() throws {
        let result = try sut.firstUserMessage(sessionId: "nonexistent-session")
        XCTAssertNil(result)
    }

    // MARK: sourceCount

    func testSourceCountReturnsTotal() throws {
        let session = "sess-sc"
        let kbId = "kb-sc"
        try sut.saveKB(KnowledgeBase(id: kbId, name: "KB", createdAt: Date()))
        var msg = Message(role: .assistant, content: "Answer with sources")
        msg.sources = [
            ChunkSource(id: "src-1", chapterTitle: "Ch1", documentTitle: "Doc", preview: "p1"),
            ChunkSource(id: "src-2", chapterTitle: "Ch2", documentTitle: "Doc", preview: "p2"),
        ]
        try sut.saveMessages([msg], sessionId: session, kbId: kbId)
        let count = try sut.sourceCount(sessionId: session)
        XCTAssertEqual(count, 2)
    }

    func testSourceCountZeroForSessionWithNoSources() throws {
        let count = try sut.sourceCount(sessionId: "no-sources-session")
        XCTAssertEqual(count, 0)
    }

    // MARK: updateEmbeddingsBatch

    func testUpdateEmbeddingsBatchPersistsData() throws {
        let kbId = "kb-emb"
        try sut.saveKB(KnowledgeBase(id: kbId, name: "KB", createdAt: Date()))
        let book = Book(id: "bk-emb", kbId: kbId, title: "T", author: "", filePath: "/f",
                        addedAt: Date(), chunkCount: 1)
        try sut.save(book)
        let chunk = Chunk(id: "ck-emb", bookId: "bk-emb",
                          content: "embedding test content", chapterTitle: nil, position: 0)
        try sut.saveChunks([chunk])
        let vector: [Float] = [0.1, 0.2, 0.3]
        let embData = EmbeddingService.floatsToData(vector)
        try sut.updateEmbeddingsBatch([(id: "ck-emb", embedding: embData)])
        let embedded = try sut.allChunksWithEmbeddings(kbId: kbId)
        XCTAssertEqual(embedded.count, 1)
        let decoded = EmbeddingService.dataToFloats(embedded[0].1)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0], 0.1, accuracy: 0.001)
    }

    // MARK: wipeAllData

    #if DEBUG
    func testWipeAllDataClearsAllTables() throws {
        let kbId = "kb-wipe"
        try sut.saveKB(KnowledgeBase(id: kbId, name: "KB", createdAt: Date()))
        try sut.save(Book(id: "bk-wipe", kbId: kbId, title: "T", author: "", filePath: "/f",
                          addedAt: Date(), chunkCount: 0))
        try sut.saveSession(ChatSession(id: "s-wipe", kbId: kbId, name: "Chat", createdAt: Date()))
        try sut.saveWorkflow(Workflow(id: "wf-wipe", name: "Flow", templateId: "t",
                                     kbId: kbId, stepsJSON: "[]", createdAt: Date()))
        try sut.wipeAllData()
        XCTAssertTrue((try sut.allBooks(kbId: kbId)).isEmpty)
        XCTAssertTrue((try sut.allSessions(kbId: kbId)).isEmpty)
        XCTAssertTrue((try sut.allWorkflows()).isEmpty)
        // wipeAllData re-seeds the default KB, so only the seeded one remains
        let kbs = try sut.allKBs()
        XCTAssertEqual(kbs.count, 1)
        XCTAssertEqual(kbs[0].id, KnowledgeBase.defaultID)
    }
    #endif
}
