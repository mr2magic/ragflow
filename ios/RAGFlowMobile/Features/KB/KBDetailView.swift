import SwiftUI

/// Detail view for a selected Knowledge Base: Chat history and Documents as bottom tabs.
struct KBDetailView: View {
    let kb: KnowledgeBase
    var initialTab: Int = 0
    var autoImport: Bool = false

    @State private var selectedTab: Int

    init(kb: KnowledgeBase, initialTab: Int = 0, autoImport: Bool = false) {
        self.kb = kb
        self.initialTab = initialTab
        self.autoImport = autoImport
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ConversationsListView(kb: kb)
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
            .tag(0)

            LibraryView(kb: kb, autoImport: autoImport)
                .tabItem { Label("Documents", systemImage: "folder") }
                .tag(1)
        }
        .toolbar(.hidden, for: .tabBar) // hides the outer Knowledge Bases/Settings tab bar
    }
}
