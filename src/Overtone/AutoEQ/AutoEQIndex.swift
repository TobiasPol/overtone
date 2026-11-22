import Foundation

/// One headphone measurement in the AutoEQ database.
struct AutoEQEntry: Identifiable, Hashable, Sendable {
    let name: String
    /// Path relative to `results/`, exactly as written in INDEX.md (spaces as %20).
    let path: String
    let source: String
    let rig: String?

    var id: String { path }
    var detail: String { rig.map { "\(source) · \($0)" } ?? source }
}

enum AutoEQIndex {
    static let baseURL = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/")!

    /// Parses lines like `- [Name](./source/rig/Name%20Folder) by source on rig`.
    /// Names may themselves contain parentheses, so the link ends at the last ") by ".
    static func parse(_ markdown: String) -> [AutoEQEntry] {
        markdown.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> AutoEQEntry? {
        guard line.hasPrefix("- ["),
              let nameEnd = line.range(of: "](./"),
              let linkEnd = line.range(of: ") by ", options: .backwards),
              nameEnd.upperBound <= linkEnd.lowerBound else { return nil }
        let name = String(line[line.index(line.startIndex, offsetBy: 3)..<nameEnd.lowerBound])
        let path = String(line[nameEnd.upperBound..<linkEnd.lowerBound])
        let attribution = String(line[linkEnd.upperBound...])
        let parts = attribution.components(separatedBy: " on ")
        let rig = parts.count > 1 ? parts.dropFirst().joined(separator: " on ") : nil
        return AutoEQEntry(name: name, path: path, source: parts[0], rig: rig)
    }

    /// URL of the entry's ParametricEQ.txt, with every path component strictly percent-encoded.
    static func profileURL(for entry: AutoEQEntry, base: URL = baseURL) -> URL? {
        let components = entry.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let folder = components.last else { return nil }
        let encoded = (components + ["\(folder) ParametricEQ.txt"]).map(encode)
        return URL(string: base.absoluteString + encoded.joined(separator: "/"))
    }

    private static let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private static func encode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: unreserved) ?? component
    }

    /// Ranked search: every query word must appear in the name, source, or rig.
    static func search(_ query: String, in entries: [AutoEQEntry], limit: Int = 80) -> [AutoEQEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let matches = entries.filter { entry in
            let haystack = "\(entry.name) \(entry.source) \(entry.rig ?? "")".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        let first = words[0]
        return Array(matches.sorted { a, b in
            let aName = a.name.lowercased(), bName = b.name.lowercased()
            let ap = aName.hasPrefix(first), bp = bName.hasPrefix(first)
            if ap != bp { return ap }
            let an = words.allSatisfy { aName.contains($0) }, bn = words.allSatisfy { bName.contains($0) }
            if an != bn { return an }
            if sourceRank(a.source) != sourceRank(b.source) { return sourceRank(a.source) < sourceRank(b.source) }
            return a.name.count < b.name.count
        }.prefix(limit))
    }

    /// AutoEQ's own recommendation order for measurement sources.
    private static func sourceRank(_ source: String) -> Int {
        ["oratory1990", "crinacle", "Innerfidelity", "Rtings", "Headphone.com Legacy"].firstIndex(of: source) ?? 99
    }
}
