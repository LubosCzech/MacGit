import Foundation

// MARK: - CLI agenti

public enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex, cursor, grok

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor Agent"
        case .grok: "Grok CLI"
        }
    }

    /// Názvy spustitelných souborů v pořadí preference.
    public var executableNames: [String] {
        switch self {
        case .claude: ["claude"]
        case .codex: ["codex"]
        case .cursor: ["cursor-agent"]
        case .grok: ["grok"]
        }
    }

    /// Modely, které lze nabídnout bez dotazu na CLI (aliasy). `nil` = výchozí model CLI.
    public var fallbackModels: [AgentModel] {
        switch self {
        case .claude: [AgentModel(id: "sonnet", name: "Sonnet (nejnovější)"), AgentModel(id: "opus", name: "Opus (nejnovější)"), AgentModel(id: "fable", name: "Fable (nejnovější)"), AgentModel(id: "haiku", name: "Haiku (nejnovější)")]
        case .codex, .cursor: []
        case .grok: [AgentModel(id: "grok-code-fast-1", name: "grok-code-fast-1"), AgentModel(id: "grok-4", name: "grok-4")]
        }
    }
}

public struct AgentModel: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct InstalledAgent: Identifiable, Hashable, Sendable {
    public var kind: AgentKind
    public var executable: String
    public var id: AgentKind { kind }
}

public enum AgentDetector {
    /// Složky, kam se CLI agenti běžně instalují (GUI aplikace je v PATH nemá).
    public static func candidateDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser, loginPath: String?) -> [String] {
        var directories = (loginPath ?? "").split(separator: ":").map(String.init)
        directories += [
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".claude/local").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"
        ]
        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func detect(in directories: [String]) -> [InstalledAgent] {
        AgentKind.allCases.compactMap { kind in
            for directory in directories {
                for name in kind.executableNames {
                    let path = (directory as NSString).appendingPathComponent(name)
                    if FileManager.default.isExecutableFile(atPath: path) {
                        return InstalledAgent(kind: kind, executable: path)
                    }
                }
            }
            return nil
        }
    }

    /// PATH z přihlašovacího shellu uživatele (včetně ~/.zshrc), aby agenti našli node, git apod.
    public static func loginShellPath() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let result = try? await ProcessRunner.run(shell, ["-ilc", "printf '__PATH__%s' \"$PATH\""], timeout: 10),
              let range = result.output.range(of: "__PATH__", options: .backwards) else { return nil }
        let path = result.output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Modely dostupné v daném CLI.
    public static func models(for agent: InstalledAgent, environment: [String: String]) async -> [AgentModel] {
        switch agent.kind {
        case .codex:
            guard let result = try? await ProcessRunner.run(agent.executable, ["debug", "models"], environment: environment, timeout: 30),
                  let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { model in
                guard let slug = model["slug"] as? String, (model["visibility"] as? String) != "hide" else { return nil }
                return AgentModel(id: slug, name: model["display_name"] as? String ?? slug)
            }
        case .cursor:
            guard let result = try? await ProcessRunner.run(agent.executable, ["--list-models"], environment: environment, timeout: 45) else { return [] }
            return parseCursorModels(result.output)
        case .claude, .grok:
            return agent.kind.fallbackModels
        }
    }

    /// `slug - Název` → model; první řádek nadpisu a `auto` (= výchozí) se přeskočí.
    public static func parseCursorModels(_ text: String) -> [AgentModel] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: " - ")
            guard parts.count >= 2 else { return nil }
            let slug = parts[0].trimmingCharacters(in: .whitespaces)
            guard !slug.isEmpty, !slug.contains(" "), slug != "auto" else { return nil }
            let name = parts[1...].joined(separator: " - ").replacingOccurrences(of: " (current, default)", with: "").trimmingCharacters(in: .whitespaces)
            return AgentModel(id: slug, name: name)
        }
    }
}

// MARK: - Spuštění review

public struct AgentInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    /// Soubor, do kterého CLI zapíše finální odpověď samo (Codex). Jinak se použije stdout.
    public var outputFile: URL?
}

