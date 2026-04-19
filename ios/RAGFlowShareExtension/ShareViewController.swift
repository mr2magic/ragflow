import SwiftUI
import UniformTypeIdentifiers
import Social

// MARK: - Extension entry point

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let hosting = UIHostingController(
            rootView: ShareView(extensionContext: extensionContext!)
        )
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.didMove(toParent: self)
    }
}

// MARK: - Lightweight group-defaults access (no GRDB dependency)

private enum GroupDefaults {
    static let suiteName = "group.com.dhorn.ragflowmobile"
    private static var suite: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    static var kbList: [[String: String]] {
        suite.array(forKey: "kbList") as? [[String: String]] ?? []
    }

    struct PendingImport: Codable {
        var id: String
        var kbId: String
        var kbName: String
        var type: ImportType
        var urlString: String
        var displayName: String
        var createdAt: Date
        enum ImportType: String, Codable { case file, url, text }
    }

    static func appendPendingImport(_ item: PendingImport) {
        var current: [PendingImport] = {
            guard let data = suite.data(forKey: "pendingImports"),
                  let items = try? JSONDecoder().decode([PendingImport].self, from: data)
            else { return [] }
            return items
        }()
        current.append(item)
        suite.set(try? JSONEncoder().encode(current), forKey: "pendingImports")
    }
}

// MARK: - UI

struct ShareView: View {
    let extensionContext: NSExtensionContext

    @State private var kbs: [[String: String]] = GroupDefaults.kbList
    @State private var selectedKBId: String?
    @State private var displayName = ""
    @State private var resolvedURL: URL?
    @State private var importType = GroupDefaults.PendingImport.ImportType.url
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if kbs.isEmpty {
                    ContentUnavailableView(
                        "No Knowledge Bases",
                        systemImage: "square.stack.3d.up",
                        description: Text("Open Ragion and create a knowledge base first.")
                    )
                } else {
                    form
                }
            }
            .navigationTitle("Add to Ragion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { extensionContext.cancelRequest(withError: CancelledError()) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { confirmImport() }
                        .disabled(selectedKBId == nil || resolvedURL == nil)
                }
            }
        }
        .task { await loadItem() }
    }

    private var form: some View {
        Form {
            Section("Import into") {
                ForEach(kbs, id: \.self) { kb in
                    let id = kb["id"] ?? ""
                    HStack {
                        Text(kb["name"] ?? "Unknown")
                        Spacer()
                        if selectedKBId == id {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedKBId = id }
                }
            }
            if !displayName.isEmpty {
                Section("Item") {
                    Label(
                        displayName,
                        systemImage: importType == .file ? "doc" : "link"
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Load shared item

    private func loadItem() async {
        defer { isLoading = false }
        guard let item = extensionContext.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { return }

        // File URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
            resolvedURL = url
            displayName = url.lastPathComponent
            importType = .file
            return
        }
        // Web URL
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            resolvedURL = url
            displayName = url.host() ?? url.absoluteString
            importType = .url
            return
        }
        // Plain text → write to shared container as .txt
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupDefaults.suiteName) {
            let dest = container.appendingPathComponent("share_\(UUID().uuidString).txt")
            if (try? text.write(to: dest, atomically: true, encoding: .utf8)) != nil {
                resolvedURL = dest
                displayName = String(text.prefix(80))
                importType = .file
            }
        }
    }

    // MARK: - Confirm

    private func confirmImport() {
        guard let kbId = selectedKBId,
              let kb = kbs.first(where: { $0["id"] == kbId }),
              let url = resolvedURL else {
            extensionContext.cancelRequest(withError: CancelledError())
            return
        }

        var finalURL = url
        // Copy file:// into shared container so main app can read it after extension dies
        if url.isFileURL,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupDefaults.suiteName) {
            let dest = container.appendingPathComponent("pending_\(UUID().uuidString)_\(url.lastPathComponent)")
            _ = url.startAccessingSecurityScopedResource()
            try? FileManager.default.copyItem(at: url, to: dest)
            url.stopAccessingSecurityScopedResource()
            finalURL = dest
        }

        GroupDefaults.appendPendingImport(.init(
            id: UUID().uuidString,
            kbId: kbId,
            kbName: kb["name"] ?? "",
            type: importType,
            urlString: finalURL.absoluteString,
            displayName: displayName,
            createdAt: Date()
        ))
        extensionContext.completeRequest(returningItems: nil)
    }
}

private struct CancelledError: Error {}
