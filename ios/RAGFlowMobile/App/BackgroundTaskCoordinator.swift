import BackgroundTasks
import UIKit
import UserNotifications

/// Central coordinator for all background processing in Ragion.
///
/// ## iOS 26 — BGContinuedProcessingTask
/// Document import and workflow execution are user-initiated tasks. On iOS 26+, the system
/// keeps the app process alive in background (Stage Manager window switch or full backgrounding)
/// for as long as `Progress` keeps advancing, and shows a live progress indicator to the user.
///
/// ## All iOS — UIApplication.beginBackgroundTask
/// LLM chat streaming receives a ~30-second background execution window, which covers typical
/// response lengths during brief Stage Manager context switches.
///
/// ## Registration
/// `BGTaskScheduler` handlers must be registered before the first SwiftUI scene connects.
/// Call site: `RagionApp.init()`.
@MainActor
final class BackgroundTaskCoordinator {
    static let shared = BackgroundTaskCoordinator()
    private init() {}

    // MARK: - Task identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)

    enum TaskID {
        static let `import` = "com.dhorn.ragflowmobile.import"
        static let workflow  = "com.dhorn.ragflowmobile.workflow"
    }

    // MARK: - In-flight state
    // AnyObject wraps BGContinuedProcessingTask so the property declarations compile on
    // all iOS versions without @available annotations on stored properties.

    private var importBGTask: AnyObject?    // BGContinuedProcessingTask on iOS 26+
    private var importProgress: Progress?
    private var importFinished = false

    private var workflowBGTask: AnyObject?  // BGContinuedProcessingTask on iOS 26+
    private var workflowProgress: Progress?
    private var workflowResult: Bool?       // nil = still running
    private var workflowName: String = ""

    // MARK: - Attachment (called from BGTaskScheduler handlers registered in App.init)

    @available(iOS 26, *)
    func attachImport(to task: BGContinuedProcessingTask) {
        importBGTask = task

        // Chain our per-file Progress into the system task's progress tree so the OS
        // progress UI reflects actual file throughput.
        if let p = importProgress {
            task.progress.totalUnitCount = 100
            task.progress.addChild(p, withPendingUnitCount: 100)
        }

        task.expirationHandler = { [weak self] in
            // OS is withdrawing the background grant. The import loop is frozen; mark
            // incomplete so the caller can surface an error to the user on foreground.
            guard let self else { return }
            self.importProgress = nil
            self.importBGTask = nil
            task.setTaskCompleted(success: false)
        }

        // If the import loop finished before the task callback fired (e.g. device was
        // fast and files were small), complete immediately.
        if importFinished {
            task.setTaskCompleted(success: true)
            importBGTask = nil
        }
    }

    @available(iOS 26, *)
    func attachWorkflow(to task: BGContinuedProcessingTask) {
        workflowBGTask = task

        if let p = workflowProgress {
            task.progress.totalUnitCount = 100
            task.progress.addChild(p, withPendingUnitCount: 100)
        }

        task.expirationHandler = { [weak self] in
            guard let self else { return }
            self.workflowProgress = nil
            self.workflowBGTask = nil
            task.setTaskCompleted(success: false)
        }

        if let result = workflowResult {
            task.setTaskCompleted(success: result)
            workflowBGTask = nil
        }
    }

    // MARK: - Import lifecycle API

    /// Call before processing the first URL. Submits a BGContinuedProcessingTask on iOS 26+.
    /// Returns a `Progress` object — the coordinator advances it; callers don't need to touch it.
    @discardableResult
    func beginImport(fileCount: Int) -> Progress {
        let p = Progress(totalUnitCount: Int64(fileCount))
        importProgress = p
        importFinished = false

        if #available(iOS 26, *) {
            let req = BGContinuedProcessingTaskRequest(
                identifier: TaskID.import,
                title: "Importing Documents",
                subtitle: "\(fileCount) file\(fileCount == 1 ? "" : "s")"
            )
            try? BGTaskScheduler.shared.submit(req)
        }
        return p
    }

    /// Call after each file in the batch is processed (whether it succeeded or failed).
    func advanceImport() {
        importProgress?.completedUnitCount += 1
    }

    /// Call when the entire import batch exits.
    func finishImport(success: Bool) {
        importFinished = true
        importProgress = nil
        if #available(iOS 26, *) {
            (importBGTask as? BGContinuedProcessingTask)?.setTaskCompleted(success: success)
        }
        importBGTask = nil
        sendBackgroundNotification(
            title: success ? "Import Complete" : "Import Incomplete",
            body: success ? "Your documents are ready in the knowledge base." : "Some files could not be imported."
        )
    }

    // MARK: - Workflow lifecycle API

    /// Call before the first step executes. Submits a BGContinuedProcessingTask on iOS 26+.
    @discardableResult
    func beginWorkflow(name: String, stepCount: Int) -> Progress {
        let p = Progress(totalUnitCount: Int64(max(stepCount, 1)))
        workflowProgress = p
        workflowResult = nil
        workflowName = name

        if #available(iOS 26, *) {
            let req = BGContinuedProcessingTaskRequest(
                identifier: TaskID.workflow,
                title: "Running Workflow",
                subtitle: name
            )
            try? BGTaskScheduler.shared.submit(req)
        }
        return p
    }

    /// Call after each workflow step completes (regardless of success/failure).
    func advanceWorkflow() {
        workflowProgress?.completedUnitCount += 1
    }

    /// Call when the workflow run exits.
    func finishWorkflow(success: Bool) {
        workflowResult = success
        workflowProgress = nil
        if #available(iOS 26, *) {
            (workflowBGTask as? BGContinuedProcessingTask)?.setTaskCompleted(success: success)
        }
        workflowBGTask = nil
        let name = workflowName
        sendBackgroundNotification(
            title: success ? "Workflow Complete" : "Workflow Failed",
            body: success ? "\(name) finished." : "\(name) did not complete."
        )
    }

    // MARK: - Local notifications

    /// Request authorization once, early in the app lifecycle. No-ops if already granted/denied.
    func requestNotificationAuthorization() {
        Task {
            try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Posts an immediate local notification — but only when the app is not in the foreground.
    private func sendBackgroundNotification(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil    // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Short-lived background fence (UIKit, all iOS versions)

    /// Executes `work` inside a UIApplication background task so the OS keeps the process
    /// alive for ~30 seconds after a Stage Manager window switch.
    ///
    /// Used for LLM streaming where `BGContinuedProcessingTask` is impractical (indeterminate
    /// progress) and where response latency is typically well under 30 seconds.
    func withBackgroundFence<T>(
        named reason: String,
        work: () async throws -> T
    ) async rethrows -> T {
        let token = UIApplication.shared.beginBackgroundTask(withName: reason) {
            // Expiration callback: the 30-second window is closing.
            // The streaming Task will be suspended by the OS on the next scheduler tick;
            // ChatViewModel's CancellationError handler will save whatever arrived.
        }
        defer { UIApplication.shared.endBackgroundTask(token) }
        return try await work()
    }
}
