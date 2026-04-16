# Contributing Guide

Guidelines for the team taking over RAGFlow Mobile development.

---

## Table of Contents

1. [Branch Strategy](#1-branch-strategy)
2. [Commit Messages](#2-commit-messages)
3. [Pull Request Process](#3-pull-request-process)
4. [Code Review Checklist](#4-code-review-checklist)
5. [Issue Labels](#5-issue-labels)
6. [Release Process](#6-release-process)
7. [Known Areas for Improvement](#7-known-areas-for-improvement)

---

## 1. Branch Strategy

```
main            — stable; always builds and passes tests
feature/<name>  — new features (branch from main)
fix/<name>      — bug fixes
refactor/<name> — refactors with no behavior change
```

- Branch from `main`
- Keep branches short-lived (days, not weeks)
- Delete branches after merge

---

## 2. Commit Messages

Use the conventional commit format:

```
<type>(<scope>): <short description>

[optional body]
```

Types: `Feat`, `Fix`, `Refactor`, `Docs`, `Test`, `Chore`

Scope (optional): `iOS`, `Chat`, `KB`, `Library`, `Workflows`, `Settings`, `RAG`, `LLM`, `DB`

Examples:
```
Feat(iOS): add PDF annotation export
Fix(Chat): cancel button does not stop stream on iPad
Refactor(RAG): extract embedding batch size to constant
Docs(iOS): update ARCHITECTURE with v9 migration details
```

---

## 3. Pull Request Process

1. Open a PR from your feature branch to `main`
2. Fill in the PR template (summary, test plan, screenshots for UI changes)
3. Assign at least one reviewer
4. All CI checks must pass before merge
5. Squash merge preferred for feature branches; merge commit for releases

### PR Template

```markdown
## What
Brief description of the change.

## Why
Context or linked issue.

## How
Notable implementation decisions.

## Test Plan
- [ ] Tested on iPhone simulator
- [ ] Tested on iPad simulator
- [ ] Tested with Claude provider
- [ ] Tested with Ollama provider
- [ ] No regressions in existing features

## Screenshots (if UI change)
```

---

## 4. Code Review Checklist

Reviewers should verify:

- [ ] No business logic in View files
- [ ] No force-unwrap (`!`) outside of tests
- [ ] New database columns use nullable or default values (migration safety)
- [ ] API keys are stored in Keychain — never `UserDefaults`, never logged
- [ ] New async work is wrapped in a background task fence for long-running operations
- [ ] `@MainActor` on all ViewModels
- [ ] New file types declared in both `RAGService.ingest()` and `.fileImporter(allowedContentTypes:)`
- [ ] New migrations are append-only and named sequentially

---

## 5. Issue Labels

| Label | Meaning |
|-------|---------|
| `bug` | Something is broken |
| `enhancement` | New feature or improvement |
| `performance` | Speed or memory issue |
| `ux` | UI/UX design concern |
| `database` | Schema or GRDB issue |
| `llm` | LLM provider integration |
| `rag` | Document parsing or retrieval |
| `background` | Background task / iOS lifecycle |
| `iPad` | iPad-specific layout issue |

---

## 6. Release Process

1. **Bump version**: `MARKETING_VERSION` in project settings (e.g., `0.2.0`)
2. **Bump build number**: `CURRENT_PROJECT_VERSION`
3. **Tag**: `git tag ios/0.2.0 && git push origin ios/0.2.0`
4. **Archive**: `Product → Archive` in Xcode
5. **Distribute**: Organizer → Distribute App → App Store Connect / TestFlight
6. **Release notes**: Document changes in GitHub Releases

---

## 7. Known Areas for Improvement

These are tracked debt items inherited from the initial build. Pick them up when they align with sprint priorities.

### High Priority

| Area | Issue | Suggested Approach |
|------|-------|--------------------|
| Import cleanup | Temp files not deleted on parse failure | Add `defer { try? FileManager.default.removeItem(at: tempURL) }` in ingest paths |
| Large files | Files >100 MB may exhaust memory during parsing | Stream-parse PDFs page-by-page without loading full text into one string |
| Test coverage | Minimal unit tests | Start with `RAGService`, `Chunker`, and `DatabaseService` — pure functions are easiest |

### Medium Priority

| Area | Issue | Suggested Approach |
|------|-------|--------------------|
| Multi-KB ranking | Chunks from multiple KBs are merged without cross-KB scoring | Apply RRF across KBs, not just within each KB |
| Workflow parallel steps | Steps run sequentially | Add a `parallel` step type that fans out and joins |
| Chat history pagination | All messages loaded on init | Load last N messages; paginate up on scroll |
| Accessibility | No comprehensive audit | Run Accessibility Inspector; add `.accessibilityLabel` to interactive elements |

### Low Priority

| Area | Issue | Suggested Approach |
|------|-------|--------------------|
| Ollama auto-download | Models must be manually pulled | Check for model presence; prompt user with `ollama pull` instructions |
| OpenAI streaming | Non-streaming request; simulated word-by-word | Use streaming API (`stream: true`) for real token delivery |
| Export | No way to export chat transcripts or workflow runs | Add share sheet with markdown export |
| Sync | Data is device-local only | CloudKit sync for KBs across devices |
