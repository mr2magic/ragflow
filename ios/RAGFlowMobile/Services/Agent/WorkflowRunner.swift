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

        defer {
            isRunning = false
            currentStep = ""
        }

        var ctx: StepContext = ["input": input]
        var finalOutput = ""
        var failed = false
        var entries: [String] = []

        for step in steps {
            guard !Task.isCancelled else { failed = true; break }

            currentStep = step.label
            log(into: &entries, "▶ \(step.label)")

            do {
                switch step.type {
                case .begin:
                    ctx[step.outputSlot] = input

                case .retrieve:
                    let query = ctx[step.querySlot] ?? input
                    let kbId = step.kbIdOverride ?? workflow.kbId
                    let chunks: [Chunk]

                    // Prefer embedding-based retrieval for Ollama
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

                    let contextText = chunks.map { c -> String in
                        if let t = c.chapterTitle { return "[\(t)] \(c.content)" }
                        return c.content
                    }.joined(separator: "\n\n")

                    ctx[step.outputSlot] = contextText
                    log(into: &entries, "  Retrieved \(chunks.count) chunks")

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
                    let rewriteStream = try await rewriteLLM.complete(messages: [rewriteMsg], context: [])
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
                    let executor = ToolExecutor(braveApiKey: settings.config.braveSearchApiKey)
                    let results = await executor.execute(name: "brave_search", input: ["query": query])
                    ctx[step.outputSlot] = results
                    log(into: &entries, "  Web results: \(results.prefix(80))…")

                case .llm:
                    let prompt = ctx.render(step.promptTemplate)
                    let llm = makeLLMService(config: settings.config)
                    let userMsg = LLMMessage(role: .user, content: prompt)
                    let stream = try await llm.complete(messages: [userMsg], context: [])

                    var response = ""
                    // Only stream to UI if this is the final LLM step before answer
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
                }
            } catch {
                log(into: &entries, "  ✗ Error: \(error.localizedDescription)")
                failed = true
                break
            }
            coordinator.advanceWorkflow()
        }

        coordinator.finishWorkflow(success: !failed)

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
