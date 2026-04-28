import SwiftUI

struct DossierKBDetailView: View {
    let kb: KnowledgeBase
    var onMessageTap: ((Message) -> Void)? = nil

    @State private var selectedTab: DossierTab = .kb
    @State private var docCount: Int = 0
    @State private var chunkCount: Int = 0

    private let db = DatabaseService.shared

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
        .onAppear { loadCounts() }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .kb:
            DossierQueryView(kb: kb, docCount: docCount, chunkCount: chunkCount)
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

    // MARK: - Data

    private func loadCounts() {
        let books = (try? db.allBooks(kbId: kb.id)) ?? []
        docCount = books.count
        chunkCount = books.reduce(0) { $0 + $1.chunkCount }
    }
}
