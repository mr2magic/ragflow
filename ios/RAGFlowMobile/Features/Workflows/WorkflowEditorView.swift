import SwiftUI

// MARK: - Workflow Editor

struct WorkflowEditorView: View {
    let onSave: (Workflow) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode

    @State private var name: String
    @State private var kbId: String
    @State private var steps: [WorkflowStep]
    @State private var showStepPicker = false
    @State private var editingStep: WorkflowStep?
    @State private var showHelp = false

    private let workflow: Workflow
    private let allKBs: [KnowledgeBase]

    init(workflow: Workflow, onSave: @escaping (Workflow) -> Void) {
        self.workflow = workflow
        self.onSave = onSave
        self.allKBs = (try? DatabaseService.shared.allKBs()) ?? []
        _name = State(initialValue: workflow.name)
        _kbId = State(initialValue: workflow.kbId)
        _steps = State(initialValue: workflow.steps)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Identity
                Section("Workflow") {
                    TextField("Name", text: $name)
                    if allKBs.count > 1 {
                        Picker("Knowledge Base", selection: $kbId) {
                            ForEach(allKBs) { kb in
                                Text(kb.name).tag(kb.id)
                            }
                        }
                    } else if let only = allKBs.first {
                        LabeledContent("Knowledge Base", value: only.name)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Steps
                Section {
                    ForEach(steps) { step in
                        Button {
                            if editMode?.wrappedValue != .active {
                                editingStep = step
                            }
                        } label: {
                            StepEditorRow(step: step)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { steps.remove(atOffsets: $0) }

                    Button {
                        showStepPicker = true
                    } label: {
                        Label("Add Step", systemImage: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Tap to configure. Tap **Edit** to drag-reorder or swipe-delete steps.")
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DT.stamp)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showHelp = true } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        EditButton()
                        Button("Save") { commitSave() }
                            .fontWeight(.semibold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || steps.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showHelp) {
                WorkflowHelpSheet()
            }
            .sheet(isPresented: $showStepPicker) {
                StepTypePicker { type in
                    let newStep = defaultStep(for: type)
                    steps.append(newStep)
                    showStepPicker = false
                    // Short delay so sheet dismissal finishes before config opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        editingStep = newStep
                    }
                }
            }
            .sheet(item: $editingStep) { step in
                StepConfigSheet(step: step, allKBs: allKBs, allSteps: steps) { updated in
                    if let i = steps.firstIndex(where: { $0.id == updated.id }) {
                        steps[i] = updated
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func commitSave() {
        guard let encoded = try? String(
            data: JSONEncoder().encode(steps), encoding: .utf8
        ) else { return }
        var updated = workflow
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.kbId = kbId
        updated.stepsJSON = encoded
        onSave(updated)
        dismiss()
    }

    private func defaultStep(for type: StepType) -> WorkflowStep {
        switch type {
        case .begin:
            return WorkflowStep(type: .begin, label: "Input", outputSlot: "input")
        case .retrieve:
            return WorkflowStep(type: .retrieve, label: "Retrieve", querySlot: "input", topK: 6, outputSlot: "context")
        case .rewrite:
            return WorkflowStep(type: .rewrite, label: "Rewrite Query", querySlot: "input", promptTemplate: "", outputSlot: "query")
        case .llm:
            return WorkflowStep(type: .llm, label: "LLM", promptTemplate: "Answer {input} using only the following context:\n\n{context}", outputSlot: "output")
        case .message:
            return WorkflowStep(type: .message, label: "Message", promptTemplate: "", outputSlot: "message")
        case .webSearch:
            return WorkflowStep(type: .webSearch, label: "Web Search", querySlot: "input", outputSlot: "search_results")
        case .answer:
            return WorkflowStep(type: .answer, label: "Result", outputSlot: "output")
        case .variableAssigner:
            return WorkflowStep(
                type: .variableAssigner,
                label: "Set Variables",
                outputSlot: "",
                assignments: [VariableAssignment()]
            )
        case .switchStep:
            return WorkflowStep(
                type: .switchStep,
                label: "Switch",
                outputSlot: "",
                switchBranches: [SwitchBranch(label: "If", conditions: [SwitchCondition()])]
            )
        case .categorize:
            return WorkflowStep(
                type: .categorize,
                label: "Classify",
                querySlot: "input",
                outputSlot: "category",
                categories: [StepBranch(label: "Category A", condition: "Category A")]
            )
        case .parallel:
            let branchA = WorkflowStep(type: .retrieve, label: "Branch A", outputSlot: "context_a")
            let branchB = WorkflowStep(type: .retrieve, label: "Branch B", outputSlot: "context_b")
            return WorkflowStep(
                type: .parallel,
                label: "Parallel",
                outputSlot: "",
                parallelBranches: [
                    ParallelBranch(label: "Branch A", step: branchA),
                    ParallelBranch(label: "Branch B", step: branchB)
                ]
            )
        }
    }
}

// MARK: - Step Editor Row

private struct StepEditorRow: View {
    let step: WorkflowStep

    var body: some View {
        HStack(spacing: 10) {
            StepTypeIcon(type: step.type)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(stepSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            // Drag-handle hint — always visible so users discover reorder.
            // Dragging only activates in Edit mode (see footer note).
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var stepSummary: String {
        switch step.type {
        case .begin:
            return "→ \(step.outputSlot)"
        case .retrieve:
            return "query: \(step.querySlot)  top \(step.topK)  → \(step.outputSlot)"
        case .rewrite:
            return "query: \(step.querySlot)  → \(step.outputSlot)"
        case .llm:
            let preview = step.promptTemplate.prefix(40).replacingOccurrences(of: "\n", with: " ")
            return preview.isEmpty ? "→ \(step.outputSlot)" : "\(preview)…"
        case .message:
            let preview = step.promptTemplate.prefix(40).replacingOccurrences(of: "\n", with: " ")
            return preview.isEmpty ? "→ \(step.outputSlot)" : "\(preview)…"
        case .webSearch:
            return "query: \(step.querySlot)  → \(step.outputSlot)"
        case .answer:
            return "reads \(step.outputSlot)"
        case .variableAssigner:
            let count = step.assignments?.count ?? 0
            return "\(count) assignment\(count == 1 ? "" : "s")"
        case .switchStep:
            let count = step.switchBranches?.count ?? 0
            return "\(count) branch\(count == 1 ? "" : "es")"
        case .categorize:
            let count = step.categories?.count ?? 0
            return "\(count) categor\(count == 1 ? "y" : "ies")  → \(step.outputSlot)"
        case .parallel:
            let count = step.parallelBranches?.count ?? 0
            return "\(count) branch\(count == 1 ? "" : "es") in parallel"
        }
    }
}

// MARK: - Step Type Picker

struct StepTypePicker: View {
    let onSelect: (StepType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(StepType.allCases, id: \.self) { type in
                    Button {
                        onSelect(type)
                    } label: {
                        HStack(spacing: 14) {
                            StepTypeIcon(type: type)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(type.stepDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Add Step")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DT.stamp)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Step Config Sheet

struct StepConfigSheet: View {
    @State private var step: WorkflowStep
    let allKBs: [KnowledgeBase]
    let allSteps: [WorkflowStep]
    let onSave: (WorkflowStep) -> Void

    @Environment(\.dismiss) private var dismiss

    init(step: WorkflowStep, allKBs: [KnowledgeBase], allSteps: [WorkflowStep], onSave: @escaping (WorkflowStep) -> Void) {
        _step = State(initialValue: step)
        self.allKBs = allKBs
        self.allSteps = allSteps.filter { $0.id != step.id }  // exclude self from routing targets
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // Label — shown for all step types
                Section("Label") {
                    TextField("Step name", text: $step.label)
                }

                // Type-specific configuration
                stepSpecificConfig

                // Output slot — hidden for parallel (each branch declares its own slot)
                if step.type != .parallel {
                    Section {
                        TextField(outputSlotPlaceholder, text: $step.outputSlot)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    } header: {
                        Text(outputSlotHeader)
                    } footer: {
                        Text(outputSlotFooter)
                    }
                }
            }
            .navigationTitle(step.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .tint(DT.stamp)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(step)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Per-Type Config

    @ViewBuilder
    private var stepSpecificConfig: some View {
        switch step.type {
        case .begin:
            EmptyView()

        case .retrieve:
            Section("Retrieval") {
                HStack {
                    Text("Query variable")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("input", text: $step.querySlot)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 140)
                }
                Stepper("Top \(step.topK) chunks", value: $step.topK, in: 1...20)
                if allKBs.count > 1 {
                    Picker("Knowledge Base", selection: Binding(
                        get: { step.kbIdOverride ?? "" },
                        set: { step.kbIdOverride = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Workflow default").tag("")
                        ForEach(allKBs) { kb in
                            Text(kb.name).tag(kb.id)
                        }
                    }
                }
            }

        case .rewrite:
            Section {
                HStack {
                    Text("Query variable")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("input", text: $step.querySlot)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 140)
                }
            } header: {
                Text("Input")
            }
            Section {
                TextEditor(text: $step.promptTemplate)
                    .frame(minHeight: 100)
                    .font(.body)
            } header: {
                Text("Rewrite Prompt (optional)")
            } footer: {
                Text("Leave blank to use the default rewrite prompt. Use {variable} to reference earlier step outputs.")
            }

        case .llm:
            Section {
                TextEditor(text: $step.promptTemplate)
                    .frame(minHeight: 120)
                    .font(.body)
            } header: {
                Text("Prompt Template")
            } footer: {
                Text("Use {input} for the user's query, {context} for retrieved passages, or any {variable} from earlier steps.")
            }

        case .message:
            Section {
                TextEditor(text: $step.promptTemplate)
                    .frame(minHeight: 100)
                    .font(.body)
            } header: {
                Text("Message Content")
            } footer: {
                Text("Static text written into the pipeline. Use {variable} to reference earlier step outputs.")
            }

        case .webSearch:
            Section {
                HStack {
                    Text("Query variable")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("input", text: $step.querySlot)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 140)
                }
                Picker("Search Engine", selection: Binding(
                    get: { step.webSearchToolId ?? "brave_search" },
                    set: { step.webSearchToolId = $0 }
                )) {
                    ForEach(SearchToolRegistry.shared.all, id: \.toolId) { tool in
                        Text(tool.displayName).tag(tool.toolId)
                    }
                }
            } header: {
                Text("Input")
            } footer: {
                Text("DuckDuckGo and Wikipedia are free — no API key needed. Brave Search requires an API key in Settings.")
            }

        case .answer:
            EmptyView()

        case .variableAssigner:
            Section {
                let assignments = Binding(
                    get: { step.assignments ?? [] },
                    set: { step.assignments = $0 }
                )
                ForEach(assignments) { $a in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("slot name", text: $a.targetSlot)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                            Picker("", selection: $a.operation) {
                                ForEach(AssignOperation.allCases, id: \.self) { op in
                                    Text(op.displayName).tag(op)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 100)
                        }
                        if a.operation.requiresValue {
                            TextField("value or {slot}", text: $a.value)
                                .font(.system(.body, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { step.assignments?.remove(atOffsets: $0) }
                Button {
                    step.assignments = (step.assignments ?? []) + [VariableAssignment()]
                } label: {
                    Label("Add Assignment", systemImage: "plus.circle")
                        .foregroundStyle(.tint)
                }
            } header: {
                Text("Assignments")
            } footer: {
                Text("Set overwrites the slot. Append adds with a newline. Clear empties it. Use {slot} in values to reference earlier outputs.")
            }

        case .switchStep:
            let branches = Binding(
                get: { step.switchBranches ?? [] },
                set: { step.switchBranches = $0 }
            )
            ForEach(branches) { $branch in
                Section {
                    TextField("Branch label", text: $branch.label)
                    ForEach($branch.conditions) { $cond in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("slot", text: $cond.slot)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: 90)
                                Picker("", selection: $cond.op) {
                                    ForEach(SwitchOperator.allCases, id: \.self) { op in
                                        Text(op.displayName).tag(op)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 120)
                            }
                            if cond.op.requiresValue {
                                TextField("value", text: $cond.value)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { branch.conditions.remove(atOffsets: $0) }
                    Button {
                        branch.conditions.append(SwitchCondition())
                    } label: {
                        Label("Add Condition", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                    if branch.conditions.count > 1 {
                        Picker("Logic", selection: $branch.logic) {
                            ForEach(ConditionLogic.allCases, id: \.self) { l in
                                Text(l.rawValue).tag(l)
                            }
                        }
                    }
                    stepTargetPicker(label: "Route to step", selection: $branch.nextStepId)
                } header: {
                    Text("Branch: \(branch.label.isEmpty ? "(unnamed)" : branch.label)")
                }
            }
            Section {
                Button {
                    step.switchBranches = (step.switchBranches ?? []) + [
                        SwitchBranch(label: "Branch \((step.switchBranches?.count ?? 0) + 1)", conditions: [SwitchCondition()])
                    ]
                } label: {
                    Label("Add Branch", systemImage: "plus.circle")
                        .foregroundStyle(.tint)
                }
                stepTargetPicker(
                    label: "Default (no match)",
                    selection: Binding(
                        get: { step.defaultNextStepId ?? "" },
                        set: { step.defaultNextStepId = $0.isEmpty ? nil : $0 }
                    )
                )
            } footer: {
                Text("Branches are evaluated top to bottom. The first matching branch wins. Default runs when no branch matches.")
            }

        case .categorize:
            Section {
                HStack {
                    Text("Input variable")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("input", text: $step.querySlot)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 140)
                }
            } header: {
                Text("Input")
            }
            let categories = Binding(
                get: { step.categories ?? [] },
                set: { step.categories = $0 }
            )
            Section {
                ForEach(categories) { $cat in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Category name", text: $cat.condition)
                            .autocorrectionDisabled()
                        stepTargetPicker(label: "Route to step", selection: $cat.nextStepId)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { step.categories?.remove(atOffsets: $0) }
                Button {
                    let n = (step.categories?.count ?? 0) + 1
                    step.categories = (step.categories ?? []) + [StepBranch(label: "Category \(n)", condition: "Category \(n)")]
                } label: {
                    Label("Add Category", systemImage: "plus.circle")
                        .foregroundStyle(.tint)
                }
                stepTargetPicker(
                    label: "Default (no match)",
                    selection: Binding(
                        get: { step.defaultNextStepId ?? "" },
                        set: { step.defaultNextStepId = $0.isEmpty ? nil : $0 }
                    )
                )
            } header: {
                Text("Categories")
            } footer: {
                Text("The AI will classify the input into one of these categories. Category names should be clear and distinct.")
            }
            Section {
                TextEditor(text: Binding(
                    get: { step.categoryPromptOverride ?? "" },
                    set: { step.categoryPromptOverride = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .font(.body)
            } header: {
                Text("Custom Prompt (optional)")
            } footer: {
                Text("Leave blank to use the default classification prompt. Use {input} for the text being classified.")
            }

        case .parallel:
            let branches = Binding(
                get: { step.parallelBranches ?? [] },
                set: { step.parallelBranches = $0 }
            )
            ForEach(branches) { $branch in
                Section {
                    TextField("Branch label", text: $branch.label)
                    Picker("Step Type", selection: $branch.step.type) {
                        ForEach([StepType.retrieve, .rewrite, .llm, .webSearch, .message], id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    HStack {
                        Text("Output slot")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("variable", text: $branch.step.outputSlot)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 140)
                    }
                    if branch.step.type == .retrieve {
                        Stepper("Top \(branch.step.topK) chunks", value: $branch.step.topK, in: 1...20)
                        if allKBs.count > 1 {
                            Picker("Knowledge Base", selection: Binding(
                                get: { branch.step.kbIdOverride ?? "" },
                                set: { branch.step.kbIdOverride = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("Workflow default").tag("")
                                ForEach(allKBs) { kb in Text(kb.name).tag(kb.id) }
                            }
                        }
                    }
                    if branch.step.type != .retrieve {
                        HStack {
                            Text("Query slot")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("input", text: $branch.step.querySlot)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: 140)
                        }
                        TextField("Prompt template (optional)", text: $branch.step.promptTemplate, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.body)
                    }
                } header: {
                    Text("Branch: \(branch.label.isEmpty ? "(unnamed)" : branch.label)")
                }
            }
            Section {
                Button {
                    let n = (step.parallelBranches?.count ?? 0) + 1
                    let newStep = WorkflowStep(type: .retrieve, label: "Branch \(n)", outputSlot: "context_\(n)")
                    step.parallelBranches = (step.parallelBranches ?? []) + [ParallelBranch(label: "Branch \(n)", step: newStep)]
                } label: {
                    Label("Add Branch", systemImage: "plus.circle")
                        .foregroundStyle(.tint)
                }
                if (step.parallelBranches?.count ?? 0) > 1 {
                    Button(role: .destructive) {
                        step.parallelBranches?.removeLast()
                    } label: {
                        Label("Remove Last Branch", systemImage: "minus.circle")
                    }
                }
            } footer: {
                Text("All branches run at the same time. Each writes its result to its output slot so later steps can reference them with {variable}.")
            }
        }
    }

    /// Picker that shows available steps by label; empty string = "None / fall through".
    @ViewBuilder
    private func stepTargetPicker(label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            Text("— none —").tag("")
            ForEach(allSteps) { s in
                HStack {
                    StepTypeIcon(type: s.type).frame(width: 20, height: 20)
                    Text(s.label)
                }
                .tag(s.id)
            }
        }
    }

    // MARK: Output Slot Labels

    private var outputSlotHeader: String {
        step.type == .answer ? "Read From Slot" : "Output Slot"
    }

    private var outputSlotPlaceholder: String {
        step.type == .answer ? "output" : "variable name"
    }

    private var outputSlotFooter: String {
        switch step.type {
        case .answer:
            return "The variable name to read the final answer from, e.g. \"output\"."
        default:
            return "Where this step writes its result, e.g. \"context\" or \"output\". Reference it in later steps with {variable}."
        }
    }
}

// MARK: - Workflow Help Sheet

struct WorkflowHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A workflow is a pipeline of steps that run in sequence. Each step reads from named **slots** (variables) and writes its result to an **output slot** for downstream steps to use.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    Text("How Workflows Work")
                }

                Section {
                    Text("Use **{variableName}** in any prompt template or message to substitute the value stored in that slot. For example, **{input}** is the user's original query, and **{context}** is text retrieved from your knowledge base.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    Text("Variable Substitution")
                }

                Section("Step Types") {
                    ForEach(StepType.allCases, id: \.self) { type in
                        HelpStepRow(type: type)
                    }
                }

                Section("Example Pipeline") {
                    VStack(alignment: .leading, spacing: 10) {
                        exampleStep(icon: "flag.fill", color: .green, title: "Begin", detail: "Captures user query → slot: input")
                        Image(systemName: "arrow.down").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center)
                        exampleStep(icon: "arrow.triangle.2.circlepath", color: .cyan, title: "Rewrite", detail: "Refines query for better search → slot: query")
                        Image(systemName: "arrow.down").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center)
                        exampleStep(icon: "magnifyingglass", color: .blue, title: "Retrieve", detail: "Searches KB with {query}, top 6 → slot: context")
                        Image(systemName: "arrow.down").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center)
                        exampleStep(icon: "brain", color: .purple, title: "LLM", detail: "Prompt: \"Answer {input} using {context}\" → slot: output")
                        Image(systemName: "arrow.down").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center)
                        exampleStep(icon: "checkmark.bubble.fill", color: .orange, title: "Answer", detail: "Reads slot: output — shows final result")
                    }
                    .padding(.vertical, 6)
                }

                Section("Tips") {
                    tipRow(icon: "arrow.up.arrow.down", text: "Tap **Edit** to reorder steps by dragging.")
                    tipRow(icon: "trash", text: "Swipe left on a step to delete it.")
                    tipRow(icon: "square.stack.3d.up", text: "A Retrieve step can target a different KB than the workflow default.")
                    tipRow(icon: "globe.americas.fill", text: "Web Search requires a Brave Search API key in Settings.")
                    tipRow(icon: "exclamationmark.triangle", text: "Every workflow needs exactly one **Begin** step and one **Answer** step.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Workflow Help")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DT.stamp)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func exampleStep(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .padding(6)
                .background(color.opacity(0.12), in: Circle())
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tipRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Help Step Row

private struct HelpStepRow: View {
    let type: StepType

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StepTypeIcon(type: type)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(type.displayName)
                    .font(.headline)
                Text(type.stepDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(helpDetail(for: type))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func helpDetail(for type: StepType) -> String {
        switch type {
        case .begin:
            return "Always the first step. Puts the user's question into the \"input\" slot so later steps can reference it as {input}."
        case .retrieve:
            return "Searches your knowledge base using a slot variable as the query. topK controls how many passages are returned. Results are written to the output slot (usually \"context\")."
        case .rewrite:
            return "Uses the LLM to rephrase a query for better search recall. Leave the prompt blank to use the default rewrite instruction, or write a custom one."
        case .llm:
            return "Calls the LLM with your prompt template. Use {input} for the original query, {context} for retrieved passages, or any {slot} from earlier steps. The response is written to the output slot."
        case .message:
            return "Injects a fixed block of text into the pipeline. Supports {slot} substitution. Useful for adding instructions or separators between steps."
        case .webSearch:
            return "Searches the web using Brave Search and stores the results in the output slot. Requires a Brave Search API key in Settings."
        case .answer:
            return "Always the last step. Reads from the specified slot and presents it as the final answer to the user. No output slot — it terminates the pipeline."
        case .variableAssigner:
            return "Sets, appends to, or clears named slots without calling the LLM. Useful for injecting fixed values, building up text across steps, or resetting a slot before a loop."
        case .switchStep:
            return "Evaluates conditions on slot values (equals, contains, is empty, etc.) and jumps to the first matching branch. Supports AND/OR logic per branch. Falls through to the default branch if nothing matches."
        case .categorize:
            return "Asks the LLM to classify the input into one of the categories you define, then routes to the matching step. Good for intent detection and routing different query types to specialised pipelines."
        case .parallel:
            return "Runs all branches simultaneously. Each branch executes its own step (retrieve, LLM, web search, etc.) and writes to a dedicated output slot. After all branches finish, the combined results are available to subsequent steps."
        }
    }
}

// MARK: - Step Type Icon (shared between editor and detail view)

struct StepTypeIcon: View {
    let type: StepType

    var body: some View {
        Image(systemName: iconName)
            .font(.caption)
            .foregroundStyle(iconColor)
            .padding(6)
            .background(iconColor.opacity(0.12), in: Circle())
    }

    var iconName: String {
        switch type {
        case .begin:            return "flag.fill"
        case .retrieve:         return "magnifyingglass"
        case .rewrite:          return "arrow.triangle.2.circlepath"
        case .llm:              return "brain"
        case .message:          return "text.bubble"
        case .webSearch:        return "globe.americas.fill"
        case .answer:           return "checkmark.bubble.fill"
        case .variableAssigner: return "arrow.left.arrow.right.square"
        case .switchStep:       return "arrow.triangle.branch"
        case .categorize:       return "tag.fill"
        case .parallel:         return "arrow.split.2"
        }
    }

    var iconColor: Color {
        switch type {
        case .begin:            return .green
        case .retrieve:         return .blue
        case .rewrite:          return .cyan
        case .llm:              return .purple
        case .message:          return .indigo
        case .webSearch:        return .teal
        case .answer:           return .orange
        case .variableAssigner: return .mint
        case .switchStep:       return .yellow
        case .categorize:       return .pink
        case .parallel:         return .red
        }
    }
}
