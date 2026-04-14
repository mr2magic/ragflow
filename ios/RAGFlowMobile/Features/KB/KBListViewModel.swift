import SwiftUI

@MainActor
final class KBListViewModel: ObservableObject {
    @Published var kbs: [KnowledgeBase] = []
    @Published var showCreateAlert = false
    @Published var newKBName = ""
    @Published var kbToRename: KnowledgeBase?
    @Published var renameText = ""
    @Published var kbToDelete: KnowledgeBase?
    @Published var kbToSettings: KnowledgeBase?

    private let db = DatabaseService.shared
    private let haptics = UINotificationFeedbackGenerator()

    init() { reload() }

    func reload() {
        let all = (try? db.allKBs()) ?? []
        if let filter = FocusFilterStore.visibleKBIds {
            kbs = all.filter { filter.contains($0.id) }
        } else {
            kbs = all
        }
    }

    @discardableResult
    func createKB() -> KnowledgeBase? {
        let name = newKBName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let kb = KnowledgeBase(id: UUID().uuidString, name: name, createdAt: Date())
        try? db.saveKB(kb)
        newKBName = ""
        reload()
        haptics.notificationOccurred(.success)
        return kb
    }

    func requestDelete(at offsets: IndexSet) {
        if let first = offsets.first {
            kbToDelete = kbs[first]
        }
    }

    func requestDelete(kb: KnowledgeBase) {
        kbToDelete = kb
    }

    func confirmDelete(onDeleted: ((KnowledgeBase) -> Void)? = nil) {
        guard let kb = kbToDelete else { return }
        try? db.deleteKB(kb.id)
        onDeleted?(kb)
        kbToDelete = nil
        reload()
        haptics.notificationOccurred(.success)
    }

    func cancelDelete() {
        kbToDelete = nil
    }

    func saveKBSettings(_ kb: KnowledgeBase) {
        try? db.saveKB(kb)
        kbToSettings = nil
        reload()
    }

    func commitRename() {
        guard let kb = kbToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { kbToRename = nil; return }
        var updated = kb
        updated.name = name
        try? db.saveKB(updated)
        kbToRename = nil
        renameText = ""
        reload()
    }
}
