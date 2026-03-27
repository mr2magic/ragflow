# RAGFlow iOS App

A standalone SwiftUI universal app (iPhone + iPad) that runs a full RAG pipeline locally — no RAGFlow server required.

---

## Features

- **Local RAG** — Import documents, chunk and index them on-device, query with keyword or vector search
- **Multiple LLM providers** — Claude (Anthropic), ChatGPT (OpenAI), or Ollama (local)
- **Multi-conversation chat** — Named chat sessions per knowledge base with full history
- **Knowledge bases** — Multiple independent document collections
- **Agent workflows** — Visual step-based pipelines with 7 step types
- **Universal layout** — Adaptive UI for iPhone (tabs) and iPad (split view)

---

## Project Structure

```
ios/RAGFlowMobile/
├── App/
│   ├── RAGFlowMobileApp.swift    # @main entry point
│   ├── AppState.swift            # Shared app state singleton
│   └── ContentView.swift         # Root layout (iPhone tabs / iPad split)
│
├── Models/
│   ├── Message.swift             # Chat message + ChunkSource
│   ├── ChatSession.swift         # Named conversation entity
│   ├── Workflow.swift            # Workflow + WorkflowRun
│   ├── LLMConfig.swift           # Provider enum + config struct
│   ├── KnowledgeBase.swift       # KB entity (GRDB persistent)
│   ├── Book.swift                # Document entity
│   └── Chunk.swift               # Text chunk with optional embedding
│
├── Features/
│   ├── Chat/
│   │   ├── ConversationsListView.swift  # List/create/delete chat sessions
│   │   ├── ChatView.swift               # Single conversation chat UI
│   │   └── ChatViewModel.swift          # Chat state, streaming, persistence
│   ├── KB/
│   │   ├── KBListView.swift             # iPad sidebar KB list
│   │   ├── KBDetailView.swift           # KB detail (Chat + Documents tabs)
│   │   ├── KBListViewModel.swift        # KB CRUD
│   │   └── PhoneKBListView.swift        # iPhone KB navigation
│   ├── Library/
│   │   ├── LibraryView.swift            # Document list + import
│   │   └── LibraryViewModel.swift       # Document ingestion pipeline
│   ├── Workflows/
│   │   ├── WorkflowListView.swift       # Workflow list + templates
│   │   ├── WorkflowListViewModel.swift  # Workflow CRUD
│   │   ├── WorkflowDetailView.swift     # Run workflow + view history
│   │   └── WorkflowEditorView.swift     # Visual step builder
│   ├── Settings/
│   │   └── SettingsView.swift           # Provider selection + API keys
│   └── Onboarding/
│       └── OnboardingView.swift         # First-launch setup
│
└── Services/
    ├── Storage/
    │   ├── DatabaseService.swift    # SQLite via GRDB (all persistence)
    │   └── SettingsStore.swift      # UserDefaults + Keychain settings
    ├── LLM/
    │   ├── LLMService.swift         # Protocol + factory function
    │   ├── ClaudeService.swift      # Anthropic API client
    │   ├── OpenAIService.swift      # OpenAI API client
    │   ├── OllamaService.swift      # Ollama streaming client
    │   ├── OllamaModelsService.swift# Fetch available Ollama models
    │   └── ToolService.swift        # Brave Search + Jina Reader tools
    ├── RAG/
    │   ├── RAGService.swift         # Document ingestion + retrieval
    │   ├── Chunker.swift            # Word-based text chunking
    │   ├── EmbeddingService.swift   # Ollama embeddings + cosine similarity
    │   ├── PDFParser.swift          # PDFKit text extraction
    │   ├── OfficeParser.swift       # DOCX/XLSX/PPTX extraction
    │   └── EMLParser.swift          # Email file parsing
    └── Agent/
        ├── WorkflowStep.swift       # StepType enum + WorkflowStep model
        ├── WorkflowTemplate.swift   # Pre-built workflow templates
        └── WorkflowRunner.swift     # Sequential step execution engine
```

---

## Data Layer

### SQLite Database (GRDB)

All app data is stored in a single SQLite file at `<ApplicationSupport>/ragflow.sqlite` with automatic schema migrations.

#### Schema

| Table | Purpose |
|-------|---------|
| `knowledge_bases` | KB metadata (id, name, createdAt) |
| `books` | Documents linked to a KB |
| `chunks` | Text chunks from documents |
| `chunks_fts` | FTS5 virtual table for keyword search |
| `chat_sessions` | Named chat conversations per KB |
| `messages` | Chat messages scoped to a session |
| `message_sources` | Chunk citations for assistant messages |
| `workflows` | Workflow definitions (steps stored as JSON) |
| `workflow_runs` | Execution history per workflow |

