import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: Tab = .library

    enum Tab {
        case library, settings
    }
}
