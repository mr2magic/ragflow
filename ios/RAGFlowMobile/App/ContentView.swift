import SwiftUI

struct ContentView: View {
    @State private var selectedBook: Book?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibraryView(selectedBook: $selectedBook)
        } detail: {
            if let book = selectedBook {
                ChatView(book: book)
            } else {
                ContentUnavailableView(
                    "Select a Book",
                    systemImage: "text.book.closed",
                    description: Text("Choose a book from your library to start chatting.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
