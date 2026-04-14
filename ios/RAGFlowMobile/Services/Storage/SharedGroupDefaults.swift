import Foundation

/// Keys and accessor for the App Group UserDefaults container shared between
/// the main app, the Share Extension, and the Widget Extension.
///
/// App Group: group.com.dhorn.ragflowmobile
enum SharedGroupDefaults {
    static let suiteName = "group.com.dhorn.ragflowmobile"

    private static var suite: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Widget / Share Extension data

    /// Lightweight KB list for display in extensions (id + name only).
    static var kbList: [[String: String]] {
        get { suite.array(forKey: "kbList") as? [[String: String]] ?? [] }
        set { suite.set(newValue, forKey: "kbList") }
    }

    /// Title of the most recent chat session.
    static var recentChatTitle: String {
        get { suite.string(forKey: "recentChatTitle") ?? "" }
        set { suite.set(newValue, forKey: "recentChatTitle") }
    }

    /// KB name of the most recent chat session.
    static var recentChatKBName: String {
        get { suite.string(forKey: "recentChatKBName") ?? "" }
        set { suite.set(newValue, forKey: "recentChatKBName") }
    }

    /// Total indexed document count across all KBs.
    static var totalDocumentCount: Int {
        get { suite.integer(forKey: "totalDocumentCount") }
        set { suite.set(newValue, forKey: "totalDocumentCount") }
    }

    // MARK: - Pending imports (Share Extension → main app)

    struct PendingImport: Codable {
        var id: String
        var kbId: String
        var kbName: String
        var type: ImportType
        var urlString: String       // either a file:// or http(s):// URL
        var displayName: String
        var createdAt: Date

        enum ImportType: String, Codable { case file, url, text }
    }

    static var pendingImports: [PendingImport] {
        get {
            guard let data = suite.data(forKey: "pendingImports"),
                  let items = try? JSONDecoder().decode([PendingImport].self, from: data) else { return [] }
            return items
        }
        set {
            suite.set(try? JSONEncoder().encode(newValue), forKey: "pendingImports")
        }
    }

    static func appendPendingImport(_ item: PendingImport) {
        var current = pendingImports
        current.append(item)
        pendingImports = current
    }

    static func removePendingImport(id: String) {
        pendingImports = pendingImports.filter { $0.id != id }
    }

    // MARK: - Sync from main app

    /// Call after any KB or document change to keep extension data fresh.
    @MainActor
    static func syncFromApp() {
        let kbs = (try? DatabaseService.shared.allKBs()) ?? []
        kbList = kbs.map { ["id": $0.id, "name": $0.name] }
        let totalDocs = kbs.reduce(0) { sum, kb in
            sum + ((try? DatabaseService.shared.allBooks(kbId: kb.id).count) ?? 0)
        }
        totalDocumentCount = totalDocs
    }
}
