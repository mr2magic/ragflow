import SwiftUI

struct KBListView: View {
    @Binding var selectedKB: KnowledgeBase?
    @StateObject private var vm = KBListViewModel()
    @State private var showSettings = false

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
                        if kb.id != KnowledgeBase.defaultID {
                            Button("Delete", role: .destructive) {
                                if let idx = vm.kbs.firstIndex(of: kb) {
                                    vm.delete(at: IndexSet(integer: idx))
                                    if selectedKB == kb { selectedKB = nil }
                                }
                            }
                        }
                    }
            }
            .onDelete { offsets in
                if let first = offsets.first, vm.kbs[first] == selectedKB {
                    selectedKB = nil
                }
                vm.delete(at: offsets)
            }
        }
        .navigationTitle("Knowledge Bases")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.showCreateAlert = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
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
