import ActivityKit
import Foundation

// MARK: - Indexing Live Activity
//
// Displayed on the Dynamic Island and lock screen while a document import is running.
// Presentation views (lock screen + Dynamic Island SwiftUI) live in RAGFlowWidget extension.

struct IndexingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var fileName: String
        var currentFile: Int
        var totalFiles: Int
        var phase: String       // "Parsing", "Chunking", "Embedding", etc.

        var progressFraction: Double {
            guard totalFiles > 0 else { return 0 }
            return Double(currentFile) / Double(totalFiles)
        }

        var progressLabel: String {
            totalFiles > 1
                ? "\(currentFile) of \(totalFiles) files"
                : phase
        }
    }

    var kbName: String
}

// MARK: - Indexing Activity Manager

@MainActor
final class IndexingActivityManager {
    static let shared = IndexingActivityManager()
    private init() {}

    private var activity: Activity<IndexingActivityAttributes>?

    func start(kbName: String, fileName: String, totalFiles: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = IndexingActivityAttributes(kbName: kbName)
        let state = IndexingActivityAttributes.ContentState(
            fileName: fileName,
            currentFile: 1,
            totalFiles: totalFiles,
            phase: "Parsing"
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
    }

    func update(fileName: String, currentFile: Int, totalFiles: Int, phase: String) {
        guard let activity else { return }
        let state = IndexingActivityAttributes.ContentState(
            fileName: fileName,
            currentFile: currentFile,
            totalFiles: totalFiles,
            phase: phase
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func finish(success: Bool) {
        guard let activity else { return }
        let state = IndexingActivityAttributes.ContentState(
            fileName: success ? "Done" : "Incomplete",
            currentFile: 0,
            totalFiles: 0,
            phase: success ? "Complete" : "Failed"
        )
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4))
            self.activity = nil
        }
    }
}
