# Background Processing — iOS 26

## Problem

All long-running operations (document import, LLM chat streaming, workflow execution) ran
exclusively on foreground Swift concurrency `Task`s with `URLSession.shared`. When the user
switched windows in Stage Manager or backgrounded the app, iOS suspended the process and all
in-flight work froze. If iOS later terminated the app under memory pressure, in-flight work
was lost entirely.

## Solution

Two complementary iOS APIs, applied per feature based on duration and progress visibility:

### 1. `BGContinuedProcessingTask` — iOS 26+ (document import, workflow execution)

`BGContinuedProcessingTask` is the iOS 26 API designed exactly for user-initiated tasks that
must survive a Stage Manager window switch. The system:

- Keeps the app process alive in background (indefinitely, while `Progress` advances)
- Shows a live progress indicator accessible from the home screen / Stage Manager strip
- Revokes the grant if progress stalls (no `completedUnitCount` advancement for too long)
- Allows the user to cancel from the system UI

**Requirements:**
- Must be triggered by an explicit user action (tap/gesture) — cannot be self-scheduled
- Must attach a `Progress` object and advance it continuously
- Must call `task.setTaskCompleted(success:)` when done or in `expirationHandler`
- Task identifiers must be declared in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`
- Handlers must be registered via `BGTaskScheduler.shared.register(...)` before the first
  scene connects (i.e., in `App.init()`)

**Used for:** Document import, workflow execution

### 2. `UIApplication.beginBackgroundTask` — all iOS (chat streaming)

Provides a ~30-second execution window after the app moves to background. Not enough for
long imports, but sufficient for typical LLM chat responses (most complete in <15 seconds).

LLM streaming (`URLSession.shared` data tasks) cannot run in background `URLSession`
configurations — the OS restriction is fundamental and unchanged in iOS 26. The 30-second
fence is the correct tool: it keeps the stream alive through brief Stage Manager context
switches (flicking to another app and back).

**Used for:** Chat streaming, single-shot LLM calls

## Architecture

```
BackgroundTaskCoordinator  (@MainActor singleton)
  ├── beginImport(fileCount:) → Progress        # submits BGContinuedProcessingTaskRequest
  ├── advanceImport()                            # increments Progress.completedUnitCount
  ├── finishImport(success:)                     # calls task.setTaskCompleted
  ├── beginWorkflow(name:stepCount:) → Progress  # submits BGContinuedProcessingTaskRequest
  ├── advanceWorkflow()
  ├── finishWorkflow(success:)
  └── withBackgroundFence(named:work:)           # wraps UIApplication.beginBackgroundTask

RAGFlowMobileApp.init()
  └── Registers BGTaskScheduler handlers (iOS 26+)
      ├── TaskID.import  → coordinator.attachImport(to:)
      └── TaskID.workflow → coordinator.attachWorkflow(to:)

LibraryViewModel.ingest(urls:)
  ├── coordinator.beginImport(fileCount:)        # BGContinuedProcessingTask submitted
  ├── loop: rag.ingest + coordinator.advanceImport()
  └── coordinator.finishImport(success:)

ChatViewModel.send()
  └── UIApplication.beginBackgroundTask fence wraps entire streamTask body

WorkflowRunner.run(workflow:input:)
  ├── coordinator.beginWorkflow(name:stepCount:) # BGContinuedProcessingTask submitted
  ├── loop: step execution + coordinator.advanceWorkflow()
  └── coordinator.finishWorkflow(success:)
```

## Info.plist Keys Added

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.dhorn.ragflowmobile.import</string>
    <string>com.dhorn.ragflowmobile.workflow</string>
</array>
```

## Behavior by Scenario

| Scenario | Before | After |
|---|---|---|
| Import 100 files → switch Stage Manager window | Import suspends; ~0–5 files complete | Import continues; system shows progress UI |
| Import 100 files → app terminated by OS | In-flight file lost; completed files saved | BGContinuedProcessingTask keeps process alive; expiration handler marks incomplete gracefully |
| Chat → switch Stage Manager window (<30s) | Stream suspends | 30-second fence keeps stream alive; user sees full response on return |
| Chat → away >30s or app terminated | Partial response or nothing | Partial text saved to DB (existing behaviour); user sees what arrived |
| Workflow run → switch Stage Manager window | Execution suspends mid-step | BGContinuedProcessingTask keeps execution alive through all steps |
| iOS <26 device | (existing behaviour) | Graceful degradation: beginBackgroundTask fence for all operations |

## Limitations

- LLM streaming (`URLSession.shared` DataTask) cannot use background URLSession — this is
  an OS-level restriction unchanged in iOS 26. The 30-second fence covers typical responses.
- `BGContinuedProcessingTask` is iOS 26+. On iOS 17–25, import and workflow use the
  30-second `beginBackgroundTask` fence as fallback.
- Background GPU (for on-device ML embedding) is a separate iOS 26 entitlement and requires
  explicit hardware capability check at runtime. Not implemented in this release.
