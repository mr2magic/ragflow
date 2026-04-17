import Foundation

/// Parses GEDCOM genealogy files (.ged) into text sections suitable for chunking and RAG retrieval.
/// Produces one section per individual and one per family, formatted as readable plain text.
struct GEDCOMParser {

    struct Section {
        let title: String
        let text: String
    }

    func parse(url: URL) throws -> [Section] {
        // GEDCOM files may use UTF-8 or Latin-1 depending on the exporting tool.
        let raw: String
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            raw = s
        } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
            raw = s
        } else {
            throw ParseError.unreadable
        }
        return parse(text: raw)
    }

    /// Visible for testing — parse raw GEDCOM text directly.
    func parse(text: String) -> [Section] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let gedLines = normalized.components(separatedBy: "\n").compactMap(parseLine)

        var individuals: [String: IndiRecord] = [:]
        var families:    [String: FamRecord]  = [:]

        enum Ctx { case none, indi(String), fam(String) }
        var ctx: Ctx = .none
        var event: String? = nil

        for line in gedLines {
            if line.level == 0 {
                event = nil
                if let xref = line.xref {
                    switch line.tag {
                    case "INDI":
                        ctx = .indi(xref)
                        individuals[xref] = IndiRecord(id: xref)
                    case "FAM":
                        ctx = .fam(xref)
                        families[xref] = FamRecord(id: xref)
                    default:
                        ctx = .none
                    }
                } else {
                    ctx = .none
                }
                continue
            }

            switch ctx {
            case .none: break
            case .indi(let id): processIndiLine(line, id: id, event: &event, into: &individuals)
            case .fam(let id):  processFamLine(line,  id: id, event: &event, into: &families)
            }
        }

        return buildSections(individuals: individuals, families: families)
    }

    // MARK: - Section builder

    private func buildSections(individuals: [String: IndiRecord],
                                families: [String: FamRecord]) -> [Section] {
        var sections: [Section] = []

        for (_, indi) in individuals.sorted(by: { $0.key < $1.key }) {
            let name = indi.name ?? "Unknown Individual"
            var parts = ["Individual: \(name)"]
            if let sex = indi.sex {
                parts.append("Sex: \(sex == "M" ? "Male" : sex == "F" ? "Female" : sex)")
            }
            if let d = indi.birthDate, !d.isEmpty {
                let place = indi.birthPlace.map { " in \($0)" } ?? ""
                parts.append("Born: \(d)\(place)")
            }
            if let d = indi.deathDate, !d.isEmpty {
                let place = indi.deathPlace.map { " in \($0)" } ?? ""
                parts.append("Died: \(d)\(place)")
            }
            if !indi.occupations.isEmpty {
                parts.append("Occupation: \(indi.occupations.joined(separator: ", "))")
            }
            if !indi.notes.isEmpty {
                parts.append("Notes: \(indi.notes.joined(separator: " "))")
            }
            sections.append(Section(title: name, text: parts.joined(separator: "\n")))
        }

        for (_, fam) in families.sorted(by: { $0.key < $1.key }) {
            let husb = fam.husbRef.flatMap { individuals[$0]?.name } ?? "Unknown"
            let wife = fam.wifeRef.flatMap { individuals[$0]?.name } ?? "Unknown"
            let title = "\(husb) and \(wife) Family"
            var parts = ["Family: \(title)"]
            if let d = fam.marriageDate, !d.isEmpty {
                let place = fam.marriagePlace.map { " in \($0)" } ?? ""
                parts.append("Married: \(d)\(place)")
            }
            let childNames = fam.childRefs.compactMap { individuals[$0]?.name }
            if !childNames.isEmpty {
                parts.append("Children: \(childNames.joined(separator: ", "))")
            }
            if !fam.notes.isEmpty {
                parts.append("Notes: \(fam.notes.joined(separator: " "))")
            }
            sections.append(Section(title: title, text: parts.joined(separator: "\n")))
        }

        return sections
    }

    // MARK: - Line processors

    private func processIndiLine(_ line: GEDLine, id: String,
                                  event: inout String?,
                                  into dict: inout [String: IndiRecord]) {
        guard var r = dict[id] else { return }
        defer { dict[id] = r }

        if line.level == 1 {
            switch line.tag {
            case "NAME":
                if r.name == nil { r.name = formatName(line.value) }
            case "SEX":
                r.sex = line.value
            case "BIRT", "DEAT":
                event = line.tag
            case "OCCU":
                event = "OCCU"
                if !line.value.isEmpty { r.occupations.append(line.value) }
            case "NOTE":
                event = "NOTE"
                if !line.value.isEmpty { r.notes.append(line.value) }
            default:
                event = line.tag
            }
        } else if line.level == 2 {
            switch line.tag {
            case "DATE":
                if event == "BIRT"      { r.birthDate = line.value }
                else if event == "DEAT" { r.deathDate = line.value }
            case "PLAC":
                if event == "BIRT"      { r.birthPlace = line.value }
                else if event == "DEAT" { r.deathPlace = line.value }
            case "CONT":
                if event == "NOTE", !r.notes.isEmpty {
                    r.notes[r.notes.count - 1] += " \(line.value)"
                }
            case "CONC":
                if event == "NOTE", !r.notes.isEmpty {
                    r.notes[r.notes.count - 1] += line.value
                }
            default: break
            }
        }
    }

    private func processFamLine(_ line: GEDLine, id: String,
                                 event: inout String?,
                                 into dict: inout [String: FamRecord]) {
        guard var r = dict[id] else { return }
        defer { dict[id] = r }

        if line.level == 1 {
            switch line.tag {
            case "HUSB": r.husbRef = line.value.isEmpty ? nil : line.value
            case "WIFE": r.wifeRef = line.value.isEmpty ? nil : line.value
            case "CHIL": if !line.value.isEmpty { r.childRefs.append(line.value) }
            case "MARR": event = "MARR"
            case "NOTE":
                event = "NOTE"
                if !line.value.isEmpty { r.notes.append(line.value) }
            default:
                event = line.tag
            }
        } else if line.level == 2 {
            switch line.tag {
            case "DATE": if event == "MARR" { r.marriageDate = line.value }
            case "PLAC": if event == "MARR" { r.marriagePlace = line.value }
            case "CONT":
                if event == "NOTE", !r.notes.isEmpty {
                    r.notes[r.notes.count - 1] += " \(line.value)"
                }
            default: break
            }
        }
    }

    // MARK: - Helpers

    private func parseLine(_ raw: String) -> GEDLine? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let parts = s.components(separatedBy: " ")
        guard parts.count >= 2, let level = Int(parts[0]) else { return nil }

        let second = parts[1]
        let xref: String?
        let tag: String
        let valueStart: Int

        if second.hasPrefix("@") && second.hasSuffix("@") && parts.count >= 3 {
            xref = second
            tag = parts[2]
            valueStart = 3
        } else {
            xref = nil
            tag = second
            valueStart = 2
        }

        let value = parts.count > valueStart
            ? parts[valueStart...].joined(separator: " ")
            : ""

        return GEDLine(level: level, xref: xref, tag: tag, value: value)
    }

    /// Convert GEDCOM name format ("Given /Surname/ Suffix") to plain "Given Surname Suffix".
    private func formatName(_ raw: String) -> String {
        var result = raw
        if let start = result.firstIndex(of: "/"),
           let end = result.lastIndex(of: "/"),
           start != end {
            let given   = String(result[..<start]).trimmingCharacters(in: .whitespaces)
            let surname = String(result[result.index(after: start)..<end])
            let suffix  = String(result[result.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            result = [given, surname, suffix].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Data types

    private struct GEDLine {
        let level: Int
        let xref: String?
        let tag: String
        let value: String
    }

    private struct IndiRecord {
        let id: String
        var name: String?
        var sex: String?
        var birthDate: String?
        var birthPlace: String?
        var deathDate: String?
        var deathPlace: String?
        var occupations: [String] = []
        var notes: [String] = []
    }

    private struct FamRecord {
        let id: String
        var husbRef: String?
        var wifeRef: String?
        var childRefs: [String] = []
        var marriageDate: String?
        var marriagePlace: String?
        var notes: [String] = []
    }

    enum ParseError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Could not read GEDCOM file." }
    }
}
