import SwiftUI

// MARK: - OS hard block

private struct UnsupportedOSView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("iOS 17 Required")
                .font(.title.bold())

            Text("RAGFlow Mobile requires iOS 17 or later. Please update your device in Settings → General → Software Update.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Link("Learn how to update",
                 destination: URL(string: "https://support.apple.com/en-us/111900")!)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Content

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var osSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0)
        )
    }

    // iPad / regular state
    @State private var selectedKB: KnowledgeBase?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showPadSettings = false
    @State private var pendingAutoImportKBId: String? = nil
    // iPhone Handoff — KB to navigate to after resume
    @State private var handoffKB: KnowledgeBase? = nil

    var body: some View {
        Group {
            if sizeClass == .compact {
                phoneLayout
            } else {
                padLayout
            }
        }
        // Hard block: OS too old — shown before onboarding, not dismissable.
        .fullScreenCover(isPresented: Binding(
            get: { !osSupported },
            set: { _ in }
        )) {
            UnsupportedOSView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { osSupported && !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
        }
        .task {
            BackgroundTaskCoordinator.shared.requestNotificationAuthorization()
            SharedGroupDefaults.syncFromApp()
        }
        // Handoff — resume a chat started on another Apple device
        .onContinueUserActivity("com.dhorn.ragflowmobile.chat") { activity in
            if let kbId = activity.userInfo?["kbId"] as? String,
               let kb = try? DatabaseService.shared.kb(id: kbId) {
                selectedKB = kb       // iPad
                handoffKB  = kb       // iPhone
            }
        }
    }

    // MARK: - iPhone / Compact

    /// Tab 1: KB list → drill into KB → Library + Chat tabs
    /// Tab 2: Workflows
    /// Tab 3: Settings
    private var phoneLayout: some View {
        TabView {
            NavigationStack {
                PhoneKBListView(handoffKB: $handoffKB)
            }
            .tabItem { Label("Knowledge Bases", systemImage: "square.stack.3d.up") }

            NavigationStack {
                WorkflowListView()
            }
            .tabItem { Label("Workflows", systemImage: "cpu") }

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
            KBListView(selectedKB: $selectedKB, pendingAutoImportKBId: $pendingAutoImportKBId)
        } detail: {
            if let kb = selectedKB {
                let autoImport = pendingAutoImportKBId == kb.id
                KBDetailView(kb: kb, initialTab: autoImport ? 1 : 0, autoImport: autoImport)
                    .id(kb.id) // force fresh ChatViewModel when KB changes
                    .onAppear { pendingAutoImportKBId = nil }
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
