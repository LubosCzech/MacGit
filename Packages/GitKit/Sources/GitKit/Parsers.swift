import Foundation

public enum GitParsers {
    static let fieldSeparator: Character = "\u{1F}"
    static let recordSeparator: Character = "\u{1E}"

    // MARK: status --porcelain=v2 -z --branch

    public static func parseStatus(_ data: Data) -> StatusSnapshot {
        let text = String(decoding: data, as: UTF8.self)
        var tokens = text.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var snapshot = StatusSnapshot()
        var index = 0

        while index < tokens.count {
            let entry = tokens[index]
            index += 1
            guard let type = entry.first else { continue }

            switch type {
            case "#":
                let parts = entry.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 3 else { continue }
                switch parts[1] {
                case "branch.oid": snapshot.branch.oid = parts[2] == "(initial)" ? nil : parts[2]
                case "branch.head": snapshot.branch.head = parts[2] == "(detached)" ? nil : parts[2]
                case "branch.upstream": snapshot.branch.upstream = parts[2]
                case "branch.ab":
                    for value in parts[2].split(separator: " ") {
                        if value.hasPrefix("+") { snapshot.branch.ahead = Int(value.dropFirst()) ?? 0 }
                        if value.hasPrefix("-") { snapshot.branch.behind = Int(value.dropFirst()) ?? 0 }
                    }
                default: break
                }

            case "1":
                // 1 XY sub mH mI mW hH hI path
                let parts = entry.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard parts.count == 9 else { continue }
                snapshot.changes.append(makeChange(xy: parts[1], path: String(parts[8]), original: nil))

            case "2":
                // 2 XY sub mH mI mW hH hI Xscore path \0 origPath
                let parts = entry.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard parts.count == 10 else { continue }
                let original = index < tokens.count ? tokens[index] : nil
                index += 1
                snapshot.changes.append(makeChange(xy: parts[1], path: String(parts[9]), original: original))

            case "u":
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                let parts = entry.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard parts.count == 11 else { continue }
                let xy = Array(parts[1])
                snapshot.changes.append(FileChange(path: String(parts[10]), indexCode: xy[0], worktreeCode: xy[1], kind: .conflicted))

            case "?":
                snapshot.changes.append(FileChange(path: String(entry.dropFirst(2)), indexCode: "?", worktreeCode: "?", kind: .untracked))

            default:
                continue
            }
        }
        tokens.removeAll()
        snapshot.changes.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return snapshot
    }

    private static func makeChange(xy: Substring, path: String, original: String?) -> FileChange {
        let codes = Array(xy)
        let x = codes.first ?? ".", y = codes.count > 1 ? codes[1] : "."
        // Pro zobrazení má přednost stav v indexu u přidání/přejmenování, jinak pracovní strom.
        let kind: ChangeKind
        if x == "A" || x == "R" || x == "C" {
            kind = ChangeKind(code: x)
        } else if y != "." {
            kind = ChangeKind(code: y)
        } else {
            kind = ChangeKind(code: x)
        }
        return FileChange(path: path, originalPath: original, indexCode: x, worktreeCode: y, kind: kind)
    }

    // MARK: log

    public static let logFormat = "%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%b%x1f%D%x1e"

    public static func parseLog(_ text: String) -> [Commit] {
        let iso = ISO8601DateFormatter()
        return text.split(separator: recordSeparator).compactMap { raw in
            let record = raw.trimmingCharacters(in: .newlines)
            let f = record.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 9 else { return nil }
            return Commit(
                hash: f[0],
                shortHash: f[1],
                parents: f[2].split(separator: " ").map(String.init),
                authorName: f[3],
                authorEmail: f[4],
                date: iso.date(from: f[5]) ?? .distantPast,
                subject: f[6],
                body: f[7].trimmingCharacters(in: .whitespacesAndNewlines),
                refs: f[8].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
        }
    }

    /// Z výstupu `git log --pretty=raw` vybere hashe commitů s hlavičkou `gpgsig` / `gpgsig-sha256`.
    /// Na rozdíl od `%G?` nic neověřuje, takže je rychlé i pro stovky commitů.
    public static func parseSignedHashes(_ raw: String) -> Set<String> {
        var signed = Set<String>()
        var current: Substring?
        var inHeader = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("commit ") {
                current = line.dropFirst(7).split(separator: " ").first
                inHeader = true
            } else if line.isEmpty {
                inHeader = false
            } else if inHeader, line.hasPrefix("gpgsig"), let current {
                signed.insert(String(current))
            }
        }
        return signed
    }

    public static let verifyFormat = "%G?%x1f%GS%x1f%GK%x1f%GF"

