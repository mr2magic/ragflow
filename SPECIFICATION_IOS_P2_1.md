# P2.1 — Connected Mode: RAGFlow Client

**Parent spec**: `SPECIFICATION_IOS.md`
**Status**: Approved
**Approved**: 2026-03-23

---

## Problem Statement

The iOS app currently operates in standalone mode only (local ePub/PDF ingest, Ollama LLM, local SQLite vector store). Users who run RAGFlow on a home server, NAS, or cloud VM have no way to access their existing knowledge bases and agents from their iPhone or iPad. P2.1 adds a first-class connected mode that turns the iOS app into a mobile frontend for any RAGFlow instance.

---

## Requirements

### Functional

| ID | Requirement |
|----|-------------|
| FR-1 | App pings RAGFlow `/v1/health` on launch and on every network change |
| FR-2 | If RAGFlow is reachable, enter connected mode automatically |
| FR-3 | If RAGFlow becomes unreachable, fall back to standalone and display a banner with the reason (timeout / auth error / server error) |
| FR-4 | Banner auto-dismisses when connectivity is restored |
| FR-5 | Settings screen accepts RAGFlow base URL and Bearer token; URL stored in UserDefaults, token in Keychain |
| FR-6 | Library screen shows a single merged list of local books (standalone) and remote items (RAGFlow KBs + canvases), visually distinguished |
| FR-7 | Remote knowledge bases fetched from `GET /v1/datasets` |
| FR-8 | Remote agents/canvases fetched from `GET /v1/canvas` |
| FR-9 | Tapping a remote KB or canvas opens `ChatView`; inference runs entirely on the RAGFlow server via SSE streaming |
| FR-10 | Tapping a local book opens `ChatView` in standalone mode regardless of connection state |
| FR-11 | When importing a document in connected mode, a destination picker sheet offers: Local only / RAGFlow KB / Both |
| FR-12 | Uploading to RAGFlow sends parsed text chunks only — original files never leave the device |
| FR-13 | Remote items show a "RAGFlow" badge/icon; local items retain the existing book icon |
| FR-14 | Mode indicator visible in the Library nav bar: "Connected" or "Offline" |

### Non-Functional

| ID | Requirement |
|----|-------------|
| NFR-1 | Original document files are never transmitted to RAGFlow or any third party |
| NFR-2 | Bearer token stored exclusively in Keychain — never in UserDefaults, logs, or crash reports |
| NFR-3 | Health check timeout: 5 seconds. Connection retry: once before declaring fallback |
| NFR-4 | Remote item list refreshes on pull-to-refresh and on foreground resume |
| NFR-5 | SSE stream from RAGFlow must begin rendering within 3 seconds or show an error |
| NFR-6 | No minimum RAGFlow version assumed beyond what ships today; use only stable v1 API |

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `Services/Remote/RAGFlowClient.swift` | URLSession API client — auth headers, JSON requests, SSE streaming |
| `Services/Remote/ConnectivityMonitor.swift` | `NWPathMonitor` + health check; publishes `ConnectionState` |
| `Models/RemoteItem.swift` | `KnowledgeBase` and `Canvas` model types decoded from API |
| `Features/Library/IngestDestinationSheet.swift` | Sheet UI: "Where do you want to save this?" picker |
| `Features/Library/ConnectionBanner.swift` | Dismissible banner showing fallback reason |

### Modified Files

| File | Change |
|------|--------|
| `Features/Library/LibraryViewModel.swift` | Merge local `[Book]` + remote `[RemoteItem]`; observe `ConnectionState` |
| `Features/Library/LibraryView.swift` | Render merged list with visual distinction; embed `ConnectionBanner` |
| `Features/Chat/ChatViewModel.swift` | Route to `RAGFlowClient.stream()` for remote items, local LLM for books |
| `Features/Settings/SettingsView.swift` | Add RAGFlow URL + Bearer token fields; test-connection button |
| `Services/RAG/RAGService.swift` | Add `uploadToRAGFlow(chunks:targetKB:)` method |

### Connection State Machine

