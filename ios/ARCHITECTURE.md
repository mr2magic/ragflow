# Architecture Reference

This document describes the design of RAGFlow Mobile — its layers, data flow, key services, and database schema — intended for engineers joining the project.

---

## Table of Contents

1. [Pattern: MVVM](#1-pattern-mvvm)
2. [Layer Map](#2-layer-map)
3. [App Entry Point](#3-app-entry-point)
4. [Feature Modules](#4-feature-modules)
5. [Models](#5-models)
6. [Services](#6-services)
7. [Database Schema](#7-database-schema)
8. [RAG Pipeline](#8-rag-pipeline)
9. [LLM Integration](#9-llm-integration)
10. [Agent Workflows](#10-agent-workflows)
11. [Background Processing](#11-background-processing)
12. [Navigation Flow](#12-navigation-flow)
13. [Data Flow: Chat Request](#13-data-flow-chat-request)
14. [Data Flow: Document Import](#14-data-flow-document-import)
15. [Security Model](#15-security-model)

---

## 1. Pattern: MVVM

The codebase uses **Model-View-ViewModel** throughout:

| Layer | Responsibility | Threading |
|-------|---------------|-----------|
| **View** | SwiftUI views — present data, forward gestures | `@MainActor` |
| **ViewModel** | `ObservableObject` — manages state, calls services | `@MainActor` |
| **Service** | Business logic — parsing, networking, database | async/await |
| **Model** | Plain data structs — `Codable`, `Identifiable` | Any |

Rules:
- Views never call services directly — always through a ViewModel.
- ViewModels are `@MainActor` to keep published property updates on the main thread.
- Services are stateless (or singletons with isolated internal state).

---

## 2. Layer Map

```
RAGFlowMobile/
├── App/                        — Entry point, root view, global state
├── Features/                   — One folder per vertical feature
│   ├── KB/                     — KBListView, KBDetailView, KBListViewModel
│   ├── Chat/                   — ChatView, ChatViewModel, ConversationsListView
│   ├── Library/                — LibraryView, LibraryViewModel, DocumentDetailView
│   ├── Workflows/              — WorkflowListView, WorkflowDetailView, WorkflowListViewModel
│   ├── Settings/               — SettingsView
│   └── Onboarding/             — OnboardingView
├── Models/                     — KnowledgeBase, Book, Chunk, Message, Workflow, LLMConfig
└── Services/
    ├── Storage/                — DatabaseService (GRDB), SettingsStore (Keychain)
    ├── RAG/                    — RAGService, parsers, Chunker, EmbeddingService
    ├── LLM/                    — LLMService protocol + Claude/OpenAI/Ollama implementations
    └── Agent/                  — WorkflowRunner, WorkflowTemplate, WorkflowStep
```

---

## 3. App Entry Point

### `RAGFlowMobileApp.swift`
- `@main` App struct.
- Registers `BGTaskScheduler` handlers in `init()` before the first scene connects. This is an iOS requirement — handlers must be registered before `sceneWillEnterForeground`.
- Task identifiers:
  - `com.dhorn.ragflowmobile.import`
  - `com.dhorn.ragflowmobile.workflow`

### `ContentView.swift`
- Detects `horizontalSizeClass` and renders either:
  - **iPhone** → `TabView` (KB, Workflows, Settings tabs)
  - **iPad** → `NavigationSplitView` (KB sidebar + detail)
- Presents `OnboardingView` as a `fullScreenCover` on first launch.
- Requests local notification authorization at launch.

### `AppState.swift`
- `@MainActor` singleton. Minimal right now — designed as a home for future global state (e.g., sync status, push tokens).

---

## 4. Feature Modules

### KB (Knowledge Base)

| File | Role |
|------|------|
| `KBListView.swift` | iPad sidebar list; context menus for rename/settings/delete |
| `PhoneKBListView.swift` | iPhone NavigationLink-based equivalent |
| `KBListViewModel.swift` | CRUD — create, rename, delete KBs; calls `DatabaseService` |
| `KBDetailView.swift` | `TabView` container: Chat (tab 0) + Documents (tab 1) |
| `KBRetrievalSettingsSheet.swift` | Per-KB RAG config: topK, topN, similarity threshold, chunk method |

**Creation flow**: New KB → `KBListViewModel.createKB()` → `DatabaseService.saveKB()` → `pendingAutoImportKBId` triggers auto-navigation to Documents tab with file importer pre-opened.

---

### Chat

| File | Role |
|------|------|
| `ConversationsListView.swift` | Session list per KB; create, rename, delete sessions |
| `ChatView.swift` | Message list, KB scope bar, input bar, citations |
| `ChatViewModel.swift` | Retrieval orchestration, LLM streaming, message persistence |

**Key ChatViewModel behaviors**:
- Supports multi-KB search — user can add/remove KBs from the scope bar.
- User message is persisted immediately (before LLM call) so it survives cancellation.
- Assistant message is persisted only on successful completion or `CancellationError`.
- Stream is wrapped in `UIApplication.beginBackgroundTask` for a 30-second background fence.
- `stop()` cancels the `Task` which propagates `CancellationError` through the `AsyncThrowingStream`.

---

### Library

| File | Role |
|------|------|
| `LibraryView.swift` | Document list, import button, progress overlay, empty state |
| `LibraryViewModel.swift` | `ingestURLs()`, `importFromURL()`, progress tracking, CRUD |

**Import flow**: File picker → security-scoped access → temp copy → `RAGService.ingest()` → parse → chunk → embed → save.

The `DocumentDetailView` (defined in `LibraryView.swift`) shows per-book chunk list with search — useful for verifying parse quality.

---

### Workflows

| File | Role |
|------|------|
| `WorkflowListView.swift` | Workflow list; hosts `NewWorkflowSheet` |
| `WorkflowListViewModel.swift` | CRUD; converts template to concrete `[WorkflowStep]`; saves as JSON |
| `WorkflowDetailView.swift` | Pipeline visualization, input area, step log, streaming output, run history |

Steps are encoded as a JSON array (`stepsJSON`) on `Workflow` records and decoded on demand.

---

### Settings

`SettingsView.swift` covers:
- LLM provider selection
- API key entry (SecureField → Keychain via `SettingsStore`)
- Ollama host + model picker + connection test
- Brave Search API key
- Debug reset controls (gated with `#if DEBUG`)

---

### Onboarding

`OnboardingView.swift` — 8-page carousel shown once at first launch. Controlled by `AppStorage("hasCompletedOnboarding")`.

---

## 5. Models

### `KnowledgeBase`
```
id: String          — UUID string, "default" for the built-in KB
name: String
createdAt: Date
topK: Int           — how many chunks to retrieve (default 10)
topN: Int           — reranker candidates (default 50)
similarityThreshold: Double   — minimum cosine score (default 0.2)
chunkMethod: String — General | Q&A | Paper | Table
chunkSize: Int      — target words per chunk (default 512)
chunkOverlap: Int   — overlap words (default 64)
```

### `Book` (ingested document)
```
id: String
kbId: String
title: String
author: String
filePath: String    — path to original file
addedAt: Date
chunkCount: Int
fileType: String    — "pdf", "epub", "docx", etc.
pageCount: Int?
wordCount: Int?
sourceURL: String?  — if imported from URL
```

### `Chunk`
```
id: String
bookId: String
content: String
chapterTitle: String?
position: Int       — order within book
embedding: Data?    — Float32 BLOB (384 or 768 dimensions depending on model)
```

### `Message`
```
id: UUID
role: "user" | "assistant"
content: String
sources: [ChunkSource]
toolActivity: String?   — e.g. "Searching Brave…"
timestamp: Date
```

### `ChatSession`
```
id: String
kbId: String
name: String
createdAt: Date
```

### `Workflow`
```
id: String
name: String
templateId: String
kbId: String
stepsJSON: String   — JSON-encoded [WorkflowStep]
createdAt: Date
```

### `WorkflowRun`
```
id: String
workflowId: String
input: String
output: String
status: "running" | "completed" | "failed"
stepLogJSON: String — JSON-encoded step log entries
createdAt: Date
```

### `LLMConfig`
```
provider: LLMProvider   — .claude | .openAI | .ollama
claudeApiKey: String
openAIApiKey: String
braveSearchApiKey: String
ollamaHost: String      — e.g. "http://localhost:11434"
ollamaModel: String     — e.g. "llama3.2"
```

---

## 6. Services

### `DatabaseService` (singleton)
- SQLite at `~/Library/Application Support/ragflow.sqlite`
- GRDB `DatabaseQueue` with **8 append-only migrations**
- Provides typed CRUD for all entities
- FTS5 index on `chunks` using the Porter stemmer tokenizer

### `SettingsStore` (singleton, `ObservableObject`)
- Source of truth for `LLMConfig`
- **Keychain**: `claude_api_key`, `openai_api_key`, `brave_search_api_key`
- **UserDefaults**: `llm_provider`, `ollama_host`, `ollama_model`
- `isConfigured` computed property — `true` when minimum credentials are present

### `RAGService` (singleton, `ObservableObject`)
- `@Published var embedProgress: Double` — drives progress bar in LibraryView
- `@Published var ingestPhase: String` — human-readable status string
- `ingest(url:kbId:) async throws -> Book` — main entry point for document import
- `retrieve(query:kb:) async -> [Chunk]` — hybrid BM25 + vector search

### `EmbeddingService`
- `POST {ollamaHost}/api/embed` with model `nomic-embed-text`
- Returns `[[Float]]` embeddings
- `cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float` via `vDSP`

### `LLMService` (protocol)
```swift
protocol LLMService {
    func complete(
        messages: [LLMMessage],
        context: String,
        books: [Book]
    ) -> AsyncThrowingStream<String, Error>
}
```
Implementations: `ClaudeService`, `OpenAIService`, `OllamaService`

Factory: `makeLLMService(config: LLMConfig) -> any LLMService`

### `WorkflowRunner` (`ObservableObject`)
- `run(workflow:input:) async -> WorkflowRun`
- Executes `[WorkflowStep]` sequentially; maintains a `StepContext` dictionary for slot passing
- Streams final LLM step output to `@Published var streamingOutput`

---

## 7. Database Schema

### Migrations (append-only — never edit existing migrations)

| # | Changes |
|---|---------|
| v1 | `books`, `chunks`, `chunks_fts` (FTS5 Porter) |
| v2 | `chunks.embedding` BLOB |
| v3 | `knowledge_bases`; seed default KB; `books.kbId` |
| v4 | `messages`, `message_sources` |
| v5 | `workflows`, `workflow_runs` |
| v6 | `chat_sessions`; `messages.sessionId` |
| v7 | `knowledge_bases.topK` |
| v8 | KB: `topN`, `chunkMethod`, `chunkSize`, `chunkOverlap`, `similarityThreshold`; Books: `fileType`, `pageCount`, `wordCount`, `sourceURL`; Sources: `documentTitle` |

### Table Relationships

```
knowledge_bases
    │
    ├──< books (kbId)
    │       └──< chunks (bookId)
    │               └── chunks_fts (content) [FTS5 mirror]
    │
    ├──< chat_sessions (kbId)
    │       └──< messages (sessionId)
    │               └──< message_sources (messageId)
    │
    └──< workflows (kbId)
            └──< workflow_runs (workflowId)
```

### Adding a Migration

Add a new `migrator.registerMigration("v9") { db in ... }` block at the bottom of `DatabaseService.swift`. Never modify existing migrations.

---

## 8. RAG Pipeline

### Ingest Pipeline

```
File URL
  │
  ▼
Parser (format dispatch)
  ├── PDFParser      → PDFKit page-by-page text extraction
  ├── EPUB           → EPUBKit chapter content
  ├── OfficeParser   → Unzip + XML extraction (DOCX/XLSX/PPTX/ODF)
  ├── EMLParser      → Email headers + body
  └── Fallback       → Plain text / HTML / CSV / code files
  │
  ▼
Chunker (NLTokenizer sentence boundaries)
  ├── Group sentences into ~chunkSize-word windows
  ├── Overlap: chunkOverlap words shared between adjacent chunks
  └── Word-boundary fallback for sentences > chunkSize
  │
  ▼
DatabaseService.saveChunks()   — persist chunks without embeddings
  │
  ▼
EmbeddingService.embed()       — batch POST to Ollama /api/embed
  │
  ▼
DatabaseService.updateEmbeddings()  — write Float32 BLOBs
```

Progress is streamed to `RAGService.ingestPhase` and `embedProgress` for UI feedback.

---

### Retrieval Pipeline

```
User query string
  │
  ├── BM25 keyword search
  │     └── FTS5 MATCH on chunks_fts → ranked [Chunk]
  │
  └── Vector search
        ├── EmbeddingService.embed(query) → query vector
        └── Cosine similarity against all chunk.embedding BLOBs → ranked [Chunk]
  │
  ▼
Reciprocal Rank Fusion (RRF)
  └── Merge BM25 + vector ranked lists → unified [Chunk] ordered by RRF score
  │
  ▼
topK filter → [Chunk] passed to LLM as context
```

If Ollama is unavailable, embedding returns nil; retrieval falls back to BM25 only.

---

## 9. LLM Integration

### Claude (`ClaudeService`)

- Endpoint: `https://api.anthropic.com/v1/messages`
- Model: `claude-sonnet-4-6`
- Max tokens: 2048
- Tool use loop (max 3 rounds) for `brave_search` and `jina_reader`
- After tool resolution, streams final text response word-by-word (5 ms delay)

### OpenAI (`OpenAIService`)

- Endpoint: `https://api.openai.com/v1/chat/completions`
- Model: `gpt-4o`
- Non-streaming request; simulates streaming word-by-word after response arrives

### Ollama (`OllamaService`)

- Endpoint: `{host}/api/generate` or `/api/chat`
- True streaming — tokens yielded as they arrive
- Model configurable in Settings; no auth

### System Prompt (`buildEnterprisePrompt`)

All providers receive a structured system prompt that includes:
- List of KB documents (title, author, type)
- Retrieved passages numbered `[1]`, `[2]`, etc.
- Instructions to cite passages, synthesize across documents, and admit uncertainty

---

## 10. Agent Workflows

Workflows are sequences of typed `WorkflowStep` nodes executed by `WorkflowRunner`.

### Step Types

| Type | Description |
|------|-------------|
| `begin` | Copy `{input}` into context slot |
| `retrieve` | Run hybrid search; write passages to output slot |
| `rewrite` | LLM reformulation of a slot (query expansion) |
| `llm` | Full LLM call with prompt template |
| `message` | Static template interpolation (no LLM) |
| `webSearch` | `brave_search` tool call; write results to slot |
| `answer` | Designate a slot as the final output |

### Slot System

Steps communicate via a `StepContext: [String: String]` dictionary. Templates use `{slotName}` placeholders rendered by `context.render(template)`.

### Built-in Templates

| Template | Steps |
|----------|-------|
| RAG Q&A | Begin → Retrieve → LLM Answer |
| Deep Summarizer | Begin → Retrieve (broad) → LLM Summarize |
| Keyword Expander | Begin → LLM Extract Keywords → Retrieve → LLM Answer |
| Multi-Hop Researcher | Begin → Retrieve → LLM Identify Gaps → Retrieve → LLM Synthesize |
| Balanced Analysis | Begin → Retrieve → LLM Multi-Perspective |
| Custom | Begin → Retrieve → Custom LLM → Answer |

---

## 11. Background Processing

### iOS 26+ (BGContinuedProcessingTask)

Both document import and workflow execution use `BackgroundTaskCoordinator` which submits a `BGContinuedProcessingTaskRequest`. This allows unlimited background time for these long-running operations, reported to the system via a hierarchical `Progress` tree.

```
BackgroundTaskCoordinator
  ├── beginImport(fileCount:)      — submit BGContinuedProcessingTaskRequest
  ├── advanceImport()              — increment Progress.completedUnitCount
  └── finishImport(success:)      — task.setTaskCompleted(success:)
```

### iOS 17–25 Fallback

Uses `UIApplication.beginBackgroundTask(withName:)` which provides approximately 30 seconds of background execution.

### Chat Streaming

Chat streaming is not a `BGContinuedProcessingTask` — it uses `UIApplication.beginBackgroundTask` in `ChatViewModel.send()`. This is intentional: URLSession streaming tasks don't survive background task replacement.

---

## 12. Navigation Flow

### iPhone (compact)

```
TabView
├── Tab 0: PhoneKBListView (NavigationStack)
│         └── KBDetailView
│               ├── Tab 0: ConversationsListView
│               │         └── (NavigationDestination) ChatView
│               └── Tab 1: LibraryView
│                         └── (Sheet) DocumentDetailView
├── Tab 1: WorkflowListView (NavigationStack)
│         └── WorkflowDetailView
└── Tab 2: SettingsView
```

### iPad (regular)

```
NavigationSplitView
├── Sidebar: KBListView
│     [toolbar] → (Sheet) SettingsView
│              → (Sheet) WorkflowListView → WorkflowDetailView
└── Detail: KBDetailView
      ├── Tab 0: ConversationsListView → ChatView
      └── Tab 1: LibraryView → DocumentDetailView
```

---

## 13. Data Flow: Chat Request

```
User taps Send
  │
  ▼
ChatViewModel.send()
  ├── Persist user Message to DB
  ├── UIApplication.beginBackgroundTask
  ├── retrieveChunks(query)
  │     └── For each activeKB:
  │           RAGService.retrieve(query:kb:) → [Chunk]
  ├── buildMessages(history + user query)
  ├── makeLLMService(config) → ClaudeService | OpenAIService | OllamaService
  ├── llm.complete(messages:context:books:) → AsyncThrowingStream<String>
  ├── For each token:
  │     messages[assistantIdx].content += token   (live UI update)
  ├── On stream end:
  │     DatabaseService.saveMessage(assistant message + sources)
  └── UIApplication.endBackgroundTask
```

---

## 14. Data Flow: Document Import

```
User picks file(s) via .fileImporter
  │
  ▼
LibraryViewModel.ingestURLs([URL])
  ├── BackgroundTaskCoordinator.beginImport(fileCount:)
  ├── For each URL:
  │     ├── RAGService.ingest(url:kbId:)
  │     │     ├── Parse (format dispatch) → raw text + metadata
  │     │     ├── Chunker.chunk(text, kb.chunkSize, kb.chunkOverlap) → [Chunk]
  │     │     ├── DatabaseService.saveBook(book)
  │     │     ├── DatabaseService.saveChunks(chunks)
  │     │     ├── EmbeddingService.embed(chunks) → [[Float]]
  │     │     └── DatabaseService.updateEmbeddings(chunks)
  │     └── BackgroundTaskCoordinator.advanceImport()
  ├── BackgroundTaskCoordinator.finishImport(success:)
  └── LibraryViewModel.reload()
```

---

## 15. Security Model

| Credential | Storage | Notes |
|------------|---------|-------|
| Claude API key | iOS Keychain | `kSecAttrAccessibleWhenUnlocked` |
| OpenAI API key | iOS Keychain | Same |
| Brave Search key | iOS Keychain | Same |
| Ollama host/model | UserDefaults | Not secret; local network only |

- API keys are never logged, never included in analytics, and never transmitted except to their respective API endpoints.
- Documents are not encrypted at rest beyond the device-level encryption provided by iOS.
- Local network access is declared in `Info.plist` with `NSLocalNetworkUsageDescription` (for Ollama).
- File Sharing (`UIFileSharingEnabled`) and open-in-place (`LSSupportsOpeningDocumentsInPlace`) are enabled.
