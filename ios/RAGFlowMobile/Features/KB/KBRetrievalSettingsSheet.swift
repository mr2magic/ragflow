import SwiftUI

/// Sheet for configuring per-KB retrieval parameters.
struct KBRetrievalSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let kb: KnowledgeBase
    @State private var topK: Int
    private let onSave: (KnowledgeBase) -> Void

    init(kb: KnowledgeBase, onSave: @escaping (KnowledgeBase) -> Void) {
        self.kb = kb
        _topK = State(initialValue: kb.topK)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $topK, in: 1...50) {
                        HStack {
                            Text("Retrieved Chunks (k)")
                            Spacer()
                            Text("\(topK)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Retrieval")
                } footer: {
                    Text("How many text chunks are pulled from this knowledge base per chat message. Higher values give the model more context but increase token usage. Recommended: 10–20 for multi-document KBs, 5–10 for single documents.")
                        .font(.footnote)
                }
            }
            .navigationTitle(kb.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = kb
                        updated.topK = topK
                        onSave(updated)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
