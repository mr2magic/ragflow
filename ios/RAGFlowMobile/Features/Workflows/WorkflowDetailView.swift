import SwiftUI

struct WorkflowDetailView: View {
    @State private var workflow: Workflow
    @StateObject private var runner = WorkflowRunner()
    @State private var input = ""
    @State private var runs: [WorkflowRun] = []
    @State private var expandedRunId: String?
    @State private var copiedOutput = false
    @State private var showEditor = false
    @State private var exportURL: URL?
    @State private var showExportSheet = false
    @State private var exportError: String?
    @State private var showExportError = false

    private let db = DatabaseService.shared

    init(workflow: Workflow) {
        _workflow = State(initialValue: workflow)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                pipelineCard
                inputSection
                if runner.isRunning { runningCard }
                if !runs.isEmpty { historySection }
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.vertical, 12)
        }
        .background(DT.manila)
        .navigationTitle(workflow.name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(DT.stamp)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button { exportWorkflow() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DT.inkSoft)
                    }
                    .accessibilityLabel("Export workflow")
                    Button("Edit") { showEditor = true }
                        .font(DT.mono(11, weight: .bold))
                        .foregroundStyle(DT.stamp)
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL { ShareSheet(url: url) }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $showEditor) {
            WorkflowEditorView(workflow: workflow) { updated in
                try? db.saveWorkflow(updated)
                workflow = updated
            }
        }
        .onAppear { reloadRuns() }
    }

    // MARK: - Pipeline Card

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PIPELINE")
                .font(DT.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(DT.inkFaint)
                .padding(.horizontal, DT.cardPadding)
                .padding(.top, DT.cardPadding)
                .padding(.bottom, 8)

            Rectangle().fill(DT.rule).frame(height: 0.5).padding(.horizontal, DT.cardPadding)

            ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 10) {
                    StepTypeIcon(type: step.type)
                        .frame(width: 28, height: 28)
                    Text(step.label)
                        .font(DT.serif(14))
                        .foregroundStyle(DT.ink)
                    Spacer()
                    Text(step.type.displayName.uppercased())
                        .font(DT.mono(8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(runner.currentStep == step.label ? .white : DT.inkFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(runner.currentStep == step.label ? DT.stamp : DT.rule.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, DT.cardPadding)
                .background(runner.currentStep == step.label ? DT.stamp.opacity(0.07) : Color.clear)

                if idx < workflow.steps.count - 1 {
                    let isBranching = step.type == .switchStep || step.type == .categorize
                    Image(systemName: isBranching ? "arrow.triangle.branch" : "arrow.down")
                        .font(.caption)
                        .foregroundStyle(isBranching ? DT.amber : DT.rule)
                        .padding(.leading, DT.cardPadding + 22)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("QUERY")
                .font(DT.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(DT.inkFaint)
                .padding(.horizontal, DT.cardPadding)
                .padding(.top, DT.cardPadding)
                .padding(.bottom, 8)

            Rectangle().fill(DT.rule).frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 8) {
                Text("INPUT →")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(DT.stamp)

                TextField("Enter your question…", text: $input, axis: .vertical)
                    .font(DT.serif(14))
                    .italic()
                    .foregroundStyle(DT.ink)
                    .lineLimit(3...6)
                    .disabled(runner.isRunning)
                    .modifier(WritingToolsLimitedModifier())

                Button {
                    Task { await runWorkflow() }
                } label: {
                    if runner.isRunning {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? DT.inkFaint : DT.stamp)
                            .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                    }
                }
                .accessibilityLabel(runner.isRunning ? "Stop workflow" : "Run workflow")
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !runner.isRunning)
            }
            .padding(.horizontal, DT.cardPadding)
            .padding(.vertical, 10)
        }
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    // MARK: - Running Card

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("PROCESSING")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(DT.inkFaint)
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(DT.inkFaint)
                if !runner.currentStep.isEmpty {
                    Text("— \(runner.currentStep)")
                        .font(DT.mono(9))
                        .foregroundStyle(DT.inkFaint)
                }
            }
            .padding(.horizontal, DT.cardPadding)
            .padding(.top, DT.cardPadding)
            .padding(.bottom, 8)

            if !runner.streamingOutput.isEmpty {
                Rectangle().fill(DT.rule).frame(height: 0.5)
                Text(runner.streamingOutput)
                    .font(DT.serif(14))
                    .foregroundStyle(DT.ink)
                    .textSelection(.enabled)
                    .padding(DT.cardPadding)
            }

            if !runner.stepLog.isEmpty {
                Rectangle().fill(DT.rule).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(runner.stepLog, id: \.self) { entry in
                        Text(entry)
                            .font(DT.mono(9))
                            .foregroundStyle(DT.inkFaint)
                    }
                }
                .padding(DT.cardPadding)
            }
        }
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RUN HISTORY")
                .font(DT.mono(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(DT.inkFaint)
                .padding(.horizontal, DT.cardPadding)
                .padding(.top, DT.cardPadding)
                .padding(.bottom, 8)

            Rectangle().fill(DT.rule).frame(height: 0.5)

            ForEach(Array(runs.enumerated()), id: \.element.id) { idx, run in
                runRow(run, index: idx)
            }
        }
        .background(DT.card)
        .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
    }

    private func runRow(_ run: WorkflowRun, index: Int) -> some View {
        let isExpanded = expandedRunId == run.id
        return VStack(alignment: .leading, spacing: 0) {
            if index > 0 {
                Rectangle().fill(DT.rule.opacity(0.4)).frame(height: 0.5)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedRunId = isExpanded ? nil : run.id
                }
            } label: {
                HStack(spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(DT.mono(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DT.ribbon)
                        .clipShape(RoundedRectangle(cornerRadius: 2))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.input)
                            .font(DT.serif(13))
                            .foregroundStyle(DT.ink)
                            .lineLimit(1)
                        Text(run.createdAt.formatted(.relative(presentation: .named)))
                            .font(DT.mono(9))
                            .foregroundStyle(DT.inkFaint)
                    }
                    Spacer()
                    statusBadge(run.status)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DT.inkFaint)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
                .padding(.horizontal, DT.cardPadding)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(DT.rule.opacity(0.4)).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 8) {
                    Text(run.output)
                        .font(DT.serif(14))
                        .foregroundStyle(DT.ink)
                        .textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button {
                            UIPasteboard.general.string = run.output
                            copiedOutput = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedOutput = false }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedOutput ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                Text(copiedOutput ? "COPIED" : "COPY")
                                    .font(DT.mono(9, weight: .bold))
                                    .tracking(1)
                            }
                            .foregroundStyle(copiedOutput ? DT.green : DT.stamp)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background((copiedOutput ? DT.green : DT.stamp).opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: DT.stampCorner)
                                .stroke((copiedOutput ? DT.green : DT.stamp).opacity(0.3), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DT.cardPadding)
            }
        }
    }

    // MARK: - Helpers

    private func statusBadge(_ status: String) -> some View {
        let isDone = status == "completed"
        let label = isDone ? "DONE" : "FAIL"
        let color = isDone ? DT.green : DT.stamp
        return Text(label)
            .font(DT.mono(8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.3), lineWidth: 0.5))
            .accessibilityLabel("Status: \(label)")
    }

    private func exportWorkflow() {
        do {
            exportURL = try ExportImportService.shared.workflowExportURL(for: workflow)
            showExportSheet = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func runWorkflow() async {
        guard !runner.isRunning else { runner.cancel(); return }
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let run = await runner.run(workflow: workflow, input: query)
        try? db.saveWorkflowRun(run)
        reloadRuns()
    }

    private func reloadRuns() {
        runs = (try? db.runsForWorkflow(workflow.id)) ?? []
    }
}
