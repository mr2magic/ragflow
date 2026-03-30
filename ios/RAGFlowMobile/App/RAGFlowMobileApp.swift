import SwiftUI
import BackgroundTasks

@main
struct RAGFlowMobileApp: App {

    init() {
        // BGTaskScheduler handlers must be registered before the first scene connects.
        // We use `using: .main` so the handler fires on the main queue, which is the
        // MainActor's executor — safe to call @MainActor-isolated coordinator methods.
        guard #available(iOS 26, *) else { return }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskCoordinator.TaskID.import,
            using: .main
        ) { task in
            guard let bgTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            BackgroundTaskCoordinator.shared.attachImport(to: bgTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskCoordinator.TaskID.workflow,
            using: .main
        ) { task in
            guard let bgTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            BackgroundTaskCoordinator.shared.attachWorkflow(to: bgTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