```
App Launch
    │
    ▼
ConnectivityMonitor.checkHealth()
    ├── reachable ──► .connected(url)     ──► fetch KBs + canvases
    └── unreachable ─► .fallback(reason)  ──► show banner, use local only

Network change (NWPathMonitor)
    ├── satisfied ──► re-run checkHealth()
    └── unsatisfied ─► .fallback(.noNetwork)

Manual retry (banner button)
    └── re-run checkHealth()
```

### Connection State Enum

```swift
enum ConnectionState: Equatable {
    case unknown
    case connected(baseURL: URL)
    case fallback(reason: FallbackReason)
}

enum FallbackReason {
    case timeout, authError, serverError(Int), noNetwork
    var displayMessage: String { ... }
}
```

---

## RAGFlow API Reference

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/v1/health` | Reachability check |
| `GET` | `/v1/datasets?page=1&page_size=50` | List knowledge bases |
| `GET` | `/v1/canvas` | List agents/canvases |
| `POST` | `/v1/canvas/{id}/completion` | Canvas chat (SSE, `query` field) |
| `POST` | `/v1/datasets/{id}/documents` | Upload document chunks to KB |

All requests include `Authorization: Bearer {token}` and `Content-Type: application/json`.

SSE format: `data: {"answer": "...", "done": false}` lines; stream ends with `data: {"done": true}`.

---

## Implementation Plan

### T1 — `ConnectivityMonitor` + health check `(traces: FR-1, FR-2, FR-3, FR-4, NFR-3)`

**Tasks:**
- Implement `ConnectivityMonitor` as `@MainActor ObservableObject`
- Use `NWPathMonitor` to observe network path changes
- On path `.satisfied`, fire `checkHealth()` — `GET /v1/health` with 5s timeout
- Parse result → publish `.connected` or `.fallback(reason)`
- Re-check on foreground resume (`scenePhase == .active`)
- Expose `retry()` for banner button

**Acceptance:** Connection state changes within 6s of network change; banner appears with correct reason string.

---

### T2 — `RAGFlowClient` API client `(traces: FR-7, FR-8, FR-9, FR-12, NFR-2, NFR-6)`

**Tasks:**
- `func datasets() async throws -> [KnowledgeBase]` — `GET /v1/datasets`
- `func canvases() async throws -> [Canvas]` — `GET /v1/canvas`
- `func stream(canvasId: String, query: String, context: [Chunk]) -> AsyncThrowingStream<String, Error>` — SSE via `URLSession.bytes`
- `func upload(chunks: [Chunk], datasetId: String) async throws` — POST parsed text
- Read Bearer token from Keychain inside client; never accept it as a parameter
- Map HTTP 401 → `FallbackReason.authError`; 5xx → `.serverError(code)`; timeout → `.timeout`

**Acceptance:** `datasets()` returns correct count against a live RAGFlow instance; SSE stream yields tokens within 3s.

---

### T3 — `RemoteItem` models `(traces: FR-6, FR-7, FR-8, FR-13)`

```swift
struct KnowledgeBase: Identifiable, Codable {
    let id: String
    let name: String
    let documentCount: Int
    let chunkCount: Int
    let createTime: Date
}

struct Canvas: Identifiable, Codable {
    let id: String
    let title: String
    let description: String?
    let updateTime: Date
}

