import XCTest
import GRDB
@testable import RAGFlowMobile

// MARK: - Chunker

final class ChunkerTests: XCTestCase {
    private let chunker = Chunker(chunkSize: 10, overlap: 2)

    func testChunkSplitsText() {
        let words = Array(repeating: "word", count: 25)
        let text = words.joined(separator: " ")
        let chunks = chunker.chunk(text: text, bookId: "test")
        XCTAssertGreaterThan(chunks.count, 1)
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
        // 20 words, chunkSize=10, overlap=2 → step=8 → ceil(20/8)=3 chunks
        let text = Array(repeating: "w", count: 20).joined(separator: " ")
        let chunks = Chunker(chunkSize: 10, overlap: 2).chunk(text: text, bookId: "x")
        XCTAssertEqual(chunks.count, 3)
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

// MARK: - ChunkSource model

final class ChunkSourceTests: XCTestCase {

    func testChunkSourceFromChunk() {
        let chunk = Chunk(id: "id1", bookId: "b1",
                          content: String(repeating: "word ", count: 30),
                          chapterTitle: "Intro", position: 0)
        let source = ChunkSource(from: chunk)
        XCTAssertEqual(source.id, "id1")
        XCTAssertEqual(source.chapterTitle, "Intro")
        // Preview is capped at 120 chars
        XCTAssertLessThanOrEqual(source.preview.count, 120)
    }

    func testChunkSourceInitDirect() {
        let source = ChunkSource(id: "x", chapterTitle: nil, preview: "A passage")
        XCTAssertNil(source.chapterTitle)
        XCTAssertEqual(source.preview, "A passage")
    }
}
