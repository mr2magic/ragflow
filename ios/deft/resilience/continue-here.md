# Continue Here

This file is the deft resilience checkpoint for RAGFlowMobile.

## How to Resume

When starting a new session, Claude reads this file to understand where things left off.

## Last Checkpoint

**Status**: 0.5.0 committed + pushed — archive ready to run from Xcode Organizer (2026-04-14)
**Phase**: Brownfield improvement — iOS-native feature wave 1 shipped
**Next**: Open Xcode → Product → Archive → Window → Organizer → Distribute to TestFlight

## What Was Done (0.3.0 session)

### Info.plist
- `CFBundleShortVersionString` 0.2.0 → 0.3.0, `CFBundleVersion` 1 → 3
- Added `UIBackgroundModes: [processing]` — required for BGProcessingTask (was silently missing)
- Improved `NSLocalNetworkUsageDescription` copy for App Store review

### Features added
- **Session auto-naming**: first message content (up to 50 chars) becomes the chat title
- **Empty KB state in chat**: when primary KB has no documents, shows "No Documents Yet" hero
- **Re-index document**: long-press context menu → "Re-index" re-parses the file with current KB chunking settings
- **Share chat history**: ShareLink toolbar button exports conversation as plain text

### Onboarding updated (0.3.0)
- Added "Library & Passages" page; updated Chat/KB/Workflows pages; 8 pages total

## What Was Done (0.4.0 session)

### Features added
- **Variable Assigner step**: set/append/clear workflow slot variables
- **Switch step**: condition-based routing between branches (cursor-driven execution model)
- **Categorize step**: LLM classifies input to a named category and routes accordingly
- **Pluggable search tools**: SearchTool protocol + SearchToolRegistry; DuckDuckGo + Wikipedia added
- **Workflow export/import**: `.ragflow-workflow` files via ExportImportService
- **KB export/import**: `.ragflow-kb` bundles include all chunks; re-embedded on import

### Architecture changes
- WorkflowRunner: cursor-driven while loop; `_next` signal in StepContext; cycle guard via visitedIds

### Onboarding updated (0.4.0)
- Page 6 (Agent Workflows): Switch/Categorize, DuckDuckGo/Wikipedia, export/import bullets

## What Was Done (0.5.0 session)

### Features added — iOS-native wave 1
- **Token pricing display**: cost chip on every assistant reply (`$0.0023 · 1.4k tokens · claude-sonnet-4-6`); free for Ollama; extracted from real API usage fields
- **Siri + App Intents**: QueryKBIntent (voice query), QuickQueryIntent (Action Button), RunWorkflowIntent, ImportURLIntent; AppShortcutsProvider surfaces "Ask RAGFlow" to Siri
- **Focus Filters**: SetFocusFilterIntent hides/shows KBs per Work/Personal Focus mode
- **Core Spotlight**: SpotlightIndexer indexes every book + chunk snippets; results appear in device Spotlight; deindexed on delete
- **Live Activities**: IndexingActivityManager (import progress) + WorkflowActivityManager (per-step); wired into LibraryViewModel and WorkflowRunner; shows on lock screen + Dynamic Island
- **Vision OCR + Document Camera**: VisionOCRParser (on-device, no server); DocumentCameraView wraps VNDocumentCameraViewController; "Scan Document" in LibraryView
- **Drag & Drop (iPad)**: `.onDrop(of: .fileURL)` on book list and empty state; drags from Files.app split-view
- **Handoff**: `.onContinueUserActivity` in ContentView restores selectedKB on resume
- **Shared App Group**: SharedGroupDefaults (`group.com.dhorn.ragflowmobile`) syncs KB list + doc count for future Share Extension + Widget
- **Apple Intelligence Writing Tools (iOS 18+)**: WritingToolsLimitedModifier on chat and workflow query inputs
- **Stage Manager / Multi-Window**: UIApplicationSupportsMultipleScenes = true

### Info.plist changes (0.5.0)
- NSSupportsLiveActivities = true, NSSupportsLiveActivitiesFrequentUpdates = true
- NSCameraUsageDescription added
- UIApplicationSupportsMultipleScenes = true
- Version: 0.5.0 build 5

### Onboarding updated (0.5.0)
- 9 pages total (was 8)
- Import page: camera scan + drag-and-drop bullets
- New page 8: "Built for iPhone & iPad" — Siri, Spotlight, Live Activities, token cost

### New files
- Services/Intents/AppEntities.swift
- Services/Intents/RAGFlowIntents.swift
- Services/Intents/FocusFilterIntent.swift
- Services/Spotlight/SpotlightIndexer.swift
- Services/LiveActivity/IndexingActivityAttributes.swift
- Services/LiveActivity/WorkflowActivityAttributes.swift
- Services/RAG/VisionOCRParser.swift
- Features/Library/DocumentCameraView.swift
- Services/Storage/SharedGroupDefaults.swift

## Active Context

- Project: RAGFlowMobile iOS app (SwiftUI + GRDB)
- Strategy: brownfield (analyze before changing)
- Version: **0.5.0** (build 5) — committed + pushed, not yet in TestFlight
- Last shipped to TestFlight: 0.2.0 on 2026-04-03

## Pending for Next Wave (0.6.0)

- App Group entitlement in Xcode Signing & Capabilities (`group.com.dhorn.ragflowmobile`) — required before Share Extension + Widget targets can share data
- Share Extension target (`RAGFlowShareExtension/ShareViewController.swift`)
- Widget Extension target (Recent Chat, KB Status, Quick Query; Live Activity presentation views)
- Core ML embeddings (.mlpackage bundle for on-device MiniLM)
- iCloud sync (CloudKit) — deferred to 0.8.0

## Notes

- Do NOT modify existing working Swift files without explicit instruction
- SharedViews.swift is the home for shared UI primitives
- Spacing enum constants should be used in all new code
- WritingToolsLimitedModifier is in SharedViews.swift (use it instead of .writingToolsBehavior directly)
- App Group suite name: "group.com.dhorn.ragflowmobile"
