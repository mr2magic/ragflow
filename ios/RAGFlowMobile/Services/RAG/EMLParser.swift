import Foundation

/// Extracts plain-text body content from .eml (RFC 2822) email files.
/// Handles multipart/alternative and multipart/mixed, quoted-printable and base64 encodings.
struct EMLParser {

    struct EMLContent {
        let subject: String
        let body: String
    }

    func parse(url: URL) throws -> EMLContent {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return parseRaw(raw)
    }

    func parseRaw(_ raw: String) -> EMLContent {
        let lines = raw.components(separatedBy: "\n")
        var headers: [String: String] = [:]
        var bodyLines: [String] = []
        var inBody = false

        // Split headers from body at first blank line
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if !inBody && line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inBody = true
                i += 1
                continue
            }
            if inBody {
                bodyLines.append(line)
            } else {
                // Handle folded headers (continuation lines start with whitespace)
                if (line.first == " " || line.first == "\t"), let lastKey = headers.keys.sorted().last {
                    headers[lastKey, default: ""] += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let colon = line.firstIndex(of: ":") {
                    let key = String(line[line.startIndex..<colon]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    headers[key] = value
                }
            }
            i += 1
        }

        let subject = headers["subject"] ?? ""
        let contentType = headers["content-type"] ?? "text/plain"
        let encoding = headers["content-transfer-encoding"]?.lowercased() ?? "7bit"
        let bodyText = bodyLines.joined(separator: "\n")

        // Multipart: extract text/plain parts
        if contentType.lowercased().contains("multipart") {
            if let boundary = extractBoundary(from: contentType) {
                let text = extractMultipartText(body: bodyText, boundary: boundary)
                return EMLContent(subject: subject, body: text)
            }
        }

        // Single part
        let decoded = decode(body: bodyText, encoding: encoding)
        return EMLContent(subject: subject, body: decoded)
    }

    // MARK: - Multipart

    private func extractMultipartText(body: String, boundary: String) -> String {
        let delimiter = "--" + boundary
        let parts = body.components(separatedBy: delimiter)

        var bestText = ""
        for part in parts {
            guard !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !part.hasPrefix("--") else { continue }

            let (partHeaders, partBody) = splitHeadersBody(part)
            let ct = partHeaders["content-type"] ?? "text/plain"
            let enc = partHeaders["content-transfer-encoding"]?.lowercased() ?? "7bit"

            if ct.lowercased().contains("text/plain") {
                let decoded = decode(body: partBody, encoding: enc)
                if decoded.count > bestText.count { bestText = decoded }
            } else if ct.lowercased().contains("text/html") && bestText.isEmpty {
                let decoded = decode(body: partBody, encoding: enc)
                bestText = stripHTML(decoded)
            } else if ct.lowercased().contains("multipart") {
                if let nested = extractBoundary(from: ct) {
                    let text = extractMultipartText(body: partBody, boundary: nested)
                    if text.count > bestText.count { bestText = text }
                }
            }
        }
        return bestText
    }

    private func splitHeadersBody(_ text: String) -> ([String: String], String) {
        let lines = text.components(separatedBy: "\n")
        var headers: [String: String] = [:]
        var bodyStart = lines.count
        for (idx, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bodyStart = idx + 1
                break
            }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colon]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                headers[key] = value
            }
        }
        let body = lines[min(bodyStart, lines.count)...].joined(separator: "\n")
        return (headers, body)
    }

    // MARK: - Decoding

    private func decode(body: String, encoding: String) -> String {
        switch encoding {
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        case "base64":
            let stripped = body.components(separatedBy: .whitespacesAndNewlines).joined()
            if let data = Data(base64Encoded: stripped),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return body
        default:
            return body
        }
    }

    private func decodeQuotedPrintable(_ input: String) -> String {
        // Join soft line breaks (=\r\n or =\n)
        let result = input
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")

        // Decode =XX hex sequences
        var output = ""
        var idx = result.startIndex
        while idx < result.endIndex {
            if result[idx] == "=" {
                let next = result.index(after: idx)
                if next < result.endIndex {
                    let nn = result.index(after: next)
                    if nn < result.endIndex {
                        let hex = String(result[next...nn])
                        if let code = UInt8(hex, radix: 16) {
                            output.append(Character(UnicodeScalar(code)))
                            idx = result.index(after: nn)
                            continue
                        }
                    }
                }
            }
            output.append(result[idx])
            idx = result.index(after: idx)
        }
        return output
    }

    // MARK: - Helpers

    private func extractBoundary(from contentType: String) -> String? {
        // boundary="..." or boundary=...
        let parts = contentType.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("boundary") {
                if let eq = trimmed.firstIndex(of: "=") {
                    let boundary = String(trimmed[trimmed.index(after: eq)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return boundary
                }
            }
        }
        return nil
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
