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
                .onAppear { vm.prepareForNewWorkflow() }
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    private func workflowRow(_ workflow: Workflow) -> some View {
        let template = WorkflowTemplates.template(id: workflow.templateId)
        let stepCount = workflow.steps.count
        return HStack(spacing: 12) {
            Image(systemName: template?.icon ?? "cpu")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(template?.name ?? workflow.templateId)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(stepCount) step\(stepCount == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "cpu")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            VStack(spacing: Spacing.sm) {
                Text("No Workflows")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Build an agent pipeline from a template or create a custom workflow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: { vm.showNewWorkflow = true }) {
                Label("New Workflow", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - New Workflow Sheet

private struct NewWorkflowSheet: View {
    @ObservedObject var vm: WorkflowListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showKBAlert = false

    private var noKBSelected: Bool {
        vm.newWorkflowKBId.trimmingCharacters(in: .whitespaces).isEmpty
            || !vm.allKBs.contains(where: { $0.id == vm.newWorkflowKBId })
    }

    private var createDisabled: Bool {
        guard let t = vm.selectedTemplate,
              !vm.newWorkflowName.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        if t.id == "custom" {
            return vm.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                // 1. NAME — top, always visible
                Section("Workflow Name") {
                    TextField("e.g. Christie Q&A", text: $vm.newWorkflowName)
                }
                .id("top")

                // 2. KNOWLEDGE BASE — always visible, required
                Section {
                    if vm.allKBs.isEmpty {
                        Label("No knowledge bases yet — create one first.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    } else {
                        Picker("Knowledge Base", selection: $vm.newWorkflowKBId) {
                            ForEach(vm.allKBs) { kb in
                                Text(kb.name).tag(kb.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } header: {
                    Text("Knowledge Base")
                } footer: {
                    Text("The workflow will retrieve passages only from the selected knowledge base.")
                        .font(.footnote)
                }

                // 3. TEMPLATE
                Section("Template") {
                    ForEach(WorkflowTemplates.all) { template in
                        templateRow(template)
                            .accessibilityIdentifier("template-\(template.id)")
                    }
                }

                // 4. CUSTOM PROMPT (only for custom template)
                if vm.selectedTemplate?.id == "custom" {
                    Section {
                        TextEditor(text: $vm.customPrompt)
                            .frame(minHeight: 160)
                            .font(.body)
                    } header: {
                        Text("System Prompt")
                    } footer: {
                        Text("Use {input} for the user's query and {context} for retrieved passages.")
                            .font(.footnote)
                    }
                }
            }
            .onChange(of: vm.selectedTemplate?.id) { _, _ in
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            }
            .navigationTitle("New Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if noKBSelected {
                            showKBAlert = true
                        } else {
                            vm.createWorkflow()
                        }
                    }
                    .disabled(createDisabled)
                }
            }
            .alert("Select a Knowledge Base", isPresented: $showKBAlert) {
                Button("OK") {}
            } message: {
                Text("You must choose a knowledge base before creating a workflow. The workflow retrieves passages from it to answer your queries.")
            }
            } // ScrollViewReader
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
