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
        defer { isRunning = false; currentStep = "" }

        var ctx: StepContext = ["input": input]
        var finalOutput = ""
        var failed = false
        var log: [String] = []

        let steps = workflow.steps

        for step in steps {
            guard !Task.isCancelled else { failed = true; break }

            currentStep = step.label
            log(into: &log, "▶ \(step.label)")

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

                    let contextText = chunks.map { c in
                        let title = c.chapterTitle.map { "[\($0)]" } ?? ""
                        return "\(title) \(c.content)"
                    }.joined(separator: "\n\n")

                    ctx[step.outputSlot] = contextText
                    log(into: &log, "  Retrieved \(chunks.count) chunks")

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
                    log(into: &log, "  LLM response: \(response.prefix(80))…")

                case .answer:
                    finalOutput = ctx[step.outputSlot] ?? ctx["output"] ?? ""
                }
            } catch {
                log(into: &log, "  ✗ Error: \(error.localizedDescription)")
                failed = true
                break
            }
        }

        if finalOutput.isEmpty { finalOutput = ctx["output"] ?? streamingOutput }
        stepLog = log

        let encodedLog = (try? String(data: JSONEncoder().encode(log), encoding: .utf8)) ?? "[]"
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
