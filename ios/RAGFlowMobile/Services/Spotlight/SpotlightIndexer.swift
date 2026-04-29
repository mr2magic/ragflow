import CoreSpotlight
import Foundation

/// Indexes Book titles and a sample of chunk content into Core Spotlight so
/// documents appear in device search and Siri Suggestions.
///
/// Usage:
///   SpotlightIndexer.shared.index(book: book, chunks: chunks)
///   SpotlightIndexer.shared.deindex(bookId: book.id)
///   SpotlightIndexer.shared.deindexAll(kbId: kb.id)
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    private init() {}

    private let domainId = "com.dhorn.ragflowmobile.documents"

    // MARK: - Index

    /// Indexes a Book and up to the first 10 chunks so Spotlight can preview content.
    func index(book: Book, chunks: [Chunk]) {
        var items: [CSSearchableItem] = []

        // One item per book (always)
        let bookAttr = CSSearchableItemAttributeSet(contentType: .item)
        bookAttr.title = book.title
        bookAttr.contentDescription = [
            book.author.isEmpty ? nil : "by \(book.author)",
            book.fileType.isEmpty ? nil : book.fileType.uppercased(),
            book.chunkCount > 0  ? "\(book.chunkCount) passages" : nil
        ].compactMap { $0 }.joined(separator: " · ")
        bookAttr.keywords = [book.title, book.author, book.fileType, "Ragion"]
            .filter { !$0.isEmpty }

        items.append(CSSearchableItem(
            uniqueIdentifier: spotlightId(bookId: book.id),
            domainIdentifier: domainId,
            attributeSet: bookAttr
        ))

        // Sample chunks for snippet search
        for chunk in chunks.prefix(10) {
            let attr = CSSearchableItemAttributeSet(contentType: .text)
            attr.title = chunk.chapterTitle ?? book.title
            attr.contentDescription = String(chunk.content.prefix(200))
            attr.keywords = [book.title, book.author].filter { !$0.isEmpty }

            items.append(CSSearchableItem(
                uniqueIdentifier: spotlightId(bookId: book.id, chunkId: chunk.id),
                domainIdentifier: domainId,
                attributeSet: attr
            ))
        }

        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    // MARK: - Deindex

    func deindex(bookId: String) {
        // Remove book item + all its chunk items
        let bookItemId = spotlightId(bookId: bookId)
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [bookItemId]
        ) { _ in }
        // Delete by domain prefix — deletes all chunk items for this book
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: ["\(domainId).\(bookId)"]
        ) { _ in }
    }

    func deindexAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainId]
        ) { _ in }
    }

    // MARK: - Helpers

    private func spotlightId(bookId: String, chunkId: String? = nil) -> String {
        if let chunkId { return "book:\(bookId):chunk:\(chunkId)" }
        return "book:\(bookId)"
    }
}
