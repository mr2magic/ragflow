# RAGFlow Architecture

## Overview

RAGFlow is a full-stack RAG (Retrieval-Augmented Generation) engine built around deep document understanding. It consists of:

- **Python backend** — Flask-based API server with microservices architecture
- **React/TypeScript frontend** — Web UI built with UmiJS
- **iOS mobile app** — SwiftUI universal app (iPhone + iPad) with local RAG pipeline
- **Infrastructure** — MySQL, Elasticsearch/Infinity, Redis, MinIO via Docker

---

## High-Level System Diagram

```
┌─────────────────────────────────────────────────────┐
│                    Web Frontend                      │
│           React/TypeScript (UmiJS + Ant Design)      │
└──────────────────────┬──────────────────────────────┘
                       │ HTTP / SSE
┌──────────────────────▼──────────────────────────────┐
│                  Flask API Server                    │
│              api/ragflow_server.py                   │
│                                                      │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  dialog_app │  │ document_app │  │ canvas_app │  │
│  │  kb_app     │  │   file_app   │  │   llm_app  │  │
│  └──────┬──────┘  └──────┬───────┘  └─────┬──────┘  │
│         │                │                │          │
│  ┌──────▼────────────────▼────────────────▼──────┐   │
│  │              Service Layer                    │   │
│  │  api/db/services/ (business logic)            │   │
│  └──────┬────────────────────────────────────────┘   │
│         │                                            │
│  ┌──────▼────────────────────────────────────────┐   │
│  │              Data Layer                       │   │
│  │  MySQL · Elasticsearch/Infinity · Redis       │   │
│  │  MinIO (object storage)                       │   │
│  └───────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                 LLM / RAG Pipeline                   │
│                                                      │
│  rag/llm/        — LiteLLM multi-provider adapter    │
│  rag/flow/       — Chunking, tokenization, parsing   │
│  deepdoc/        — PDF OCR, layout analysis          │
│  rag/graphrag/   — Knowledge graph construction      │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│              iOS Mobile App (standalone)             │
│                                                      │
│  SwiftUI + GRDB (SQLite) + LLM APIs (Claude/OpenAI)  │
│  Local RAG pipeline — no server required             │
└──────────────────────────────────────────────────────┘
```

---

## Backend Architecture

### Entry Point
**`api/ragflow_server.py`** — Flask application factory. Registers all blueprints, initializes database, starts background workers.

### Blueprints (`api/apps/`)

| Blueprint | Route Prefix | Responsibility |
|-----------|-------------|----------------|
| `kb_app.py` | `/kb` | Knowledge base CRUD, document parsing triggers |
| `dialog_app.py` | `/dialog` | Chat configuration (create, list, update, delete) |
| `conversation_app.py` | `/conversation` | Chat sessions, message streaming, TTS, STT |
| `document_app.py` | `/document` | Document upload, chunking, status |
| `canvas_app.py` | `/canvas` | Agent workflow execution |
| `file_app.py` | `/file` | File upload and management |
| `llm_app.py` | `/llm` | LLM provider config, API key validation |
| `user_app.py` | `/user` | Auth, user management |

### Service Layer (`api/db/services/`)

- **`llm_service.py`** — `LLMBundle` wrapper with token tracking and Langfuse observability
- **`tenant_llm_service.py`** — Provider API key storage, model instantiation, `model@factory` name parsing
- **`knowledgebase_service.py`** — KB CRUD and document linking
- **`dialog_service.py`** — Dialog and conversation business logic

### Database Models (`api/db/db_models.py`)

| Model | Table | Key Fields |
|-------|-------|-----------|
| `Dialog` | `dialog` | `llm_id`, `prompt_config`, `kb_ids`, `llm_setting` |
| `Conversation` | `conversation` | `dialog_id`, `message` (JSON array), `reference` |
| `TenantLLM` | `tenant_llm` | `llm_factory`, `llm_name`, `api_key`, `api_base` |
| `LLMFactories` | `llm_factories` | `name`, `tags`, `status` |
| `LLM` | `llm` | `fid` (factory), `llm_name`, `model_type`, `is_tools` |
| `Knowledgebase` | `knowledgebase` | `name`, `tenant_id`, `doc_ids` |
| `Document` | `document` | `kb_id`, `location`, `parser_id`, `progress` |

---

## LLM Provider System

### Factory Registration

LLM providers are registered in **`rag/llm/__init__.py`** using the `MODULE_MAPPING` dictionary. Classes declare their factory name via `_FACTORY_NAME`.

### Multi-Provider Adapter

**`LiteLLMBase`** in `rag/llm/chat_model.py` handles 30+ providers through the LiteLLM library, including:

- **Anthropic** (`claude-*` models)
- **OpenAI** (`gpt-*` models)
- **Azure-OpenAI**, **Bedrock**, **Gemini**, **Ollama**, **DeepSeek**, and more

### Provider Configuration

Supported models and their metadata are defined in **`conf/llm_factories.json`**. Each provider entry includes:
- `name` — factory identifier (e.g., `"Anthropic"`, `"OpenAI"`)
- `llm[]` — array of supported models with `max_tokens`, `model_type`, `is_tools`
- `tags` — capability tags: `LLM`, `TEXT EMBEDDING`, `TTS`, `RERANK`, `ASR`

### Model Name Convention

Models are referenced as `model_name@factory_name`, e.g.:
- `claude-sonnet-4-6@Anthropic`
- `gpt-4o@OpenAI`

---

## RAG Pipeline (`rag/`)

### Document Processing Flow

```
Upload → Parser → Chunker → Embedder → Index (Elasticsearch/Infinity)
```

1. **Parsing** (`deepdoc/`) — Layout-aware PDF parsing, OCR, table extraction
2. **Chunking** (`rag/flow/`) — Configurable chunk size, overlap, and strategy
3. **Embedding** (`rag/llm/embedding_model.py`) — Text → vector via selected embedding model
4. **Indexing** — Dual storage: Elasticsearch/Infinity for vector search + MySQL for metadata

### Retrieval

Hybrid retrieval combining:
- **Vector search** — cosine similarity via Elasticsearch/Infinity kNN
- **Keyword search** — BM25 full-text scoring
- **Reranking** — Optional cross-encoder rerank pass

---

## Agent System (`agent/`)

The agent system provides a visual workflow canvas (similar to n8n/LangChain) for building multi-step AI pipelines.

### Step Components (`agent/component/`)

Each component is a callable step type:
- `retrieval.py` — KB search with configurable topK
- `llm.py` — Direct LLM call with prompt template
- `categorize.py` — Route inputs to branches
- `answer.py` — Terminal output node
- `wikipedia.py`, `tavily.py`, `sql.py` — External tool integrations

---

## Infrastructure

### Docker Services (`docker/`)

| Service | Image | Purpose |
|---------|-------|---------|
| `ragflow-server` | Custom | Flask API + Celery workers |
| `mysql` | MySQL 8.0 | Relational metadata storage |
| `es01` | Elasticsearch 8 | Vector + keyword search |
| `redis` | Redis 6 | Task queue, caching |
| `minio` | MinIO | Object storage (documents) |

### Configuration

- **`docker/.env`** — All service credentials and feature flags
- **`docker/service_conf.yaml.template`** — Backend service endpoints
- **`pyproject.toml`** — Python dependencies (`uv` managed)
