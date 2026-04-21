import SwiftUI

// MARK: - Theme enum

enum AppTheme: String, CaseIterable, Identifiable {
    case simple  = "simple"
    case dossier = "dossier"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simple:  "Simple"
        case .dossier: "Dossier"
        }
    }
}

// MARK: - Environment key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .simple
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
