# RAGFlow iOS — Specification

**Date**: 2026-03-22
**Platform**: iOS 26+ / iPadOS 26+
**Status**: Draft
**Parent spec**: [SPECIFICATION.md](SPECIFICATION.md)

---

## Overview

A native Swift/SwiftUI app that brings RAGFlow to iPhone and iPad. The app operates in two modes:

- **Connected mode**: Communicates with a local RAGFlow instance (Docker on Mac, home network) over LAN. RAGFlow handles chunking, embedding, indexing, and LLM. No corpus content reaches the internet.
- **Standalone mode**: No RAGFlow reachable. Full on-device RAG pipeline using Foundation Models (iOS 26) and NLEmbedding. Knowledge bases stored in local SQLite.

Documents are always parsed on-device before anything is sent anywhere. Original files never leave the device. In connected mode, parsed text is sent to local RAGFlow over the home network — not the internet.

---

## Corpus Privacy Constraint

This is a hard architectural constraint, not a preference:

- Original document files: never transmitted. Stay on device.
- Parsed text: may be sent to local RAGFlow (same home network). Never to internet.
- Retrieved chunks used as LLM context: sent to local RAGFlow LLM layer only. Never to cloud LLM APIs directly from the app.
- URLs ingested: fetched from the public web (intended behavior). Resulting content stored locally.

---

## Requirements

### Functional

| ID | Requirement |
|----|-------------|
| FR-1 | Connect to a local RAGFlow instance by IP/hostname; authenticate via Bearer token |
| FR-2 | Browse and query all knowledge bases on the connected RAGFlow instance |
| FR-3 | Chat interface against any RAGFlow knowledge base or canvas |
| FR-4 | Ingest documents from Files app, Photos, Share Sheet, clipboard, and direct camera capture |
| FR-5 | Supported ingest formats: PDF, JPEG/PNG/HEIC/image (OCR), MP3/M4A/WAV/audio (transcription), MP4/MOV/video (transcription), TXT/MD/RTF/CSV, EPUB, Pages/Numbers/Keynote (best-effort), URLs |
| FR-6 | All document parsing runs on-device before any data leaves the phone |
| FR-7 | Standalone offline mode: full RAG pipeline on-device when RAGFlow unreachable |
| FR-8 | Local knowledge bases in standalone mode persist in on-device SQLite |
| FR-9 | URL ingestion: fetch and clean web content via Jina Reader, store locally |
| FR-10 | Sync: documents ingested offline can be pushed to RAGFlow when reconnected |
| FR-11 | iPad: full split-view and multitasking support |

### Non-Functional

| ID | Requirement |
|----|-------------|
| NFR-1 | Corpus privacy: no document content transmitted to internet under any circumstance |
| NFR-2 | iOS 26+ / iPadOS 26+ minimum. No visionOS target. |
| NFR-3 | All parsing and standalone inference runs on-device, no cloud dependency |
| NFR-4 | Initial setup (no model download in connected mode): under 2 minutes |
| NFR-5 | Query response in connected mode: follows RAGFlow latency (~3-10s) |
| NFR-6 | Query response in standalone mode: under 15s on A16+ |
| NFR-7 | App binary under 50MB. Models downloaded separately on demand. |
| NFR-8 | Sideload-first. App Store packaging deferred to Phase 4. |

---

## Architecture

### Two-Mode Design

