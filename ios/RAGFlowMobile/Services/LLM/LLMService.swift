import Foundation

protocol LLMService {
    func complete(messages: [LLMMessage], context: [Chunk], books: [Book]) async throws -> AsyncThrowingStream<String, Error>
    var lastUsage: TokenUsage? { get }
}

// MARK: - Token Usage

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int
    let model: String
    let provider: LLMProvider

    var totalTokens: Int { inputTokens + outputTokens }

    var cost: Double {
        let r = ModelPricing.rates[model] ?? (0, 0)
        return Double(inputTokens) * r.0 / 1_000_000
             + Double(outputTokens) * r.1 / 1_000_000
    }

    var formattedCost: String {
        if provider == .ollama { return "Free" }
        if cost < 0.000_05 { return "<$0.0001" }
        return String(format: "$%.4f", cost)
    }

    var formattedTokens: String {
        totalTokens >= 1000
            ? String(format: "%.1fk tokens", Double(totalTokens) / 1000)
            : "\(totalTokens) tokens"
    }
}

enum ModelPricing {
    /// (input $/M, output $/M) — update as provider pricing changes
    static let rates: [String: (Double, Double)] = [
        // Claude
        "claude-opus-4-6":         (15.00, 75.00),
        "claude-sonnet-4-6":       ( 3.00, 15.00),
        "claude-haiku-4-5-20251001":( 0.80,  4.00),
        "claude-haiku-4-5":        ( 0.80,  4.00),
        "claude-haiku-3-5":        ( 0.80,  4.00),
        // OpenAI
        "gpt-4o":                  ( 2.50, 10.00),
        "gpt-4o-mini":             ( 0.15,  0.60),
        "gpt-4-turbo":             (10.00, 30.00),
        "o1":                      (15.00, 60.00),
        "o1-mini":                 ( 3.00, 12.00),
        "o3-mini":                 ( 1.10,  4.40),
    ]
}

struct LLMMessage {
    var role: Role
    var content: String

    enum Role: String {
        case system, user, assistant
    }
}

struct ChatParams {
    var modelOverride: String?
    var temperature: Double?
    var topP: Double?
    var extraSystemPrompt: String

    static let `default` = ChatParams(
        modelOverride: nil,
        temperature: nil,
        topP: nil,
        extraSystemPrompt: ""
    )
}

func makeLLMService(config: LLMConfig, params: ChatParams = .default) -> any LLMService {
    switch config.provider {
    case .claude:
        return ClaudeService(apiKey: config.claudeApiKey, braveApiKey: config.braveSearchApiKey, params: params)
    case .openAI:
        return OpenAIService(apiKey: config.openAIApiKey, params: params)
    case .ollama:
        let model = params.modelOverride ?? config.ollamaModel
        return OllamaService(host: config.ollamaHost, model: model, params: params)
    }
}

// MARK: - Shared enterprise system prompt

/// Builds the RAGflow-style enterprise knowledge assistant system prompt.
/// Used by all three LLM service implementations.
func buildEnterprisePrompt(context: [Chunk], books: [Book], extraInstructions: String = "") -> String {
    let catalog: String
    if books.isEmpty {
        catalog = ""
    } else {
        let entries = books.enumerated().map { i, b -> String in
            var line = "  \(i + 1). \"\(b.title)\""
            if !b.author.isEmpty { line += " — \(b.author)" }
            let meta = [
                b.fileType.isEmpty ? nil : b.fileType.uppercased(),
                b.pageCount > 0 ? "\(b.pageCount) pages" : nil,
                b.wordCount > 0 ? "\(b.wordCount / 1000)k words" : nil,
                "\(b.chunkCount) passages"
            ].compactMap { $0 }.joined(separator: ", ")
            if !meta.isEmpty { line += " (\(meta))" }
            return line
        }.joined(separator: "\n")
        catalog = """
        KNOWLEDGE BASE — \(books.count) document\(books.count == 1 ? "" : "s") indexed:
        \(entries)

        """
    }

    let passages: String
    if context.isEmpty {
        passages = "(no passages retrieved for this query)"
    } else {
        passages = context.enumerated().map { i, chunk in
            var header = "[\(i + 1)]"
            if !chunk.chapterTitle.isNilOrEmpty { header += " \(chunk.chapterTitle!)" }
            return "\(header)\n\(chunk.content)"
        }.joined(separator: "\n\n")
    }

    let extra = extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "" : "\n\(extraInstructions)\n"

    return """
    You are an enterprise knowledge assistant with access to an indexed knowledge base.
    Your role is to answer questions accurately using the retrieved passages below.

    \(catalog)INSTRUCTIONS:
    - When asked which documents are available, enumerate the full KNOWLEDGE BASE list above.
    - Cite specific passages using their number, e.g. [1], [2], [3].
    - If multiple passages support an answer, cite all of them.
    - Cross-document synthesis: draw connections across documents when relevant.
    - If the answer is not in the retrieved passages, say so clearly — do not hallucinate.
    - Be precise and professional. Structure long answers with headers or bullet points.\(extra)

    RETRIEVED PASSAGES:
    \(passages)
    """
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
