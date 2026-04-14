import Foundation
import Zip

/// Extracts plain text from DOCX, XLSX, and PPTX files.
/// All Office Open XML formats (.docx/.xlsx/.pptx) are ZIP archives containing XML parts.
struct OfficeParser {

    struct Section {
        let title: String
        let text: String
    }

    // MARK: - DOCX

    func parseDOCX(url: URL) throws -> [Section] {
        let dest = try unzip(url)
        defer { try? FileManager.default.removeItem(at: dest) }
        return try parseDOCXContent(dir: dest, fileName: url.deletingPathExtension().lastPathComponent)
    }

    /// Visible for testing — parse an already-unzipped DOCX directory.
    func parseDOCXContent(dir: URL, fileName: String) throws -> [Section] {
        let xmlURL = dir.appendingPathComponent("word/document.xml")
        guard let data = try? Data(contentsOf: xmlURL),
              let xml = String(data: data, encoding: .utf8) else {
            throw OfficeError.missingPart("word/document.xml")
        }

        // Extract text runs — <w:t> elements hold actual text content
        let text = extractWText(xml)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfficeError.emptyContent
        }
        return [Section(title: fileName, text: text)]
    }

    // MARK: - XLSX

    func parseXLSX(url: URL) throws -> [Section] {
        let dest = try unzip(url)
        defer { try? FileManager.default.removeItem(at: dest) }
        return try parseXLSXContent(dir: dest, fileName: url.deletingPathExtension().lastPathComponent)
    }

    /// Visible for testing — parse an already-unzipped XLSX directory.
    func parseXLSXContent(dir: URL, fileName: String) throws -> [Section] {
        // Build shared strings table
        var sharedStrings: [String] = []
        let ssURL = dir.appendingPathComponent("xl/sharedStrings.xml")
        if let data = try? Data(contentsOf: ssURL),
           let xml = String(data: data, encoding: .utf8) {
            sharedStrings = extractAll(pattern: "<si>.*?</si>", from: xml)
                .map { stripXML($0) }
        }

        // Parse sheet1 into TSV rows
        let sheetURL = dir.appendingPathComponent("xl/worksheets/sheet1.xml")
        guard let data = try? Data(contentsOf: sheetURL),
              let xml = String(data: data, encoding: .utf8) else {
            throw OfficeError.missingPart("xl/worksheets/sheet1.xml")
        }

        var rows: [String] = []
        let rowMatches = extractAll(pattern: "<row[^>]*>.*?</row>", from: xml)
        for rowXML in rowMatches {
            let cells = extractAll(pattern: "<c[^>]*>.*?</c>", from: rowXML)
            let values: [String] = cells.map { cellXML -> String in
                // Determine if this is a shared-string reference (t="s") or inline value
                let isShared = cellXML.contains("t=\"s\"")
                guard let vMatch = extractFirst(pattern: "<v>([^<]*)</v>", in: cellXML) else { return "" }
                if isShared, let idx = Int(vMatch), idx < sharedStrings.count {
                    return sharedStrings[idx]
                }
                return vMatch
            }
            let line = values.joined(separator: "\t")
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append(line)
            }
        }

        guard !rows.isEmpty else { throw OfficeError.emptyContent }
        return [Section(title: fileName, text: rows.joined(separator: "\n"))]
    }

    // MARK: - PPTX

    func parsePPTX(url: URL) throws -> [Section] {
        let dest = try unzip(url)
        defer { try? FileManager.default.removeItem(at: dest) }
        return try parsePPTXContent(dir: dest)
    }

    /// Visible for testing — parse an already-unzipped PPTX directory.
    func parsePPTXContent(dir: URL) throws -> [Section] {
        let slidesDir = dir.appendingPathComponent("ppt/slides")
        guard let slideFiles = try? FileManager.default.contentsOfDirectory(
            at: slidesDir, includingPropertiesForKeys: nil
        ) else {
            throw OfficeError.missingPart("ppt/slides/")
        }

        // Sort slide1.xml, slide2.xml … numerically
        let slides = slideFiles
            .filter { $0.lastPathComponent.hasPrefix("slide") && $0.pathExtension == "xml" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var sections: [Section] = []
        for (i, slideURL) in slides.enumerated() {
            guard let data = try? Data(contentsOf: slideURL),
                  let xml = String(data: data, encoding: .utf8) else { continue }
            let text = stripXML(xml)
            guard text.count > 20 else { continue }
            sections.append(Section(title: "Slide \(i + 1)", text: text))
        }

        guard !sections.isEmpty else { throw OfficeError.emptyContent }
        return sections
    }

    // MARK: - Helpers

    private func unzip(_ url: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Zip.unzipFile(url, destination: dest, overwrite: true, password: nil)
        return dest
    }

    /// Extract <w:t> text runs from a Word document XML, preserving paragraph breaks.
    private func extractWText(_ xml: String) -> String {
        // <w:p> = paragraph, <w:t> = text run
        var result = ""
        var remaining = xml[xml.startIndex...]
        while let pStart = remaining.range(of: "<w:p[ >]", options: .regularExpression) {
            remaining = remaining[pStart.lowerBound...]
            guard let pEnd = remaining.range(of: "</w:p>") else { break }
            let para = String(remaining[remaining.startIndex..<pEnd.upperBound])
            remaining = remaining[pEnd.upperBound...]

            // Collect all <w:t> runs within this paragraph
            var paraText = ""
            var inner = para[para.startIndex...]
            while let tStart = inner.range(of: "<w:t") {
                guard let gt = inner[tStart.upperBound...].range(of: ">") else { break }
                let contentStart = gt.upperBound
                guard let tEnd = inner[contentStart...].range(of: "</w:t>") else { break }
                paraText += String(inner[contentStart..<tEnd.lowerBound])
                inner = inner[tEnd.upperBound...]
            }
            if !paraText.isEmpty { result += paraText + "\n" }
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stripXML(_ xml: String) -> String {
        xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns all non-overlapping matches of a regex pattern (must not use look-around).
    private func extractAll(pattern: String, from string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = string as NSString
        return regex.matches(in: string, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// Returns the first capture group of a regex match.
    private func extractFirst(pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[range])
    }

    // MARK: - ODT

    /// OpenDocument Text (.odt) — ZIP archive, text lives in content.xml under XML tags.
    func parseODT(url: URL) throws -> [Section] {
        let dest = try unzip(url)
        defer { try? FileManager.default.removeItem(at: dest) }
        return try parseODTContent(dir: dest, fileName: url.deletingPathExtension().lastPathComponent)
    }

    /// Visible for testing — parse an already-unzipped ODT directory.
    func parseODTContent(dir: URL, fileName: String) throws -> [Section] {
        let xmlURL = dir.appendingPathComponent("content.xml")
        guard let data = try? Data(contentsOf: xmlURL),
              let xml = String(data: data, encoding: .utf8) else {
            throw OfficeError.missingPart("content.xml")
        }
        let text = stripXML(xml)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfficeError.emptyContent
        }
        return [Section(title: fileName, text: text)]
    }

    enum OfficeError: LocalizedError {
        case missingPart(String), emptyContent

        var errorDescription: String? {
            switch self {
            case .missingPart(let p): return "Missing Office XML part: \(p)"
            case .emptyContent: return "Document contained no extractable text."
            }
        }
    }
}
