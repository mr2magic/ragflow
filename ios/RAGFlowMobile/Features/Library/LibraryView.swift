import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let kb: KnowledgeBase
    @StateObject private var vm: LibraryViewModel

    init(kb: KnowledgeBase) {
        self.kb = kb
        _vm = StateObject(wrappedValue: LibraryViewModel(kb: kb))
    }

    var body: some View {
        Group {
            if vm.books.isEmpty && !vm.isIngesting {
                emptyState
            } else {
                bookList
            }
        }
        .navigationTitle(kb.name)
        .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search documents")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $vm.showImporter,
            allowedContentTypes: [.epub, .pdf],
            allowsMultipleSelection: true
        ) { result in
            Task { await vm.importFiles(result: result) }
        }
        .overlay { ingestOverlay }
        .alert("Import Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
        .alert("Rename Document", isPresented: Binding(
            get: { vm.bookToRename != nil },
            set: { if !$0 { vm.bookToRename = nil } }
        )) {
            TextField("Title", text: $vm.renameText)
            Button("Save") { vm.commitRename() }
            Button("Cancel", role: .cancel) { vm.bookToRename = nil }
        }
    }

    // MARK: - Document List

    private var bookList: some View {
        List {
            ForEach(vm.filteredBooks) { book in
                BookRow(book: book)
                    .contextMenu {
                        Button("Rename") {
                            vm.renameText = book.title
                            vm.bookToRename = book
                        }
                        Button("Delete", role: .destructive) {
                            vm.delete(book: book)
                        }
                    }
            }
            .onDelete { vm.delete(at: $0) }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: vm.filteredBooks.map(\.id))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            Text("No Documents Yet")
                .font(.title2.bold())

            Text("Import ePubs or PDFs to start chatting with \(kb.name).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { vm.showImporter = true }) {
                Label("Import Documents", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { vm.showImporter = true }) {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker("Sort By", selection: $vm.sortOrder) {
                    ForEach(LibraryViewModel.SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
    }

    // MARK: - Ingest Overlay

    @ViewBuilder
    private var ingestOverlay: some View {
        if vm.isIngesting {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(vm.ingestProgress.isEmpty ? "Importing…" : vm.ingestProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if RAGService.shared.embedProgress > 0 && RAGService.shared.embedProgress < 1 {
                        VStack(spacing: 6) {
                            ProgressView(value: RAGService.shared.embedProgress)
                                .frame(width: 180)
                            Text("Embedding \(Int(RAGService.shared.embedProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

// MARK: - Book Row

private struct BookRow: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.headline)
                .lineLimit(2)
            if !book.author.isEmpty {
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(book.chunkCount) chunks", systemImage: "square.stack")
                Label(book.addedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

extension Book: Hashable {
    public static func == (lhs: Book, rhs: Book) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