public enum AgentCommand {
    /// Sestaví příkaz pro review v režimu jen pro čtení.
    public static func review(agent: InstalledAgent, model: String?, prompt: String, workingDirectory: URL, outputFile: URL) -> AgentInvocation {
        let model = model.flatMap { $0.isEmpty ? nil : $0 }
        switch agent.kind {
        case .claude:
            var args = [
                "-p", prompt,
                "--output-format", "text",
                "--permission-mode", "dontAsk",
                "--allowedTools", "Read,Grep,Glob,LS,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git status:*)",
                "--disallowedTools", "Edit,Write,NotebookEdit,WebFetch,WebSearch"
            ]
            if let model { args += ["--model", model] }
            return AgentInvocation(executable: agent.executable, arguments: args, outputFile: nil)

        case .codex:
            var args = ["exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral",
                        "-C", workingDirectory.path, "-o", outputFile.path]
            if let model { args += ["-m", model] }
            args.append(prompt)
            return AgentInvocation(executable: agent.executable, arguments: args, outputFile: outputFile)

        case .cursor:
            var args = ["-p", "--output-format", "text", "--mode", "ask", "--trust", "--workspace", workingDirectory.path]
            if let model { args += ["--model", model] }
            args.append(prompt)
            return AgentInvocation(executable: agent.executable, arguments: args, outputFile: nil)

        case .grok:
            // Grok CLI (superagent-ai/grok-cli) – neinteraktivní režim přes --prompt.
            var args = ["--prompt", prompt, "--directory", workingDirectory.path]
            if let model { args += ["--model", model] }
            return AgentInvocation(executable: agent.executable, arguments: args, outputFile: nil)
        }
    }
}

// MARK: - Prompt

public struct ReviewScope: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Všechny změny větve od merge-base se základní větví.
        case branch
        /// Jeden commit oproti svému (prvnímu) rodiči.
        case commit(hash: String, subject: String)
    }

    public var kind: Kind
    /// Větev, nebo krátký hash u commitu.
    public var branch: String
    /// Základní větev, nebo rodič commitu.
    public var baseBranch: String
    /// Revize, od které se změny počítají (merge-base / rodič / prázdný strom).
    public var mergeBase: String
    public var commits: [String]
    public var diffStat: String

    public init(kind: Kind = .branch, branch: String, baseBranch: String, mergeBase: String, commits: [String], diffStat: String) {
        self.kind = kind
        self.branch = branch
        self.baseBranch = baseBranch
        self.mergeBase = mergeBase
        self.commits = commits
        self.diffStat = diffStat
    }
}

public enum ReviewPrompt {
    public static func build(scope: ReviewScope, extraInstructions: String?) -> String {
        let commits = scope.commits.prefix(50).map { "- \($0)" }.joined(separator: "\n")
        let intro: String
        let heading: String
        switch scope.kind {
        case .branch:
            heading = "Review větve \(scope.branch)"
            intro = """
            You are a senior engineer doing a careful code review of the git branch `\(scope.branch)` \
            against `\(scope.baseBranch)`. The branch is checked out in the current directory (read-only review copy).

            Scope of the review: everything introduced since the merge base.
            - See the full change with: `git diff \(scope.mergeBase)...HEAD`
            - Commits on the branch: `git log --oneline \(scope.mergeBase)..HEAD`
            - Read surrounding code with your file tools whenever the diff alone is not enough.

            Commits:
            \(commits.isEmpty ? "(none)" : commits)
            """
        case let .commit(hash, subject):
            heading = "Review commitu \(scope.branch)"
            let diffCommand = scope.mergeBase == GitRepository.emptyTree ? "git show HEAD" : "git diff \(scope.mergeBase) HEAD"
            intro = """
            You are a senior engineer doing a careful code review of a single git commit \
            `\(hash)` ("\(subject)"). The repository is checked out at exactly this commit in the current directory \
            (read-only review copy), so the working tree shows the code as it was right after the commit.

            Scope of the review: only the changes introduced by this commit.
            - See the change with: `\(diffCommand)`
            - Full commit message: `git log -1 --format=%B HEAD`
            - Read surrounding code with your file tools whenever the diff alone is not enough; do not review unrelated older code.
            """
        }
        var prompt = intro + """


        Changed files:
        \(scope.diffStat.isEmpty ? "(none)" : scope.diffStat)

        Rules:
        - Do NOT modify any files, create commits or run builds/tests. Only read.
        - Report only real, specific problems backed by the code. No generic advice, no praise padding.
        - Every finding must reference a file and line in the NEW version of the code.
        - Write the whole review in Czech. Keep code identifiers, file paths and snippets as they are.
        - Your final answer must contain ONLY the review document below: start directly with the `#` heading, no preamble or closing remarks.

        Output format (Markdown, exactly these sections in this order; write "Bez nálezů." under a section with nothing to report):

        # \(heading)

        ## Shrnutí
        2–4 sentences: what the change does and your overall verdict.

        ## Celkové riziko
        One line: `Riziko: nízké`, `Riziko: střední` or `Riziko: vysoké`, followed by one sentence why.

        ## Místa k prověření
        The most important part. One bullet per finding, most severe first, using EXACTLY this shape:
        - [KRITICKÉ] path/to/file.ext:123 — short title
          Explanation of the problem and its impact (1–3 sentences).
          Návrh: concrete fix.
        Severity tags (use only these): [KRITICKÉ] = bug, data loss, security hole or crash; \
        [DŮLEŽITÉ] = likely bug, missing error handling, race, notable performance issue; \
        [K ZVÁŽENÍ] = maintainability, naming, minor design concern worth a look.

        ## Bezpečnost
        ## Výkon
        ## Testy
        What is untested or which tests should be added.
        ## Doporučení
        Short prioritized list of next steps before merging.
        """
        if let extraInstructions, !extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nAdditional instructions from the author:\n\(extraInstructions)"
        }
        return prompt
    }
}