    public static func parseVerification(_ text: String) -> SignatureVerification {
        let f = text.trimmingCharacters(in: .newlines).split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        return SignatureVerification(
            code: f.first?.first ?? "N",
            signer: f.count > 1 ? f[1] : "",
            key: f.count > 2 ? f[2] : "",
            fingerprint: f.count > 3 ? f[3] : ""
        )
    }

    // MARK: branches

    public static let branchFormat = "%(refname)%1f%(refname:short)%1f%(objectname:short)%1f%(upstream:short)%1f%(HEAD)%1f%(upstream:track)"

    public static func parseBranches(_ text: String) -> [Branch] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, !f[0].hasSuffix("/HEAD") else { return nil }
            let isRemote = f[0].hasPrefix("refs/remotes/")
            // Samotný remote bez větve (`refs/remotes/origin`) přeskočíme.
            if isRemote && !f[1].contains("/") { return nil }
            return Branch(
                fullName: f[0],
                name: f[1],
                shortHash: f[2],
                upstream: f[3].isEmpty ? nil : f[3],
                isCurrent: f[4] == "*",
                isRemote: isRemote,
                track: f[5]
            )
        }
    }

    // MARK: remotes

    public static func parseRemotes(_ text: String) -> [Remote] {
        var fetch: [String: String] = [:], push: [String: String] = [:], order: [String] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 3 else { continue }
            if !order.contains(parts[0]) { order.append(parts[0]) }
            if parts[2] == "(push)" { push[parts[0]] = parts[1] } else { fetch[parts[0]] = parts[1] }
        }
        return order.map { Remote(name: $0, fetchURL: fetch[$0] ?? "", pushURL: push[$0] ?? fetch[$0] ?? "") }
    }

    // MARK: name-status

    public static func parseNameStatus(_ text: String) -> [CommitFile] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 2, let code = parts[0].first else { return nil }
            if (code == "R" || code == "C"), parts.count >= 3 {
                return CommitFile(path: parts[2], originalPath: parts[1], kind: ChangeKind(code: code))
            }
            return CommitFile(path: parts[1], originalPath: nil, kind: ChangeKind(code: code))
        }
    }

    // MARK: unified diff

    public static func parseDiff(_ text: String, path: String) -> FileDiff {
        var hunks: [DiffHunk] = []
        var current: DiffHunk?
        var oldLine = 0, newLine = 0, lineID = 0
        var isBinary = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("@@") {
                if let current { hunks.append(current) }
                (oldLine, newLine) = parseHunkHeader(line)
                current = DiffHunk(id: hunks.count, header: line, lines: [])
                continue
            }
            guard current != nil else {
                if line.hasPrefix("Binary files") || line.hasPrefix("GIT binary patch") { isBinary = true }
                continue
            }
            lineID += 1
            if line.hasPrefix("+") {
                current!.lines.append(DiffLine(id: lineID, kind: .addition, oldLine: nil, newLine: newLine, text: String(line.dropFirst())))
                newLine += 1
            } else if line.hasPrefix("-") {
                current!.lines.append(DiffLine(id: lineID, kind: .deletion, oldLine: oldLine, newLine: nil, text: String(line.dropFirst())))
                oldLine += 1
            } else if line.hasPrefix(" ") {
                current!.lines.append(DiffLine(id: lineID, kind: .context, oldLine: oldLine, newLine: newLine, text: String(line.dropFirst())))
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("\\") {
                current!.lines.append(DiffLine(id: lineID, kind: .meta, oldLine: nil, newLine: nil, text: line))
            } else if line.hasPrefix("diff --git") {
                // Další soubor ve stejném výstupu – ukončíme aktuální hunk.
                hunks.append(current!)
                current = nil
            }
        }
        if let current { hunks.append(current) }
        return FileDiff(path: path, hunks: hunks, isBinary: isBinary)
    }

    static func parseHunkHeader(_ header: String) -> (Int, Int) {
        // @@ -a,b +c,d @@
        let parts = header.split(separator: " ")
        func start(_ token: Substring?) -> Int {
            guard let token else { return 1 }
            return Int(token.dropFirst().split(separator: ",").first ?? "1") ?? 1
        }
        let old = parts.first { $0.hasPrefix("-") }
        let new = parts.first { $0.hasPrefix("+") }
        return (start(old), start(new))
    }

    /// Nový (untracked) soubor zobrazíme jako diff plný přidaných řádků.
    public static func additionDiff(for content: String, path: String) -> FileDiff {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        let diffLines = lines.enumerated().map { DiffLine(id: $0.offset, kind: .addition, oldLine: nil, newLine: $0.offset + 1, text: $0.element) }
        let hunk = DiffHunk(id: 0, header: "@@ -0,0 +1,\(lines.count) @@ nový soubor", lines: diffLines)
        return FileDiff(path: path, hunks: diffLines.isEmpty ? [] : [hunk])
    }
}
