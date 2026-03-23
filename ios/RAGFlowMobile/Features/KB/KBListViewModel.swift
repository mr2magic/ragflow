import SwiftUI

@MainActor
final class KBListViewModel: ObservableObject {
    @Published var kbs: [KnowledgeBase] = []
    @Published var showCreateAlert = false
    @Published var newKBName = ""
    @Published var kbToRename: KnowledgeBase?
    @Published var renameText = ""

    private let db = DatabaseService.shared
    private let haptics = UINotificationFeedbackGenerator()

    init() { reload() }

    func reload() {
        kbs = (try? db.allKBs()) ?? []
    }

    func createKB() {
        let name = newKBName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let kb = KnowledgeBase(id: UUID().uuidString, name: name, createdAt: Date())
        try? db.saveKB(kb)
        newKBName = ""
        reload()
        haptics.notificationOccurred(.success)
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            try? db.deleteKB(kbs[i].id)
        }
        reload()
        haptics.notificationOccurred(.success)
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
