# RAGFlowMobile — Task Backlog

Last updated: 2026-04-16

---

## Bug Fixes / Polish

| # | Task | Status |
|---|------|--------|
| 7 | Add tooltips to retrieval settings (KBRetrievalSettingsSheet.swift) | pending |
| 8 | Fix onboarding dialog scroll area — universally responsive across all device sizes | pending |
| 9 | Audit and fix "LLM returned unexpected..." alert triggers — trace all false-positive paths | pending |
| 10 | Test all retrieval settings end-to-end with real data — verify every control works correctly | pending |

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
