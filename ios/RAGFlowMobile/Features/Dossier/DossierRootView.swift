import SwiftUI

struct DossierRootView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var selectedKB: KnowledgeBase?

    var body: some View {
        Group {
            if hSizeClass == .compact && vSizeClass == .compact {
                // iPhone landscape — 2-column split
                DossierIPhoneLandscapeLayout()
            } else if hSizeClass == .compact {
                // iPhone portrait — push navigation
                NavigationStack {
                    DossierKBListView(selectedKB: $selectedKB)
                }
            } else {
                // iPad — 3-column layout
                DossierIPadLayout()
            }
        }
        .tint(DT.stamp)
    }
}

// MARK: - iPad 3-column layout

private struct DossierIPadLayout: View {
    @StateObject private var vm = KBListViewModel()
    @State private var selectedKB: KnowledgeBase?
    @State private var selectedTab: DossierTab = .query
    @State private var selectedMessage: Message?
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                sidebarColumn
                Divider().background(DT.rule)
                mainColumn
                Divider().background(DT.rule)
                sourcesPanel(width: max(280, geo.size.width * 0.30))
            }
        }
        .background(DT.manila)
        .onAppear {
            vm.reload()
            if selectedKB == nil { selectedKB = vm.kbs.first }
        }
        .onChange(of: vm.kbs) { _, kbs in
            if selectedKB == nil { selectedKB = kbs.first }
        }
        .alert("New Knowledge Base", isPresented: $vm.showCreateAlert) {
            TextField("Name", text: $vm.newKBName)
            Button("Create") {
                if let created = vm.createKB() {
                    selectedKB = created
                    selectedTab = .docs
                }
            }
            Button("Cancel", role: .cancel) { vm.newKBName = "" }
        }
        .confirmationDialog(
            "Delete \"\(vm.kbToDelete?.name ?? "this dossier")\"?",
            isPresented: Binding(
                get: { vm.kbToDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let deleted = vm.kbToDelete
                vm.confirmDelete()
                if let d = deleted, selectedKB?.id == d.id {
                    selectedKB = vm.kbs.first
                }
            }
            Button("Cancel", role: .cancel) { vm.cancelDelete() }
        } message: {
            Text("All documents and chat sessions in this dossier will be permanently deleted.")
        }
        .sheet(item: $vm.kbToRename) { _ in
            RenameSheet(title: "Rename Dossier", text: $vm.renameText) {
                vm.commitRename()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Left sidebar (240pt)

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarBrand
            sidebarTabNav
            Divider().background(DT.rule)
            sidebarKBList
        }
        .frame(width: 240)
        .background(DT.manilaDeep)
    }

    private var sidebarBrand: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RAGION")
                    .font(DT.mono(10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(DT.stamp)
                Text("Dossier")
                    .font(DT.serif(20, weight: .semibold))
                    .foregroundStyle(DT.ink)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DT.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            Button { vm.showCreateAlert = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DT.stamp)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New knowledge base")
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var sidebarTabNav: some View {
        VStack(spacing: 0) {
            ForEach(DossierTab.allCases, id: \.self) { tab in
                sidebarTabRow(tab)
            }
        }
        .padding(.bottom, 8)
    }

    private func sidebarTabRow(_ tab: DossierTab) -> some View {
        let isActive = tab == selectedTab
        return Button { selectedTab = tab } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? DT.stamp : Color.clear)
                    .frame(width: 3)
                Text(tab.label)
                    .font(DT.mono(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(isActive ? DT.stamp : DT.inkFaint)
                    .padding(.leading, 12)
                Spacer()
            }
            .frame(height: 36)
            .background(isActive ? DT.stamp.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarKBList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("KNOWLEDGEBASES")
                    .font(DT.mono(8, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                    .padding(.horizontal, DT.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                ForEach(Array(vm.kbs.enumerated()), id: \.element.id) { i, kb in
                    sidebarKBRow(kb, index: i)
                }
            }
        }
    }

    private func sidebarKBRow(_ kb: KnowledgeBase, index: Int) -> some View {
        let palette: [Color] = [DT.ribbon, DT.stamp, DT.green, DT.amber, DT.inkSoft]
        let accent = palette[index % palette.count]
        let isSelected = selectedKB?.id == kb.id
        return Button {
            selectedKB = kb
            selectedMessage = nil
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(kb.name)
                    .font(DT.mono(10))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? DT.ink : DT.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.vertical, 7)
            .background(isSelected ? DT.stamp.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                vm.renameText = kb.name
                vm.kbToRename = kb
            }
            Divider()
            Button("Delete", role: .destructive) {
                vm.requestDelete(kb: kb)
            }
        }
    }

    // MARK: - Middle column (flex)

    @ViewBuilder
    private var mainColumn: some View {
        if let kb = selectedKB {
            tabContent(for: kb)
                .id("\(kb.id)-\(selectedTab.rawValue)")
        } else {
            emptyMiddle
        }
    }

    @ViewBuilder
    private func tabContent(for kb: KnowledgeBase) -> some View {
        switch selectedTab {
        case .kb:
            DossierQueryView(kb: kb)
        case .docs:
            DossierDocumentListView(kb: kb)
        case .query:
            DossierChatView(kb: kb, onMessageTap: { selectedMessage = $0 })
        case .flow:
            DossierWorkflowView(kb: kb)
        case .arch:
            DossierArchiveView(kb: kb)
        }
    }

    private var emptyMiddle: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("SELECT A DOSSIER")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Choose a knowledge base from the sidebar.")
                .font(DT.serif(14))
                .italic()
                .foregroundStyle(DT.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(DT.manila)
    }

    // MARK: - Right sources panel (proportional ~30% of width)

    private func sourcesPanel(width: CGFloat) -> some View {
        DossierSourcesPanel(message: selectedMessage)
            .frame(width: width)
    }
}

// MARK: - iPhone landscape 2-column layout

private struct DossierIPhoneLandscapeLayout: View {
    @StateObject private var vm = KBListViewModel()
    @State private var selectedKB: KnowledgeBase?

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
            Divider().background(DT.rule)
            detailColumn
        }
        .background(DT.manila)
        .onAppear {
            vm.reload()
            if selectedKB == nil { selectedKB = vm.kbs.first }
        }
        .onChange(of: vm.kbs) { _, kbs in
            if selectedKB == nil { selectedKB = kbs.first }
        }
    }

    // MARK: - Left sidebar (~200pt)

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider().background(DT.rule)
            kbList
        }
        .frame(width: 200)
        .background(DT.manilaDeep)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RAGION")
                .font(DT.mono(9, weight: .bold))
                .tracking(3)
                .foregroundStyle(DT.stamp)
            Text("Dossier")
                .font(DT.serif(16, weight: .semibold))
                .foregroundStyle(DT.ink)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var kbList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(vm.kbs.enumerated()), id: \.element.id) { i, kb in
                    kbRow(kb, index: i)
                }
            }
        }
    }

    private func kbRow(_ kb: KnowledgeBase, index: Int) -> some View {
        let palette: [Color] = [DT.ribbon, DT.stamp, DT.green, DT.amber, DT.inkSoft]
        let accent = palette[index % palette.count]
        let isSelected = selectedKB?.id == kb.id
        return Button { selectedKB = kb } label: {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(kb.name)
                    .font(DT.mono(9))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? DT.ink : DT.inkSoft)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.vertical, 8)
            .background(isSelected ? DT.stamp.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let kb = selectedKB {
            NavigationStack {
                DossierKBDetailView(kb: kb)
            }
            .id(kb.id)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Text("SELECT A DOSSIER")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(DT.manila)
        }
    }
}
