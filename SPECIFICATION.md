# RAGFlow — Specification

**Date**: 2026-03-22
**Strategy**: Full path
**PRD**: [PRD.md](PRD.md)
**Status**: Approved

---

## Overview

RAGFlow is a forked, locally-deployed RAG (Retrieval-Augmented Generation) engine for personal/internal use on macOS. The platform combines deep document understanding with a modular agent system. This specification covers Phase 1 (web platform hardening and extension) and outlines Phase 2 (iOS standalone app) for future planning.

---

## Requirements

Traced from [PRD.md](PRD.md). Each task below references its requirement ID.

### Functional
| ID | Requirement |
|----|-------------|
| FR-1 | Brave Search tool in agent canvas, API key from env var |
| FR-2 | Extensible agent tool framework via module auto-discovery |
| FR-3 | `sys.query` correctly populated from canvas completion API |
| FR-4 | Docker macOS stability: pre-built image, remapped ports, TTY support, untracked `.env` |
| FR-5 | Configurable document chunking and improved PDF parsing |
| FR-6 | *(Phase 2)* Standalone iOS Swift app with on-device RAG |

### Non-Functional
| ID | Requirement |
|----|-------------|
| NFR-1 | No secrets in git; `.env` permanently untracked |
| NFR-2 | New tools follow `ToolParamBase`/`ToolBase` pattern |
| NFR-3 | Tool calls complete within 12s; Docker healthy in under 3 min |
| NFR-4 | ≥85% test coverage on new Python and TypeScript code |

---

## Architecture

### Backend (`api/`, `agent/`, `rag/`)
- **Flask** app server (`api/ragflow_server.py`) with blueprint-based routing
- **Agent system**: canvas-driven pipelines in `agent/component/`, tools in `agent/tools/`
- **Tool discovery**: `agent/tools/__init__.py` auto-imports all `*.py` files — drop a file in, it registers
- **RAG pipeline**: chunking, embedding, retrieval in `rag/`
- **LLM integration**: `rag/llm/` — abstracts chat, embedding, reranking models via LiteLLM

### Frontend (`web/`)
- React + TypeScript, UmiJS framework
- Ant Design + shadcn/ui components, Tailwind CSS
- Zustand state management

### Infrastructure (`docker/`)
- `docker-compose-macos.yml` — local macOS dev stack
- `docker-compose.yml` — CPU/GPU production variants
- `docker-compose-base.yml` — shared services (MySQL, Redis, MinIO, Elasticsearch)
- Secrets in `docker/.env` (untracked)

---

## Implementation Plan

### Phase 1 — Web Platform Enhancements

---

#### P1.1 — Brave Search Tool ✅ COMPLETE
*(traces: FR-1, FR-2, NFR-1, NFR-2)*

**Status**: Done

**Tasks**:
- [x] T1: Create `agent/tools/brave.py` with `BraveSearchParam` + `BraveSearch` classes
- [x] T2: Add `BRAVE_SEARCH_API_KEY` to `docker/.env` (untracked)
- [x] T3: Default `api_key` to `os.environ.get("BRAVE_SEARCH_API_KEY", "")` in param init
- [x] T4: Verify tool auto-registers via module discovery on container start

**Acceptance**:
- `BraveSearch` appears as a tool option in the agent canvas UI
- Searching returns chunked results in the RAG pipeline format
- API key not present in any committed file

---

#### P1.2 — Additional Agent Tools
*(traces: FR-2, NFR-2)*

**Status**: ✅ COMPLETE

**Goal**: Expand the tool library with high-value search and data providers.

**Candidate tools** (implement in priority order):
1. **Perplexity Search** — AI-powered search via Perplexity API
2. **NewsAPI** — real-time news retrieval
3. **OpenMeteo** — free weather data (no API key required)
4. **Jina Reader** — clean web content extraction via `r.jina.ai`
5. **YouTube Transcript** — fetch transcripts from YouTube videos

**Tasks** (per tool):
- [ ] T1: Create `agent/tools/{name}.py` following `ToolParamBase`/`ToolBase` pattern
- [ ] T2: Add API key env var to `docker/.env` and read in param `__init__`
- [ ] T3: Add env var placeholder to `docker/.env.example`
- [ ] T4: Write pytest unit tests (`test/tools/test_{name}.py`) with mocked HTTP responses
- [ ] T5: Verify auto-registration on container restart

**Acceptance**:
- Tool appears in agent canvas without any framework changes
- Tests pass with ≥85% coverage on new file (NFR-4)
- API key never committed (NFR-1)

---

