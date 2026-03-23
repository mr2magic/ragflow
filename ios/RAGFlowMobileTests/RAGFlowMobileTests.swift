import XCTest
@testable import RAGFlowMobile

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
}
