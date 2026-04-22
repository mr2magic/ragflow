import SwiftUI
import UniformTypeIdentifiers

struct WorkflowListView: View {
    @StateObject private var vm = WorkflowListViewModel()
    @State private var showWorkflowImporter = false
    @State private var importError: String?
    @State private var showImportError = false

    @State private var selectedWorkflow: Workflow?
    @State private var exportURL: URL?
    @State private var showExportSheet = false
    @State private var exportError: String?
    @State private var showExportError = false

    var body: some View {
        Group {
            if vm.workflows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(vm.workflows) { workflow in
                        Button {
                            selectedWorkflow = workflow
                        } label: {
                            workflowRow(workflow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                exportWorkflow(workflow)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                vm.delete(workflow)
                                vm.reload()
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                exportWorkflow(workflow)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { vm.delete(vm.workflows[i]) }
                    }
                }
            }
        }
        .navigationTitle("Workflows")
        .navigationDestination(item: $selectedWorkflow) { workflow in
            WorkflowDetailView(workflow: workflow)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.showNewWorkflow = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showWorkflowImporter = true
                } label: {
                    Label("Import Workflow", systemImage: "square.and.arrow.down")
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
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true
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