```
┌──────────────────────────────────────────────────────┐
│                    iOS App                           │
│                                                      │
│   ┌─────────────────┐     ┌──────────────────────┐  │
│   │  Capture &      │     │   Chat / Query UI    │  │
│   │  Ingestion UI   │     │                      │  │
│   └────────┬────────┘     └──────────┬───────────┘  │
│            │                         │               │
│   ┌────────▼─────────────────────────▼───────────┐  │
│   │              Document Parser                 │  │
│   │   PDFKit │ Vision │ Speech │ Text │ EPUB     │  │
│   │          Always on-device                    │  │
│   └────────────────────┬─────────────────────────┘  │
│                        │                             │
│   ┌────────────────────▼─────────────────────────┐  │
│   │              Mode Router                     │  │
│   │         RAGFlow reachable? Y / N             │  │
│   └──────────┬───────────────────────┬───────────┘  │
│              │                       │               │
│   ┌──────────▼──────────┐ ┌──────────▼────────────┐ │
│   │   Connected Mode    │ │   Standalone Mode      │ │
│   │                     │ │                        │ │
│   │  RAGFlow REST API   │ │  Foundation Models     │ │
│   │  (local LAN only)   │ │  NLEmbedding           │ │
│   │  KB browse/query    │ │  SQLite vector store   │ │
│   │  Document upload    │ │  On-device chunking    │ │
│   └─────────────────────┘ └────────────────────────┘ │
│                                                      │
│   ┌──────────────────────────────────────────────┐  │
│   │           Local Storage (always)             │  │
│   │  Original files │ Parsed text │ Local SQLite │  │
│   │  Pending sync queue for offline ingestion    │  │
│   └──────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
                    │ LAN only, never internet
                    ▼
          ┌──────────────────────┐
          │   RAGFlow on Mac     │
          │   Docker :8080       │
          │   Existing instance  │
          └──────────────────────┘
```

### Connected Mode Detail

- Discovers RAGFlow by manually configured IP:port (e.g. `192.168.1.x:8080`)
- Authenticates with user's RAGFlow Bearer token (stored in iOS Keychain)
- Uses existing RAGFlow REST API:
  - `GET /v1/dataset` — list knowledge bases
  - `POST /v1/dataset/{id}/document` — upload parsed document text
  - `POST /v1/canvas/{id}/completion` — chat with canvas (query field)
  - `POST /v1/retrieval` — direct retrieval if needed
- Parsed text (not original file) is what gets sent to RAGFlow
- RAGFlow's configured LLM (Claude, OpenAI, Ollama, etc.) handles generation
- No changes required to the RAGFlow backend

### Standalone Mode Detail

- Triggered automatically when RAGFlow is unreachable
- LLM: `FoundationModels.framework` — Apple Intelligence on-device model (iOS 26, no download)
- Embeddings: `NLEmbedding` (`NaturalLanguage.framework`) — built-in sentence embeddings, no download
- Vector store: SQLite with manual cosine similarity search (pure Swift, no extension dependency)
- Chunking: sentence-boundary chunking in Swift (~300 tokens per chunk, 50-token overlap)
- Knowledge bases created offline are local-only until synced to RAGFlow

**Open question at implementation time**: Does `FoundationModels.framework` in the shipped iOS 26 expose a public embedding API? If yes, prefer it over `NLEmbedding`. If no, `NLEmbedding` is the fallback. Architecture supports either.

**Open question at implementation time**: Is sqlite-vec available as a Swift Package for iOS by the time of implementation? If yes, use it for ANN search. If no, brute-force cosine similarity is sufficient for personal-scale knowledge bases (<50K chunks).

### Document Parser Layer

Always runs on-device, before anything is sent anywhere.

| Format | Framework | Notes |
|--------|-----------|-------|
| PDF (born-digital) | PDFKit | `PDFDocument` text extraction per page |
| PDF (scanned) | Vision `VNRecognizeTextRequest` | On-device OCR, accurate layout |
| JPEG / PNG / HEIC / image | Vision `VNRecognizeTextRequest` | On-device OCR |
| MP3 / M4A / WAV / audio | `SFSpeechRecognizer` | `requiresOnDeviceRecognition = true`. Chunk at silence boundaries using `AVAudioEngine`. |
| MP4 / MOV / video | `AVAssetImageGenerator` + Speech | Extract audio track via `AVAssetExportSession`, then transcribe |
| TXT / MD / RTF | `NSAttributedString` / native | Trivial |
| CSV | Swift `split` | Rows joined as structured text |
| EPUB | `ZipArchive` + XML | Parse OPF manifest, read HTML content files in spine order, strip tags |
| Pages / Numbers / Keynote | `QLPreviewController` text extraction | Best-effort. Lossy for structured content. Labeled as such in UI. |
| URL | `URLSession` + Jina Reader (`r.jina.ai/{url}`) | Fetches public web content. Result stored locally as corpus. |

