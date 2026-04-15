import WidgetKit
import SwiftUI

@main
struct RAGFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        KBStatusWidget()
        RecentChatWidget()
        QuickQueryWidget()
    }
}

// MARK: - Shared group-defaults access (no GRDB dependency)

enum WidgetGroupDefaults {
    static let suiteName = "group.com.dhorn.ragflowmobile"
    private static var suite: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    static var kbList: [[String: String]] {
        suite.array(forKey: "kbList") as? [[String: String]] ?? []
    }
    static var recentChatTitle: String { suite.string(forKey: "recentChatTitle") ?? "" }
    static var recentChatKBName: String { suite.string(forKey: "recentChatKBName") ?? "" }
    static var totalDocumentCount: Int { suite.integer(forKey: "totalDocumentCount") }
}

// MARK: - Deep-link URL builder

extension URL {
    /// ragflow://kb/{id}  — handled by ContentView .onOpenURL
    static func ragflowKB(id: String) -> URL {
        URL(string: "ragflow://kb/\(id)")!
    }
    static let ragflowHome = URL(string: "ragflow://")!
}
