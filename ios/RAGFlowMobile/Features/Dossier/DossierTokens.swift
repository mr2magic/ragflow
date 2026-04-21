import SwiftUI

// MARK: - Dossier design tokens
// Derived from the Ragion — Dossier.html prototype (Claude Design).

enum DT {
    // MARK: Colors
    static let manila      = Color(hex: "#E8DCC0")
    static let manilaDeep  = Color(hex: "#D4C39B")
    static let cream       = Color(hex: "#F6F1E4")
    static let card        = Color(hex: "#FAF7EE")
    static let ink         = Color(hex: "#15130E")
    static let inkSoft     = Color(hex: "#4B4538")
    static let inkFaint    = Color(hex: "#8B8473")
    static let rule        = Color(hex: "#B6A988")
    static let ruleDark    = Color(hex: "#8B8473")
    static let stamp       = Color(hex: "#B82E2E")
    static let ribbon      = Color(hex: "#2E4F7A")
    static let green       = Color(hex: "#5A7341")
    static let amber       = Color(hex: "#8B6F35")

    // MARK: Typography
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Iowan Old Style", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("SF Mono", size: size).weight(weight)
    }

    // MARK: Spacing
    static let pagePadding: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let rowSpacing: CGFloat  = 6

    // MARK: Shape
    static let cardCorner: CGFloat  = 2
    static let stampCorner: CGFloat = 3
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >>  8) & 0xFF) / 255
        let b = Double( rgb        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
