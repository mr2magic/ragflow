# Development Guide

Everything you need to build, run, test, and debug RAGFlow Mobile.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Getting the Code](#2-getting-the-code)
3. [Opening the Project](#3-opening-the-project)
4. [First-Run Setup](#4-first-run-setup)
5. [Build & Run](#5-build--run)
6. [Running Tests](#6-running-tests)
7. [Debug Utilities](#7-debug-utilities)
8. [Code Conventions](#8-code-conventions)
9. [Adding a Feature](#9-adding-a-feature)
10. [Adding an LLM Provider](#10-adding-an-llm-provider)
11. [Adding a Document Parser](#11-adding-a-document-parser)
12. [Database Migrations](#12-database-migrations)
13. [Archiving for Release](#13-archiving-for-release)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Xcode | 15+ | Mac App Store |
| iOS target | 17.0+ | Simulator or device |
| XcodeGen *(optional)* | 2.x | `brew install xcodegen` |
| Ollama *(optional)* | any | [ollama.com](https://ollama.com) |

You do **not** need Node, Python, Docker, or the RAGFlow backend server to run the iOS app.

---

## 2. Getting the Code

```bash
git clone https://github.com/<your-org>/ragflow.git
cd ragflow/ios
```

The `.xcodeproj` is checked in. If you need to regenerate it from `project.yml`:

```bash
xcodegen generate
```

---

## 3. Opening the Project

```bash
open RAGFlowMobile.xcodeproj
```

Select the **RAGFlowMobile** scheme and a simulator or device target.

---

## 4. First-Run Setup

### LLM Provider

The app requires at least one provider to be configured before chat works.

**Claude (recommended)**:
1. Create an account at [console.anthropic.com](https://console.anthropic.com)
2. Generate an API key
3. In the app: Settings → Provider: Claude → paste key

**OpenAI**:
1. [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Settings → Provider: ChatGPT → paste key

**Ollama (local, no cost)**:
1. Install Ollama: `brew install ollama`
2. Pull models: `ollama pull llama3.2 && ollama pull nomic-embed-text`
3. Start: `ollama serve`
4. Settings → Provider: Ollama → host: `http://localhost:11434` → select model

> **Note**: Embeddings (for vector search) require Ollama regardless of which chat provider you use. If Ollama is not available, retrieval falls back to BM25 keyword search only.

---

## 5. Build & Run

```
Cmd + B    Build
Cmd + R    Run
Cmd + .    Stop
```

### Simulator Tips

- Use **iPhone 16** or **iPad Pro 13"** simulators to test both layout branches.
- To test the adaptive split-view on iPad, use the 13" simulator and ensure it's full-screen.
- File import works in the simulator — use the Files app to place test documents in iCloud Drive.

### Device Testing

- Requires a valid provisioning profile (free Apple ID works for personal builds).
- Background task behavior (`BGContinuedProcessingTask`) only fires on a real device, not the simulator.

---

## 6. Running Tests

```
Cmd + U     Run all tests
```

Test targets:
- `RAGFlowMobileTests` — unit tests for services and models
- `RAGFlowMobileUITests` — UI automation tests

To run a single test file: open the file and click the diamond run button next to the test class or method.

---

## 7. Debug Utilities

In **DEBUG builds**, `SettingsView` shows a debug section at the bottom:

| Button | Effect |
|--------|--------|
| Reset Onboarding | Clears `hasCompletedOnboarding`; shows the carousel on next launch |
| Wipe All App Data | Deletes the entire SQLite database, clears UserDefaults and Keychain entries |

`KBListViewModel` has a `seedDummy()` method that creates test KBs, books, and chunks — useful for testing the chat UI without importing real documents.

### Useful Breakpoints

- `RAGService.ingest(url:kbId:)` — verify file is being parsed
- `EmbeddingService.embed(texts:)` — check Ollama is reachable
- `ClaudeService` / `OpenAIService` stream handlers — inspect token delivery

### Console Logging

No third-party logging framework is used. `print()` statements are scattered through services and are stripped in release builds. Use Xcode Console to filter by subsystem.

---

## 8. Code Conventions

### SwiftUI Views

- Keep views thin — no business logic, no service calls.
- Use `@StateObject` for ViewModels owned by the view.
- Use `@ObservedObject` for ViewModels passed in from a parent.
- Use `@EnvironmentObject` sparingly; prefer explicit bindings.

### ViewModels

- Always `@MainActor` to avoid published-on-background-thread warnings.
- Prefix state booleans with `show` (e.g., `showCreateAlert`, `showDeleteConfirm`).
- Error state: `@Published var showError = false` + `@Published var errorMessage = ""`.

### Async Patterns

- Use `Task { }` inside `@MainActor` types to kick off async work.
- Prefer `AsyncThrowingStream` for streaming results (LLM responses).
- Cancel tasks by holding a `Task?` reference and calling `.cancel()`.

### Naming

- Files match their primary type: `KBListViewModel.swift` contains `KBListViewModel`.
- Services are singletons accessed via `.shared`.
- Views end in `View`, ViewModels end in `ViewModel`, Services end in `Service`.

### No Force Unwrap

Avoid `!` except in test code. Use `guard let`, `if let`, or provide a safe default.

---

## 9. Adding a Feature

1. Create a folder under `Features/` (e.g., `Features/Annotations/`)
2. Add a `ViewModel` (`@MainActor ObservableObject`) for business logic
3. Add `View` files for the UI
4. Add a database migration if new tables are needed (see [section 12](#12-database-migrations))
5. Wire up navigation in `ContentView.swift` (iPhone tab) or `KBListView.swift` (iPad toolbar)
6. Add tests in `RAGFlowMobileTests/`

---

## 10. Adding an LLM Provider

1. Create `Services/LLM/YourProviderService.swift`
2. Implement the `LLMService` protocol:
   ```swift
   func complete(
       messages: [LLMMessage],
       context: String,
       books: [Book]
   ) -> AsyncThrowingStream<String, Error>
   ```
3. Add a case to `LLMProvider` enum in `LLMConfig.swift`
4. Add the new case to `makeLLMService(config:)` in `LLMService.swift`
5. Add UI in `SettingsView.swift` (credential fields, connection test if needed)
6. Add credential storage in `SettingsStore.swift` (Keychain for API keys)

---

## 11. Adding a Document Parser

1. Create `Services/RAG/YourFormatParser.swift`
2. Implement a function that accepts a `URL` and returns parsed text (and optionally metadata)
3. Register the new format in `RAGService.ingest(url:kbId:)`:
   - Add the UTType to the format dispatch `switch`
   - Call your parser
4. Declare the UTType in `LibraryView.swift`'s `.fileImporter(allowedContentTypes:)` array
5. Add the UTType to `Info.plist` document types if needed for open-in-place support

---

## 12. Database Migrations

Migrations live in `DatabaseService.swift` and are **append-only** — never edit or remove an existing migration.

To add a migration:

```swift
migrator.registerMigration("v9") { db in
    try db.alter(table: "books") { t in
        t.add(column: "language", .text).notNull().defaults(to: "en")
    }
}
```

Then update the corresponding model struct and GRDB `CodingKeys` to include the new column.

**Rules**:
- Name migrations sequentially (`v9`, `v10`, …)
- Make all new columns nullable or provide a default — existing rows must satisfy the constraint
- Never drop columns or tables in a migration (data loss risk)
- Test with a device/simulator that has an older build installed to verify upgrade path

---

## 13. Archiving for Release

1. Set the correct **version** and **build number** in the project settings
2. Select **Any iOS Device (arm64)** as the target
3. `Product → Archive`
4. In Organizer: Distribute App → App Store Connect (or Ad Hoc)

The `ExportOptions.plist` in the `ios/` directory contains the export method and provisioning config used for automated builds.

---

## 14. Troubleshooting

### "Cannot find type 'X' in scope"

Check that the file is added to the `RAGFlowMobile` target (not just on disk).

### Ollama connection fails in Settings

- Confirm Ollama is running: `curl http://localhost:11434/api/tags`
- On simulator, `localhost` resolves correctly. On device, use your Mac's LAN IP.
- Check `NSLocalNetworkUsageDescription` is present in `Info.plist` (it is).

### Embeddings are missing (chunks show orange warning badge)

- Embeddings require Ollama with `nomic-embed-text` pulled.
- Pull it: `ollama pull nomic-embed-text`
- Re-import the document to regenerate embeddings.

### "BGTaskScheduler: Tasks registered after the first scene connects"

This is a fatal iOS requirement. `BGTaskScheduler.shared.register(...)` calls must happen in `RAGFlowMobileApp.init()`, not in `ContentView.onAppear`. This is already correct in the codebase — this error indicates the init() was accidentally moved.

### Chat shows "No API key configured" banner

- Go to Settings, select a provider, and enter a valid API key.
- `SettingsStore.isConfigured` returns `false` until minimum credentials are present.

### Database is corrupted / app won't launch

In DEBUG builds: Settings → Wipe All App Data.
In release builds: Delete and reinstall the app (this is destructive — all KB data is lost).
