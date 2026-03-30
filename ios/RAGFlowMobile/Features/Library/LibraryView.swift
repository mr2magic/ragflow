import SwiftUI
import UniformTypeIdentifiers

// Pulled out so Swift's type checker doesn't time out inside body.
private let supportedImportTypes: [UTType] = {
    // Abstract parent types — iOS uses conformance so all variants are shown
    // (e.g. .spreadsheet covers .xlsx AND .xls AND .ods, etc.)
    var types: [UTType] = [
        .pdf, .epub,
        .spreadsheet,    // xls, xlsx, ods, numbers, …
        .presentation,   // ppt, pptx, odp, key, …
        .html, .xml, .json, .commaSeparatedText, .plainText,
    ]
    // Explicit extensions — belt-and-suspenders for formats whose abstract type
    // may not be declared on the device, and for formats with no abstract parent.
    let explicit = [
        // Office Open XML + legacy Office
        "docx", "doc", "xlsx", "xls", "pptx", "ppt",
        "odt", "ods", "odp",
        // Email
        "eml", "emlx",
        // Markup / text variants
        "htm", "rtf", "md", "mdx", "jsonl", "yml", "yaml", "tsv",
        // Code
        "py", "js", "ts", "swift", "java", "c", "cpp", "h", "go", "sql", "sh",
    ]
    for ext in explicit {
        if let t = UTType(filenameExtension: ext) { types.append(t) }
    }
    return types
}()

struct LibraryView: View {
    let kb: KnowledgeBase
    let autoImport: Bool
    @StateObject private var vm: LibraryViewModel
    @ObservedObject private var ragService = RAGService.shared
    @State private var showImportOptions = false
    @State private var showImporter = false
    @State private var selectedBook: Book?
    @State private var didAutoImport = false

    init(kb: KnowledgeBase, autoImport: Bool = false) {
        self.kb = kb
        self.autoImport = autoImport
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
        // Apple-standard file importer — handles search, iCloud, presentation context natively.
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: supportedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                // Copy each file to temp while the security scope is active, then release.
                // This prevents lazy-reading parsers (PDFKit, EPUBKit) from hitting the scope
                // after it has expired, which would silently produce empty results.
                let localURLs: [URL] = urls.compactMap { url in
                    guard url.startAccessingSecurityScopedResource() else { return nil }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    return (try? FileManager.default.copyItem(at: url, to: tmp)) != nil ? tmp : nil
                }
                Task { await vm.ingestURLs(localURLs) }
            case .failure(let error):
                vm.errorMessage = error.localizedDescription
                vm.showError = true
            }
        }
        .confirmationDialog("Import Documents", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button("Browse Files (iPhone & iCloud)") { showImporter = true }
            Button("Import from URL") { vm.showURLEntry = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose from On My iPhone, iCloud Drive, or paste a web link to a supported document.")
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
        .sheet(item: $selectedBook) { book in
            DocumentDetailView(book: book)
        }
        .task {
            guard autoImport, !didAutoImport else { return }
            didAutoImport = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            showImporter = true
        }
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
        .confirmationDialog(
            "Delete \"\(vm.bookToDelete?.title ?? "this document")\"?",
            isPresented: Binding(
                get: { vm.bookToDelete != nil || vm.offsetsToDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { vm.confirmDelete() }
            Button("Cancel", role: .cancel) { vm.cancelDelete() }
        } message: {
            Text("This removes the document and all its indexed chunks. This cannot be undone.")
        }
    }

    // MARK: - Document List

    private var bookList: some View {
        List {
            ForEach(vm.filteredBooks) { book in
                Button(action: { selectedBook = book }) {
                    BookRow(book: book, isIndexing: vm.ingestingFilePaths.contains(book.filePath))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename") {
                        vm.renameText = book.title
                        vm.bookToRename = book
                    }
                    Button("Delete", role: .destructive) {
                        vm.requestDelete(book: book)
                    }
                }
            }
            .onDelete { vm.requestDelete(at: $0) }

            Section {
                Button(action: { showImportOptions = true }) {
                    Label("Import Documents", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
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

            Text("Add PDFs, ePubs, Office docs, emails, or text files to \(kb.name) — then ask questions about them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

            // 3-step workflow
            VStack(alignment: .leading, spacing: 14) {
                IngestStepRow(number: "1", icon: "arrow.down.doc.fill", color: .blue,
                             title: "Import", detail: "PDF · ePub · Word · Excel · PowerPoint · LibreOffice · Email · HTML · Markdown · CSV · JSON · YAML · Swift · Python · JS · Go · SQL · shell — from Files or a URL")
                IngestStepRow(number: "2", icon: "bolt.fill", color: .orange,
                             title: "Index", detail: "AI chunks and embeds automatically")
                IngestStepRow(number: "3", icon: "bubble.left.and.text.bubble.right.fill", color: .green,
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
                    if !ragService.ingestPhase.isEmpty {
                        Text(ragService.ingestPhase)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
    var isIndexing: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
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
                    Text(metaLabel)
                    Spacer()
                    Label(book.addedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            statusBadge
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isIndexing {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 24, height: 24)
        } else if book.chunkCount > 0 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.medium)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.medium)
        }
    }

    private var metaLabel: String {
        var parts: [String] = []
        if !book.fileType.isEmpty { parts.append(book.fileType.uppercased()) }
        if book.pageCount > 0 { parts.append("\(book.pageCount)p") }
        if book.wordCount > 0 { parts.append("\(book.wordCount / 1000)k words") }
        parts.append("\(book.chunkCount) passages")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Workflow Step

private struct IngestStepRow: View {
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

// MARK: - Document Detail (Chunk Viewer)

struct DocumentDetailView: View {
    let book: Book
    @State private var chunks: [Chunk] = []
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    private let db = DatabaseService.shared

    private var filteredChunks: [Chunk] {
        guard !searchText.isEmpty else { return chunks }
        return chunks.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !book.author.isEmpty {
                        LabeledContent("Author", value: book.author)
                    }
                    if !book.fileType.isEmpty {
                        LabeledContent("Type", value: book.fileType.uppercased())
                    }
                    if book.pageCount > 0 {
                        LabeledContent("Pages", value: "\(book.pageCount)")
                    }
                    if book.wordCount > 0 {
                        LabeledContent("Words", value: "\(book.wordCount)")
                    }
                    LabeledContent("Passages", value: "\(chunks.count)")
                    LabeledContent("Indexed", value: book.addedAt.formatted(date: .abbreviated, time: .omitted))
                    if !book.sourceURL.isEmpty {
                        LabeledContent("Source URL", value: book.sourceURL)
                    }
                } header: {
                    Text(book.title).font(.headline).textCase(nil).foregroundStyle(.primary)
                }

                Section("Indexed Passages") {
                    if filteredChunks.isEmpty {
                        Text(searchText.isEmpty ? "No passages — try re-importing this document." : "No passages match your search.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredChunks) { chunk in
                            ChunkRowView(chunk: chunk)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search chunks")
            .navigationTitle("Passage Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                chunks = (try? db.chunks(bookId: book.id)) ?? []
            }
        }
    }
}

private struct ChunkRowView: View {
    let chunk: Chunk
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("[\(chunk.position + 1)]")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                if let title = chunk.chapterTitle, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(chunk.content.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(chunk.content)
                .font(.caption)
                .lineLimit(expanded ? nil : 4)
                .foregroundStyle(.primary)
            if chunk.content.count > 200 {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation { expanded.toggle() }
                }
                .font(.caption)
                .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
