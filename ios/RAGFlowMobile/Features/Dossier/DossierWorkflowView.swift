import SwiftUI

struct DossierWorkflowView: View {
    let kb: KnowledgeBase

    @StateObject private var vm = WorkflowListViewModel()
    @State private var selectedWorkflow: Workflow?

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
                Text("\(kbWorkflows.count) ACTIVE")
                    .font(DT.mono(10))
                    .tracking(1)
                    .foregroundStyle(DT.inkFaint)
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
        VStack(spacing: 12) {
            Spacer()
            Text("NO WORKFLOWS")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Create workflows via the Workflows tab.")
                .font(DT.serif(14))
                .foregroundStyle(DT.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
