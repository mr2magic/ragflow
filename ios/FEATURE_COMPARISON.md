# RAGFlow Feature Comparison: Web App vs iOS Mobile

> Last updated: 2026-04-14 (Web: main branch · iOS: 0.3.0)
>
> **Legend:** ✅ Full support · ⚡ Partial / limited · ❌ Not available · 🔜 Planned

---

## Knowledge Base Management

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| Create / rename / delete KB | ✅ | ✅ |
| Bulk KB operations | ✅ | ❌ |
| Retrieval settings (Top-K, Top-N, threshold) | ✅ | ✅ |
| Keyword similarity weight adjustment | ✅ | ❌ |
| Reranking model selection | ✅ | ❌ |
| Knowledge graph enhancement toggle | ✅ | ❌ |
| Cross-language retrieval | ✅ | ❌ |
| Table of contents enhancement | ✅ | ❌ |
| Chunking method selection | ✅ (12+ methods) | ✅ (4 methods: General, Q&A, Paper, Table) |
| Chunk size + overlap configuration | ✅ | ✅ |

---

## Document Import & File Types

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| PDF | ✅ | ✅ |
| ePub | ✅ | ✅ |
| Word (DOCX / DOC) | ✅ | ✅ |
| Excel (XLSX / XLS) | ✅ | ✅ |
| PowerPoint (PPTX / PPT) | ✅ | ✅ |
| LibreOffice (ODT / ODS / ODP) | ✅ | ✅ |
| HTML / XML | ✅ | ✅ |
| JSON / JSONL | ✅ | ✅ |
| CSV / TSV | ✅ | ✅ |
| YAML | ✅ | ✅ |
| Plain text / RTF / Markdown | ✅ | ✅ |
| Email (EML / EMLX) | ✅ | ✅ |
| Code files (Swift, Python, JS, Go, SQL, etc.) | ✅ | ✅ |
| Audio files | ✅ | ❌ |
| Images / OCR | ✅ | ❌ |
| Import from URL | ✅ | ✅ |
| Drag-and-drop upload | ✅ | ❌ (file picker) |
| Import from iCloud Drive | ❌ | ✅ |
| Bulk upload (multiple files at once) | ✅ | ✅ |
| Import from Confluence / Notion / Google Drive / etc. | ✅ (28+ sources) | ❌ |

---

## Document Library & Management

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| Document list with status badges | ✅ | ✅ |
| Search documents | ✅ | ✅ |
| Sort (date, title, author) | ✅ | ✅ |
| Rename documents | ✅ | ✅ |
| Delete documents | ✅ | ✅ |
| Bulk document delete | ✅ | ❌ |
| Re-index document | ✅ | ✅ |
| Passage / chunk viewer | ✅ | ✅ |
| Search within passages | ✅ | ✅ |
| Document preview (raw) | ✅ | ❌ |
| Move documents between KBs | ✅ | ❌ |
| Document metadata / tags | ✅ | ❌ |
| Manual / empty document creation | ✅ | ❌ |
| Parsing process logs | ✅ | ❌ |
| Knowledge graph visualization | ✅ | ❌ |

---

## Chat & Conversations

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| Create / rename / delete sessions | ✅ | ✅ |
| Session auto-naming from first message | ❌ | ✅ |
| Multi-KB search in one chat | ✅ | ✅ |
| Source citation / passages used | ✅ | ✅ |
| Streaming responses | ✅ | ✅ |
| Stop mid-stream | ✅ | ✅ |
| Copy message | ✅ | ✅ |
| Export / share chat history | ✅ | ✅ |
| Suggested prompts (empty state) | ❌ | ✅ |
| LLM model selection per chat | ✅ | ❌ (global setting) |
| Temperature / Top-P / token settings | ✅ | ❌ |
| Chat-level system prompt | ✅ | ❌ |
| Conversation history window config | ✅ | ❌ |
| Embedded chat widget (iframe) | ✅ | ❌ |
| Public share link for chat | ✅ | ❌ |
| Batch delete conversations | ✅ | ❌ |
| Search conversations | ✅ | ❌ |

---

## Search Applications

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| Standalone search app creation | ✅ | ❌ |
| Embedded search widget | ✅ | ❌ |
| Public share link | ✅ | ❌ |
| Custom styling | ✅ | ❌ |

---

