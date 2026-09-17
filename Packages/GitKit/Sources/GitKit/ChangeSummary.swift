import Foundation

/// Kompaktní textový přehled změn pro jazykový model s malým kontextem.
public enum ChangeSummary {
    /// - Parameter characterLimit: horní mez délky výstupu (≈ 3,5 znaku na token u kódu).
    public static func render(_ items: [(change: FileChange, diff: FileDiff?)], characterLimit: Int) -> String {
        var output = "Changed files (\(items.count)):\n"
        for item in items {
            let stats = item.diff.map { $0.isBinary ? "binary" : "+\($0.additions) -\($0.deletions)" } ?? ""
            let rename = item.change.originalPath.map { " (from \($0))" } ?? ""
            output += "\(item.change.kind.letter) \(item.change.path)\(rename) \(stats)\n"
        }
        guard output.count < characterLimit else { return String(output.prefix(characterLimit)) }

        let excerpts = items.filter { $0.diff.map { !$0.isBinary && !$0.isEmpty } ?? false }
        guard !excerpts.isEmpty else { return output }
        output += "\nDiff excerpts (only changed lines, may be truncated):\n"

        var remaining = characterLimit - output.count
        for (index, item) in excerpts.enumerated() {
            guard remaining > 80, let diff = item.diff else { break }
            // Zbylý rozpočet se dělí rovným dílem mezi soubory, které ještě nepřišly na řadu.
            let budget = max(200, remaining / (excerpts.count - index))
            let excerpt = excerptLines(diff, budget: budget)
            output += excerpt
            remaining -= excerpt.count
        }
        return String(output.prefix(characterLimit))
    }

    static func excerptLines(_ diff: FileDiff, budget: Int) -> String {
        var text = "### \(diff.path)\n"
        for hunk in diff.hunks {
            // Kontext za @@ bývá název funkce – pro shrnutí užitečnější než kontextové řádky.
            if let context = hunk.header.components(separatedBy: "@@").last?.trimmingCharacters(in: .whitespaces), !context.isEmpty {
                text += "@@ \(context)\n"
            }
            for line in hunk.lines where line.kind == .addition || line.kind == .deletion {
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let rendered = (line.kind == .addition ? "+" : "-") + String(trimmed.prefix(160)) + "\n"
                if text.count + rendered.count > budget {
                    return text + "…\n"
                }
                text += rendered
            }
        }
        return text
    }
}

extension GitRepository {
    /// Přehled vybraných změn pro generování commit zprávy.
    public func changeSummary(for changes: [FileChange], characterLimit: Int) async -> String {
        var items: [(change: FileChange, diff: FileDiff?)] = []
        for change in changes {
            items.append((change, try? await diff(for: change)))
        }
        return ChangeSummary.render(items, characterLimit: characterLimit)
    }

    /// Předměty posledních commitů – model podle nich odhadne styl zpráv v repozitáři.
    public func recentSubjects(limit: Int = 5) async -> [String] {
        (try? await log(limit: limit).map(\.subject)) ?? []
    }
}
