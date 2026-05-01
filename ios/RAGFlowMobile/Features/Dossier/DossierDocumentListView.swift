import SwiftUI
import UniformTypeIdentifiers

// Pulled out to avoid type-checker timeout inside body.
private let dossierImportTypes: [UTType] = {
    var types: [UTType] = [
        .pdf, .epub,
        .spreadsheet,
        .presentation,
        .html, .xml, .json, .commaSeparatedText, .plainText,
    ]
    let explicit = [
        "docx", "doc", "xlsx", "xls", "pptx", "ppt",
        "odt", "ods", "odp",
        "eml", "emlx",
        "htm", "rtf", "md", "mdx", "jsonl", "yml", "yaml", "tsv",
        "py", "js", "ts", "swift", "java", "c", "cpp", "h", "go", "sql", "sh",
        "ged", "zip",
    ]
    for ext in explicit {
        if let t = UTType(filenameExtension: ext) { types.append(t) }
    }
    return types
}()

struct DossierDocumentListView: View {
    let kb: KnowledgeBase

    @StateObject private var vm: LibraryViewModel
    @ObservedObject private var ragService = RAGService.shared

    // D-DOC6 — chunk viewer
    @State private var selectedBook: Book?

    // Import orchestration (D-DOC1, D-DOC9, D-DOC10, D-DOC11, D-DOC12)
    @State private var showImportOptions = false
    private enum FileImportMode { case documents, kbArchive }
    @State private var activeImportMode: FileImportMode?
    @State private var showCameraScanner = false
    @State private var isDropTargeted = false

    // KB archive export/import (D-DOC12)
    @State private var kbExportURL: URL?
    @State private var showKBExportSheet = false
    @State private var kbExportError: String?
    @State private var showKBExportError = false
    @State private var kbImportError: String?
    @State private var showKBImportError = false

    private var fileImporterBinding: Binding<Bool> {
        Binding(get: { activeImportMode != nil }, set: { if !$0 { activeImportMode = nil } })
    }

    private var activeImportTypes: [UTType] {
        activeImportMode == .kbArchive
            ? [UTType("com.dhorn.ragflowmobile.ragflow-kb") ?? UTType(filenameExtension: "ragflow-kb") ?? .json]
            : dossierImportTypes
    }

