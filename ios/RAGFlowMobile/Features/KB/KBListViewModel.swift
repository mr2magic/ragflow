import SwiftUI

@MainActor
final class KBListViewModel: ObservableObject {
    @Published var kbs: [KnowledgeBase] = []
    @Published var showCreateAlert = false
    @Published var newKBName = ""
    @Published var kbToRename: KnowledgeBase?
    @Published var renameText = ""
    @Published var kbToDelete: KnowledgeBase?

    private let db = DatabaseService.shared
    private let haptics = UINotificationFeedbackGenerator()

    init() { reload() }

    func reload() {
        kbs = (try? db.allKBs()) ?? []
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

    #if DEBUG
    func seedDummy() {
        try? db.seedDummyData()
        reload()
        haptics.notificationOccurred(.success)
    }
    #endif

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
