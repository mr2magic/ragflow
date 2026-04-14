# Continue Here

This file is the deft resilience checkpoint for RAGFlowMobile.

## How to Resume

When starting a new session, Claude reads this file to understand where things left off.

## Last Checkpoint

**Status**: 0.6.0 committed + pushed (build 6) — archive failed due to expired Xcode credentials (2026-04-14)
**Phase**: Brownfield improvement — iOS-native feature wave 1 (0.5.0) shipped; 0.6.0 import/parser fixes committed
**Next**: Open Xcode → Settings → Accounts → re-sign in → Product → Archive → Distribute to TestFlight

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

## What Was Done (0.6.0 session)

### Bugs fixed
- **EMLParser**: header trimming `.whitespaces` → `.whitespacesAndNewlines` — CRLF emails left `\r` on subject/headers
- **OfficeParser.extractWText**: off-by-one: `index(after: gt.upperBound)` → `gt.upperBound` — first character of every `<w:t>` run in DOCX was silently dropped
- **RAGService.ingestPDF**: added VisionOCRParser fallback for image-only (scanned) PDFs
- **RAGService**: added `.emlx` to EML dispatch case; added `.odt` case → new `ingestODT`
- **OfficeParser**: added `parseODT` method; refactored DOCX/XLSX/PPTX/ODT to expose dir-based `parseXContent` methods (bypasses Zip, testable)

### Audit fixes
- **KBListViewModel.reload()**: now applies `FocusFilterStore.visibleKBIds` — filter was silently ignored
- **KBListView / PhoneKBListView**: observe `.focusFilterChanged` notification; removed Seed Test Data button
- **PhoneKBListView / ContentView**: added `handoffKB` `@Binding` so Handoff opens correct KB on iPhone (was only working on iPad)
- **LibraryViewModel**: removed dead `importFiles()` method
- **DatabaseService**: removed `#if DEBUG seedDummyData()` block

### Infrastructure
- **App Group entitlement**: `RAGFlowMobile/RAGFlowMobile.entitlements` created with `group.com.dhorn.ragflowmobile`; wired into both Debug + Release build configs in pbxproj

### Tests
- **ImportParserTests**: 17/17 passing — CSV, EML, EMLX, EPUB (structure), HTML, JSON, Markdown, ODT, PDF (text), PPTX, Python, RTF, SQL, Swift, TXT, XLSX, YAML

### Info.plist changes (0.6.0)
- Version: 0.6.0 build 6

## Active Context

- Project: RAGFlowMobile iOS app (SwiftUI + GRDB)
- Strategy: brownfield (analyze before changing)
- Version: **0.6.0** (build 6) — committed + pushed, archive blocked by expired Xcode credentials
- Last shipped to TestFlight: 0.2.0 on 2026-04-03

## To Archive for TestFlight

The xcodebuild archive command fails with "No Account for Team 5FLM4GQ73L". Steps to fix:

1. Open Xcode → Settings (⌘,) → Accounts
2. Re-sign in with your Apple ID
3. Then run from `/Users/Dans_iMac/Projects/ragflow/ragflow/ios`:
   ```bash
   xcodebuild archive \
     -project RAGFlowMobile.xcodeproj \
     -scheme RAGFlowMobile \
     -configuration Release \
     -destination "generic/platform=iOS" \
     -archivePath "$HOME/Library/Developer/Xcode/Archives/RAGFlowMobile-0.6.0.xcarchive" \
     -allowProvisioningUpdates \
     CODE_SIGN_STYLE=Automatic \
     DEVELOPMENT_TEAM=5FLM4GQ73L
   ```
4. Then export to TestFlight via Xcode Organizer or:
   ```bash
   xcrun altool --upload-app --type ios \
     --file RAGFlowMobile-0.6.0.ipa \
     --apiKey <key> --apiIssuer <issuer>
   ```

## Pending for Next Wave (0.7.0)

- Share Extension target (`RAGFlowShareExtension/ShareViewController.swift`) — App Group entitlement already in place
- Widget Extension target (Recent Chat, KB Status, Quick Query; Live Activity presentation views)
- Core ML embeddings (.mlpackage bundle for on-device MiniLM)
- iCloud sync (CloudKit) — deferred to 0.8.0

## Notes

- Do NOT modify existing working Swift files without explicit instruction
- SharedViews.swift is the home for shared UI primitives
- Spacing enum constants should be used in all new code
- WritingToolsLimitedModifier is in SharedViews.swift (use it instead of .writingToolsBehavior directly)
- App Group suite name: "group.com.dhorn.ragflowmobile"
- Xcode team ID: 5FLM4GQ73L
