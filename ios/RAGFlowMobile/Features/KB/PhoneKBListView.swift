import SwiftUI

/// Compact (iPhone) KB list. Uses NavigationLink → KBDetailView.
/// Reuses KBListViewModel for all CRUD logic.
struct PhoneKBListView: View {
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
            KBDetailView(kb: kb, initialTab: 1)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.showCreateAlert = true } label: {
                    Image(systemName: "plus")
                }
            }
            #if DEBUG
            ToolbarItem(placement: .secondaryAction) {
                Button("Seed Test Data") { vm.seedDummy() }
            }
            #endif
        }
        .alert("New Knowledge Base", isPresented: $vm.showCreateAlert) {
            TextField("Name", text: $vm.newKBName)
            Button("Create") { newKBDestination = vm.createKB() }
            Button("Cancel", role: .cancel) { vm.newKBName = "" }
        }
        .alert("Rename", isPresented: Binding(
            get: { vm.kbToRename != nil },
            set: { if !$0 { vm.kbToRename = nil } }
        )) {
            TextField("Name", text: $vm.renameText)
            Button("Save") { vm.commitRename() }
            Button("Cancel", role: .cancel) { vm.kbToRename = nil }
        }
        .onAppear { vm.reload() }
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
