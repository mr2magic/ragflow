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
                    Text("Tap a step to configure it. Use Edit to reorder or delete.")
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        EditButton()
                        Button("Save") { commitSave() }
                            .fontWeight(.semibold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || steps.isEmpty)
                    }
                }
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
                StepConfigSheet(step: step, allKBs: allKBs) { updated in
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
            Image(systemName: "chevron.right")
                .font(.caption2)
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
    let onSave: (WorkflowStep) -> Void

    @Environment(\.dismiss) private var dismiss

    init(step: WorkflowStep, allKBs: [KnowledgeBase], onSave: @escaping (WorkflowStep) -> Void) {
        _step = State(initialValue: step)
        self.allKBs = allKBs
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

                // Output slot — shown for all step types with appropriate label
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
            .navigationTitle(step.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
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
            } header: {
                Text("Input")
            } footer: {
                Text("Searches the web using the value stored in this variable. Requires a Brave Search API key in Settings.")
            }

        case .answer:
            EmptyView()
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
        case .begin:     return "flag.fill"
        case .retrieve:  return "magnifyingglass"
        case .rewrite:   return "arrow.triangle.2.circlepath"
        case .llm:       return "brain"
        case .message:   return "text.bubble"
        case .webSearch: return "globe.americas.fill"
        case .answer:    return "checkmark.bubble.fill"
        }
    }

    var iconColor: Color {
        switch type {
        case .begin:     return .green
        case .retrieve:  return .blue
        case .rewrite:   return .cyan
        case .llm:       return .purple
        case .message:   return .indigo
        case .webSearch: return .teal
        case .answer:    return .orange
        }
    }
}
