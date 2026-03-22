# RAGFlow — Product Requirements Document

**Date**: 2026-03-22
**Owner**: Dan
**Status**: Draft — awaiting approval

---

## Problem Statement

RAGFlow is a powerful open-source RAG engine, but the upstream version lacks customization for personal/internal use: limited search tool support, Docker friction on macOS, and no mobile presence. This project forks RAGFlow and evolves it in two phases — first hardening and extending the web platform, then porting the core experience to a standalone iOS app.

---

## Goals

1. Extend the agent tool ecosystem with additional search and data providers
2. Improve agent workflow reliability and canvas usability
3. Improve document processing quality (parsing, chunking, OCR)
4. Stabilize and maintain the local macOS Docker deployment
5. *(Phase 2)* Build a standalone iOS Swift app replicating core RAGFlow functionality natively on-device

---

## Out of Scope

- Cloud deployment (local/Mac only for now)
- Multi-tenant SaaS features
- The iOS app is out of scope for Phase 1 — spec'd separately when Phase 1 is stable

---

## User Stories

### Phase 1 — Web Platform Enhancements

**Search & Tools**
- US-1: As Dan, I want to use Brave Search in my agents so I can get privacy-respecting web results without a Tavily subscription
- US-2: As Dan, I want additional search/data tools available in the agent canvas so I can build richer workflows
- US-3: As Dan, I want agent tool API keys to be pre-loaded from environment variables so I don't re-enter them in every canvas

**Agent Workflows**
- US-4: As Dan, I want the agent canvas `sys.query` to be correctly populated from user input so agents respond to what I actually typed
- US-5: As Dan, I want agent pipelines to run reliably without silent failures
- US-6: As Dan, I want to be able to run Claude Code interactively inside Docker containers so I can develop and debug efficiently

**Document Processing**
- US-7: As Dan, I want better PDF and document parsing so knowledge bases are more accurate
- US-8: As Dan, I want chunking strategies I can tune per knowledge base

**Infrastructure**
- US-9: As Dan, I want the macOS Docker setup to start cleanly without port conflicts or build failures
- US-10: As Dan, I want secrets never committed to git so my API keys stay private

### Phase 2 — iOS Standalone App *(future)*

- US-11: As Dan, I want a native iOS app that provides RAG-style document Q&A on-device
- US-12: As Dan, I want to ingest documents directly from iOS (Files, Photos, Safari share sheet)
- US-13: As Dan, I want to run local LLM inference or connect to a remote API from the iOS app
- US-14: As Dan, I want agent-like tool calling in the iOS app (search, retrieval, etc.)

---

## Functional Requirements

### FR-1: Brave Search Tool
- Brave Search tool available in agent canvas
- API key loaded from `BRAVE_SEARCH_API_KEY` env var by default
- Supports `query`, `count`, `search_lang`, `freshness` parameters
- Returns formatted chunks compatible with the RAG retrieval pipeline

### FR-2: Additional Agent Tools
- Framework in place to easily add new tools following `ToolParamBase`/`ToolBase` pattern
- Each tool auto-registers via the `agent/tools/__init__.py` module discovery

### FR-3: Agent Canvas Input Fix
- `sys.query` correctly populated from user message input in canvas completion API
- Trip Planner Charleston agent receives and processes user query end-to-end

### FR-4: Docker macOS Stability
- `docker-compose-macos.yml` uses pre-built image (no from-source build)
- Ports remapped to avoid macOS system conflicts (8080/8443)
- `stdin_open: true` + `tty: true` on ragflow service for interactive CLI support
- `docker/.env` untracked in git; `.env.example` provided with placeholder keys

### FR-5: Document Processing
- Configurable chunking per knowledge base
- Improved PDF parsing accuracy

### FR-6: iOS App *(Phase 2)*
- Standalone Swift app, no dependency on running RAGFlow server
- Document ingestion from iOS share sheet and Files app
- Local or remote LLM inference
- Agent tool calling (search, retrieval)

---

## Non-Functional Requirements

### NFR-1: Security
- No secrets in git history
- `docker/.env` permanently untracked
- API keys sourced from environment variables

### NFR-2: Maintainability
- New agent tools follow existing patterns (no framework changes required)
- Docker setup documented and reproducible on macOS

### NFR-3: Performance
- Agent tool calls complete within 12 seconds (existing `COMPONENT_EXEC_TIMEOUT`)
- Docker startup to healthy state in under 3 minutes

### NFR-4: Test Coverage
- ≥85% coverage on new Python code
- ≥85% coverage on new TypeScript code

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Brave Search returns results in agent | ✅ Done |
| `sys.query` correctly populated | Fix verified via API test |
| Docker starts clean on macOS | No manual intervention needed |
| `.env` never appears in `git log` | Verified clean history |
| iOS app Phase 2 spec approved | After Phase 1 stable |

---

## Phases

### Phase 1 — Web Platform (Current)
1. Agent tool ecosystem (Brave Search ✅, additional tools)
2. Agent canvas `sys.query` fix
3. Docker macOS stability ✅
4. Document processing improvements
5. Test coverage for new code

### Phase 2 — iOS App (Future)
1. Specification interview (separate PRD)
2. Swift app architecture
3. On-device document ingestion + RAG
4. LLM integration (local + remote)
5. Agent tool calling on iOS

---

**Generated by**: deft-setup skill
**Strategy**: Full path
