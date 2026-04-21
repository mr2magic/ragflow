import SwiftUI

struct DossierKBListView: View {
    @StateObject private var vm = KBListViewModel()
    @State private var selectedKB: KnowledgeBase?
    @State private var docCounts: [String: Int] = [:]
    @State private var chunkCounts: [String: Int] = [:]
    @State private var showCreateAlert = false
    @State private var newKBName = ""

    private let db = DatabaseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            if vm.kbs.isEmpty {
                emptyState
            } else {
                kbList
            }
        }
        .background(DT.manila)
        .navigationDestination(item: $selectedKB) { kb in
            DossierKBDetailView(kb: kb)
        }
        .alert("New Dossier", isPresented: $showCreateAlert) {
            TextField("Name", text: $newKBName)
            Button("Create") { createKB() }
            Button("Cancel", role: .cancel) { newKBName = "" }
        }
        .onAppear { loadCounts() }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAGION")
                        .font(DT.mono(10, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(DT.stamp)
                    Text("Dossier Cabinet")
                        .font(DT.serif(26, weight: .semibold))
                        .foregroundStyle(DT.ink)
                }
                Spacer()
                Button {
                    showCreateAlert = true
                } label: {
                    Text("NEW")
                        .font(DT.mono(10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DT.stamp)
                        .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(DT.rule).frame(height: 0.5)
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - KB list

    private var kbList: some View {
        ScrollView {
            LazyVStack(spacing: DT.rowSpacing) {
                ForEach(Array(vm.kbs.enumerated()), id: \.element.id) { i, kb in
                    DossierKBCard(
                        kb: kb,
                        index: i,
                        docCount: docCounts[kb.id] ?? 0,
                        chunkCount: chunkCounts[kb.id] ?? 0
                    )
                    .onTapGesture { selectedKB = kb }
                }
            }
            .padding(.horizontal, DT.pagePadding)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("CABINET EMPTY")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Tap NEW to create your first dossier.")
                .font(DT.serif(15))
                .italic()
                .foregroundStyle(DT.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func createKB() {
        let name = newKBName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        vm.newKBName = name
        vm.createKB()
        newKBName = ""
        loadCounts()
    }

    private func loadCounts() {
        vm.reload()
        for kb in vm.kbs {
            let books = (try? db.allBooks(kbId: kb.id)) ?? []
            docCounts[kb.id] = books.count
            chunkCounts[kb.id] = books.reduce(0) { $0 + $1.chunkCount }
        }
    }
}
