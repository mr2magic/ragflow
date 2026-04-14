import AppIntents
import Foundation

// MARK: - Query Knowledge Base (Siri voice query)

struct QueryKBIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask RAGFlow"
    static var description = IntentDescription(
        "Ask a question against one of your RAGFlow knowledge bases and get a cited AI answer."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Knowledge Base") var kb: KBEntity
    @Parameter(title: "Question") var query: String

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let kbs = (try? DatabaseService.shared.allKBs()) ?? []
        guard let knowledgeBase = kbs.first(where: { $0.id == kb.id }) else {
            throw RAGFlowIntentError.kbNotFound
        }
        let chunks = (try? RAGService.shared.retrieve(query: query, kb: knowledgeBase)) ?? []
        let allBooks = (try? DatabaseService.shared.allBooks(kbId: knowledgeBase.id)) ?? []
        let llm = makeLLMService(config: SettingsStore.shared.config)
        let stream = try await llm.complete(
            messages: [LLMMessage(role: .user, content: query)],
            context: chunks,
            books: allBooks
        )
        var answer = ""
        for try await token in stream { answer += token }
        let result = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return .result(value: result, dialog: "\(result)")
    }
}

// MARK: - Quick Query (Action Button / Shortcuts)

struct QuickQueryIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick RAGFlow Query"
    static var description = IntentDescription(
        "Open RAGFlow ready to type a question. Assign this to the Action Button in Settings."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Run Workflow

struct RunWorkflowIntent: AppIntent {
    static var title: LocalizedStringResource = "Run RAGFlow Workflow"
    static var description = IntentDescription(
        "Open RAGFlow and navigate to a saved workflow."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Workflow") var workflow: WorkflowEntity

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Import URL

struct ImportURLToRAGFlowIntent: AppIntent {
    static var title: LocalizedStringResource = "Import URL to RAGFlow"
    static var description = IntentDescription(
        "Download and index a web page into a RAGFlow knowledge base."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "URL") var url: URL
    @Parameter(title: "Knowledge Base") var kb: KBEntity

    func perform() async throws -> some IntentResult {
        // Deep-link into LibraryView with URL pre-filled.
        // Full background import requires openAppWhenRun = false + App Group,
        // which will be wired up in the Share Extension flow instead.
        return .result()
    }
}

// MARK: - App Shortcuts (surfaces intents to Siri without user setup)

struct RAGFlowAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickQueryIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Ask \(.applicationName)",
                "Query \(.applicationName)"
            ],
            shortTitle: "Ask RAGFlow",
            systemImageName: "books.vertical.fill"
        )
    }
}

// MARK: - Error

enum RAGFlowIntentError: LocalizedError {
    case kbNotFound
    case providerNotConfigured

    var errorDescription: String? {
        switch self {
        case .kbNotFound:           return "Knowledge base not found."
        case .providerNotConfigured: return "No AI provider configured. Open RAGFlow Settings to add an API key."
        }
    }
}
