import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
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
            ["epub", "pdf", "docx", "xlsx", "pptx", "eml"].contains($0.pathExtension.lowercased()) && !existing.contains($0.path)
        }
        guard !supported.isEmpty else { return }
        await ingest(urls: supported)
    }

    func ingestURLs(_ urls: [URL]) async {
        await ingest(urls: urls)
    }

    func importFiles(result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            show(error: error.localizedDescription)
        case .success(let urls):
            // Start security scope for all URLs; only release the ones that returned true.
            // Files from "On My iPhone" return false (no scoping needed) but are still readable.
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            await ingest(urls: urls)
        }
    }

    func requestDelete(at offsets: IndexSet) {
        offsetsToDelete = offsets
    }

    func requestDelete(book: Book) {
        bookToDelete = book
    }

    func confirmDelete() {
        if let book = bookToDelete {
            try? db.deleteBook(book.id)
            bookToDelete = nil
        } else if let offsets = offsetsToDelete {
            for i in offsets { try? db.deleteBook(filteredBooks[i].id) }
            offsetsToDelete = nil
        }
        reload()
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

    func importFromURL() async {
        let urlString = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        urlInput = ""
        guard let url = URL(string: urlString),
              let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            show(error: "Please enter a valid http or https URL.")
            return
        }
        isIngesting = true
        defer { isIngesting = false; ingestProgress = "" }
        ingestProgress = "Downloading…"
        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: url)
            let ext = url.pathExtension.lowercased().isEmpty ? "pdf" : url.pathExtension.lowercased()
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            ingestProgress = "Indexing…"
            _ = try await rag.ingest(url: destURL, kbId: kb.id, sourceURL: urlString)
            reload()
            haptics.notificationOccurred(.success)
        } catch {
            show(error: "Could not import from URL: \(error.localizedDescription)")
        }
    }

    private func ingest(urls: [URL]) async {
        isIngesting = true
        let coordinator = BackgroundTaskCoordinator.shared
        coordinator.beginImport(fileCount: urls.count)
        defer {
            isIngesting = false
            ingestProgress = ""
            ingestingFilePaths = []
        }
        var succeeded = 0
        for (i, url) in urls.enumerated() {
            ingestProgress = "Importing \(i + 1) of \(urls.count)…"
            ingestingFilePaths.insert(url.path)
            do {
                _ = try await rag.ingest(url: url, kbId: kb.id)
                succeeded += 1
            } catch {
                show(error: "Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
            ingestingFilePaths.remove(url.path)
            coordinator.advanceImport()
            reload()
        }
        coordinator.finishImport(success: succeeded > 0)
        if succeeded > 0 { haptics.notificationOccurred(.success) }
    }

    private func show(error message: String) {
        errorMessage = message
        showError = true
    }
}
