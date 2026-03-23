import Foundation
import EPUBKit

@MainActor
final class RAGService: ObservableObject {
    static let shared = RAGService()

    private let db = DatabaseService.shared
    private let chunker = Chunker()

    func ingest(epubURL: URL) async throws -> Book {
        guard let document = EPUBDocument(url: epubURL) else {
            throw RAGError.invalidEPUB
        }

        let bookId = UUID().uuidString
        var allChunks: [Chunk] = []

        for spineItem in document.spine.items {
            guard let manifestItem = document.manifest.items[spineItem.idref] else { continue }

            let fileURL = document.contentDirectory.appendingPathComponent(manifestItem.path)
            guard let html = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let text = stripHTML(html)
            guard !text.isEmpty else { continue }

            let chapterTitle = URL(fileURLWithPath: manifestItem.path)
                .deletingPathExtension().lastPathComponent

            let chunks = chunker.chunk(text: text, bookId: bookId, chapterTitle: chapterTitle)
            allChunks.append(contentsOf: chunks)
        }

        let book = Book(
            id: bookId,
            title: document.metadata.title ?? epubURL.deletingPathExtension().lastPathComponent,
            author: document.metadata.creator?.name ?? "",
            filePath: epubURL.path,
            addedAt: Date(),
            chunkCount: allChunks.count
        )

        try db.save(book)
        try db.saveChunks(allChunks)

        return book
    }

    func retrieve(query: String, topK: Int = 5) throws -> [Chunk] {
        try db.search(query: query, limit: topK)
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum RAGError: LocalizedError {
        case invalidEPUB

        var errorDescription: String? {
            switch self {
            case .invalidEPUB: return "Could not parse ePub file."
            }
        }
    }
}
