import SwiftUI

/// iPhone detail view for a selected KB: Library and Chat as bottom tabs.
struct KBDetailView: View {
    let kb: KnowledgeBase

    var body: some View {
        TabView {
            LibraryView(kb: kb)
                .tabItem { Label("Library", systemImage: "books.vertical") }

            ChatView(kb: kb)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
        }
    }
}