### Local Storage

```
App Documents/
├── originals/          # Original files, never transmitted
│   └── {uuid}.{ext}
├── parsed/             # Extracted text per document
│   └── {uuid}.txt
└── ragflow_ios.sqlite  # Local KB, chunks, embeddings, sync queue
    ├── documents
    ├── chunks
    ├── embeddings      # NLEmbedding float arrays (blob)
    ├── local_kbs
    └── sync_queue      # Pending uploads for when reconnected
```

---

## Implementation Plan

### P2.1 — Connected Mode: RAGFlow Client

**Goal**: Working mobile frontend to existing RAGFlow.

**Tasks**:
- [ ] T1: Xcode project, SwiftUI app target, iOS 26 deployment target
- [ ] T2: Settings screen — RAGFlow URL, Bearer token input, stored in Keychain
- [ ] T3: Reachability check — ping RAGFlow health endpoint on launch and network change
- [ ] T4: Knowledge base list screen (`GET /v1/dataset`)
- [ ] T5: Chat screen against selected KB via canvas completion API (`POST /v1/canvas/{id}/completion`, `query` field)
- [ ] T6: Streaming response display (SSE parsing from RAGFlow)
- [ ] T7: Mode indicator in UI (connected / standalone)

**Acceptance**:
- Can connect to local RAGFlow, browse KBs, and chat against them from iPhone/iPad
- Bearer token stored securely in Keychain, not in UserDefaults

---

### P2.2 — Document Ingestion Pipeline

**Goal**: Parse any supported file on-device and upload parsed text to RAGFlow.

**Tasks**:
- [ ] T1: File picker (`UIDocumentPickerViewController`) — all supported UTTypes
- [ ] T2: Share Sheet extension — receive files from other apps
- [ ] T3: PDF parser (PDFKit for digital, Vision for scanned — auto-detect by checking if PDFPage has text)
- [ ] T4: Image OCR (Vision `VNRecognizeTextRequest`, accurate mode)
- [ ] T5: Audio transcription (Speech framework, on-device, chunked at silence with `AVAudioEngine`)
- [ ] T6: Video ingestion (extract audio via AVFoundation, then T5 pipeline)
- [ ] T7: Plain text formats (TXT, MD, RTF, CSV)
- [ ] T8: EPUB parser (ZipArchive + OPF manifest + HTML strip)
- [ ] T9: Pages/Numbers/Keynote (QuickLook text, labeled best-effort in UI)
- [ ] T10: URL ingestion (URLSession → `r.jina.ai/{url}` → store content)
- [ ] T11: Chunking (sentence-boundary, ~300 tokens, 50-token overlap, pure Swift)
- [ ] T12: Upload parsed text to RAGFlow selected KB (`POST /v1/dataset/{id}/document`)
- [ ] T13: Ingestion progress UI (per-file status, error states)

**Acceptance**:
- All formats ingest without transmitting original files
- Parsed text visible in RAGFlow KB after upload
- Failed ingestion shows clear error; partial success handled per-file

---

### P2.3 — Standalone Offline Mode

**Goal**: Full RAG pipeline on-device when RAGFlow is unreachable.

**Tasks**:
- [ ] T1: SQLite schema for local KBs, chunks, embeddings, sync queue (`GRDB.swift`)
- [ ] T2: `NLEmbedding` integration — embed chunks at ingestion time, store as blob
- [ ] T3: Cosine similarity search in Swift — top-k retrieval from local embeddings
- [ ] T4: `FoundationModels` integration — `LanguageModelSession`, RAG prompt assembly
- [ ] T5: Fallback chain: Foundation Models unavailable → surface clear error to user
- [ ] T6: Local KB management UI (create, rename, delete local knowledge bases)
- [ ] T7: Sync queue — track offline-ingested documents, upload to RAGFlow on reconnect
- [ ] T8: Mode auto-switch — seamless transition when network state changes mid-session
- [ ] T9: Resolve open question: Foundation Models embedding API available? If yes, prefer over NLEmbedding.
- [ ] T10: Resolve open question: sqlite-vec iOS SPM available? If yes, replace brute-force search.

