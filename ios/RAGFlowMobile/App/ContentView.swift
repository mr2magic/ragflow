import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // iPad / regular state
    @State private var selectedKB: KnowledgeBase?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if sizeClass == .compact {
                phoneLayout
            } else {
                padLayout
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
        }
    }

    // MARK: - iPhone / Compact

    /// Tab 1: KB list → drill into KB → Library + Chat tabs
    /// Tab 2: Settings
    private var phoneLayout: some View {
        TabView {
            NavigationStack {
                PhoneKBListView()
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }

    // MARK: - iPad / Regular

    /// 3-column split: KB sidebar | Library | Chat
    /// Settings accessible via gear button in the sidebar toolbar.
    private var padLayout: some View {
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
