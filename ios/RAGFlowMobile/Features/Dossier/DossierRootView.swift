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
                NavigationSplitView {
                    DossierKBListView(selectedKB: $selectedKB)
                } detail: {
                    if let kb = selectedKB {
                        DossierKBDetailView(kb: kb)
                            .id(kb.id)
                    } else {
                        ContentUnavailableView(
                            "Select a Dossier",
                            systemImage: "folder",
                            description: Text("Choose a dossier from the cabinet to view or chat.")
                        )
                    }
                }
            }
        }
        .tint(DT.stamp)
    }
}
