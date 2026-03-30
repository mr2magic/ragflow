import SwiftUI

@MainActor
final class WorkflowListViewModel: ObservableObject {
    @Published var workflows: [Workflow] = []
    @Published var showNewWorkflow = false
    @Published var selectedTemplate: WorkflowTemplate?
    @Published var newWorkflowName = ""
    @Published var newWorkflowKBId = KnowledgeBase.defaultID
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var customPrompt = ""

    var allKBs: [KnowledgeBase] { (try? DatabaseService.shared.allKBs()) ?? [] }

    /// Call when the sheet opens to pre-select the first available KB.
    func prepareForNewWorkflow() {
        newWorkflowName = ""
        customPrompt = ""
        selectedTemplate = nil
        if let first = allKBs.first {
            newWorkflowKBId = first.id
        }
    }

    private let db = DatabaseService.shared

    func reload() {
        workflows = (try? db.allWorkflows()) ?? []
    }

    func createWorkflow() {
        guard let template = selectedTemplate else { return }
        let name = newWorkflowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let steps: [WorkflowStep]
        if template.id == "custom" {
            let prompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return }
            steps = [
                WorkflowStep(type: .begin,    label: "Input",      outputSlot: "input"),
                WorkflowStep(type: .retrieve, label: "Retrieve",   querySlot: "input", topK: 8, outputSlot: "context"),
                WorkflowStep(type: .llm,      label: "Custom LLM", promptTemplate: prompt, outputSlot: "output"),
                WorkflowStep(type: .answer,   label: "Result",     outputSlot: "output"),
            ]
        } else {
            steps = template.steps
        }

        let stepsJSON = (try? String(
            data: JSONEncoder().encode(steps), encoding: .utf8
        )) ?? "[]"

        let workflow = Workflow(
            id: UUID().uuidString,
            name: name,
            templateId: template.id,
            kbId: newWorkflowKBId,
            stepsJSON: stepsJSON,
            createdAt: Date()
        )
        do {
            try db.saveWorkflow(workflow)
            reload()
            showNewWorkflow = false
            newWorkflowName = ""
            customPrompt = ""
            selectedTemplate = nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func delete(_ workflow: Workflow) {
        try? db.deleteWorkflow(workflow.id)
        reload()
    }
}
