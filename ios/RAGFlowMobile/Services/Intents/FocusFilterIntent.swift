import AppIntents

// MARK: - Focus Filter
//
// Allows users to configure RAGFlow in System Settings → Focus → [Focus Mode] → App Filters.
// When a Focus is active, AppState applies the configured KB filter so only relevant KBs appear.

struct RAGFlowFocusFilterIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Filter Knowledge Bases"
    static var description: LocalizedStringResource =
        "Show only selected knowledge bases while this Focus is active."

    /// The KB IDs that should be visible. Empty = show all.
    @Parameter(title: "Knowledge Bases", default: [])
    var visibleKBs: [KBEntity]

    var displayRepresentation: DisplayRepresentation {
        if visibleKBs.isEmpty {
            return DisplayRepresentation(title: "Show all knowledge bases")
        }
        let names = visibleKBs.prefix(3).map(\.name).joined(separator: ", ")
        return DisplayRepresentation(title: "Show: \(names)")
    }

    func perform() async throws -> Never {
        // Store the IDs so AppState can filter the KB list.
        let ids = visibleKBs.map(\.id)
        let defaults = UserDefaults.standard
        if ids.isEmpty {
            defaults.removeObject(forKey: "focusFilter_visibleKBIds")
        } else {
            defaults.set(ids, forKey: "focusFilter_visibleKBIds")
        }
        // Notify the app that the filter changed.
        NotificationCenter.default.post(name: .focusFilterChanged, object: nil)
        throw CancellationError()   // required by SetFocusFilterIntent
    }
}

extension Notification.Name {
    static let focusFilterChanged = Notification.Name("com.dhorn.ragflowmobile.focusFilterChanged")
}

// MARK: - Focus Filter Store

/// Lightweight accessor used by KBListViewModel/PhoneKBListView to filter KBs.
enum FocusFilterStore {
    /// Returns nil when no filter is active (show all KBs).
    static var visibleKBIds: Set<String>? {
        guard let ids = UserDefaults.standard.stringArray(forKey: "focusFilter_visibleKBIds"),
              !ids.isEmpty else { return nil }
        return Set(ids)
    }
}
