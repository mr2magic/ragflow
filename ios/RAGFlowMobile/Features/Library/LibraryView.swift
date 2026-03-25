import SwiftUI
import UniformTypeIdentifiers
import UIKit

// Pulled out so Swift's type checker doesn't time out inside body.
private let supportedImportTypes: [UTType] = {
    var types: [UTType] = [.pdf, .epub, .plainText, .html, .xml, .json, .commaSeparatedText]
    let extensions = ["md", "mdx", "rtf", "jsonl", "yml", "yaml", "csv", "tsv",
                      "py", "js", "ts", "swift", "sql", "sh"]
    for ext in extensions {
        types.append(UTType(filenameExtension: ext) ?? .plainText)
    }
    return types
}()

// MARK: - UIKit document picker wrapper
// Uses the key window's root view controller so presentation always succeeds,
// regardless of where this representable sits in the SwiftUI view tree.
// A small async delay lets any SwiftUI action-sheet animation finish before
// the system file picker presents over it.
private struct DocumentPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented, onPick: onPick) }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented else { return }

        // Wait long enough for any in-flight confirmation-dialog dismissal animation
        // to fully complete before we push the file picker on top.  One run-loop tick
        // is not enough when the user taps "Browse Files" from inside an action sheet —
        // the sheet is still mid-dismissal and presentedViewController is non-nil.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard context.coordinator.isPresented else { return }

            // Find the topmost non-dismissing view controller in the key window.
            guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })?
                    .windows.first(where: { $0.isKeyWindow }),
                  let root = window.rootViewController else { return }

            var presenter = root
            while let next = presenter.presentedViewController, !next.isBeingDismissed {
                presenter = next
            }
            // Allow presenting when there is no presentedVC, or the existing one is
            // already in the process of being dismissed (safe to present over it).
            let existingVC = presenter.presentedViewController
            guard existingVC == nil || existingVC?.isBeingDismissed == true else { return }

            let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedImportTypes)
            picker.allowsMultipleSelection = true
            picker.shouldShowFileExtensions = true
            picker.delegate = context.coordinator
            presenter.present(picker, animated: true)
        }
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        @Binding var isPresented: Bool
        let onPick: ([URL]) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping ([URL]) -> Void) {
            _isPresented = isPresented
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            onPick(urls)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
            }
            isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented = false
        }
    }
}

struct LibraryView: View {
    let kb: KnowledgeBase
    @StateObject private var vm: LibraryViewModel
    @ObservedObject private var ragService = RAGService.shared
    @State private var showImportOptions = false
    @State private var showImporter = false
    @State private var selectedBook: Book?

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
        .background(
            DocumentPickerPresenter(isPresented: $showImporter) { urls in
                Task { await vm.ingestURLs(urls) }
            }
            .frame(width: 0, height: 0)
        )
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
                    BookRow(book: book)
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
                             title: "Import", detail: "PDF, ePub, DOCX, XLSX, PPTX, EML, HTML, CSV, RTF, JSON, code — from Files or a URL")
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
                    LabeledContent("Added", value: book.addedAt.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Chunks", value: "\(chunks.count)")
                } header: {
                    Text(book.title).font(.headline).textCase(nil).foregroundStyle(.primary)
                }

                Section("Indexed Chunks") {
                    if filteredChunks.isEmpty {
                        Text(searchText.isEmpty ? "No chunks — try re-importing this document." : "No chunks match your search.")
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
            .navigationTitle("Chunk Viewer")
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
