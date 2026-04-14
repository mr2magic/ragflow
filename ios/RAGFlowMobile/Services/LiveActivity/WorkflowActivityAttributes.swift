import ActivityKit
import Foundation

// MARK: - Workflow Live Activity

struct WorkflowActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentStepLabel: String
        var currentStepIndex: Int
        var totalSteps: Int
        var status: Status

        enum Status: String, Codable { case running, completed, failed }

        var progressFraction: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(currentStepIndex) / Double(totalSteps)
        }
    }

    var workflowName: String
}

// MARK: - Workflow Activity Manager

@MainActor
final class WorkflowActivityManager {
    static let shared = WorkflowActivityManager()
    private init() {}

    private var activity: Activity<WorkflowActivityAttributes>?

    func start(workflowName: String, firstStepLabel: String, totalSteps: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkflowActivityAttributes(workflowName: workflowName)
        let state = WorkflowActivityAttributes.ContentState(
            currentStepLabel: firstStepLabel,
            currentStepIndex: 1,
            totalSteps: totalSteps,
            status: .running
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
    }

    func update(stepLabel: String, stepIndex: Int, totalSteps: Int) {
        guard let activity else { return }
        let state = WorkflowActivityAttributes.ContentState(
            currentStepLabel: stepLabel,
            currentStepIndex: stepIndex,
            totalSteps: totalSteps,
            status: .running
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func finish(success: Bool, totalSteps: Int) {
        guard let activity else { return }
        let state = WorkflowActivityAttributes.ContentState(
            currentStepLabel: success ? "Complete" : "Failed",
            currentStepIndex: totalSteps,
            totalSteps: totalSteps,
            status: success ? .completed : .failed
        )
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4))
            self.activity = nil
        }
    }
}
