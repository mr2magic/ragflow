import Foundation

// MARK: - Step Types

enum StepType: String, Codable, CaseIterable {
    case begin       // entry point — holds user input in context["input"]
    case retrieve    // keyword/vector search → writes chunks text to outputSlot
    case llm         // LLM call with promptTemplate → writes response to outputSlot
    case answer      // terminal node — reads from inputSlot, produces final output
}

// MARK: - Step Model

struct WorkflowStep: Codable, Identifiable {
    var id: String
    var type: StepType
    var label: String

    // Retrieve config
    var querySlot: String   // which context slot to use as search query
    var topK: Int           // number of chunks to retrieve
    var kbIdOverride: String? // nil = use workflow's default kbId

    // LLM config — prompt can reference slots with {slotName}
    var promptTemplate: String

    // Output
    var outputSlot: String  // where to write this step's result

    init(
        id: String = UUID().uuidString,
        type: StepType,
        label: String,
        querySlot: String = "input",
        topK: Int = 5,
        kbIdOverride: String? = nil,
        promptTemplate: String = "",
        outputSlot: String
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.querySlot = querySlot
        self.topK = topK
        self.kbIdOverride = kbIdOverride
        self.promptTemplate = promptTemplate
        self.outputSlot = outputSlot
    }
}

// MARK: - Execution Context

/// A simple string→string dictionary passed between steps.
/// Slots: "input" (user query), "context" (retrieved text), "output" (final answer), plus any step-specific slots.
typealias StepContext = [String: String]

extension StepContext {
    /// Substitute {slotName} placeholders in a template string.
    func render(_ template: String) -> String {
        var result = template
        for (key, value) in self {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
