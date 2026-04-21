import SwiftUI

struct DossierRootView: View {
    var body: some View {
        NavigationStack {
            DossierKBListView()
        }
        .tint(DT.stamp)
    }
}