    init(kb: KnowledgeBase) {
        self.kb = kb
        _vm = StateObject(wrappedValue: LibraryViewModel(kb: kb))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            searchBar          // D-DOC2
            if vm.filteredBooks.isEmpty && !vm.isIngesting {
                emptyState
            } else {
                bookList
            }
        }
        .background(DT.manila)
        // D-DOC1 / D-DOC11 — import options
        .confirmationDialog("Import Documents", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button("Browse Files (iPhone & iCloud)") { activeImportMode = .documents }
            Button("Import from URL") { vm.showURLEntry = true }
            if isDocumentScanningAvailable {
                Button("Scan Document") { showCameraScanner = true }         // D-DOC10
            }
            Button("Import Knowledge Base Archive") { activeImportMode = .kbArchive } // D-DOC12
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose from On My iPhone, iCloud Drive, or paste a web link to a supported document.")
        }
        .fileImporter(
            isPresented: fileImporterBinding,
            allowedContentTypes: activeImportTypes,
            allowsMultipleSelection: activeImportMode == .documents
        ) { result in
            switch activeImportMode {
            case .kbArchive: handleKBImport(result: result)
            default:         handleFileImport(result: result)
            }
        }
        // D-DOC10 — camera scan
        .fullScreenCover(isPresented: $showCameraScanner) {
            DocumentCameraView(kbId: kb.id)
        }
        // D-DOC11 — URL import
        .sheet(isPresented: $vm.showURLEntry) {
            URLImportSheet(urlInput: $vm.urlInput) {
                Task { await vm.importFromURL() }
            }
        }
        // D-DOC6 — chunk viewer
        .sheet(item: $selectedBook) { book in
            DocumentDetailView(book: book)
        }
        // D-DOC12 — KB export share sheet
        .sheet(isPresented: $showKBExportSheet) {
            if let url = kbExportURL { ShareSheet(url: url) }
        }
        // D-DOC4 — rename sheet
        .sheet(item: $vm.bookToRename) { _ in
            RenameSheet(title: "Rename Document", text: $vm.renameText) {
                vm.commitRename()
            }
        }
        // D-DOC4/5 — delete confirmation
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
        .confirmationDialog(
            "Duplicate Document\(vm.duplicateFilenames.count == 1 ? "" : "s") Found",
            isPresented: $vm.showDuplicatePrompt,
            titleVisibility: .visible
        ) {
            Button("Replace Existing", role: .destructive) { Task { await vm.importReplacingDuplicates() } }
            Button("Skip Duplicates") { Task { await vm.importSkippingDuplicates() } }
            Button("Cancel", role: .cancel) { vm.cancelDuplicateImport() }
        } message: {
            Text("Already in this knowledge base: \(vm.duplicateFilenames.joined(separator: ", ")). Replace the existing version or skip?")
        }
        .alert("Export Failed", isPresented: $showKBExportError) {
            Button("OK", role: .cancel) {}
        } message: { Text(kbExportError ?? "") }
        .alert("Import Failed", isPresented: $showKBImportError) {
            Button("OK", role: .cancel) {}
        } message: { Text(kbImportError ?? "") }
        .alert("Import Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: { Text(vm.errorMessage) }
        // D-DOC7 — ingest overlay
        .overlay { ingestOverlay }
        .onReceive(NotificationCenter.default.publisher(for: .scanImportComplete)) { note in
            guard (note.object as? String) == kb.id else { return }
            vm.reload()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DOCUMENTS")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                capacityLabel      // D-DOC8
                sortMenu           // D-DOC3
                // D-DOC12 — export KB
                Button { exportKB() } label: {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .accessibilityLabel("Export knowledge base")
                // D-DOC1 — import
                Button { showImportOptions = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DT.stamp)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .accessibilityLabel("Import documents")
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // D-DOC8 — capacity indicator
    private var capacityLabel: some View {
        let total = vm.books.count
        let cap = LibraryViewModel.maxDocuments
        let nearCap = total >= cap - 5
        return HStack(spacing: 3) {
            if nearCap {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            Text("\(total)/\(cap)")
                .font(DT.mono(10))
                .tracking(0.5)
                .foregroundStyle(nearCap ? .orange : DT.inkFaint)
        }
    }

    // D-DOC3 — sort menu
    private var sortMenu: some View {
        Menu {
            ForEach(LibraryViewModel.SortOrder.allCases) { order in
                Button {
                    vm.sortOrder = order
                } label: {
                    if vm.sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Text(order.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: vm.sortOrder == .dateAdded
                  ? "arrow.up.arrow.down"
                  : "arrow.up.arrow.down.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DT.inkSoft)
        }
        .padding(.leading, 6)
        .accessibilityLabel("Sort documents — \(vm.sortOrder.rawValue)")
    }

    // D-DOC2 — search bar
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DT.inkFaint)
                .accessibilityHidden(true)
            TextField("Search documents", text: $vm.searchText)
                .font(DT.serif(13))
                .foregroundStyle(DT.ink)
            if !vm.searchText.isEmpty {
                Button { vm.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DT.inkFaint)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
        .padding(.horizontal, DT.pagePadding)
        .padding(.bottom, 6)
    }

    // MARK: - Book list

    private var bookList: some View {
        List {
            // D-DOC9 — iPad drag-and-drop drop target banner
            if isDropTargeted {
                HStack {
                    Image(systemName: "arrow.down.doc.fill")
                        .accessibilityHidden(true)
                    Text("Drop to import")
                        .font(DT.mono(11, weight: .bold))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DT.stamp.opacity(0.12))
                .foregroundStyle(DT.stamp)
                .listRowBackground(DT.manila)
                .listRowSeparator(.hidden)
            }

            ForEach(Array(vm.filteredBooks.enumerated()), id: \.element.id) { i, book in
                DossierDocumentRow(
                    book: book,
                    index: i,
                    isSelected: selectedBook?.id == book.id,
                    isIndexing: vm.ingestingFilePaths.contains(book.filePath)  // D-DOC13
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedBook = book }   // D-DOC6
                // D-DOC4 — context menu
                .contextMenu {
                    Button("Rename") {
                        vm.renameText = book.title
                        vm.bookToRename = book
                    }
                    Button("Re-index") {
                        Task { await vm.reindex(book: book) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        vm.requestDelete(book: book)
                    }
                }
                // UI9 — swipe actions
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        vm.requestDelete(book: book)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        vm.renameText = book.title
                        vm.bookToRename = book
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .listRowBackground(DT.card)
                .listRowSeparatorTint(DT.rule)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DT.manila)
        // D-DOC9 — iPad drag-and-drop
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    let tmpDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                    let tmp = tmpDir.appendingPathComponent(url.lastPathComponent)
                    let copied = (try? FileManager.default.copyItem(at: url, to: tmp)) != nil
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    guard copied else { return }
                    Task { @MainActor in await vm.ingestURLs([tmp]) }
                }
            }
            return true
        }
    }

    // MARK: - Empty state (D-DOC1)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 44))
                .foregroundStyle(DT.inkFaint)
            Text("NO DOCUMENTS")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Import PDFs, ePubs, Office docs, emails, or text files to start building your dossier.")
                .font(DT.serif(14))
                .italic()
                .foregroundStyle(DT.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showImportOptions = true } label: {
                Text("IMPORT DOCUMENTS")
                    .font(DT.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DT.stamp)
                    .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    let tmpDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                    let tmp = tmpDir.appendingPathComponent(url.lastPathComponent)
                    let copied = (try? FileManager.default.copyItem(at: url, to: tmp)) != nil
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    guard copied else { return }
                    Task { @MainActor in await vm.ingestURLs([tmp]) }
                }
            }
            return true
        }
    }

    // MARK: - Ingest overlay (D-DOC7)

    @ViewBuilder
    private var ingestOverlay: some View {
        if vm.isIngesting {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(DT.stamp)
                    Text(vm.ingestProgress.isEmpty ? "Importing…" : vm.ingestProgress)
                        .font(DT.mono(12))
                        .foregroundStyle(DT.ink)
                    if !ragService.ingestPhase.isEmpty {
                        Text(ragService.ingestPhase)
                            .font(DT.mono(10))
                            .foregroundStyle(DT.inkSoft)
                    }
                    if ragService.embedProgress > 0 && ragService.embedProgress < 1 {
                        VStack(spacing: 6) {
                            ProgressView(value: ragService.embedProgress)
                                .frame(width: 180)
                                .tint(DT.stamp)
                            Text("Embedding \(Int(ragService.embedProgress * 100))%")
                                .font(DT.mono(10))
                                .foregroundStyle(DT.inkSoft)
                        }
                    }
                }
                .padding(32)
                .background(DT.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DT.rule, lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Import handlers

    private func exportKB() {
        do {
            kbExportURL = try ExportImportService.shared.kbExportURL(for: kb.id, kbName: kb.name)
            showKBExportSheet = true
        } catch {
            kbExportError = error.localizedDescription
            showKBExportError = true
        }
    }

    private func handleKBImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("ragflow-kb")
            guard (try? FileManager.default.copyItem(at: url, to: tmp)) != nil else {
                kbImportError = "Could not read the file."
                showKBImportError = true
                return
            }
            Task {
                do {
                    _ = try await ExportImportService.shared.importKB(from: tmp)
                    vm.reload()
                } catch {
                    kbImportError = error.localizedDescription
                    showKBImportError = true
                }
            }
        case .failure(let error):
            kbImportError = error.localizedDescription
            showKBImportError = true
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let localURLs: [URL] = urls.compactMap { url in
                guard url.startAccessingSecurityScopedResource() else { return nil }
                defer { url.stopAccessingSecurityScopedResource() }
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let tmp = tmpDir.appendingPathComponent(url.lastPathComponent)
                return (try? FileManager.default.copyItem(at: url, to: tmp)) != nil ? tmp : nil
            }
            Task { await vm.ingestURLs(localURLs) }
        case .failure(let error):
            vm.errorMessage = error.localizedDescription
            vm.showError = true
        }
    }
}
