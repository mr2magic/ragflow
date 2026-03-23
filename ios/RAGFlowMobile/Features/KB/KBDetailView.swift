import SwiftUI

/// iPhone detail view for a selected KB: Library and Chat as bottom tabs.
struct KBDetailView: View {
    let kb: KnowledgeBase

    var body: some View {
        TabView {
            ChatView(kb: kb)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }

            LibraryView(kb: kb)
                .tabItem { Label("Documents", systemImage: "folder") }
        }
        .toolbar(.hidden, for: .tabBar) // hides the outer Library/Settings tab bar while in KB detail
    }
}
