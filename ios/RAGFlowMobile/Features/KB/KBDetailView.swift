import SwiftUI

/// Detail view for a selected Knowledge Base: Chats and Documents as bottom tabs.
/// On iPhone, a ⋯ menu in the nav bar provides quick access to Settings and Workflows
/// since the outer tab bar is hidden while inside a KB.
struct KBDetailView: View {
    let kb: KnowledgeBase
    var initialTab: Int = 0
    var autoImport: Bool = false

    @State private var selectedTab: Int
    @State private var showSettings = false
    @State private var showWorkflows = false
    @Environment(\.horizontalSizeClass) private var sizeClass

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
                    .toolbar { kbAccessMenu }
            }
            .tabItem { Label("Chats", systemImage: "bubble.left.and.text.bubble.right") }
            .tag(0)

            NavigationStack {
                LibraryView(kb: kb, autoImport: autoImport)
                    .toolbar { kbAccessMenu }
            }
            .tabItem { Label("Documents", systemImage: "folder") }
            .tag(1)
        }
        .toolbar(.hidden, for: .tabBar) // hides the outer Knowledge Bases/Settings tab bar
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showWorkflows) {
            NavigationStack {
                WorkflowListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showWorkflows = false }
                        }
                    }
            }
        }
    }

    /// On iPhone (compact), adds a ⋯ menu to the leading nav bar area so users can reach
    /// Settings and Workflows without tapping Back. Hidden on iPad where the sidebar already
    /// provides access via the KBListView toolbar.
    @ToolbarContentBuilder
    private var kbAccessMenu: some ToolbarContent {
        if sizeClass == .compact {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button { showWorkflows = true } label: {
                        Label("Workflows", systemImage: "cpu")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }
}
