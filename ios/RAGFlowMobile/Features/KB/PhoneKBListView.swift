import SwiftUI

/// Compact (iPhone) KB list. Uses NavigationLink → KBDetailView.
/// Reuses KBListViewModel for all CRUD logic.
struct PhoneKBListView: View {
    @StateObject private var vm = KBListViewModel()

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
                    if kb.id != KnowledgeBase.defaultID {
                        Button("Delete", role: .destructive) {
                            if let idx = vm.kbs.firstIndex(of: kb) {
                                vm.delete(at: IndexSet(integer: idx))
                            }
                        }
                    }
                }
            }
            .onDelete { vm.delete(at: $0) }
        }
        .navigationTitle("Knowledge Bases")
        .navigationDestination(for: KnowledgeBase.self) { kb in
            KBDetailView(kb: kb)
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
            Button("Create") { vm.createKB() }
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
    }
}
