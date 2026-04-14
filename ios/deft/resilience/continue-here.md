# Continue Here

This file is the deft resilience checkpoint for RAGFlowMobile.

## How to Resume

When starting a new session, Claude reads this file to understand where things left off.

## Last Checkpoint

**Status**: 0.3.0 committed and pushed — ready for TestFlight archive (2026-04-14)
**Phase**: Brownfield improvement — feature gaps + App Store compliance pass
**Next**: Archive 0.3.0 in Xcode → upload to TestFlight, then decide next feature area

## What Was Done (0.3.0 session)

### Info.plist
- `CFBundleShortVersionString` 0.2.0 → 0.3.0, `CFBundleVersion` 1 → 3
- Added `UIBackgroundModes: [processing]` — required for BGProcessingTask (was silently missing)
- Improved `NSLocalNetworkUsageDescription` copy for App Store review

### Features added
- **Session auto-naming**: first message content (up to 50 chars) becomes the chat title; `sessionTitle` published property keeps nav bar in sync
- **Empty KB state in chat**: when primary KB has no documents, shows "No Documents Yet" hero instead of generic prompts
- **Re-index document**: long-press context menu → "Re-index" re-parses the file with current KB chunking settings; graceful error if original file was a temp copy
- **Share chat history**: ShareLink toolbar button (appears when conversation has messages) exports as plain text

### App Store / reliability fixes
- `UIBackgroundModes` now declares `processing` (was missing, would fail background task registration)
- All icon-only buttons have `.accessibilityLabel` (send, stop, play/stop workflow, clear, add/remove KB tag, share)
- Decorative images (chevrons, connector arrows, empty-state icons) have `.accessibilityHidden(true)`
- Status badges (indexed, not-indexed, done, failed, indexing) have `.accessibilityLabel`
- Typing indicator has `.accessibilityLabel("AI is typing")`

### What was NOT changed (deliberately)
- `PrivacyInfo.xcprivacy` — current declaration correct (UserDefaults CA92.1); no new API types needed
- App icon — only 1024x1024 JPG; App Store accepts this via asset catalog compilation, but ideally should be PNG. Cannot fix without the source image.
- Cross-KB document search — deferred to later version
- Workflow undo — deferred

## Active Context

- Project: RAGFlowMobile iOS app (SwiftUI + GRDB)
- Strategy: brownfield (analyze before changing)
- Version: **0.3.0** (build 3) — committed, not yet in TestFlight
- Last shipped to TestFlight: 0.2.0 on 2026-04-03

## Notes

- Do NOT modify existing working Swift files without explicit instruction
- SharedViews.swift is the home for shared UI primitives (RenameSheet, CreateKBSheet, URLImportSheet, Spacing)
- Spacing enum constants should be used in all new code
- Re-index requires file to still exist at `book.filePath`; temp-copy imports won't work (documented in error message)