## Agent Workflows

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| Create / rename / delete workflows | ✅ | ✅ |
| Workflow templates | ✅ (10+) | ✅ (4: RAG Q&A, Summarizer, Keyword Expander, Custom) |
| Custom LLM prompt step | ✅ | ✅ |
| Retrieve step (query KB) | ✅ | ✅ |
| Rewrite query step | ✅ | ✅ |
| Answer / output step | ✅ | ✅ |
| Message step | ✅ | ✅ |
| Web search step (Brave) | ❌ | ✅ |
| Web search (Tavily / DuckDuckGo / Google / Bing) | ✅ | ❌ |
| Categorize / classify step | ✅ | ❌ |
| Switch / conditional branching | ✅ | ❌ |
| Iteration / loop steps | ✅ | ❌ |
| Sub-agent invocation | ✅ | ❌ |
| Code execution (Python / JS) | ✅ | ❌ |
| SQL execution | ✅ | ❌ |
| Web crawler step | ✅ | ❌ |
| Email send/receive step | ✅ | ❌ |
| GitHub integration step | ✅ | ❌ |
| PDF generator step | ✅ | ❌ |
| Wikipedia / PubMed / ArXiv search | ✅ | ❌ |
| MCP tool integration | ✅ | ❌ |
| Visual canvas / node graph editor | ✅ | ❌ (linear list editor) |
| Drag-and-drop step reordering | ✅ | ✅ |
| Global / conversation variables | ✅ | ❌ |
| Structured output (JSON schema) | ✅ | ❌ |
| Workflow export / import (JSON) | ✅ | ❌ |
| Publish / version workflows | ✅ | ❌ |
| Execution logs / debug trace | ✅ | ⚡ (step log in running card) |
| Run history | ✅ | ✅ |
| Copy run output | ✅ | ✅ |
| Webhook triggers | ✅ | ❌ |
| Embedded agent widget | ✅ | ❌ |

---

## LLM Providers

| Provider | Web App | iOS Mobile |
|---|:---:|:---:|
| Anthropic Claude | ✅ | ✅ |
| OpenAI / GPT | ✅ | ✅ |
| Ollama (local) | ✅ | ✅ |
| Azure OpenAI | ✅ | ❌ |
| Google Gemini | ✅ | ❌ |
| AWS Bedrock | ✅ | ❌ |
| Baidu / Spark / Yiyan | ✅ | ❌ |
| Volc Engine / Tencent | ✅ | ❌ |
| MinerU / PaddleOCR | ✅ | ❌ |
| Model selection per session | ✅ | ❌ (global only) |
| Multiple providers simultaneously | ✅ | ❌ (one active) |

---

## Settings & Configuration

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| API key storage (Keychain) | ❌ (server-side) | ✅ |
| Ollama host + model config | ✅ | ✅ |
| Ollama connection test | ✅ | ✅ |
| Brave Search API key | ❌ | ✅ |
| User profile / avatar | ✅ | ❌ |
| Language / locale selection | ✅ (18+ languages) | ❌ (system locale) |
| Programmatic API key generation | ✅ | ❌ |
| Team / user management | ✅ | ❌ |

---

## Data Sources & Integrations

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| iCloud Drive | ❌ | ✅ |
| On My iPhone (Files app) | ❌ | ✅ |
| Confluence | ✅ | ❌ |
| Notion | ✅ | ❌ |
| Google Drive | ✅ | ❌ |
| Gmail / IMAP | ✅ | ❌ |
| Dropbox / Box | ✅ | ❌ |
| S3 / R2 / GCS / OCI | ✅ | ❌ |
| GitHub / GitLab / Bitbucket | ✅ | ❌ |
| Jira / Asana / Zendesk | ✅ | ❌ |
| MySQL / PostgreSQL | ✅ | ❌ |
| WebDAV / Seafile | ✅ | ❌ |

---

## Collaboration, Sharing & Enterprise

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| Multi-user / team accounts | ✅ | ❌ |
| Role-based access control | ✅ | ❌ |
| Public share links (chat, search, agent) | ✅ | ❌ |
| Embedded widgets for websites | ✅ | ❌ |
| Admin dashboard | ✅ | ❌ |
| Usage analytics / monitoring | ✅ | ❌ |
| IP / API key whitelisting | ✅ | ❌ |
| Sandbox (code execution env) | ✅ | ❌ |

---

## Platform & Access

| Feature | Web App | iOS Mobile |
|---|:---:|:---:|
| Self-hosted deployment | ✅ | ❌ |
| Works offline (local Ollama) | ⚡ (Ollama must be running) | ✅ |
| iCloud Drive access | ❌ | ✅ |
| Runs on iPhone / iPad | ❌ | ✅ |
| Share sheet (iOS system share) | ❌ | ✅ |
| Background indexing | ❌ | ✅ (BGProcessingTask) |
| On-device SQLite (GRDB) | ❌ | ✅ |
| Keychain credential storage | ❌ | ✅ |
| REST API access | ✅ | ❌ |
| Docker deployment | ✅ | ❌ |

---

## Summary

| Category | Web App | iOS Mobile |
|---|:---:|:---:|
| Knowledge base features | ★★★★★ | ★★★☆☆ |
| Document import breadth | ★★★★★ | ★★★★☆ |
| Chat features | ★★★★★ | ★★★★☆ |
| Workflow / agent capability | ★★★★★ | ★★☆☆☆ |
| LLM provider support | ★★★★★ | ★★★☆☆ |
| Integrations / data sources | ★★★★★ | ★★☆☆☆ |
| Collaboration / enterprise | ★★★★★ | ★☆☆☆☆ |
| Mobile / offline experience | ★☆☆☆☆ | ★★★★★ |
| Privacy (on-device / Keychain) | ★★☆☆☆ | ★★★★★ |

**Web app** is the full-featured platform — best for teams, power users, complex pipelines, and self-hosted deployments.

**iOS mobile** is optimized for personal, private, on-the-go document Q&A — best for single users who want a native iPhone/iPad experience with iCloud, local Ollama, or cloud AI.
