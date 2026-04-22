import SwiftUI
import UniformTypeIdentifiers

struct DossierWorkflowView: View {
    let kb: KnowledgeBase

    @StateObject private var vm = WorkflowListViewModel()
    @State private var selectedWorkflow: Workflow?
    @State private var showAllWorkflows = false          // D-WF4
    @State private var workflowToDelete: Workflow?       // D-WF3
    @State private var workflowToRename: Workflow?       // D-WF2
    @State private var renameText = ""                   // D-WF2

    var kbWorkflows: [Workflow] {
        vm.workflows.filter { $0.kbId == kb.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if kbWorkflows.isEmpty {
                emptyState
            } else {
                workflowList
            }
        }
        .background(DT.manila)
        .onAppear { vm.reload() }
        .navigationDestination(item: $selectedWorkflow) { workflow in
            WorkflowDetailView(workflow: workflow)
        }
        // D-WF1 — New workflow sheet
        .sheet(isPresented: $vm.showNewWorkflow, onDismiss: { vm.reload() }) {
            NewWorkflowSheet(vm: vm)
                .onAppear { vm.prepareForNewWorkflow() }
        }
        // D-WF2 — Rename alert
        .alert("Rename Workflow", isPresented: Binding(
            get: { workflowToRename != nil },
            set: { if !$0 { workflowToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { workflowToRename = nil }
        }
        // D-WF3 — Delete confirmation
        .confirmationDialog(
            "Delete \"\(workflowToDelete?.name ?? "this workflow")\"?",
            isPresented: Binding(
                get: { workflowToDelete != nil },
                set: { if !$0 { workflowToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let w = workflowToDelete { vm.delete(w) }
                workflowToDelete = nil
            }
            Button("Cancel", role: .cancel) { workflowToDelete = nil }
        } message: {
            Text("This workflow will be permanently deleted.")
        }
        // D-WF4 — All workflows sheet
        .sheet(isPresented: $showAllWorkflows) {
            NavigationStack {
                WorkflowListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showAllWorkflows = false }
                        }
                    }
            }
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("WORKFLOWS")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                // D-WF4 — All workflows
                Button { showAllWorkflows = true } label: {
                    Text("ALL")
                        .font(DT.mono(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DT.inkSoft)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                // D-WF1 — New workflow
                Button { vm.showNewWorkflow = true } label: {
                    Text("NEW")
                        .font(DT.mono(10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DT.stamp)
                        .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Workflow list

    private var workflowList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(kbWorkflows.enumerated()), id: \.element.id) { i, workflow in
                    workflowRow(workflow, index: i)
                        .onTapGesture { selectedWorkflow = workflow }
                        // D-WF2/3 — Context menu
                        .contextMenu {
                            Button("Rename") {
                                renameText = workflow.name
                                workflowToRename = workflow
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                workflowToDelete = workflow
                            }
                        }
                }
            }
            .background(DT.card)
            .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 4)
    }

    private func workflowRow(_ workflow: Workflow, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("WF\(String(format: "%02d", index + 1))")
                .font(DT.mono(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DT.ribbon)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(workflow.name)
                    .font(DT.serif(14))
                    .foregroundStyle(DT.ink)

                Text(workflow.templateId.uppercased())
                    .font(DT.mono(9))
                    .tracking(1)
                    .foregroundStyle(DT.inkFaint)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DT.inkFaint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DT.cardPadding)
        .background(selectedWorkflow?.id == workflow.id ? DT.manila.opacity(0.5) : DT.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DT.rule.opacity(0.4)).frame(height: 0.5)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("NO WORKFLOWS")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Tap NEW to create a workflow for this dossier.")
                .font(DT.serif(14))
                .italic()
                .foregroundStyle(DT.inkSoft)
            Button { vm.showNewWorkflow = true } label: {
                Text("NEW WORKFLOW")
                    .font(DT.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DT.stamp)
                    .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    // D-WF2 — Commit rename
    private func commitRename() {
        guard let workflow = workflowToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let updated = Workflow(
            id: workflow.id,
            name: name,
            templateId: workflow.templateId,
            kbId: workflow.kbId,
            stepsJSON: workflow.stepsJSON,
            createdAt: workflow.createdAt
        )
        try? DatabaseService.shared.saveWorkflow(updated)
        vm.reload()
        workflowToRename = nil
    }
}
