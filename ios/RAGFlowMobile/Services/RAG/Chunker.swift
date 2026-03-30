import Foundation
import NaturalLanguage

/// Sentence-boundary chunker mirroring RAGflow's "General" chunking strategy.
///
/// For natural prose, splits at sentence boundaries (NLTokenizer) and groups
/// sentences into overlapping windows of approximately `chunkSize` words.
/// When a single sentence exceeds `chunkSize` (e.g. code, CSV, repeat-word text),
/// falls back to word-boundary splitting within that sentence so chunks are
/// always bounded.
struct Chunker {
    var chunkSize: Int    // target words per chunk
    var overlap: Int      // words carried over from the previous chunk

    init(chunkSize: Int = 512, overlap: Int = 64) {
        self.chunkSize = chunkSize
        self.overlap = overlap
    }

    func chunk(text: String, bookId: String, chapterTitle: String? = nil) -> [Chunk] {
        let sentences = tokenizeSentences(text)
        guard !sentences.isEmpty else { return [] }

        var result: [Chunk] = []
        var buffer: [String] = []
        var position = 0

        func emit() {
            guard !buffer.isEmpty else { return }
            let content = buffer.joined(separator: " ")
            guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            result.append(Chunk(
                id: UUID().uuidString,
                bookId: bookId,
                content: content,
                chapterTitle: chapterTitle,
                position: position
            ))
            position += 1
            buffer = Array(buffer.suffix(overlap))
        }

        for sentence in sentences {
            let words = sentence.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

            if words.count > chunkSize {
                // Single sentence exceeds chunk size — split at word boundaries
                // (handles code, CSV, structured text without sentence terminators)
                var i = 0
                while i < words.count {
                    let space = max(chunkSize - buffer.count, 1)   // always advance ≥1 word
                    let end = min(i + space, words.count)
                    buffer.append(contentsOf: words[i..<end])
                    if buffer.count >= chunkSize { emit() }
                    i = end
                }
            } else {
                buffer.append(contentsOf: words)
                if buffer.count >= chunkSize { emit() }
            }
        }

        // Flush remaining content
        if !buffer.isEmpty { emit() }

        return result
    }

    // MARK: - Tokenization

    private func tokenizeSentences(_ text: String) -> [String] {
        var result: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
            return true
        }
        // Fallback for structured/code text with no sentence terminators
        if result.isEmpty {
            result = text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return result
    }
}
