import SwiftUI

struct LibraryView: View {
    @StateObject private var vm = LibraryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.books.isEmpty {
                    ContentUnavailableView(
                        "No Books",
                        systemImage: "books.vertical",
                        description: Text("Import an ePub from Files or iCloud Drive.")
                    )
                } else {
                    List {
                        ForEach(vm.books) { book in
                            NavigationLink(destination: ChatView(book: book)) {
                                BookRow(book: book)
                            }
                        }
                        .onDelete { indexSet in
                            vm.delete(at: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { vm.showImporter = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $vm.showImporter,
                allowedContentTypes: [.epub],
                allowsMultipleSelection: false
            ) { result in
                Task { await vm.importEPUB(result: result) }
            }
            .overlay {
                if vm.isIngesting {
                    ProgressView("Ingesting…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Import Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage)
            }
        }
    }
}

private struct BookRow: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.headline)
            if !book.author.isEmpty {
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(book.chunkCount) chunks")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
