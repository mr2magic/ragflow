# Ragion — iOS App

> **Chat with your documents using Claude, OpenAI, or local Ollama models.**

Ragion is an iOS application (iOS 17+) that lets you build private knowledge bases from your documents, then ask questions about them using any LLM. Documents are parsed, chunked, embedded, and stored locally on your device. No data leaves your device unless you're calling an external LLM API.

---

## Features

| Feature | Description |
|---------|-------------|
| **Knowledge Bases** | Organize documents into topic-specific KBs |
| **Document Import** | 20+ file types: PDF, EPUB, DOCX, XLSX, PPTX, EML, HTML, code files, and more |
| **Hybrid Search** | BM25 keyword + vector (cosine similarity) retrieval with Reciprocal Rank Fusion |
| **Multi-LLM** | Claude (Anthropic), ChatGPT (OpenAI), Ollama (local) |
| **Agent Workflows** | Multi-step pipelines: RAG Q&A, Deep Summarizer, Multi-Hop Researcher, and more |
| **Citations** | Every answer links back to the exact source passages |
| **Background Processing** | Import and workflows continue when you switch apps (iOS 26+) |
| **iPad + iPhone** | Adaptive layout — split view on iPad, tab bar on iPhone |

---

## Supported File Types

PDFs, EPUB, DOCX, XLSX, PPTX, ODP, ODS, ODT, HTML, JSON, JSONL, CSV, TSV, YAML, EML, EMLX, RTF, TXT, MD, MDX, and source code files (`.py`, `.js`, `.ts`, `.swift`, `.java`, `.c`, `.cpp`, `.go`, `.sql`, `.sh`).

---

## Quick Start

### Requirements

- Xcode 15+ (Swift 5.9)
- iOS 17.0+ device or simulator
- An LLM API key **or** a running [Ollama](https://ollama.com) instance

### Run Locally

```bash
cd ios
open RAGFlowMobile.xcodeproj
```

1. Select the `RAGFlowMobile` scheme and your target device
2. Press `Cmd + R` to build and run
3. Complete the onboarding, then go to **Settings** and add your API key

### First Use

1. **Settings** → choose a provider (Claude, ChatGPT, or Ollama) and enter credentials
2. Tap **+** to create a Knowledge Base
3. Go to the **Documents** tab → **+** → import a PDF or EPUB
4. Wait for indexing to complete (green checkmark)
5. Switch to the **Chat** tab → **New Chat** → ask a question

---

## Project Structure

```
ios/
├── RAGFlowMobile/              # All Swift source code
│   ├── App/                    # Entry point, root view, background task coordinator
│   ├── Features/               # UI feature modules
│   │   ├── KB/                 # Knowledge base list and detail
│   │   ├── Chat/               # Conversation UI and message streaming
│   │   ├── Library/            # Document import and index management
│   │   ├── Workflows/          # Agent pipeline builder and runner
│   │   ├── Settings/           # Provider config, API keys
│   │   └── Onboarding/         # Welcome carousel
│   ├── Models/                 # Data structures (KnowledgeBase, Book, Message, etc.)
│   └── Services/               # Business logic
│       ├── Storage/            # SQLite (GRDB) + Keychain/UserDefaults
│       ├── RAG/                # Document parsing, chunking, embedding, retrieval
│       ├── LLM/                # Claude, OpenAI, Ollama service integrations
│       └── Agent/              # Workflow runner and templates
├── RAGFlowMobileTests/         # Unit tests
├── RAGFlowMobileUITests/       # UI tests
├── project.yml                 # XcodeGen project spec
├── ARCHITECTURE.md             # Deep-dive architecture reference
├── DEVELOPMENT.md              # Dev setup, conventions, and workflows
└── CONTRIBUTING.md             # How to contribute to this project
```

---

## Documentation

| Document | Contents |
|----------|----------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, data flow, service contracts, database schema |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Setup guide, build commands, testing, debugging |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branch strategy, coding conventions, PR process |

---

## Dependencies

| Package | Version | Used For |
|---------|---------|----------|
| [GRDB](https://github.com/groue/GRDB.swift) | 6.27.0 | SQLite ORM and migrations |
| [EPUBKit](https://github.com/witekio/EPUBKit) | 0.4.1 | EPUB document parsing |
| [Zip](https://github.com/marmelroy/Zip) | 2.1.0 | Unzip Office documents (DOCX/XLSX/PPTX) |
| PDFKit | System | PDF text extraction |
| Accelerate / vDSP | System | Vector math for cosine similarity |

---

## Architecture Overview

The app follows **MVVM** with clear layer separation:

```
View (SwiftUI)
  └── ViewModel (ObservableObject, @MainActor)
        └── Service (RAGService, LLMService, DatabaseService)
              └── Model (KnowledgeBase, Book, Chunk, Message…)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full breakdown.

---

## License

This iOS client is part of the [RAGFlow](https://github.com/infiniflow/ragflow) open-source project. See the root `LICENSE` file for terms.
