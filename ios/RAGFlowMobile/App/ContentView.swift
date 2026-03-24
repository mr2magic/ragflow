import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // iPad / regular state
    @State private var selectedKB: KnowledgeBase?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showPadSettings = false

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
    /// Tab 2: Workflows
    /// Tab 3: Settings
    private var phoneLayout: some View {
        TabView {
            NavigationStack {
                PhoneKBListView()
            }
            .tabItem { Label("Knowledge Bases", systemImage: "square.stack.3d.up") }

            NavigationStack {
                WorkflowListView()
            }
            .tabItem { Label("Workflows", systemImage: "gearshape.2") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }

    // MARK: - iPad / Regular

    /// 2-column split: KB sidebar | Chat + Documents tabs
    /// Using 2 columns avoids showing two identical "Select a KB" placeholders on launch.
    private var padLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            KBListView(selectedKB: $selectedKB)
        } detail: {
            if let kb = selectedKB {
                KBDetailView(kb: kb)
                    .id(kb.id) // force fresh ChatViewModel when KB changes
            } else {
                ContentUnavailableView(
                    "Select a Knowledge Base",
                    systemImage: "square.stack.3d.up",
                    description: Text("Choose a knowledge base from the sidebar to start chatting or browsing documents.")
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showPadSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showPadSettings) { SettingsView() }
    }
}