// MARK: - Parsování výstupu

public struct ReviewFinding: Identifiable, Hashable, Sendable {
    public enum Severity: String, CaseIterable, Sendable {
        case critical = "KRITICKÉ"
        case important = "DŮLEŽITÉ"
        case consider = "K ZVÁŽENÍ"
    }

    public var id: Int
    public var severity: Severity
    public var file: String?
    public var line: Int?
    public var title: String
    public var details: String
}

public struct ReviewSection: Identifiable, Hashable, Sendable {
    public var id: Int
    public var title: String
    public var body: String
}

public struct ParsedReview: Sendable {
    public var title: String?
    public var risk: String?
    public var sections: [ReviewSection]
    public var findings: [ReviewFinding]

    /// Text od prvního nadpisu – agenti občas přidají úvodní větu.
    public static func trimmedDocument(_ markdown: String) -> String {
        guard let range = markdown.range(of: "(?m)^# ", options: .regularExpression), range.lowerBound != markdown.startIndex else { return markdown }
        return String(markdown[range.lowerBound...])
    }

    public static func parse(_ markdown: String) -> ParsedReview {
        var title: String?
        var sections: [ReviewSection] = []
        var currentTitle: String?
        var currentBody: [String] = []

        func flush() {
            if let currentTitle {
                sections.append(ReviewSection(id: sections.count, title: currentTitle, body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            currentBody = []
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("## ") {
                flush()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("# "), title == nil, currentTitle == nil {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if currentTitle != nil {
                currentBody.append(line)
            }
        }
        flush()

        let findings = sections.first { $0.title.localizedCaseInsensitiveContains("prověření") }.map { parseFindings($0.body) } ?? []
        let risk = sections.first { $0.title.localizedCaseInsensitiveContains("riziko") }?.body
            .split(separator: "\n").first.map { String($0).replacingOccurrences(of: "`", with: "") }
        return ParsedReview(title: title, risk: risk, sections: sections, findings: findings)
    }

    static func parseFindings(_ body: String) -> [ReviewFinding] {
        var findings: [ReviewFinding] = []
        let tags = ReviewFinding.Severity.allCases.map { NSRegularExpression.escapedPattern(for: $0.rawValue) }.joined(separator: "|")
        let pattern = try! NSRegularExpression(pattern: #"^\s*[-*]\s+\**\[("# + tags + #")\]\**\s+`?([^\s`]+?)(?::(\d+)(?:-\d+)?)?`?\s+[—–-]+\s+(.+)$"#)

        var current: ReviewFinding?
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            if let match = pattern.firstMatch(in: line, range: range) {
                if let current { findings.append(current) }
                func group(_ index: Int) -> String? {
                    Range(match.range(at: index), in: line).map { String(line[$0]) }
                }
                current = ReviewFinding(
                    id: findings.count,
                    severity: ReviewFinding.Severity(rawValue: group(1) ?? "") ?? .consider,
                    file: group(2),
                    line: group(3).flatMap(Int.init),
                    title: group(4)?.trimmingCharacters(in: .whitespaces) ?? "",
                    details: ""
                )
            } else if current != nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                current!.details += (current!.details.isEmpty ? "" : "\n") + trimmed
            }
        }
        if let current { findings.append(current) }
        return findings
    }
}

// MARK: - Git: dočasná pracovní kopie

extension GitRepository {
    /// Výchozí základní větev pro porovnání (origin/HEAD → main → master).
    public func defaultBaseBranch() async -> String? {
        if let result = try? await git(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], allowFailure: true),
           result.status == 0 {
            let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        let names = (try? await branches().map(\.name)) ?? []
        return ["main", "master", "origin/main", "origin/master", "develop"].first { names.contains($0) }
    }

    /// Rozsah review jednoho commitu: změny oproti prvnímu rodiči (u prvního commitu oproti prázdnému stromu).
    public func reviewScope(commit hash: String) async throws -> ReviewScope {
        let full = try await git(["rev-parse", "--verify", "\(hash)^{commit}"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = try await git(["log", "-1", "--format=%h%x1f%s", full]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = info.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
        let short = parts.first ?? String(full.prefix(7))
        let subject = parts.count > 1 ? parts[1] : ""
        let parentResult = try await git(["rev-parse", "--verify", "--quiet", "\(full)^1"], allowFailure: true)
        let parent = parentResult.status == 0 ? parentResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : Self.emptyTree
        let stat = try await git(["diff", "--stat=160", parent, full]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewScope(
            kind: .commit(hash: full, subject: subject),
            branch: short,
            baseBranch: parent == Self.emptyTree ? "prázdný repozitář" : String(parent.prefix(7)),
            mergeBase: parent,
            commits: ["\(short) \(subject)"],
            diffStat: stat
        )
    }

    public func reviewScope(branch: String, base: String) async throws -> ReviewScope {
        let mergeBase = try await git(["merge-base", base, branch]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let commits = try await git(["log", "--format=%h %s", "--max-count=200", "\(mergeBase)..\(branch)"]).output
            .split(separator: "\n").map(String.init)
        let stat = try await git(["diff", "--stat=160", "\(mergeBase)...\(branch)"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewScope(branch: branch, baseBranch: base, mergeBase: mergeBase, commits: commits, diffStat: stat)
    }

    /// Vytvoří odpojený worktree větve v dočasné složce – pracovní kopie uživatele zůstane nedotčená.
    public func addTemporaryWorktree(for revision: String, in parent: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let directory = parent.appendingPathComponent("review-\(UUID().uuidString.prefix(8))")
        try await git(["worktree", "add", "--detach", directory.path, revision])
        return directory
    }

    public func removeTemporaryWorktree(_ directory: URL) async {
        _ = try? await git(["worktree", "remove", "--force", directory.path], allowFailure: true)
        try? FileManager.default.removeItem(at: directory)
        _ = try? await git(["worktree", "prune"], allowFailure: true)
    }
}

// MARK: - Obecné spouštění procesů

public enum ProcessRunner {
    public struct Result: Sendable {
        public var status: Int32
        public var output: String
        public var errorOutput: String
    }

    /// Jednoduché spuštění s časovým limitem (detekce modelů, PATH).
    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                           currentDirectory: URL? = nil, timeout: TimeInterval) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment { process.environment = environment }
                if let currentDirectory { process.currentDirectoryURL = currentDirectory }
                process.standardInput = FileHandle.nullDevice
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do { try process.run() } catch { continuation.resume(throwing: error); return }

                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

                let errorBox = LockedData()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errorBox.set(err.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                let output = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    output: String(decoding: output, as: UTF8.self),
                    errorOutput: String(decoding: errorBox.get(), as: UTF8.self)
                ))
            }
        }
    }
}

final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func set(_ value: Data) { lock.withLock { data = value } }
    func append(_ value: Data) { lock.withLock { data.append(value) } }
    func get() -> Data { lock.withLock { data } }
}
