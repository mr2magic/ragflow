import SwiftUI
import UIKit

// MARK: - Spacing Design Tokens

/// App-wide spacing scale. Use these instead of magic numbers so the layout
/// stays consistent as the app grows.
enum Spacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Rename Sheet

/// Small bottom sheet for renaming a KB, chat session, or document.
/// Pass the current name as `text` (pre-populated before presenting).
struct RenameSheet: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_theme") private var themeRaw: String = AppTheme.simple.rawValue

    private var isDossier: Bool { AppTheme(rawValue: themeRaw) == .dossier }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $text)
                    .submitLabel(.done)
                    .onSubmit { saveIfValid() }
            }
            .scrollContentBackground(.hidden)
            .background(isDossier ? DT.manila : Color(uiColor: .systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveIfValid() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(160)])
        .presentationDragIndicator(.visible)
    }

    private func saveIfValid() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave()
        dismiss()
    }
}

// MARK: - Create KB Sheet

/// Bottom sheet for creating a new Knowledge Base with a name field.
struct CreateKBSheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. My Research", text: $name)
                        .submitLabel(.done)
                        .onSubmit { createIfValid() }
                } footer: {
                    Text("Give your knowledge base a clear name so you can find it later.")
                        .font(.footnote)
                }
            }
            .navigationTitle("New Knowledge Base")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        name = ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createIfValid() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
    }

    private func createIfValid() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onCreate()
        dismiss()
    }
}

// MARK: - URL Import Sheet

/// Bottom sheet for importing a document by pasting a direct URL.
struct URLImportSheet: View {
    @Binding var urlInput: String
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/report.pdf", text: $urlInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .submitLabel(.done)
                } footer: {
                    Text("Paste a direct link to a PDF, ePub, Word doc, or other supported file.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        urlInput = ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importIfValid() }
                        .fontWeight(.semibold)
                        .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
    }

    private func importIfValid() {
        guard !urlInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onImport()
        dismiss()
    }
}

// MARK: - Share Sheet

/// Thin wrapper around UIActivityViewController for sharing a file URL.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Writing Tools Behavior

/// Applies `.writingToolsBehavior(.limited)` on iOS 18+ so Apple Intelligence
/// can rewrite/proofread but not summarize user-typed chat/query input.
struct WritingToolsLimitedModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.writingToolsBehavior(.limited)
        } else {
            content
        }
    }
}
