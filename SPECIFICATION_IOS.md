# RAGFlow iOS — Specification

**Date**: 2026-03-23
**Platform**: iOS 17+ / iPadOS 17+
**Status**: Approved
**Replaces**: previous draft 2026-03-22

---

## Vision

A native Swift/SwiftUI app that is a **complete, independent RAGFlow implementation** — not a client for any server. All features of RAGFlow run on-device. No Docker. No backend. No dependency on any RAGFlow instance, ever.

The only optional external connections are:
- **Ollama** (local network LLM/embedding server — user's own Mac or NAS)
- **Claude API** (Anthropic hosted LLM — requires user's API key)
- **FoundationModels** (Apple on-device LLM/generation — iOS 26, no key, no network)
- **Agent tool APIs** (Brave Search, Jina Reader — only invoked when the LLM calls a tool, never receives corpus content)

---

## Corpus Privacy

Hard architectural constraint — not a preference:

- Original files: never leave the device
- Parsed text: stays on device; sent to Ollama only if user configures it and Ollama is on the same local network
- LLM context (retrieved chunks): sent only to the user-configured LLM backend (Ollama LAN, Claude API, or on-device FoundationModels)
- No document content is ever sent to any cloud service except a user-configured Claude API key
- Agent tools (web search, URL fetch) receive only the search query or URL — never document chunks

---

## Requirements

### Functional

| ID | Requirement |
|----|-------------|
| FR-1 | Multiple named knowledge bases — create, rename, delete, select as active |
| FR-2 | Ingest documents into any KB: PDF, ePub, JPEG/PNG/HEIC, MP3/M4A/WAV, MP4/MOV, TXT/MD/RTF/CSV, URL |
| FR-3 | PDF: PDFKit for born-digital; Vision OCR for scanned (auto-detect) |
| FR-4 | Image: Vision `VNRecognizeTextRequest`, on-device, accurate mode |
| FR-5 | Audio: `SFSpeechRecognizer` (< 60s segments) or `SpeechAnalyzer`/`SpeechModules` (iOS 26, longer audio) — `requiresOnDeviceRecognition = true` |
| FR-6 | Video: extract audio via `AVFoundation`, then FR-5 pipeline |
| FR-7 | URL: fetch via `URLSession` → clean with Jina Reader (`r.jina.ai/{url}`), store locally |
| FR-8 | Share Sheet extension: receive files from any app and ingest into selected KB |
| FR-9 | Chunking: sentence-boundary (~300 tokens, 50-token overlap) — default strategy |
| FR-10 | Embeddings: pluggable — Ollama (local), NLEmbedding (on-device, no server) |
| FR-11 | Hybrid search: FTS5 keyword candidates + vector cosine similarity re-rank (Accelerate/vDSP) |
| FR-12 | Chat against any KB; LLM backend pluggable: FoundationModels, Ollama, Claude API |
| FR-13 | Agent tools available during chat: Brave Search, Jina Reader URL fetch |
| FR-14 | Source citations shown for every assistant response — expandable chunk previews |
| FR-15 | Conversation history per KB, persisted across launches |
| FR-16 | Document management within each KB: list, preview metadata, delete |
| FR-17 | iPad: NavigationSplitView with KB list + document list + chat in three columns |
| FR-18 | Import via Files app, drag-and-drop (iPad), camera scan (VisionKit) |

### Non-Functional

| ID | Requirement |
|----|-------------|
| NFR-1 | Zero Docker dependency — the app has no knowledge of or connection to any RAGFlow server |
| NFR-2 | Fully offline capable when FoundationModels + NLEmbedding are used |
| NFR-3 | All document parsing runs on-device before any text goes anywhere |
| NFR-4 | API keys (Claude, Brave) stored in Keychain only |
| NFR-5 | App binary under 50MB; models downloaded on demand (Ollama) or system-provided (FoundationModels) |
| NFR-6 | Minimum deployment: iOS 17; FoundationModels features gated behind iOS 26 availability check |
| NFR-7 | No original file ever transmitted; parsed text sent only to user-configured local LLM |

---

## Architecture

### Layer Map

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI Views                                           │
│  KBListView  DocumentListView  ChatView  SettingsView    │
├─────────────────────────────────────────────────────────┤
│  ViewModels (MainActor ObservableObject)                 │
│  KBViewModel  DocumentViewModel  ChatViewModel           │
├──────────────────┬──────────────────┬───────────────────┤
│  RAG Pipeline    │  LLM Services    │  Storage          │
│  IngestService   │  LLMService      │  DatabaseService  │
│  ChunkService    │   ├ FoundationLLM│  (GRDB, SQLite)   │
│  EmbedService    │   ├ OllamaLLM    │                   │
│  RetrieveService │   └ ClaudeAPI    │                   │
├──────────────────┴──────────────────┴───────────────────┤
│  Document Parsers                                        │
│  PDFParser  EPUBParser  OCRParser  SpeechParser          │
│  VideoParser  TextParser  URLParser                      │
├─────────────────────────────────────────────────────────┤
│  Agent Tools                                             │
│  ToolExecutor  BraveSearch  JinaReader  (extensible)     │
└─────────────────────────────────────────────────────────┘
             ↕ Ollama (LAN, optional)
             ↕ Claude API (internet, optional, key required)
             ↕ FoundationModels (on-device, iOS 26)
```

### Data Model

```
KnowledgeBase
  id, name, description, createdAt, embeddingModel, llmBackend

Document
  id, kbId, title, sourceType (pdf/epub/image/audio/video/url/text)
  filePath (original, device-only), parsedAt, chunkCount

Chunk
  id, documentId, kbId, content, chapterTitle, position
  embedding BLOB (float32 array)

Conversation
  id, kbId, createdAt, title

Message
  id, conversationId, role, content, sources [ChunkSource], createdAt
```

### LLM Backend Protocol

```swift
protocol LLMService {
    func complete(messages: [LLMMessage], context: [Chunk]) async throws
        -> AsyncThrowingStream<String, Error>
}
// Implementations: FoundationLLMService, OllamaService, ClaudeService
```

### Embedding Backend Protocol

```swift
protocol EmbeddingService {
    func embed(texts: [String]) async throws -> [[Float]]
}
// Implementations: NLEmbeddingService (on-device), OllamaEmbeddingService
```

---

## Implementation Phases

### P2.2 — Knowledge Base Management *(highest priority)*

**Goal**: Replace flat book library with multiple named knowledge bases. This is the structural foundation everything else builds on.

**Tasks**:
- [ ] T1: SQLite schema — `knowledge_bases` table; migrate existing `books` → default KB "My Library"
- [ ] T2: `KBListView` — list KBs, swipe-to-delete, rename, create new
- [ ] T3: `DocumentListView` — documents within a KB, chunk count, source type badge
- [ ] T4: Three-column iPad layout: KB list | Document list | Chat
- [ ] T5: `KBViewModel` + `DocumentViewModel` — CRUD operations
- [ ] T6: Settings per KB: embedding model picker, LLM backend picker
- [ ] T7: Migrate `ChatView` to be scoped to a KB (not a single Book)
- [ ] T8: Conversation history persisted per KB

**Acceptance**:
- User can create "Work Notes", "Research", "Fiction" as separate KBs
- Documents in one KB are not retrieved when chatting in another
- Existing ePub + PDF ingest works into any KB

---

### P2.3 — Full Document Format Support

**Goal**: Match RAGFlow's document ingestion breadth — every common format handled on-device.

**Tasks**:
- [ ] T1: `OCRParser.swift` — Vision `VNRecognizeTextRequest`, accurate mode, page layout preserved
- [ ] T2: Scanned PDF auto-detection — check `PDFPage.string` length; fall back to OCR if < 50 chars/page
- [ ] T3: `SpeechParser.swift` — audio transcription; `SFSpeechRecognizer` for < 60s; `SpeechAnalyzer` for longer (iOS 26+); chunk at silence boundaries with `AVAudioEngine`
- [ ] T4: `VideoParser.swift` — extract audio track via `AVAssetExportSession`, then T3 pipeline
- [ ] T5: `URLParser.swift` — `URLSession` → `r.jina.ai/{url}` → store cleaned text as document
- [ ] T6: File picker expansion — add image, audio, video UTTypes to `fileImporter`
- [ ] T7: Share Sheet extension target — receive files from other apps, KB picker, ingest
- [ ] T8: Camera scan — `VNDocumentCameraViewController` (VisionKit), multi-page, then OCR pipeline
- [ ] T9: Drag-and-drop iPad ingest — `onDrop` handler in `DocumentListView`

**Acceptance**:
- Photo of a whiteboard → searchable text chunks
- 10-minute podcast → transcribed, chunked, retrievable
- Any web URL → content ingested and citable in chat

---

### P2.4 — On-Device LLM + Embeddings (Full Offline)

**Goal**: Zero network dependency. App works with no Ollama, no Claude API, no internet.

**Tasks**:
- [ ] T1: `NLEmbeddingService.swift` — wrap `NLEmbedding.sentenceEmbedding(for:)`, return `[Float]` arrays; same `EmbeddingService` protocol as Ollama
- [ ] T2: `FoundationLLMService.swift` — `LanguageModelSession`, RAG prompt assembly, tool-calling via `FoundationModels` tool API; stream tokens as `AsyncThrowingStream`
- [ ] T3: Embedding backend picker in KB settings — "On-Device (NLEmbedding)" / "Ollama"
- [ ] T4: LLM backend picker in KB settings — "On-Device (Apple Intelligence)" / "Ollama" / "Claude API"
- [ ] T5: iOS 26 availability gate — `if #available(iOS 26, *)` wraps FoundationModels usage; graceful error on iOS 17-25 if selected
- [ ] T6: Re-embed trigger — if embedding model changes for a KB, offer to re-embed all chunks
- [ ] T7: Offline indicator — Settings shows "Fully offline capable" when NLEmbedding + FoundationModels selected

**Acceptance**:
- Airplane mode: ingest a PDF, ask a question, get a grounded answer — zero network calls
- Embedding model swap re-embeds existing chunks correctly

---

### P2.5 — Advanced Retrieval + Agent Tools

**Goal**: Close the remaining retrieval quality and tool coverage gaps vs. RAGFlow.

**Tasks**:
- [ ] T1: Re-ranking — score FTS5 + vector candidates with combined BM25+cosine score; expose top-k tunable per KB
- [ ] T2: Chunking strategy options per KB — Sentence (default), Paragraph, Q&A extraction (extract question+answer pairs), Fixed-size
- [ ] T3: Q&A chunker — extract implicit Q&A pairs using LLM at ingest time, store as dedicated chunk type
- [ ] T4: Tool executor expansion — add Wikipedia search, calculator, `DateTool` (current date/time)
- [ ] T5: Brave Search API key field in Settings (already partially wired)
- [ ] T6: Tool activity UI — named labels per tool type in chat ("Searching Wikipedia…", "Calculating…")
- [ ] T7: Retrieval diagnostics view — show which chunks were retrieved, their scores, for any response

**Acceptance**:
- Q&A chunking on a textbook produces better answers than sentence chunking
- Tool use cites its sources (search results) separately from document citations

---

### P2.6 — iPad & UX Polish

**Goal**: Full iPad support, accessibility, App Store-ready UX.

**Tasks**:
- [ ] T1: Three-column `NavigationSplitView` — KB list | Document list | Chat (already partially done)
- [ ] T2: Keyboard shortcuts (⌘N new KB, ⌘D new document, ⌘K search)
- [ ] T3: Dark mode audit — all custom colors use semantic system colors
- [ ] T4: Dynamic Type — all text scales correctly to accessibility sizes
- [ ] T5: VoiceOver labels on all interactive elements
- [ ] T6: Haptics — success/error feedback on ingest complete, message send
- [ ] T7: Empty states — every screen has a clear empty state with a call to action
- [ ] T8: Ingest progress — per-document progress, cancellable, background capable
- [ ] T9: `PrivacyInfo.xcprivacy` — document all API usage for App Store review

---

### P2.7 — App Store

- Provisioning profiles, signing certificates
- App Store screenshots (iPhone 16, iPad Pro 13")
- Privacy policy URL (required for API key usage)
- App Store description and keywords
- TestFlight beta distribution first

---

## Resolved Decisions

| Topic | Decision |
|-------|----------|
| Docker / RAGFlow server | Not involved. Removed entirely from scope. |
| Connected mode (P2.1) | Cancelled. No server sync of any kind. |
| On-device embeddings | `NLEmbedding` — confirmed no embedding API in `FoundationModels` iOS 26 |
| Vector search | Accelerate/vDSP cosine similarity — sufficient for personal KB scale |
| sqlite-vec | Deferred to P3; no official iOS SPM; brute-force is fine |
| Audio transcription | `SFSpeechRecognizer` < 60s; `SpeechAnalyzer`/`SpeechModules` (iOS 26) for longer |
| LLM on-device | `FoundationModels.LanguageModelSession` — text generation + tool-calling confirmed |

---

## What's Already Built (P2.1 baseline)

| Component | File | Status |
|-----------|------|--------|
| ePub ingest + chunking | `RAGService.swift`, `EPUBParser` via EPUBKit | ✅ |
| PDF ingest (born-digital) | `PDFParser.swift` | ✅ |
| Embeddings (Ollama) | `EmbeddingService.swift` | ✅ |
| FTS5 + vector hybrid search | `DatabaseService.swift` | ✅ |
| Claude API LLM + streaming | `ClaudeService.swift` | ✅ |
| Ollama LLM + streaming | `OllamaService.swift` | ✅ |
| Tool use (Brave, Jina) | `ToolService.swift` | ✅ |
| Source citations UI | `ChatView.swift` | ✅ |
| Library + Chat UI | `LibraryView`, `ChatView` | ✅ |
| Settings + Keychain | `SettingsView`, `SettingsStore` | ✅ |
| NavigationSplitView (iPhone) | `ContentView.swift` | ✅ |

---

## Testing Strategy

| Layer | Approach |
|-------|----------|
| Parsers (PDF, OCR, Speech) | Unit tests with fixture files; assert chunk count and content |
| Chunker | Unit tests — chunk count, overlap boundaries, Q&A pair extraction |
| Embedding + retrieval | Unit tests with known vectors; assert top-k order is deterministic |
| LLM services | Protocol mock; assert message format and tool-call handling |
| KB CRUD | Integration tests against in-memory GRDB database |
| Full chat pipeline | XCTest UI test — ingest file, ask question, assert non-empty cited response |
| Privacy | Manual: Charles Proxy on LAN — assert zero corpus content reaches internet |

---

**Approved**: 2026-03-23
**OQ resolved**: 2026-03-23 (all)
