import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var showImporter = false
    @Published var isIngesting = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let db = DatabaseService.shared
    private let rag = RAGService.shared

    init() {
        reload()
        Task { await scanDocumentsFolder() }
    }

    func scanDocumentsFolder() async {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let existing = Set(books.map { $0.filePath })
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
        let epubs = files.filter { $0.pathExtension.lowercased() == "epub" && !existing.contains($0.path) }
        guard !epubs.isEmpty else { return }

        isIngesting = true
        defer { isIngesting = false }
        for url in epubs {
            do {
                _ = try await rag.ingest(epubURL: url)
            } catch {
                show(error: "Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        reload()
    }

    func reload() {
        books = (try? db.allBooks()) ?? []
    }

    func importEPUB(result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            show(error: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            isIngesting = true
            defer { isIngesting = false }

            guard url.startAccessingSecurityScopedResource() else {
                show(error: "Permission denied for selected file.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                _ = try await rag.ingest(epubURL: url)
                reload()
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            try? db.deleteBook(books[i].id)
        }
        books.remove(atOffsets: offsets)
    }

    private func show(error message: String) {
        errorMessage = message
        showError = true
    }
}
