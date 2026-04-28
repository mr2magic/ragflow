import SwiftUI

struct DossierRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedKB: KnowledgeBase?

    var body: some View {
        Group {
            if sizeClass == .compact {
                NavigationStack {
                    DossierKBListView(selectedKB: $selectedKB)
                }
            } else {
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
        VStack(alignment: .leading, spacing: 2) {
            Text("RAGION")
                .font(DT.mono(10, weight: .bold))
                .tracking(3)
                .foregroundStyle(DT.stamp)
            Text("Dossier")
                .font(DT.serif(20, weight: .semibold))
                .foregroundStyle(DT.ink)
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
                Spacer()
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.vertical, 7)
            .background(isSelected ? DT.stamp.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
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
            DossierQueryView(kb: kb, docCount: 0, chunkCount: 0)
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
