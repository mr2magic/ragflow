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
        let pageCount = min(doc.pageCount, 1_000)

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

    /// Returns true when PDFKit found no text layer (e.g. scanned/image-only PDF).
    /// Callers should fall back to VisionOCRParser in that case.
    func hasTextLayer(url: URL) -> Bool {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return false }
        // Sample the first 3 pages; if any yield text, the PDF has a text layer.
        for p in 0..<min(3, doc.pageCount) {
            if let text = doc.page(at: p)?.string,
               text.count > 20 { return true }
        }
        return false
    }
}
