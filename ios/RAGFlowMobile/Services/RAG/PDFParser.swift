import Foundation
import PDFKit

struct PDFParser {
    struct PDFSection {
        let title: String
        let text: String
    }

    func parse(url: URL) -> [PDFSection] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var sections: [PDFSection] = []

        // Group every 5 pages into a section to keep chunks meaningful
        let groupSize = 5
        let pageCount = doc.pageCount

        var i = 0
        while i < pageCount {
            let end = min(i + groupSize, pageCount)
            var text = ""
            for p in i..<end {
                if let page = doc.page(at: p), let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            let cleaned = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleaned.isEmpty {
                sections.append(PDFSection(
                    title: "Pages \(i + 1)–\(end)",
                    text: cleaned
                ))
            }
            i = end
        }

        return sections
    }
}
