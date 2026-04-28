import SwiftUI

// MARK: - Tab identifiers

enum DossierTab: Int, CaseIterable {
    case kb    = 0
    case docs  = 1
    case query = 2
    case flow  = 3
    case arch  = 4

    var label: String {
        switch self {
        case .kb:    "KB"
        case .docs:  "DOCS"
        case .query: "QUERY"
        case .flow:  "FLOW"
        case .arch:  "LOG"
        }
    }
}

// MARK: - Custom tab bar view

struct DossierTabBar: View {
    @Binding var selected: DossierTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DossierTab.allCases, id: \.self) { tab in
                tabItem(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DT.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(DT.manila)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DT.rule)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: DossierTab) -> some View {
        let isActive = tab == selected
        Button {
            selected = tab
        } label: {
            VStack(spacing: 4) {
                if isActive {
                    Circle()
                        .fill(DT.stamp)
                        .frame(width: 5, height: 5)
                } else {
                    Spacer().frame(height: 5)
                }
                Text(tab.label)
                    .font(DT.mono(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(isActive ? DT.stamp : DT.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
