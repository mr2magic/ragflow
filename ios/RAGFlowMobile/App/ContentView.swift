import SwiftUI

struct ContentView: View {
    @State private var selectedKB: KnowledgeBase?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            KBListView(selectedKB: $selectedKB)
        } content: {
            if let kb = selectedKB {
                LibraryView(kb: kb)
            } else {
                ContentUnavailableView(
                    "Select a Knowledge Base",
                    systemImage: "square.stack.3d.up",
                    description: Text("Choose a knowledge base to see its documents.")
                )
            }
        } detail: {
            if let kb = selectedKB {
                ChatView(kb: kb)
            } else {
                ContentUnavailableView(
                    "Select a Knowledge Base",
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("Select a knowledge base to start chatting.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
