import SwiftUI

/// Compact (iPhone) KB list. Uses a single navigationDestination to avoid
/// multiple competing destinations for the same KnowledgeBase type.
struct PhoneKBListView: View {
    @Binding var handoffKB: KnowledgeBase?
    @StateObject private var vm = KBListViewModel()
    @AppStorage("activeKBId") private var activeKBId: String = ""

    /// Unified nav destination — one state drives all navigation paths:
    /// row taps, new-KB creation (with autoImport), and Handoff resumption.
    @State private var navDest: KBNavDest?

    var body: some View {
        List {
            ForEach(vm.kbs) { kb in
                KBRow(kb: kb, isActive: kb.id == activeKBId)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    activeKBId = kb.id
                    navDest = KBNavDest(kb: kb)
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
            }
        }
        .navigationTitle("Knowledge Bases")
        .navigationDestination(item: $navDest) { dest in
            KBDetailView(kb: dest.kb, initialTab: dest.initialTab, autoImport: dest.autoImport)
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
                if let created = vm.createKB() {
                    navDest = KBNavDest(kb: created, initialTab: 1, autoImport: true)
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
        .onAppear { vm.reload() }
        .onChange(of: handoffKB) { _, kb in
            if let kb { navDest = KBNavDest(kb: kb) }
        }
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

// MARK: - Navigation destination wrapper

/// Wraps a KnowledgeBase with the context needed to open the correct detail tab.
/// Using a distinct Identifiable type ensures SwiftUI has a single, unambiguous
/// navigationDestination registration — avoiding the undefined behaviour that
/// arises from registering multiple destinations for the same KnowledgeBase type.
private struct KBNavDest: Identifiable, Hashable {
    let kb: KnowledgeBase
    var initialTab: Int = 0
    var autoImport: Bool = false

    var id: String { kb.id }

    func hash(into hasher: inout Hasher) { hasher.combine(kb.id) }
    static func == (lhs: KBNavDest, rhs: KBNavDest) -> Bool { lhs.kb.id == rhs.kb.id }
}
