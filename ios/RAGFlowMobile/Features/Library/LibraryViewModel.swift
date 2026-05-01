import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    static let maxDocuments = 50

    @Published var books: [Book] = []
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .dateAdded
    @Published var showURLEntry = false
    @Published var urlInput = ""
    @Published var isIngesting = false
    @Published var ingestProgress: String = ""
    @Published var ingestingFilePaths: Set<String> = []
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var bookToRename: Book?
    @Published var renameText = ""
    @Published var bookToDelete: Book?
    @Published var offsetsToDelete: IndexSet?

    // Duplicate import resolution
    @Published var showDuplicatePrompt = false
    private(set) var duplicateFilenames: [String] = []
    private var pendingImportURLs: [URL] = []

    let kb: KnowledgeBase

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateAdded = "Date Added"
        case title = "Title"
        case author = "Author"
        var id: String { rawValue }
    }

    var filteredBooks: [Book] {
        let sorted: [Book]
        switch sortOrder {
        case .dateAdded: sorted = books.sorted { $0.addedAt > $1.addedAt }
        case .title:     sorted = books.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .author:    sorted = books.sorted { $0.author.localizedCompare($1.author) == .orderedAscending }
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.author.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let db = DatabaseService.shared
    private let rag = RAGService.shared
    private let haptics = UINotificationFeedbackGenerator()

    // Scan once per app session regardless of how many LibraryViewModels are created.
    private static var hasScannedDocumentsFolder = false

    init(kb: KnowledgeBase) {
        self.kb = kb
        reload()
        if !LibraryViewModel.hasScannedDocumentsFolder {
            LibraryViewModel.hasScannedDocumentsFolder = true
            Task { await scanDocumentsFolder() }
        }
    }

    func reload() {
        books = (try? db.allBooks(kbId: kb.id)) ?? []
    }

    func scanDocumentsFolder() async {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let existing = Set(books.map { $0.filePath })
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
        let supported = files.filter {
            ["epub", "pdf", "docx", "xlsx", "pptx", "eml", "ged", "zip"].contains($0.pathExtension.lowercased()) && !existing.contains($0.path)
        }
        guard !supported.isEmpty else { return }
        await ingest(urls: supported)
    }

    func ingestURLs(_ urls: [URL]) async {
        let existingNames = Set(books.map { $0.title.lowercased() })
        let dupes = urls.filter { existingNames.contains($0.deletingPathExtension().lastPathComponent.lowercased()) }
        if !dupes.isEmpty {
            duplicateFilenames = dupes.map { $0.lastPathComponent }
            pendingImportURLs = urls
            showDuplicatePrompt = true
            return
        }
        await ingest(urls: urls)
    }

    func importSkippingDuplicates() async {
        let existingNames = Set(books.map { $0.title.lowercased() })
        let filtered = pendingImportURLs.filter {
            !existingNames.contains($0.deletingPathExtension().lastPathComponent.lowercased())
        }
        clearDuplicateState()
        await ingest(urls: filtered)
    }

    func importReplacingDuplicates() async {
        let existingNames = Set(books.map { $0.title.lowercased() })
        for url in pendingImportURLs {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            if existingNames.contains(name),
               let existing = books.first(where: { $0.title.lowercased() == name }) {
                SpotlightIndexer.shared.deindex(bookId: existing.id)
                try? db.deleteBook(existing.id)
            }
        }
        let urls = pendingImportURLs
        clearDuplicateState()
        reload()
        await ingest(urls: urls)
    }

    func cancelDuplicateImport() {
        clearDuplicateState()
    }

    private func clearDuplicateState() {
        duplicateFilenames = []
        pendingImportURLs = []
        showDuplicatePrompt = false
    }

    func requestDelete(at offsets: IndexSet) {
        offsetsToDelete = offsets
    }

    func requestDelete(book: Book) {
        bookToDelete = book
    }

    func confirmDelete() {
        if let book = bookToDelete {
            SpotlightIndexer.shared.deindex(bookId: book.id)
            try? db.deleteBook(book.id)
            bookToDelete = nil
        } else if let offsets = offsetsToDelete {
            for i in offsets {
                SpotlightIndexer.shared.deindex(bookId: filteredBooks[i].id)
                try? db.deleteBook(filteredBooks[i].id)
            }
            offsetsToDelete = nil
        }
        reload()
        SharedGroupDefaults.syncFromApp()
        haptics.notificationOccurred(.success)
    }

    func cancelDelete() {
        bookToDelete = nil
        offsetsToDelete = nil
    }

    func commitRename() {
        guard let book = bookToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { bookToRename = nil; return }
        var updated = book
        updated.title = name
        try? db.save(updated)
        bookToRename = nil
        renameText = ""
        reload()
    }

    /// Delete the document's existing chunks and re-parse from the stored file path,
    /// applying the KB's current chunking settings. Requires the original file to still
    /// exist on disk (files in the app's Documents folder persist; temp-copy imports may not).
    func reindex(book: Book) async {
        let filePath = book.filePath
        guard FileManager.default.fileExists(atPath: filePath) else {
            show(error: "Original file not found on disk. Please re-import the document to apply new settings.")
            return
        }
        isIngesting = true
        ingestingFilePaths.insert(filePath)
        ingestProgress = "Re-indexing…"
        defer {
            isIngesting = false
            ingestingFilePaths.remove(filePath)
            ingestProgress = ""
        }
        do {
            // Remove existing record (cascades to chunks + FTS index)
            try db.deleteBook(book.id)
            // Re-parse with current KB chunking settings; creates a new book record
            let reindexedBook = try await rag.ingest(url: URL(fileURLWithPath: filePath), kbId: book.kbId)
            let reindexedChunks = (try? db.chunks(bookId: reindexedBook.id)) ?? []
            SpotlightIndexer.shared.index(book: reindexedBook, chunks: reindexedChunks)
            SharedGroupDefaults.syncFromApp()
            reload()
            haptics.notificationOccurred(.success)
        } catch {
            // Restore old record on failure so the document isn't lost
            try? db.save(book)
            show(error: "Re-index failed: \(error.localizedDescription)")
        }
    }

    func importFromURL() async {
        guard availableSlots > 0 else {
            show(error: "This knowledge base has reached its \(LibraryViewModel.maxDocuments)-document limit. Delete some documents before importing more.")
            urlInput = ""
            return
        }
        let urlString = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        urlInput = ""
        guard let url = URL(string: urlString),
              let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            show(error: "Please enter a valid http or https URL.")
            return
        }
        isIngesting = true
        defer { isIngesting = false; ingestProgress = "" }
        ingestProgress = "Resolving…"
        do {
            // Resolve Gutenberg book page URLs to a direct file download.
            let resolvedURL: URL
            if GutenbergResolver.isGutenbergBookPage(url) {
                let book = try await GutenbergResolver.resolve(url)
                resolvedURL = book.downloadURL
            } else {
                resolvedURL = url
            }
            ingestProgress = "Downloading…"
            let (tmpURL, _) = try await URLSession.shared.download(from: resolvedURL)
            let ext = resolvedURL.pathExtension.lowercased().isEmpty ? "pdf" : resolvedURL.pathExtension.lowercased()
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            ingestProgress = "Indexing…"
            let importedBook = try await rag.ingest(url: destURL, kbId: kb.id, sourceURL: urlString)
            let importedChunks = (try? db.chunks(bookId: importedBook.id)) ?? []
            SpotlightIndexer.shared.index(book: importedBook, chunks: importedChunks)
            SharedGroupDefaults.syncFromApp()
            reload()
            haptics.notificationOccurred(.success)
        } catch {
            show(error: "Could not import from URL: \(error.localizedDescription)")
        }
    }

    var availableSlots: Int { max(0, LibraryViewModel.maxDocuments - books.count) }

    private func ingest(urls allURLs: [URL]) async {
        let slots = availableSlots
        guard slots > 0 else {
            show(error: "This knowledge base has reached its \(LibraryViewModel.maxDocuments)-document limit. Delete some documents before importing more.")
            return
        }
        let urls: [URL]
        if allURLs.count > slots {
            show(error: "Only \(slots) slot\(slots == 1 ? "" : "s") remaining — importing the first \(slots) of \(allURLs.count) files.")
            urls = Array(allURLs.prefix(slots))
        } else {
            urls = allURLs
        }
        isIngesting = true
        let coordinator = BackgroundTaskCoordinator.shared
        coordinator.beginImport(fileCount: urls.count)
        let firstFileName = urls.first?.lastPathComponent ?? "file"
        IndexingActivityManager.shared.start(kbName: kb.name, fileName: firstFileName, totalFiles: urls.count)
        defer {
            isIngesting = false
            ingestProgress = ""
            ingestingFilePaths = []
        }
        var succeeded = 0
        for (i, url) in urls.enumerated() {
            ingestProgress = "Importing \(i + 1) of \(urls.count)…"
            ingestingFilePaths.insert(url.path)
            IndexingActivityManager.shared.update(
                fileName: url.lastPathComponent,
                currentFile: i + 1,
                totalFiles: urls.count,
                phase: "Parsing"
            )
            do {
                let book = try await rag.ingest(url: url, kbId: kb.id)
                succeeded += 1
                // Index in Spotlight after successful ingest
                let chunks = (try? db.chunks(bookId: book.id)) ?? []
                SpotlightIndexer.shared.index(book: book, chunks: chunks)
            } catch {
                show(error: "Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
            ingestingFilePaths.remove(url.path)
            coordinator.advanceImport()
            reload()
        }
        coordinator.finishImport(success: succeeded > 0)
        IndexingActivityManager.shared.finish(success: succeeded > 0)
        SharedGroupDefaults.syncFromApp()
        if succeeded > 0 { haptics.notificationOccurred(.success) }
    }

    private func show(error message: String) {
        errorMessage = message
        showError = true
    }
}
