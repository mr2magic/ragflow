# Ragion — Task Backlog

Last updated: 2026-04-17

---

## Bug Fixes / Polish

| # | Task | Status |
|---|------|--------|
| 7 | Add tooltips to retrieval settings (KBRetrievalSettingsSheet.swift) | done |
| 8 | Fix onboarding dialog scroll area — universally responsive across all device sizes | done |
| 9 | Audit and fix "LLM returned unexpected..." alert triggers — trace all false-positive paths | done |
| 10 | Test all retrieval settings end-to-end with real data — verify every control works correctly | done |
| 11 | **Import from scan not working** — Fixed: single-step temp file write (no more UUID+rename); posts `.scanImportComplete` notification; LibraryView reloads on receipt | done |
| 12 | **KB tap does nothing on iPhone** — Fixed: replaced three competing `navigationDestination` registrations for `KnowledgeBase` (undefined SwiftUI behavior) with a single `KBNavDest` wrapper + `navigationDestination(item:)`; row taps now use `Button` that sets `navDest` directly | done |
| 13 | **Simulator regression suite — iPhone 17 Pro (landscape + portrait)** — Run full app flow in iPhone 17 Pro simulator: KB create/tap/delete, import files, scan (if camera stub available), chat, workflows, settings; capture any layout breaks in landscape | pending |
| 19 | **All tooltips must be multiline and fit the tooltip area properly** — Fixed: SettingHelpButton popover now uses fixedSize(horizontal:false,vertical:true) + multilineTextAlignment(.leading) + minWidth:220; text wraps correctly on all devices | done |
| 20 | **Cap files per KB at 50** — Done: LibraryViewModel enforces 50-doc limit on all ingest paths (file import, URL, scan); shows count badge "X of 50" in LibraryView list (orange when ≤5 slots remain); DocumentCameraView checks cap before OCR | done |

## New Features

| # | Task | Status |
|---|------|--------|
| 14 | **Splash screen** — Done: SplashView.swift with app icon, title, version, animated entrance; "Get Started" → OnboardingView (first run) or "Open" → ContentView (returning); wired into RAGFlowMobileApp.swift | done |
| 16 | **Import and export workflows** — Done: export via context menu + leading swipe on each row; import via toolbar secondaryAction (.ragflow-workflow file); WorkflowDetailView toolbar export already existed; all paths wired to ExportImportService + ShareSheet | done |
| 17 | **Update Onboarding with all new features and file types** — Audit all 9 pages; update Import Documents page (GEDCOM, ZIP); update Agent Workflows page; update iOS features page; add any new capabilities added since 0.5.0 | done |
| 18 | **"Where is New Chat?"** — Fixed: added `square.and.pencil` toolbar button to ChatView; tapping it calls `onNewChat` closure passed from ConversationsListView, which creates a session and navigates to it — no need to back out of a chat to start a new one | done |

## Core ML Embeddings (0.7.x)

| # | Task | Status |
|---|------|--------|
| 1 | Bundle quantized MiniLM .mlpackage in Xcode project resources | pending |
| 2 | Implement CoreMLEmbeddingService.swift — on-device embeddings via bundled model | pending |
| 3 | Wire CoreML into RAGService + Settings toggle (On-device / API) | pending |

## iCloud Sync / CloudKit (0.8.0)

| # | Task | Status |
|---|------|--------|
| 4 | Enable CloudKit capability + define CKRecord schema (KBs, sessions, messages, config) | pending |
| 5 | Implement CloudKitSyncService — push/pull, conflict resolution, offline queuing | pending |
| 6 | Add iCloud sync UI — Settings toggle, last-synced timestamp, manual sync, error display | pending |
