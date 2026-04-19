import Foundation

@MainActor
final class WorkflowRunner: ObservableObject {
    @Published var isRunning = false
    @Published var currentStep = ""
    @Published var stepLog: [String] = []
    @Published var streamingOutput = ""

    private let rag = RAGService.shared
    private let settings = SettingsStore.shared
    private var runTask: Task<Void, Never>?

    func run(workflow: Workflow, input: String) async -> WorkflowRun {
        isRunning = true
        stepLog = []
        streamingOutput = ""

        let coordinator = BackgroundTaskCoordinator.shared
        let steps = workflow.steps
        coordinator.beginWorkflow(name: workflow.name, stepCount: steps.count)
        WorkflowActivityManager.shared.start(
            workflowName: workflow.name,
            firstStepLabel: steps.first?.label ?? "Starting…",
            totalSteps: steps.count
        )

        defer {
            isRunning = false
            currentStep = ""
        }

        var ctx: StepContext = ["input": input]
        var finalOutput = ""
        var failed = false
        var entries: [String] = []

        // Build O(1) step lookup for routing
        let stepIndex: [String: WorkflowStep] = Dictionary(
            uniqueKeysWithValues: steps.map { ($0.id, $0) }
        )
        var visitedIds = Set<String>()   // cycle guard

        var cursor: WorkflowStep? = steps.first
        while let step = cursor {
            guard !Task.isCancelled else { failed = true; break }

            // Cycle guard — prevents runaway loops in malformed switch graphs
            guard !visitedIds.contains(step.id) else {
                log(into: &entries, "  ✗ Cycle detected at step '\(step.label)' — stopping")
                failed = true
                break
            }
            visitedIds.insert(step.id)

            currentStep = step.label
            log(into: &entries, "▶ \(step.label)")
            WorkflowActivityManager.shared.update(
                stepLabel: step.label,
                stepIndex: visitedIds.count,
                totalSteps: steps.count
            )

            do {
                switch step.type {
                case .begin:
                    ctx[step.outputSlot] = input

                case .retrieve:
                    let query = ctx[step.querySlot] ?? input
                    let kbId = step.kbIdOverride ?? workflow.kbId
                    let chunks: [Chunk]

                    if settings.config.provider == .ollama {
                        let embService = EmbeddingService(host: settings.config.ollamaHost)
                        if let vec = try? await embService.embed(text: query) {
                            chunks = try rag.retrieveWithEmbedding(query: query, queryEmbedding: vec, kbId: kbId, topK: step.topK)
                        } else {
                            chunks = try rag.retrieve(query: query, kbId: kbId, topK: step.topK)
                        }
                    } else {
                        chunks = try rag.retrieve(query: query, kbId: kbId, topK: step.topK)
                    }

                    if chunks.isEmpty {
                        ctx[step.outputSlot] = "[No relevant content found in the knowledge base for this query. The knowledge base may be empty, or no documents match the search terms.]"
                        log(into: &entries, "  ⚠ 0 chunks retrieved — check KB assignment and document indexing. '\(step.outputSlot)' will signal no-context to the LLM.")
                    } else {
                        let contextText = chunks.map { c -> String in
                            if let t = c.chapterTitle { return "[\(t)] \(c.content)" }
                            return c.content
                        }.joined(separator: "\n\n")
                        ctx[step.outputSlot] = contextText
                        log(into: &entries, "  Retrieved \(chunks.count) chunks → '\(step.outputSlot)'")
                    }

                case .rewrite:
                    let query = ctx[step.querySlot] ?? input
                    let rewritePrompt: String
                    if step.promptTemplate.isEmpty {
                        rewritePrompt = "Rewrite the following question into a concise, search-friendly query. Return only the rewritten query, nothing else.\n\nOriginal: \(query)"
                    } else {
                        rewritePrompt = ctx.render(step.promptTemplate)
                    }
                    let rewriteLLM = makeLLMService(config: settings.config)
                    let rewriteMsg = LLMMessage(role: .user, content: rewritePrompt)
                    let rewriteStream = try await rewriteLLM.complete(messages: [rewriteMsg], context: [], books: [])
                    var rewritten = ""
                    for try await token in rewriteStream { rewritten += token }
                    rewritten = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
                    ctx[step.outputSlot] = rewritten
                    log(into: &entries, "  Rewritten query: \(rewritten.prefix(80))")

                case .message:
                    ctx[step.outputSlot] = ctx.render(step.promptTemplate)
                    log(into: &entries, "  Message injected into \(step.outputSlot)")

                case .webSearch:
                    let query = ctx[step.querySlot] ?? input
                    let toolId = step.webSearchToolId ?? "brave_search"
                    let results = await SearchToolRegistry.shared
                        .tool(id: toolId)?
                        .search(query: query, apiKey: settings.config.braveSearchApiKey)
                        ?? "Search tool '\(toolId)' not found."
                    ctx[step.outputSlot] = results
                    log(into: &entries, "  Web results: \(results.prefix(80))…")

                case .llm:
                    let prompt = ctx.render(step.promptTemplate)
                    let llm = makeLLMService(config: settings.config)
                    let userMsg = LLMMessage(role: .user, content: prompt)
                    let stream = try await llm.complete(messages: [userMsg], context: [], books: [])

                    var response = ""
                    // Only stream to UI if this is the last LLM step before answer
                    let isLastLLM = steps.drop(while: { $0.id != step.id }).dropFirst()
                        .first(where: { $0.type == .llm }) == nil
                    for try await token in stream {
                        response += token
                        if isLastLLM { streamingOutput = response }
                    }
                    ctx[step.outputSlot] = response
                    log(into: &entries, "  LLM response: \(response.prefix(80))…")

                case .answer:
                    finalOutput = ctx[step.outputSlot] ?? ctx["output"] ?? ""

                // ── Phase 1: new step types ────────────────────────────────

                case .variableAssigner:
                    for a in step.assignments ?? [] {
                        let target = a.targetSlot.trimmingCharacters(in: .whitespaces)
                        guard !target.isEmpty else { continue }
                        switch a.operation {
                        case .set:
                            ctx[target] = ctx.render(a.value)
                        case .append:
                            let existing = ctx[target] ?? ""
                            let appended = ctx.render(a.value)
                            ctx[target] = existing.isEmpty ? appended : "\(existing)\n\(appended)"
                        case .clear:
                            ctx[target] = ""
                        }
                    }
                    log(into: &entries, "  Assigned \(step.assignments?.count ?? 0) variable(s)")

                case .switchStep:
                    var matched = false
                    outer: for branch in step.switchBranches ?? [] {
                        let results: [Bool] = branch.conditions.map { c in
                            let v = ctx[c.slot] ?? ""
                            switch c.op {
                            case .equals:      return v == c.value
                            case .notEquals:   return v != c.value
                            case .contains:    return v.localizedCaseInsensitiveContains(c.value)
                            case .notContains: return !v.localizedCaseInsensitiveContains(c.value)
                            case .isEmpty:     return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            case .isNotEmpty:  return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            }
                        }
                        let passes = branch.logic == .and
                            ? results.allSatisfy({ $0 })
                            : results.contains(where: { $0 })
                        if passes && !branch.nextStepId.isEmpty {
                            ctx["_next"] = branch.nextStepId
                            matched = true
                            log(into: &entries, "  Switch → branch '\(branch.label)'")
                            break outer
                        }
                    }
                    if !matched {
                        if let fb = step.defaultNextStepId, !fb.isEmpty {
                            ctx["_next"] = fb
                            log(into: &entries, "  Switch → default branch")
                        } else {
                            log(into: &entries, "  Switch — no branch matched, falling through")
                        }
                    }

                case .categorize:
                    let categories = step.categories ?? []
                    guard !categories.isEmpty else {
                        log(into: &entries, "  Categorize — no categories defined, skipping")
                        break
                    }
                    let categoryList = categories.map { "- \($0.condition)" }.joined(separator: "\n")
                    let prompt: String
                    if let override = step.categoryPromptOverride, !override.isEmpty {
                        prompt = ctx.render(override)
                    } else {
                        prompt = """
                        Classify the following text into exactly one of these categories. \
                        Reply with ONLY the category name, nothing else.

                        Categories:
                        \(categoryList)

                        Text: \(ctx[step.querySlot] ?? input)
                        """
                    }
                    let llm = makeLLMService(config: settings.config)
                    let msg = LLMMessage(role: .user, content: prompt)
                    let stream = try await llm.complete(messages: [msg], context: [], books: [])
                    var raw = ""
                    for try await token in stream { raw += token }
                    raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    ctx[step.outputSlot] = raw

                    if let match = categories.first(where: { raw.localizedCaseInsensitiveContains($0.condition) }),
                       !match.nextStepId.isEmpty {
                        ctx["_next"] = match.nextStepId
                        log(into: &entries, "  Categorize → '\(match.condition)'")
                    } else if let fb = step.defaultNextStepId, !fb.isEmpty {
                        ctx["_next"] = fb
                        log(into: &entries, "  Categorize → default (category: '\(raw)')")
                    } else {
                        log(into: &entries, "  Categorize — no match for '\(raw)', falling through")
                    }
                }
            } catch {
                log(into: &entries, "  ✗ Error: \(error.localizedDescription)")
                failed = true
                break
            }
            coordinator.advanceWorkflow()

            // ── Routing: _next > explicit nextStepId > array-sequential fallback ──
            if let nextId = ctx.removeValue(forKey: "_next") {
                cursor = stepIndex[nextId]
            } else if let nextId = step.nextStepId, !nextId.isEmpty {
                cursor = stepIndex[nextId]
            } else if let idx = steps.firstIndex(where: { $0.id == step.id }), idx + 1 < steps.count {
                cursor = steps[idx + 1]
            } else {
                cursor = nil
            }
        }

        coordinator.finishWorkflow(success: !failed)
        WorkflowActivityManager.shared.finish(success: !failed, totalSteps: steps.count)

        if finalOutput.isEmpty { finalOutput = ctx["output"] ?? streamingOutput }
        stepLog = entries

        let encodedLog = (try? String(data: JSONEncoder().encode(entries), encoding: .utf8)) ?? "[]"
        return WorkflowRun(
            id: UUID().uuidString,
            workflowId: workflow.id,
            input: input,
            output: finalOutput,
            status: failed ? "failed" : "completed",
            stepLogJSON: encodedLog,
            createdAt: Date()
        )
    }

    func cancel() {
        runTask?.cancel()
        isRunning = false
        currentStep = ""
    }

    private func log(into log: inout [String], _ message: String) {
        log.append(message)
        stepLog = log
    }
}
