import Foundation

struct Chunker {
    var chunkSize: Int
    var overlap: Int

    init(chunkSize: Int = 512, overlap: Int = 64) {
        self.chunkSize = chunkSize
        self.overlap = overlap
    }

    func chunk(text: String, bookId: String, chapterTitle: String? = nil) -> [Chunk] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        var chunks: [Chunk] = []
        var position = 0
        var start = 0

        while start < words.count {
            let end = min(start + chunkSize, words.count)
            let content = words[start..<end].joined(separator: " ")

            chunks.append(Chunk(
                id: UUID().uuidString,
                bookId: bookId,
                content: content,
                chapterTitle: chapterTitle,
                position: position
            ))

            position += 1
            start += chunkSize - overlap
        }

        return chunks
    }
}
