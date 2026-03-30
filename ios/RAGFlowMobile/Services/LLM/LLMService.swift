import Foundation

protocol LLMService {
    func complete(messages: [LLMMessage], context: [Chunk], books: [Book]) async throws -> AsyncThrowingStream<String, Error>
}

struct LLMMessage {
    var role: Role
    var content: String

    enum Role: String {
        case system, user, assistant
    }
}

func makeLLMService(config: LLMConfig) -> any LLMService {
    switch config.provider {
    case .claude:
        return ClaudeService(apiKey: config.claudeApiKey, braveApiKey: config.braveSearchApiKey)
    case .openAI:
        return OpenAIService(apiKey: config.openAIApiKey)
    case .ollama:
        return OllamaService(host: config.ollamaHost, model: config.ollamaModel)
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