#### P1.3 — Agent Canvas `sys.query` Fix
*(traces: FR-3)*

**Status**: ✅ COMPLETE (not a bug — wrong field name in test)

**Finding**: `canvas_app.py:186` reads `req.get("query", "")` and `canvas_service.py:209` accepts `query` or `question`. The test used `{"message": "..."}` which is incorrect.

**Correct API usage**:
```bash
curl -X POST http://localhost:8080/v1/canvas/{canvas_id}/completion \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"query": "your question here"}'
```

- [x] T1–T6: Investigated and resolved — use `query` field, not `message`

---

#### P1.4 — Docker macOS Stability ✅ MOSTLY COMPLETE
*(traces: FR-4, NFR-1)*

**Status**: Largely done — one item remaining

**Completed**:
- [x] `stdin_open: true` + `tty: true` on all ragflow services
- [x] Switched macOS compose to pre-built image (`infiniflow/ragflow:v0.24.0`)
- [x] Ports remapped: 80→8080, 443→8443
- [x] `docker/.env` removed from git tracking (`git rm --cached`)

**Completed**:
- [x] `stdin_open: true` + `tty: true` on all ragflow services
- [x] Switched macOS compose to pre-built image (`infiniflow/ragflow:v0.24.0`)
- [x] Ports remapped: 80→8080, 443→8443
- [x] `docker/.env` removed from git tracking (`git rm --cached`)
- [x] `docker/.env.example` created with all keys and API key placeholders

**Status**: ✅ COMPLETE

---

#### P1.5 — Document Processing Improvements
*(traces: FR-5)*

**Status**: ✅ COMPLETE (upstream already provides full configurability)

**Audit findings** (`rag/app/naive.py`, `common/constants.py`):

**15 parser types available**: `naive`, `paper`, `book`, `resume`, `qa`, `table`, `presentation`, `laws`, `manual`, `picture`, `one`, `audio`, `email`, `knowledge_graph`, `tag`

**Per-document `parser_config` keys**:
| Key | Default | Description |
|-----|---------|-------------|
| `chunk_token_num` | 512 | Chunk size in tokens |
| `delimiter` | `\n!?。；！？` | Split characters |
| `overlapped_percent` | — | Chunk overlap ratio |
| `layout_recognize` | `DeepDOC` | OCR/layout engine |
| `pages` | `[[1, 1000000]]` | Page range to parse |
| `table_context_size` | 0 | Context around tables |
| `image_context_size` | 0 | Context around images |
| `analyze_hyperlink` | true | Follow hyperlinks |

All settings are configurable per knowledge base and per document in the existing UI. No additional development required from this fork.

**Tasks**:
- [x] T1: Audit chunking strategies — 15 parser types, full `parser_config` documented above
- [x] T2: Per-KB chunking already exposed in UI (upstream feature)
- [ ] T3: *(Optional)* Test PDF parsing on problematic documents if issues arise in use

---

#### P1.6 — Test Coverage
*(traces: NFR-4)*

**Status**: ✅ COMPLETE

**Goal**: Ensure all new code meets ≥85% coverage threshold.

**Tasks**:
- [x] T1: Add `pytest` tests for `agent/tools/brave.py` (`test/test_tools/test_brave.py`)
- [x] T2: Add tests for each new tool added in P1.2 (`test/test_tools/test_perplexity.py`, `test_newsapi.py`, `test_openmeteo.py`, `test_jinareader.py`, `test_youtubetranscript.py`)
- [x] T3: Add end-to-end API test for canvas completion with `sys.query` populated (P1.3)
- [x] T4: Configure coverage reporting in `pyproject.toml` if not already set
- [x] T5: Add `task test:coverage` to `Taskfile.yml` (or create `Taskfile.yml`)

**Acceptance**:
- `pytest --cov` reports ≥85% on `agent/tools/` and new modules
- Coverage gate runs in pre-commit or CI

---

### Phase 2 — iOS Standalone App
*(traces: FR-6 through FR-10)*

**Status**: In Progress — scaffolded 2026-03-22

---

#### Requirements

| ID | Requirement |
|----|-------------|
| FR-6 | Chat with ePub library using Claude or Ollama |
| FR-7 | Import ePubs from Files app and iCloud Drive |
| FR-8 | Cross-library RAG: query answers from entire book collection |
| FR-9 | LLM toggle: Claude API (Anthropic) or Ollama (local network) |
| FR-10 | Universal SwiftUI app, portrait + landscape, iPhone + iPad |
| NFR-5 | API keys stored in iOS Keychain, never in source |
| NFR-6 | Works fully offline when using Ollama |

