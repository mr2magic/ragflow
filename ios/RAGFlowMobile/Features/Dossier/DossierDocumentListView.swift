import SwiftUI

struct DossierDocumentListView: View {
    let kb: KnowledgeBase

    @StateObject private var vm: LibraryViewModel
    @State private var selectedBook: Book?

    init(kb: KnowledgeBase) {
        self.kb = kb
        _vm = StateObject(wrappedValue: LibraryViewModel(kb: kb))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if vm.filteredBooks.isEmpty {
                emptyState
            } else {
                bookList
            }
        }
        .background(DT.manila)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DOCUMENTS")
                    .font(DT.mono(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(DT.inkFaint)
                Spacer()
                Text("\(vm.filteredBooks.count) FILES")
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

    // MARK: - Book list

    private var bookList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(vm.filteredBooks.enumerated()), id: \.element.id) { i, book in
                    DossierDocumentRow(book: book, index: i, isSelected: selectedBook?.id == book.id)
                        .onTapGesture { selectedBook = book }
                }
            }
            .background(DT.card)
            .overlay(Rectangle().stroke(DT.rule, lineWidth: 0.5))
        }
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("NO DOCUMENTS")
                .font(DT.mono(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(DT.inkFaint)
            Text("Add documents via the Library tab.")
                .font(DT.serif(14))
                .foregroundStyle(DT.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
