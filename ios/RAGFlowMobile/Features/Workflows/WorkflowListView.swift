import SwiftUI

struct WorkflowListView: View {
    @StateObject private var vm = WorkflowListViewModel()

    var body: some View {
        Group {
            if vm.workflows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(vm.workflows) { workflow in
                        NavigationLink {
                            WorkflowDetailView(workflow: workflow)
                        } label: {
                            workflowRow(workflow)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { vm.delete(vm.workflows[i]) }
                    }
                }
            }
        }
        .navigationTitle("Workflows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.showNewWorkflow = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { vm.reload() }
        .sheet(isPresented: $vm.showNewWorkflow, onDismiss: { vm.reload() }) {
            NewWorkflowSheet(vm: vm)
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    private func workflowRow(_ workflow: Workflow) -> some View {
        let template = WorkflowTemplates.template(id: workflow.templateId)
        return HStack(spacing: 12) {
            Image(systemName: template?.icon ?? "gearshape.2")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.headline)
                Text(template?.name ?? workflow.templateId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Workflows",
            systemImage: "gearshape.2",
            description: Text("Tap + to create an agent workflow from a template.")
        )
    }
}

// MARK: - New Workflow Sheet

private struct NewWorkflowSheet: View {
    @ObservedObject var vm: WorkflowListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    ForEach(WorkflowTemplates.all) { template in
                        templateRow(template)
                    }
                }

                if vm.selectedTemplate != nil {
                    Section("Name") {
                        TextField("Workflow name", text: $vm.newWorkflowName)
                    }

                    Section("Knowledge Base") {
                        Picker("KB", selection: $vm.newWorkflowKBId) {
                            ForEach(vm.allKBs) { kb in
                                Text(kb.name).tag(kb.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle("New Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { vm.createWorkflow() }
                        .disabled(vm.selectedTemplate == nil || vm.newWorkflowName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func templateRow(_ template: WorkflowTemplate) -> some View {
        let isSelected = vm.selectedTemplate?.id == template.id
        return Button {
            vm.selectedTemplate = template
            if vm.newWorkflowName.isEmpty {
                vm.newWorkflowName = template.name
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
