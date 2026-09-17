import Foundation

/// Srozumitelné shrnutí chybového výstupu gitu – bez průběhu fetch a dalšího šumu.
public struct GitErrorSummary: Sendable, Equatable {
    public var title: String
    public var explanation: String
    /// Celý původní výstup (pro rozbalení a kopírování).
    public var details: String

    public static func make(from message: String) -> GitErrorSummary {
        let details = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for known in knownProblems where known.matches(details) {
            return GitErrorSummary(title: known.title, explanation: known.explanation, details: details)
        }
        let meaningful = details.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            !line.isEmpty && !isNoise(line)
        }
        let fatal = meaningful.filter { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") }
        let chosen = fatal.isEmpty ? Array(meaningful.suffix(3)) : fatal
        let explanation = chosen.map { line in
            line.replacingOccurrences(of: "fatal: ", with: "").replacingOccurrences(of: "error: ", with: "")
        }.joined(separator: "\n")
        return GitErrorSummary(title: "Git hlásí chybu", explanation: explanation.isEmpty ? details : explanation, details: details)
    }

    /// Řádky průběhu fetch/push, které samy o sobě chybu nepopisují.
    static func isNoise(_ line: String) -> Bool {
        line.hasPrefix("From ") || line.hasPrefix("To ") || line.hasPrefix("* [") || line.hasPrefix("+ ")
            || line.hasPrefix("remote: Enumerating") || line.hasPrefix("remote: Counting") || line.hasPrefix("remote: Compressing")
            || line.hasPrefix("remote: Total") || line.hasPrefix("Receiving objects") || line.hasPrefix("Resolving deltas")
            || line.hasPrefix("Unpacking objects") || line.hasPrefix("- [deleted]") || line.range(of: #"^[0-9a-f]{7,}\.\.[0-9a-f]{7,}"#, options: .regularExpression) != nil
    }

    private struct Known {
        var needles: [String]
        var title: String
        var explanation: String
        func matches(_ text: String) -> Bool { needles.contains { text.contains($0) } }
    }

    private static let knownProblems: [Known] = [
        Known(needles: ["There is no tracking information for the current branch"],
              title: "Větev nemá nastavenou vzdálenou větev",
              explanation: "Git neví, odkud má aktuální větev stahovat (chybí upstream). Stává se to po odebrání a znovupřidání remotu. Pushni větev, nebo ji propoj s větví na serveru."),
        Known(needles: ["could not read Username", "terminal prompts disabled"],
              title: "Chybí přihlašovací údaje",
              explanation: "Remote používá HTTPS a git nemá uložené jméno ani heslo. Nastav přihlášení v inspektoru → Repozitář, nebo změň remote na SSH."),
        Known(needles: ["Permission denied (publickey"],
              title: "Server odmítl SSH klíč",
              explanation: "Tvůj SSH klíč není na serveru nahraný nebo nemáš k repozitáři přístup. Přidej veřejný klíč ve svém profilu na GitHubu/GitLabu."),
        Known(needles: ["Repository not found", "does not appear to be a git repository", "repository '"],
              title: "Repozitář nebyl nalezen",
              explanation: "Adresa remotu je špatně, nebo k repozitáři nemáš přístup."),
        Known(needles: ["Could not resolve host", "Connection timed out", "Network is unreachable", "Operation timed out"],
              title: "Server není dostupný",
              explanation: "Nepodařilo se spojit se serverem. Zkontroluj připojení k internetu nebo VPN."),
        Known(needles: ["Updates were rejected because the tip of your current branch is behind", "[rejected]", "non-fast-forward"],
              title: "Push byl odmítnut",
              explanation: "Na serveru jsou novější commity. Nejdřív udělej Pull a pak push zopakuj."),
        Known(needles: ["Need to specify how to reconcile divergent branches", "have diverged"],
              title: "Větve se rozešly",
              explanation: "Lokální i vzdálená větev mají nové commity. Zvol Pull (merge), nebo Pull s rebase."),
        Known(needles: ["Your local changes to the following files would be overwritten"],
              title: "Neuložené změny by se přepsaly",
              explanation: "Operace by přepsala rozpracované soubory. Commitni je, nebo je odlož do shelfu, a akci zopakuj."),
        Known(needles: ["CONFLICT (", "Automatic merge failed"],
              title: "Konflikt při slučování",
              explanation: "Některé soubory se nepodařilo sloučit automaticky. Vyřeš konflikty v seznamu změn a dokonči commit.")
    ]
}
