import Foundation

/// Drains the App Group pending-imports queue written by the Share Extension.
/// Call `processPendingImports()` on app foreground.
@MainActor
enum PendingImportProcessor {
    static func processPendingImports() async {
        let items = SharedGroupDefaults.pendingImports
        guard !items.isEmpty else { return }

        for item in items {
            guard let url = URL(string: item.urlString) else {
                SharedGroupDefaults.removePendingImport(id: item.id)
                continue
            }
            do {
                _ = try await RAGService.shared.ingest(url: url, kbId: item.kbId)
                SharedGroupDefaults.removePendingImport(id: item.id)
            } catch {
                // Leave failed items in queue — user can clear manually in Settings
                // (avoids infinite retry loops on permanently bad files)
            }
        }

        // Refresh widget data after processing
        SharedGroupDefaults.syncFromApp()
    }
}
