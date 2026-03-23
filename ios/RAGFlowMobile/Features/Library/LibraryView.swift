import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let kb: KnowledgeBase
    @StateObject private var vm: LibraryViewModel
    @ObservedObject private var ragService = RAGService.shared
    @State private var showImportOptions = false

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
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search documents")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $vm.showImporter,
            allowedContentTypes: [.epub, .pdf, .plainText,
                                  UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: true
        ) { result in
            Task { await vm.importFiles(result: result) }
        }
        .confirmationDialog("Import Documents", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button("Browse Files (iPhone & iCloud)") { vm.showImporter = true }
            Button("Import from URL") { vm.showURLEntry = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose from On My iPhone, iCloud Drive, or paste a web link to a PDF or document.")
        }
        .alert("Import from URL", isPresented: $vm.showURLEntry) {
            TextField("https://example.com/report.pdf", text: $vm.urlInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("Import") { Task { await vm.importFromURL() } }
            Button("Cancel", role: .cancel) { vm.urlInput = "" }
        } message: {
            Text("Paste a direct link to a PDF, ePub, or text file.")
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
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)

            Text("No Documents Yet")
                .font(.title2.bold())
                .padding(.bottom, 6)

            Text("Add PDFs, ePubs, or text files to \(kb.name) — then ask questions about them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            // 3-step workflow
            VStack(alignment: .leading, spacing: 14) {
                WorkflowStep(number: "1", icon: "arrow.down.doc.fill", color: .blue,
                             title: "Import", detail: "PDF, ePub, TXT — from Files or a URL")
                WorkflowStep(number: "2", icon: "bolt.fill", color: .orange,
                             title: "Index", detail: "AI chunks and embeds automatically")
                WorkflowStep(number: "3", icon: "bubble.left.and.text.bubble.right.fill", color: .green,
                             title: "Ask", detail: "Chat with cited answers from your corpus")
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)

            Button(action: { showImportOptions = true }) {
                Label("Import Documents", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showImportOptions = true }) {
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
                    if ragService.embedProgress > 0 && ragService.embedProgress < 1 {
                        VStack(spacing: 6) {
                            ProgressView(value: ragService.embedProgress)
                                .frame(width: 180)
                            Text("Embedding \(Int(ragService.embedProgress * 100))%")
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

// MARK: - Workflow Step

private struct WorkflowStep: View {
    let number: String
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)").font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension Book: Hashable {
    public static func == (lhs: Book, rhs: Book) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