**Acceptance**:
- Full query cycle works with no network
- Answers grounded in local documents
- On reconnect, pending documents sync to RAGFlow automatically

---

### P2.4 — iPad & Polish

**Goal**: Full iPad support, UX polish, sideload-ready.

**Tasks**:
- [ ] T1: iPad split-view layout (KB list + chat side by side)
- [ ] T2: Drag-and-drop file ingestion on iPad
- [ ] T3: Camera capture — live document scan via VisionKit `VNDocumentCameraViewController`
- [ ] T4: Haptics, loading states, empty states, error messages
- [ ] T5: On-device diagnostic view (chunk count, embedding count, sync queue depth) — no corpus content exposed
- [ ] T6: Dark mode, Dynamic Type, accessibility labels

**Acceptance**:
- App usable one-handed on iPhone and in split-view on iPad
- No crashes on file types that fail parsing — graceful degradation

---

### P2.5 — App Store Prep *(Deferred)*

- Proper provisioning, entitlements review
- Privacy manifest (`PrivacyInfo.xcprivacy`) — document all API usage
- App Store screenshots, description
- Apple Intelligence / Foundation Models entitlement if required
- Review guideline audit

---

## Open Questions

These are unresolved at spec time. Must be answered before P2.3 begins.

| # | Question | Impact | How to resolve |
|---|----------|--------|----------------|
| OQ-1 | Does shipped iOS 26 `FoundationModels` expose a public embedding API? | If yes: use it instead of `NLEmbedding`, better quality | Check Apple Developer docs / release notes |
| OQ-2 | Is sqlite-vec available as an iOS Swift Package? | If yes: replace brute-force cosine search, better ANN performance at scale | Check sqlite-vec GitHub releases |
| OQ-3 | SFSpeechRecognizer on-device session limits in iOS 26? | Affects audio chunking strategy | Test on device / check release notes |

---

## Testing Strategy

| Layer | Approach | Note |
|-------|----------|------|
| Parsers | Unit tests with fixture files (PDF, image, audio, EPUB) | No network needed |
| Chunker | Unit tests — verify chunk count, overlap, boundaries | Pure logic |
| Embedding + retrieval | Unit tests with known vectors, assert top-k correct | Deterministic |
| Connected mode API | Integration tests against local RAGFlow — mock for CI | Requires running instance for full test |
| Standalone mode E2E | XCTest UI test — ingest file, query, assert non-empty response | On-device only |
| Privacy | Manual audit: Charles Proxy on same network, assert zero corpus traffic to internet | Per release |

---

## Secrets & Configuration

- RAGFlow Bearer token: iOS Keychain (`kSecClassGenericPassword`)
- RAGFlow URL: `UserDefaults` (not sensitive)
- No API keys in source code
- No analytics, no crash reporting (corpus privacy constraint precludes any telemetry)

---

## Dependencies

| Library | Purpose | Why |
|---------|---------|-----|
| `GRDB.swift` | SQLite ORM | Well-maintained, Swift-native, no C bridging needed |
| `ZipArchive` (or `ZIPFoundation`) | EPUB unpacking | EPUB is a ZIP container |
| No networking library | URLSession is sufficient | Avoid dependencies for security-sensitive data paths |

All Apple frameworks used (`PDFKit`, `Vision`, `Speech`, `AVFoundation`, `NaturalLanguage`, `FoundationModels`) are built-in. No ML model downloads required for core functionality.

---

**Approved**: pending
**Generated**: 2026-03-22
