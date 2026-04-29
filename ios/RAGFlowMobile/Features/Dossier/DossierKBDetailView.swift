import SwiftUI

struct DossierKBDetailView: View {
    let kb: KnowledgeBase
    var onMessageTap: ((Message) -> Void)? = nil

    @State private var selectedTab: DossierTab = .kb

    var body: some View {
        tabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DossierTabBar(selected: $selectedTab)
            }
            .background(DT.manila)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(kb.name)
                    .font(DT.mono(12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(DT.ink)
            }
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .kb:
            DossierQueryView(kb: kb)
        case .docs:
            DossierDocumentListView(kb: kb)
        case .query:
            DossierChatView(kb: kb, onMessageTap: onMessageTap)
        case .flow:
            DossierWorkflowView(kb: kb)
        case .arch:
            DossierArchiveView(kb: kb)
        }
    }

}
