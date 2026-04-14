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
            VStack(alignment: .leading, spacing: 20) {
                pipelineCard
                inputSection
                if runner.isRunning { runningCard }
                if !runs.isEmpty { historySection }
            }
            .padding()
        }
        .navigationTitle(workflow.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button {
                        exportWorkflow()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export workflow")
                    Button("Edit") { showEditor = true }
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
            ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 10) {
                    StepTypeIcon(type: step.type)
                        .frame(width: 28, height: 28)
                    Text(step.label)
                        .font(.subheadline)
                    Spacer()
                    Text(step.type.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(runner.currentStep == step.label ? Color.accentColor.opacity(0.12) : Color.clear)

                if idx < workflow.steps.count - 1 {
                    let isBranching = step.type == .switchStep || step.type == .categorize
                    Image(systemName: isBranching ? "arrow.triangle.branch" : "arrow.down")
                        .font(.caption)
                        .foregroundStyle(isBranching ? Color.yellow : Color.secondary.opacity(0.5))
                        .padding(.leading, 22)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query").font(.headline)
            HStack {
                TextField("Enter your question…", text: $input, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .disabled(runner.isRunning)
                    .modifier(WritingToolsLimitedModifier())

                Button {
                    Task { await runWorkflow() }
                } label: {
                    if runner.isRunning {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }
                }
                .accessibilityLabel(runner.isRunning ? "Stop workflow" : "Run workflow")
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !runner.isRunning)
            }
        }
    }

    // MARK: - Running Card

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(runner.currentStep.isEmpty ? "Running…" : runner.currentStep)
                    .font(.subheadline.weight(.medium))
            }

            if !runner.streamingOutput.isEmpty {
                Divider()
                Text(runner.streamingOutput)
                    .font(.body)
                    .textSelection(.enabled)
            }

            Divider()
            ForEach(runner.stepLog, id: \.self) { entry in
                Text(entry)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline)
            ForEach(runs) { run in
                runRow(run)
            }
        }
    }

    private func runRow(_ run: WorkflowRun) -> some View {
        let isExpanded = expandedRunId == run.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedRunId = isExpanded ? nil : run.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.input)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(run.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge(run.status)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)

            if isExpanded {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 8) {
                    Text(run.output)
                        .font(.body)
                        .textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button {
                            UIPasteboard.general.string = run.output
                            copiedOutput = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedOutput = false }
                        } label: {
                            Label(copiedOutput ? "Copied" : "Copy", systemImage: copiedOutput ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
    }

    // MARK: - Helpers

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

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = status == "completed"
            ? ("Done", .green)
            : ("Failed", .red)
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(label)")
    }
}