---

#### Architecture

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI, universal layout |
| Document parsing | EPUBKit |
| Chunking | Swift naive chunker (word-based, configurable size + overlap) |
| Search | SQLite FTS5 (via GRDB.swift) — no external vector store for MVP |
| Metadata store | SQLite via GRDB.swift |
| LLM | Anthropic Claude API + Ollama (local network), toggle in Settings |
| API key storage | iOS Keychain |

---

#### Directory Structure

```
ios/
├── project.yml                         # XcodeGen config
├── RAGFlowMobile/
│   ├── App/                            # Entry point, AppState, ContentView
│   ├── Features/
│   │   ├── Library/                    # Book list + ePub import
│   │   ├── Chat/                       # Chat UI + RAG query
│   │   └── Settings/                   # LLM provider + API key
│   ├── Models/                         # Book, Chunk, Message, LLMConfig
│   ├── Services/
│   │   ├── LLM/                        # LLMService protocol, ClaudeService, OllamaService
│   │   ├── RAG/                        # RAGService (ingest + retrieve), Chunker
│   │   └── Storage/                    # DatabaseService (GRDB), SettingsStore (Keychain)
│   └── Resources/                      # Info.plist, Assets
└── RAGFlowMobileTests/                 # XCTest — ChunkerTests + more
```

---

#### Implementation Phases

---

##### P2.1 — ePub Ingestion ✅ SCAFFOLDED
- [x] EPUBKit integration in `RAGService.ingest(epubURL:)`
- [x] Word-based chunker with configurable size/overlap (`Chunker.swift`)
- [x] SQLite storage with FTS5 full-text search (`DatabaseService.swift`)
- [x] Files/iCloud import via SwiftUI `fileImporter` in `LibraryView`
- [ ] Test on real ePub files; tune chunker defaults

---

##### P2.2 — Chat Interface ✅ SCAFFOLDED
- [x] SwiftUI chat view with streaming token display (`ChatView.swift`)
- [x] RAG retrieval → LLM call pipeline (`ChatViewModel.swift`)
- [x] Portrait + landscape layout (universal)
- [ ] Verify streaming on device

---

##### P2.3 — LLM Integration ✅ SCAFFOLDED
- [x] `LLMService` protocol with `AsyncThrowingStream<String, Error>` streaming
- [x] `ClaudeService` — Anthropic Messages API with SSE streaming
- [x] `OllamaService` — Ollama `/api/chat` with streaming
- [x] Settings screen with provider picker + API key (Keychain) (`SettingsView.swift`)
- [ ] Test Claude streaming end-to-end
- [ ] Test Ollama with local instance

---

##### P2.4 — Xcode Project Generation
- [ ] Install XcodeGen: `brew install xcodegen`
- [ ] Run `xcodegen generate` in `ios/` to create `.xcodeproj`
- [ ] Open in Xcode, resolve SPM packages (EPUBKit, GRDB)
- [ ] Build and run on simulator

---

##### P2.5 — Agent Tools *(post-MVP)*
- [ ] Brave Search, Perplexity via Claude tool use API
- [ ] Same tool set as web app

---

#### To Get Started

```bash
# One-time setup
brew install xcodegen

# Generate Xcode project
cd ios
xcodegen generate

# Open in Xcode
open RAGFlowMobile.xcodeproj
```

---

## Testing Strategy

| Layer | Tool | Target |
|-------|------|--------|
| Python unit | `pytest` | ≥85% on new modules |
| Python integration | `pytest` + real DB | Canvas API, tool invocation |
| Frontend unit | Jest + React Testing Library | ≥85% on new components |
| API | HTTP tests in `test/` | Canvas completion end-to-end |

**Run tests**:
```bash
uv run pytest                        # All Python tests
uv run pytest --cov agent/tools/     # Coverage for tools
cd web && npm run test               # Frontend tests
```

---

## Secrets & Security

- `docker/.env` — untracked, never commit (NFR-1)
- `docker/.env.example` — committed, all values empty
- API keys sourced from env vars in tool `__init__` methods
- Pattern: `self.api_key = os.environ.get("MY_API_KEY", "")`

---

## Deployment

**Local macOS**:
```bash
cd docker
cp .env.example .env        # Fill in your keys
docker compose -f docker-compose-macos.yml up -d
# Access at http://localhost:8080
```

**Rebuild after code changes** (tools, backend):
```bash
docker restart docker-ragflow-1
```

---

**Generated by**: deft-setup skill
**Approved**: 2026-03-22
