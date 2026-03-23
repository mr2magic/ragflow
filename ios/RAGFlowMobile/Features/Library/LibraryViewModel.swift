import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .dateAdded
    @Published var showImporter = false
    @Published var isIngesting = false
    @Published var ingestProgress: String = ""
    @Published var showError = false
    @Published var errorMessage = ""

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

    init() {
        reload()
        Task { await scanDocumentsFolder() }
    }

    func reload() {
        books = (try? db.allBooks()) ?? []
    }

    func scanDocumentsFolder() async {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let existing = Set(books.map { $0.filePath })
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
        let epubs = files.filter {
            ["epub", "pdf"].contains($0.pathExtension.lowercased()) && !existing.contains($0.path)
        }
        guard !epubs.isEmpty else { return }
        await ingest(urls: epubs)
    }

    func importEPUBs(result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            show(error: error.localizedDescription)
        case .success(let urls):
            let accessible = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessible.forEach { $0.stopAccessingSecurityScopedResource() } }
            await ingest(urls: accessible)
        }
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            try? db.deleteBook(filteredBooks[i].id)
        }
        reload()
        haptics.notificationOccurred(.success)
    }

    private func ingest(urls: [URL]) async {
        isIngesting = true
        defer { isIngesting = false; ingestProgress = "" }
        var succeeded = 0
        for (i, url) in urls.enumerated() {
            ingestProgress = "Importing \(i + 1) of \(urls.count)…"
            do {
                _ = try await rag.ingest(epubURL: url)
                succeeded += 1
            } catch {
                show(error: "Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        reload()
        if succeeded > 0 { haptics.notificationOccurred(.success) }
    }

    private func show(error message: String) {
        errorMessage = message
        showError = true
    }
}
