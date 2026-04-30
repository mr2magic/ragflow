import SwiftUI

struct KBListView: View {
    @Binding var selectedKB: KnowledgeBase?
    @Binding var pendingAutoImportKBId: String?
    @StateObject private var vm = KBListViewModel()
    @AppStorage("activeKBId") private var activeKBId: String = ""
    @State private var showSettings = false
    @State private var showWorkflows = false

    var body: some View {
        List(selection: $selectedKB) {
            ForEach(vm.kbs) { kb in
                KBRow(kb: kb, isActive: kb.id == activeKBId)
                .tag(kb)
                    .contextMenu {
                        Button("Rename") {
                            vm.renameText = kb.name
                            vm.kbToRename = kb
                        }
                        Button("Retrieval Settings") {
                            vm.kbToSettings = kb
                        }
                        Button("Delete", role: .destructive) {
                            vm.requestDelete(kb: kb)
                        }
                    }
            }
            .onDelete { vm.requestDelete(at: $0) }
        }
        .navigationTitle("Knowledge Bases")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.showCreateAlert = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                HStack {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("btn.settings")
                    Button { showWorkflows = true } label: {
                        Image(systemName: "cpu")
                    }
                    .accessibilityLabel("Workflows")
                    .accessibilityIdentifier("btn.workflows")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
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
        // MARK: - Create KB
        .sheet(isPresented: $vm.showCreateAlert) {
            CreateKBSheet(name: $vm.newKBName) {
                if let kb = vm.createKB() {
                    pendingAutoImportKBId = kb.id
                    selectedKB = kb
                }
            }
        }
        // MARK: - Rename KB
        .sheet(item: $vm.kbToRename) { _ in
            RenameSheet(title: "Rename Knowledge Base", text: $vm.renameText) {
                vm.commitRename()
            }
        }
        .sheet(item: $vm.kbToSettings) { kb in
            KBRetrievalSettingsSheet(kb: kb) { updated in
                vm.saveKBSettings(updated)
            }
        }
        .onChange(of: selectedKB) { _, kb in if let kb { activeKBId = kb.id } }
        .onAppear { vm.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .focusFilterChanged)) { _ in
            vm.reload()
        }
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
            }
            Button("Cancel", role: .cancel) { vm.cancelDelete() }
        } message: {
            Text("All documents and chat history in this knowledge base will be permanently deleted.")
        }
    }
}

struct KBRow: View {
    let kb: KnowledgeBase
    let isActive: Bool

    var body: some View {
        HStack {
            Label(kb.name, systemImage: "square.stack.3d.up")
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
                .opacity(isActive ? 1 : 0)
        }
    }
}
