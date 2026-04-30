import SwiftUI
import UniformTypeIdentifiers

struct WorkflowListView: View {
    @StateObject private var vm = WorkflowListViewModel()
    @AppStorage("activeWorkflowId") private var activeWorkflowId: String = ""
    @State private var showWorkflowImporter = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var importedWorkflowName: String?
    @State private var showImportSuccess = false

    @State private var selectedWorkflow: Workflow?
    @State private var exportURL: URL?
    @State private var showExportSheet = false
    @State private var exportError: String?
    @State private var showExportError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.workflows.isEmpty {
                emptyState
            } else {
                workflowList
            }
        }
        .background(DT.manila)
        .navigationTitle("Workflows")
        .navigationBarTitleDisplayMode(.inline)
        .tint(DT.stamp)
        .navigationDestination(item: $selectedWorkflow) { workflow in
            WorkflowDetailView(workflow: workflow)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    Button { showWorkflowImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DT.inkSoft)
                    }
                    .accessibilityLabel("Import Workflow")
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
            }
        }
        .onAppear { vm.reload() }
        .sheet(isPresented: $vm.showNewWorkflow, onDismiss: { vm.reload() }) {
            NewWorkflowSheet(vm: vm)
                .onAppear { vm.prepareForNewWorkflow() }
        }
        .fileImporter(
            isPresented: $showWorkflowImporter,
            allowedContentTypes: [UTType("com.dhorn.ragflowmobile.ragflow-workflow") ?? UTType(filenameExtension: "ragflow-workflow") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            handleWorkflowImport(result: result)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert("Workflow Imported", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(importedWorkflowName ?? "Workflow")\" was imported successfully.")
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL { ShareSheet(url: url) }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    // MARK: - Workflow List

    private var workflowList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(vm.workflows.enumerated()), id: \.element.id) { i, workflow in
                    workflowRow(workflow, index: i)
                        .onTapGesture {
                            activeWorkflowId = workflow.id
                            selectedWorkflow = workflow
                        }
                        .contextMenu {
                            Button { exportWorkflow(workflow) } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                vm.delete(workflow)
                                vm.reload()
                            }
                        }
                }
            }
            .background(DT.card)
            .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 8)
    }

    private func workflowRow(_ workflow: Workflow, index: Int) -> some View {
        let template = WorkflowTemplates.template(id: workflow.templateId)
        let stepCount = workflow.steps.count
        return HStack(alignment: .top, spacing: 10) {
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
                HStack(spacing: 6) {
                    Text(template?.name ?? workflow.templateId)
                        .font(DT.mono(9))
                        .foregroundStyle(DT.inkFaint)
                    Text("·")
                        .foregroundStyle(DT.rule)
                    Text("\(stepCount) step\(stepCount == 1 ? "" : "s")")
                        .font(DT.mono(9))
                        .foregroundStyle(DT.inkFaint)
                }
            }

            Spacer()

            if workflow.id == activeWorkflowId {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DT.stamp)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DT.inkFaint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DT.cardPadding)
        .background(DT.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DT.rule.opacity(0.4)).frame(height: 0.5)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("NO WORKFLOWS")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Tap NEW to create a workflow.")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func exportWorkflow(_ workflow: Workflow) {
        do {
            exportURL = try ExportImportService.shared.workflowExportURL(for: workflow)
            showExportSheet = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func handleWorkflowImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("ragflow-workflow")
            guard (try? FileManager.default.copyItem(at: url, to: tmp)) != nil else {
                importError = "Could not read the file."
                showImportError = true
                return
            }
            do {
                let workflow = try ExportImportService.shared.importWorkflow(from: tmp)
                try DatabaseService.shared.saveWorkflow(workflow)
                vm.reload()
                importedWorkflowName = workflow.name
                showImportSuccess = true
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true
        }
    }
}

// MARK: - New Workflow Sheet

struct NewWorkflowSheet: View {
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
                    Section("Workflow Name") {
                        TextField("e.g. Christie Q&A", text: $vm.newWorkflowName)
                    }
                    .id("top")

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

                    Section("Template") {
                        ForEach(WorkflowTemplates.all) { template in
                            templateRow(template)
                                .accessibilityIdentifier("template-\(template.id)")
                        }
                    }

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
                .tint(DT.stamp)
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
                    .foregroundStyle(isSelected ? DT.stamp : DT.inkSoft)
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
                        .foregroundStyle(DT.stamp)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