enum LibraryItem: Identifiable {
    case local(Book)
    case remoteKB(KnowledgeBase)
    case remoteCanvas(Canvas)
    var id: String { ... }
}
```

---

### T4 — `LibraryViewModel` merge `(traces: FR-6, FR-10, FR-14, NFR-4)`

**Tasks:**
- Add `@Published var remoteItems: [LibraryItem] = []`
- Add `@Published var connectionState: ConnectionState = .unknown`
- `fetchRemote()` — call `RAGFlowClient.datasets()` + `.canvases()` concurrently, map to `LibraryItem`
- `var allItems: [LibraryItem]` — computed: local books + remote items, sorted by name
- Trigger `fetchRemote()` on `.connected` state change and on pull-to-refresh
- Filter/search applies to `allItems`

---

### T5 — `LibraryView` updates `(traces: FR-6, FR-13, FR-14)`

**Tasks:**
- Replace `List(vm.filteredBooks)` with `List(vm.filteredItems)`
- `LocalBookRow` — existing `BookRow` unchanged
- `RemoteKBRow` — cloud icon, KB name, document count, "RAGFlow" caption
- `RemoteCanvasRow` — agent icon, canvas title, description preview
- `.refreshable { await vm.fetchRemote() }`
- `ConnectionBanner` overlaid at top of list when `vm.connectionState == .fallback`
- Nav bar subtitle or toolbar badge: "Connected" (green dot) / "Offline" (gray dot)

---

### T6 — `ConnectionBanner` `(traces: FR-3, FR-4)`

```swift
struct ConnectionBanner: View {
    let reason: FallbackReason
    let onRetry: () async -> Void
    // Yellow/orange bar: "{reason.displayMessage} · Using local library"
    // Retry button on right
    // Auto-hides when state returns to .connected
}
```

---

### T7 — `ChatViewModel` routing `(traces: FR-9, FR-10)`

**Tasks:**
- `ChatViewModel` accepts `LibraryItem` instead of `Book`
- `case .local(let book)`: existing standalone path (FTS5 + Ollama/Claude)
- `case .remoteKB(let kb)`: retrieve via `RAGFlowClient.stream()` using canvas or dialog endpoint
- `case .remoteCanvas(let canvas)`: stream via `RAGFlowClient.stream(canvasId:)`
- Source citations: remote responses parse `reference_chunks` from SSE payload if present
- No local retrieval for remote items — RAGFlow does all retrieval

---

### T8 — `IngestDestinationSheet` `(traces: FR-11, FR-12)`

**Tasks:**
- Present as `.sheet` after file picker selection, only when `connectionState == .connected`
- Options: "Save to My Books" / "Upload to RAGFlow KB" (picker of KB names) / "Both"
- "Both" path: `RAGService.ingest()` locally AND `RAGFlowClient.upload(chunks:datasetId:)`
- If RAGFlow upload fails, local ingest still completes — show partial-success message
- In standalone mode: skip sheet, always ingest locally

---

### T9 — `SettingsView` updates `(traces: FR-5, NFR-2)`

**Tasks:**
- "RAGFlow Server" section: URL text field + Bearer token secure field (replaces plain text)
- Token saved via `SecItemAdd`/`SecItemUpdate` to Keychain on change
- "Test Connection" button: runs `ConnectivityMonitor.checkHealth()`, shows inline result
- Clear existing Keychain item on token field clear

---

## Testing Strategy

| Layer | Approach |
|-------|----------|
| `ConnectivityMonitor` | Unit test state transitions with mock `URLSession`; assert `.fallback` on timeout |
| `RAGFlowClient` | Unit tests with `URLProtocol` mock; assert auth header present; SSE parsing |
| `LibraryViewModel` merge | Unit test `allItems` ordering and filter with mixed local + remote fixture data |
| `ChatViewModel` routing | Unit test that `.remoteCanvas` path calls `RAGFlowClient.stream`, not local LLM |
| `IngestDestinationSheet` | UI test: import a file in connected mode, select "Both", assert local book + upload call |
| Integration | Manual: connect to local RAGFlow, browse KBs, send a query, verify streamed response |

---

## Open Questions

| # | Question | Impact | Resolution |
|---|----------|--------|------------|
| OQ-1 | Does `GET /v1/canvas` exist, or is it `GET /v1/canvases`? | API client URL | Check `canvas_app.py` route registration before T2 |
| OQ-2 | What is the exact SSE payload schema for canvas completion? | SSE parser | Inspect live response or `canvas_app.py` before T2 |
| OQ-3 | Does `/v1/datasets/{id}/documents` accept pre-chunked text, or raw file? | Upload format | Check `document_app.py` before T8 |

---

## Dependency on Existing Work

- Requires: P2 standalone mode (already complete) — `LibraryViewModel`, `ChatViewModel`, `DatabaseService`, `RAGService` all exist
- Does not require: P2.2 (additional formats), P2.3 (FoundationModels), P2.4 (iPad polish)
- Parallel-safe with: P2.2, P2.4

---

**Generated by**: deft speckit workflow
**Approved**: 2026-03-23
