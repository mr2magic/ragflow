import SwiftUI

/// Compact (iPhone) KB list. Uses NavigationLink → KBDetailView.
/// Reuses KBListViewModel for all CRUD logic.
struct PhoneKBListView: View {
    @Binding var handoffKB: KnowledgeBase?
    @StateObject private var vm = KBListViewModel()
    @State private var newKBDestination: KnowledgeBase?

    var body: some View {
        List {
            ForEach(vm.kbs) { kb in
                NavigationLink(value: kb) {
                    Label(kb.name, systemImage: "square.stack.3d.up")
                }
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
        .navigationDestination(for: KnowledgeBase.self) { kb in
            KBDetailView(kb: kb)
        }
        .navigationDestination(item: $newKBDestination) { kb in
            KBDetailView(kb: kb, initialTab: 1, autoImport: true)
        }
        .navigationDestination(item: $handoffKB) { kb in
            KBDetailView(kb: kb)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.showCreateAlert = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        // MARK: - Create KB
        .sheet(isPresented: $vm.showCreateAlert) {
            CreateKBSheet(name: $vm.newKBName) {
                newKBDestination = vm.createKB()
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
            Button("Delete", role: .destructive) { vm.confirmDelete() }
            Button("Cancel", role: .cancel) { vm.cancelDelete() }
        } message: {
            Text("All documents and chat history in this knowledge base will be permanently deleted.")
        }
    }
}
