import SwiftUI
import BackgroundTasks

@main
struct RagionApp: App {

    @State private var splashDismissed = false

    init() {
        // BGTaskScheduler handlers must be registered before the first scene connects.
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
            if splashDismissed {
                ContentView()
            } else {
                SplashView { splashDismissed = true }
            }
        }
    }
}
