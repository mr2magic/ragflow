import Foundation

// MARK: - Step Types

enum StepType: String, Codable, CaseIterable {
    case begin             // entry point — holds user input in context["input"]
    case retrieve          // keyword/vector search → writes chunks text to outputSlot
    case rewrite           // LLM rewrites querySlot into a better search query → outputSlot
    case llm               // LLM call with promptTemplate → writes response to outputSlot
    case message           // static text injection — renders promptTemplate into outputSlot
    case webSearch         // web lookup → writes results to outputSlot
    case answer            // terminal node — reads from outputSlot, produces final output
    case variableAssigner  // set/append/clear slots without LLM
    case switchStep        // condition-based routing — evaluates branches and sets _next
    case categorize        // LLM classifies input into one of N categories → routes to matching step
    case parallel          // runs multiple branches concurrently; merges outputs into context

    var displayName: String {
        switch self {
        case .begin:            return "Begin"
        case .retrieve:         return "Retrieve"
        case .rewrite:          return "Rewrite"
        case .llm:              return "LLM"
        case .message:          return "Message"
        case .webSearch:        return "Web Search"
        case .answer:           return "Answer"
        case .variableAssigner: return "Set Variables"
        case .switchStep:       return "Switch"
        case .categorize:       return "Categorize"
        case .parallel:         return "Parallel"
        }
    }

    var stepDescription: String {
        switch self {
        case .begin:            return "Entry point — captures the user's input"
        case .retrieve:         return "Search the knowledge base for relevant passages"
        case .rewrite:          return "Use AI to refine the query before retrieval"
        case .llm:              return "Generate text using AI with a custom prompt"
        case .message:          return "Inject a fixed message or text template"
        case .webSearch:        return "Search the web for current information"
        case .answer:           return "Produce the final output shown to the user"
        case .variableAssigner: return "Set, append, or clear slot values"
        case .switchStep:       return "Branch to different steps based on conditions"
        case .categorize:       return "Classify input with AI and route to matching branch"
        case .parallel:         return "Run multiple steps at the same time"
        }
    }
}

// MARK: - Branch & Condition Types (Switch + Categorize)

/// A single branch arm used by Switch and Categorize steps.
struct StepBranch: Codable, Identifiable {
    var id: String = UUID().uuidString
    var label: String = ""
    /// For Switch: unused (conditions are in SwitchBranch).
    /// For Categorize: the category name the LLM should output.
    var condition: String = ""
    var nextStepId: String = ""
}

/// Comparison operators for Switch step conditions.
enum SwitchOperator: String, Codable, CaseIterable {
    case equals     = "="
    case notEquals  = "≠"
    case contains   = "contains"
    case notContains = "not contains"
    case isEmpty    = "is empty"
    case isNotEmpty = "is not empty"

    var displayName: String { rawValue }
    /// Whether the operator needs a comparison value field.
    var requiresValue: Bool { self != .isEmpty && self != .isNotEmpty }
}

/// One condition clause within a SwitchBranch.
struct SwitchCondition: Codable, Identifiable {
    var id: String = UUID().uuidString
    var slot: String = "input"
    var op: SwitchOperator = .contains
    var value: String = ""
}

/// AND / OR combiner for multiple SwitchConditions.
enum ConditionLogic: String, Codable, CaseIterable {
    case and = "AND"
    case or  = "OR"
}

/// A full Switch branch: conditions + logic + target step.
struct SwitchBranch: Codable, Identifiable {
    var id: String = UUID().uuidString
    var label: String = ""
    var logic: ConditionLogic = .and
    var conditions: [SwitchCondition] = []
    var nextStepId: String = ""
}

// MARK: - Variable Assigner Types

enum AssignOperation: String, Codable, CaseIterable {
    case set    = "Set"
    case append = "Append"
    case clear  = "Clear"

    var displayName: String { rawValue }
    var requiresValue: Bool { self != .clear }
}

struct VariableAssignment: Codable, Identifiable {
    var id: String = UUID().uuidString
    var targetSlot: String = ""
    var operation: AssignOperation = .set
    var value: String = ""
}

// MARK: - Parallel Branch

/// One branch within a parallel step. Each branch holds a single step that runs
/// concurrently with the other branches; its output is written to `step.outputSlot`.
struct ParallelBranch: Codable, Identifiable {
    var id: String = UUID().uuidString
    var label: String = ""
    var step: WorkflowStep
}

// MARK: - Step Model

struct WorkflowStep: Codable, Identifiable {
    var id: String
    var type: StepType
    var label: String

    // Retrieve config
    var querySlot: String    // which context slot to use as search query
    var topK: Int            // number of chunks to retrieve
    var kbIdOverride: String? // nil = use workflow's default kbId

    // LLM / message / rewrite config — supports {slot} substitution
    var promptTemplate: String

    // Output
    var outputSlot: String   // where to write this step's result

    // ── Routing (all optional, nil = sequential fallback) ───────────────────
    /// Explicit next step ID override. Skips array-order if set.
    var nextStepId: String?
    /// Fallback step ID used by Switch / Categorize when no branch matches.
    var defaultNextStepId: String?

    // ── Variable Assigner config ─────────────────────────────────────────────
    var assignments: [VariableAssignment]?

    // ── Switch step config ───────────────────────────────────────────────────
    var switchBranches: [SwitchBranch]?

    // ── Categorize step config ───────────────────────────────────────────────
    var categories: [StepBranch]?
    var categoryPromptOverride: String?

    // ── Web search tool selection ─────────────────────────────────────────────
    /// Tool ID from SearchToolRegistry. Defaults to "brave_search" when nil.
    var webSearchToolId: String?

    // ── Parallel step config ──────────────────────────────────────────────────
    /// Branches executed concurrently. Each branch runs its embedded step and
    /// writes the result to that step's outputSlot in the shared context.
    var parallelBranches: [ParallelBranch]?

    init(
        id: String = UUID().uuidString,
        type: StepType,
        label: String,
        querySlot: String = "input",
        topK: Int = 5,
        kbIdOverride: String? = nil,
        promptTemplate: String = "",
        outputSlot: String,
        nextStepId: String? = nil,
        defaultNextStepId: String? = nil,
        assignments: [VariableAssignment]? = nil,
        switchBranches: [SwitchBranch]? = nil,
        categories: [StepBranch]? = nil,
        categoryPromptOverride: String? = nil,
        webSearchToolId: String? = nil,
        parallelBranches: [ParallelBranch]? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.querySlot = querySlot
        self.topK = topK
        self.kbIdOverride = kbIdOverride
        self.promptTemplate = promptTemplate
        self.outputSlot = outputSlot
        self.nextStepId = nextStepId
        self.defaultNextStepId = defaultNextStepId
        self.assignments = assignments
        self.switchBranches = switchBranches
        self.categories = categories
        self.categoryPromptOverride = categoryPromptOverride
        self.webSearchToolId = webSearchToolId
        self.parallelBranches = parallelBranches
    }
}

// MARK: - Execution Context

/// A simple string→string dictionary passed between steps.
/// Slots: "input" (user query), "context" (retrieved text), "output" (final answer),
/// "_next" (routing signal written by Switch/Categorize, consumed by WorkflowRunner),
/// plus any step-specific slots.
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