#### Migration Versions

| Version | Changes |
|---------|---------|
| v1 | `books`, `chunks`, `chunks_fts` |
| v2 | `embedding` column on chunks |
| v3 | `knowledge_bases`, `kbId` on books |
| v4 | `messages`, `message_sources` |
| v5 | `workflows`, `workflow_runs` |
| v6 | `chat_sessions`, `sessionId` on messages; migrates existing messages |

### Settings Storage

| Setting | Storage |
|---------|---------|
| LLM provider | UserDefaults |
| Ollama host/model | UserDefaults |
| Claude API key | iOS Keychain |
| OpenAI API key | iOS Keychain |
| Brave Search API key | iOS Keychain |

---

## LLM Providers

### Claude (Anthropic)

- **Model**: `claude-sonnet-4-6`
- **Endpoint**: `https://api.anthropic.com/v1/messages`
- **Auth**: `x-api-key` header
- **Features**: Tool use (Brave Search, Jina Reader), agentic loops

### ChatGPT (OpenAI)

- **Model**: `gpt-4o`
- **Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Auth**: `Authorization: Bearer {key}` header
- **Features**: Standard chat completion

### Ollama (Local)

- **Endpoint**: Configurable (default `http://localhost:11434`)
- **Chat**: `/api/chat` with streaming
- **Embeddings**: `/api/embed` with `nomic-embed-text`
- **Features**: Vector search when embeddings available

---

## Chat History

Each knowledge base supports multiple named **chat sessions**. Sessions are independent — each has its own message history.

### CRUD Operations

| Operation | UI Location |
|-----------|------------|
| **Create** | "New Chat" button in `ConversationsListView` toolbar |
| **List** | `ConversationsListView` — shows all sessions for the active KB |
| **Rename** | Long-press context menu on a session row |
| **Delete** | Swipe-to-delete or context menu; cascades all messages |

### Storage

Messages are saved immediately on send and on stream completion. If a stream is cancelled before any content arrives, the message pair is rolled back.

---

## Workflow System

Workflows are pipelines of named steps executed sequentially. Each step reads from and writes to named **slots** (string variables).

### Step Types

| Type | Icon | Description |
|------|------|-------------|
| **Begin** | 🟢 flag | Entry point — captures user query into `input` slot |
| **Retrieve** | 🔵 magnifier | Searches KB for relevant passages |
| **Rewrite** | 🩵 arrows | AI-refines the query for better recall |
| **LLM** | 🟣 brain | Calls LLM with a custom prompt template |
| **Message** | 🟦 bubble | Injects static text into the pipeline |
| **Web Search** | 🟦 globe | Brave Search integration |
| **Answer** | 🟠 checkmark | Terminal step — outputs final result to user |

### Variable Substitution

Use `{slotName}` in any prompt template or message to reference a slot value. For example:
- `{input}` — the user's original query
- `{context}` — text retrieved from the KB
- `{output}` — result from an LLM step

### Pre-built Templates

| Template | Steps |
|----------|-------|
| RAG Q&A | begin → retrieve → llm → answer |
| Deep Summarizer | begin → retrieve → llm (summarize) → answer |
| Keyword Expander | begin → rewrite → retrieve → llm → answer |
| Multi-Hop Researcher | begin → rewrite → retrieve → llm → retrieve → llm → answer |
| Balanced Analysis | begin → rewrite → retrieve → web search → llm → answer |

---

## Universal App Layout

The app adapts automatically to the device size class:

### iPhone (Compact)

```
TabView
├── Tab 1: Knowledge Bases → [KB] → ConversationsListView → ChatView
├── Tab 2: Workflows → WorkflowDetailView / WorkflowEditorView
└── Tab 3: Settings
```

### iPad (Regular)

```
NavigationSplitView
├── Sidebar: KBListView
└── Detail: KBDetailView
    ├── Tab: Chat → ConversationsListView → ChatView
    └── Tab: Documents → LibraryView
```

---

## Building

### Requirements

- Xcode 15+
- iOS 17+ deployment target
- Swift Package Manager (GRDB dependency)

### Setup

1. Open `ios/RAGFlowMobile.xcodeproj` in Xcode
2. Select your team in Signing & Capabilities
3. Build and run on simulator or device

### API Keys

Configure in the app under **Settings**:
- **Claude**: Get a key at console.anthropic.com
- **ChatGPT**: Get a key at platform.openai.com
- **Brave Search** (optional): Enables web search in Claude/workflows
- **Ollama**: Point to a running Ollama instance on your network
