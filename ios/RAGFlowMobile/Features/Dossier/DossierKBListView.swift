import SwiftUI

struct DossierKBListView: View {
    @Binding var selectedKB: KnowledgeBase?
    @StateObject private var vm = KBListViewModel()
    @State private var docCounts: [String: Int] = [:]
    @State private var chunkCounts: [String: Int] = [:]
    @State private var showSettings = false      // D-KBL1
    @State private var showWorkflows = false     // D-KBL2

    private let db = DatabaseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            if vm.kbs.isEmpty {
                emptyState
            } else {
                kbList
            }
        }
        .background(DT.manila)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedKB) { kb in
            DossierKBDetailView(kb: kb)
        }
        // Create KB
        .alert("New Knowledge Base", isPresented: $vm.showCreateAlert) {
            TextField("Name", text: $vm.newKBName)
            Button("Create") { createKB() }
            Button("Cancel", role: .cancel) { vm.newKBName = "" }
        }
        // D-KBL6 — Rename sheet
        .sheet(item: $vm.kbToRename) { _ in
            RenameSheet(title: "Rename Knowledge Base", text: $vm.renameText) {
                vm.commitRename()
                loadCounts()
            }
        }
        // D-KBL8 — Retrieval Settings sheet
        .sheet(item: $vm.kbToSettings) { kb in
            KBRetrievalSettingsSheet(kb: kb) { updated in
                vm.saveKBSettings(updated)
            }
        }
        // D-KBL1 — Settings
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // D-KBL2 — Workflows
        .sheet(isPresented: $showWorkflows) {
            NavigationStack {
                WorkflowListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showWorkflows = false }
                        }
                    }
            }
        }
        // D-KBL7 — Delete confirmation
        .confirmationDialog(
            "Delete \"\(vm.kbToDelete?.name ?? "this knowledge base")\"?",
            isPresented: Binding(
                get: { vm.kbToDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                vm.confirmDelete { deleted in
                    if selectedKB?.id == deleted.id { selectedKB = nil }
                }
                loadCounts()
            }
            Button("Cancel", role: .cancel) { vm.cancelDelete() }
        } message: {
            Text("All documents and chat history will be permanently deleted.")
        }
        .onAppear { loadCounts() }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAGION")
                        .font(DT.mono(10, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(DT.stamp)
                    Text("Knowledgebases")
                        .font(DT.serif(26, weight: .semibold))
                        .foregroundStyle(DT.ink)
                }
                Spacer()
                // D-KBL1 — Settings
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                // D-KBL2 — Workflows
                Button { showWorkflows = true } label: {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                // New dossier
                Button { vm.showCreateAlert = true } label: {
                    Text("NEW")
                        .font(DT.mono(10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DT.stamp)
                        .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - KB list

    private var kbList: some View {
        List {
            ForEach(Array(vm.kbs.enumerated()), id: \.element.id) { i, kb in
                DossierKBCard(
                    kb: kb,
                    index: i,
                    docCount: docCounts[kb.id] ?? 0,
                    chunkCount: chunkCounts[kb.id] ?? 0,
                    isSelected: selectedKB?.id == kb.id
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedKB = kb }
                .contextMenu {
                    Button("Rename") {
                        vm.renameText = kb.name
                        vm.kbToRename = kb
                    }
                    Button("Retrieval Settings") {
                        vm.kbToSettings = kb
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        vm.requestDelete(kb: kb)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        vm.requestDelete(kb: kb)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        vm.renameText = kb.name
                        vm.kbToRename = kb
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: DT.pagePadding, bottom: 3, trailing: DT.pagePadding))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DT.manila)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("NO KNOWLEDGEBASES")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Tap NEW to create your first knowledge base.")
                .font(DT.serif(15))
                .italic()
                .foregroundStyle(DT.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func createKB() {
        let name = vm.newKBName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        vm.createKB()
        loadCounts()
    }

    private func loadCounts() {
        vm.reload()
        for kb in vm.kbs {
            let books = (try? db.allBooks(kbId: kb.id)) ?? []
            docCounts[kb.id] = books.count
            chunkCounts[kb.id] = books.reduce(0) { $0 + $1.chunkCount }
        }
    }
}
