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

**Status**: Planned

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

**Status**: Identified — not yet fixed

**Problem**: The `/v1/canvas/{id}/completion` API receives `{"message": "..."}` but the Begin node sees `sys.query = ""`. User input is not wiring through to agent components.

**Investigation needed**:
- [ ] T1: Read `api/apps/canvas_app.py` — find how `message`/`query` is parsed and mapped to `sys.query`
- [ ] T2: Check Begin node component (`agent/component/begin.py`) — how it sets `sys.query`
- [ ] T3: Identify the correct request field name (`message` vs `query` vs form input key)
- [ ] T4: Fix the mapping or document the correct API usage
- [ ] T5: Test end-to-end: send query → verify agent receives it → verify response references the query content
- [ ] T6: Update canvas API documentation/comment in `canvas_app.py`

**Acceptance**:
- Trip Planner Charleston agent receives the user query in `sys.query`
- Agent response directly addresses the query content (not a generic "please provide details" fallback)

---

#### P1.4 — Docker macOS Stability ✅ MOSTLY COMPLETE
*(traces: FR-4, NFR-1)*

**Status**: Largely done — one item remaining

**Completed**:
- [x] `stdin_open: true` + `tty: true` on all ragflow services
- [x] Switched macOS compose to pre-built image (`infiniflow/ragflow:v0.24.0`)
- [x] Ports remapped: 80→8080, 443→8443
- [x] `docker/.env` removed from git tracking (`git rm --cached`)

**Remaining**:
- [ ] T1: Create `docker/.env.example` with all required keys as empty placeholders
- [ ] T2: Add `docker/.env.example` to git and commit

**Acceptance**:
- Fresh clone + copy `.env.example` → `.env` + fill keys → `docker compose up -d` works
- `git log -- docker/.env` shows no secrets ever committed

---

#### P1.5 — Document Processing Improvements
*(traces: FR-5)*

**Status**: Planned

**Goal**: Improve parsing accuracy and give users control over chunking.

**Tasks**:
- [ ] T1: Audit current chunking strategies in `rag/flow/` — document available options
- [ ] T2: Expose per-knowledge-base chunking config in the UI (chunk size, overlap, strategy)
- [ ] T3: Investigate PDF parsing failures — test against a set of problematic PDFs
- [ ] T4: Evaluate and integrate improved PDF parser if gaps found (e.g. better table extraction)
- [ ] T5: Add tests for chunking strategies (`test/rag/test_chunking.py`)

**Acceptance**:
- Users can configure chunk size/overlap per knowledge base in the UI
- PDF parsing accuracy improves on test document set
- Tests pass with ≥85% coverage on new code (NFR-4)

---

#### P1.6 — Test Coverage
*(traces: NFR-4)*

**Status**: Ongoing

**Goal**: Ensure all new code meets ≥85% coverage threshold.

**Tasks**:
- [ ] T1: Add `pytest` tests for `agent/tools/brave.py` (`test/tools/test_brave.py`)
- [ ] T2: Add tests for each new tool added in P1.2
- [ ] T3: Add end-to-end API test for canvas completion with `sys.query` populated (P1.3)
- [ ] T4: Configure coverage reporting in `pyproject.toml` if not already set
- [ ] T5: Add `task test:coverage` to `Taskfile.yml` (or create `Taskfile.yml`)

**Acceptance**:
- `pytest --cov` reports ≥85% on `agent/tools/` and new modules
- Coverage gate runs in pre-commit or CI

---

### Phase 2 — iOS Standalone App *(Future)*
*(traces: FR-6)*

**Status**: Future — spec separately when Phase 1 is stable

**Outline**:
- Swift app, no dependency on running RAGFlow server
- On-device document ingestion (Files app, share sheet, camera)
- RAG pipeline implemented in Swift (chunking, embedding, retrieval)
- LLM: CoreML on-device or remote API (OpenAI/Anthropic/Ollama)
- Agent tool calling: search, retrieval, web content extraction
- Knowledge base management in app (SQLite + vector store)

**Trigger**: Begin Phase 2 spec interview after P1.3, P1.4, P1.5 are complete.

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
