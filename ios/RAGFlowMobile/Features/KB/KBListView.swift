import SwiftUI

struct KBListView: View {
    @Binding var selectedKB: KnowledgeBase?
    @StateObject private var vm = KBListViewModel()
    @State private var showSettings = false
    @State private var showWorkflows = false

    var body: some View {
        List(selection: $selectedKB) {
            ForEach(vm.kbs) { kb in
                Label(kb.name, systemImage: "square.stack.3d.up")
                    .tag(kb)
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
                    Button { showWorkflows = true } label: {
                        Image(systemName: "cpu")
                    }
                }
            }
            #if DEBUG
            ToolbarItem(placement: .secondaryAction) {
                Button("Seed Test Data") { vm.seedDummy() }
            }
            #endif
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
        .alert("New Knowledge Base", isPresented: $vm.showCreateAlert) {
            TextField("Name", text: $vm.newKBName)
            Button("Create") {
                if let kb = vm.createKB() { selectedKB = kb }
            }
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
