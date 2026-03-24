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

    var allKBs: [KnowledgeBase] { (try? DatabaseService.shared.allKBs()) ?? [] }

    private let db = DatabaseService.shared

    func reload() {
        workflows = (try? db.allWorkflows()) ?? []
    }

    func createWorkflow() {
        guard let template = selectedTemplate else { return }
        let name = newWorkflowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let stepsJSON = (try? String(
            data: JSONEncoder().encode(template.steps), encoding: .utf8
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
