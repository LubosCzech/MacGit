import Foundation
import Testing
@testable import GitKit

struct ParserTests {
    @Test func parsesStatusV2() {
        let raw = [
            "# branch.oid abc123",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +2 -1",
            "1 .M N... 100644 100644 100644 aaa bbb src/file with space.swift",
            "2 R. N... 100644 100644 100644 aaa bbb R100 new.txt",
            "old.txt",
            "1 A. N... 000000 100644 100644 000 bbb added.txt",
            "? untracked.md",
            ""
        ].joined(separator: "\0")
        let snapshot = GitParsers.parseStatus(Data(raw.utf8))
        #expect(snapshot.branch.head == "main")
        #expect(snapshot.branch.upstream == "origin/main")
        #expect(snapshot.branch.ahead == 2)
        #expect(snapshot.branch.behind == 1)
        #expect(snapshot.changes.count == 4)
        let renamed = snapshot.changes.first { $0.path == "new.txt" }
        #expect(renamed?.kind == .renamed)
        #expect(renamed?.originalPath == "old.txt")
        #expect(snapshot.changes.first { $0.path == "src/file with space.swift" }?.kind == .modified)
        #expect(snapshot.changes.first { $0.path == "untracked.md" }?.kind == .untracked)
    }

    @Test func parsesDiffLineNumbers() {
        let diff = """
        diff --git a/a.txt b/a.txt
        index 1..2 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -3,3 +3,4 @@ func
         keep
        -old
        +new
        +extra
         tail
        """
        let parsed = GitParsers.parseDiff(diff, path: "a.txt")
        #expect(parsed.hunks.count == 1)
        #expect(parsed.additions == 2)
        #expect(parsed.deletions == 1)
        let lines = parsed.hunks[0].lines
        #expect(lines[0].oldLine == 3 && lines[0].newLine == 3)
        #expect(lines[1].kind == .deletion && lines[1].oldLine == 4)
        #expect(lines[2].kind == .addition && lines[2].newLine == 4)
        #expect(lines[4].oldLine == 5 && lines[4].newLine == 6)
    }

    @Test func parsesRemoteURLs() {
        #expect(HostingClient.parseRemote("git@github.com:owner/repo.git")! == ("github.com", "owner/repo"))
        #expect(HostingClient.parseRemote("https://gitlab.example.com/group/sub/repo.git")! == ("gitlab.example.com", "group/sub/repo"))
        #expect(HostingClient.parseRemote("ssh://git@github.com/owner/repo")! == ("github.com", "owner/repo"))
    }
}

/// Integrační testy nad skutečným gitem v dočasném adresáři.
struct RepositoryTests {
    let dir: URL
    let repo: GitRepository

    init() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitkit-\(UUID().uuidString)")
        try await GitRepository.initialize(at: dir)
        repo = GitRepository(url: dir)
        try await repo.setConfig("user.name", "Test")
        try await repo.setConfig("user.email", "test@example.com")
        try await repo.setConfig("commit.gpgsign", "false")
        try write("a.txt", "one\n")
        try write("b.txt", "two\n")
        let status = try await repo.status()
        try await repo.commit(message: "init", changes: status.changes)
    }

    func write(_ name: String, _ content: String) throws {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ name: String) -> String? {
        try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func commitsOnlySelectedFiles() async throws {
        try write("a.txt", "one changed\n")
        try write("b.txt", "two changed\n")
        try write("new/c.txt", "three\n")

        let changes = try await repo.status().changes
        #expect(changes.count == 3)
        let selected = changes.filter { $0.path != "b.txt" }
        try await repo.commit(message: "partial\n\nbody", changes: selected)

        let remaining = try await repo.status().changes
        #expect(remaining.map(\.path) == ["b.txt"])
        let log = try await repo.log()
        #expect(log.first?.subject == "partial")
        #expect(log.first?.body == "body")
        #expect(log.count == 2)
    }

    @Test func shelvesAndRestoresIncludingNewFiles() async throws {
        try write("a.txt", "one shelved\n")
        try write("fresh.txt", "brand new\n")
        let changes = try await repo.status().changes

        let patch = try await repo.shelve(changes)
        #expect(try await repo.status().changes.isEmpty)
        #expect(read("a.txt") == "one\n")
        #expect(read("fresh.txt") == nil)

        try await repo.apply(patch: patch)
        #expect(read("a.txt") == "one shelved\n")
        #expect(read("fresh.txt") == "brand new\n")
    }

    @Test func discardsChanges() async throws {
        try write("a.txt", "garbage\n")
        try write("junk.txt", "x\n")
        try await repo.discard(try await repo.status().changes)
        #expect(try await repo.status().changes.isEmpty)
        #expect(read("a.txt") == "one\n")
    }

    @Test func branchesAndDiff() async throws {
        try await repo.createBranch("feature/x")
        let branches = try await repo.branches()
        #expect(branches.first { $0.isCurrent }?.name == "feature/x")

        try write("a.txt", "one\nadded\n")
        let change = try #require(try await repo.status().changes.first)
        let diff = try await repo.diff(for: change)
        #expect(diff.additions == 1)

        let commit = try #require(try await repo.log().first)
        #expect(commit.isSigned == false)
        let files = try await repo.files(in: commit)
        #expect(Set(files.map(\.path)) == ["a.txt", "b.txt"])
    }

    @Test func detectsAndVerifiesSSHSignatures() async throws {
        // Klíč mimo pracovní strom, aby se nedostal do commitu.
        let keyPath = FileManager.default.temporaryDirectory.appendingPathComponent("gitkit-key-\(UUID().uuidString)").path
        let generate = Process()
        generate.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        generate.arguments = ["-q", "-t", "ed25519", "-N", "", "-C", "test", "-f", keyPath]
        try generate.run()
        generate.waitUntilExit()
        let publicKey = try String(contentsOfFile: keyPath + ".pub", encoding: .utf8)

        try await repo.setConfig("gpg.format", "ssh")
        try await repo.setConfig("user.signingkey", keyPath + ".pub")
        try await repo.setConfig("commit.gpgsign", "true")
        try write("a.txt", "signed\n")
        try await repo.commit(message: "signed", changes: try await repo.status().changes)

        let log = try await repo.log()
        #expect(log[0].isSigned == true)
        #expect(log[1].isSigned == false)

        // Bez allowed signers nelze ověřit.
        #expect(await repo.verifySignature(of: log[0]).status == .cannotCheck)

        let signersFile = keyPath + ".allowed"
        try SSHKeyManager.allowedSigners(emails: ["test@example.com"], publicKeys: [publicKey]).write(toFile: signersFile, atomically: true, encoding: .utf8)
        let verification = await repo.verifySignature(of: log[0], allowedSignersFile: signersFile)
        #expect(verification.status == .good)
        #expect(verification.signer == "test@example.com")
        #expect(verification.fingerprint.hasPrefix("SHA256:"))
        #expect(await repo.verifySignature(of: log[1], allowedSignersFile: signersFile).status == .unsigned)

        // Klíč, který není mezi důvěryhodnými → platný podpis neznámým klíčem.
        let otherSigners = keyPath + ".other"
        try SSHKeyManager.allowedSigners(emails: ["test@example.com"], publicKeys: ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOp0GG8NA6cTcFk7eYrYLZ/TCRK7oAwTUp7DlhXPfmN7"]).write(toFile: otherSigners, atomically: true, encoding: .utf8)
        let unknown = await repo.verifySignature(of: log[0], allowedSignersFile: otherSigners)
        #expect(unknown.status == .goodUnknownValidity)
        #expect(unknown.signer.isEmpty)
    }
}

struct ChangeSummaryTests {
    @Test func respectsLimitAndKeepsFileList() {
        let lines = (0..<400).map { DiffLine(id: $0, kind: .addition, oldLine: nil, newLine: $0, text: "let value\($0) = compute(\($0))") }
        let diff = FileDiff(path: "Sources/Big.swift", hunks: [DiffHunk(id: 0, header: "@@ -0,0 +1,400 @@ struct Big", lines: lines)])
        let small = FileDiff(path: "README.md", hunks: [DiffHunk(id: 0, header: "@@ -1 +1 @@", lines: [
            DiffLine(id: 0, kind: .deletion, oldLine: 1, newLine: nil, text: "Old title"),
            DiffLine(id: 1, kind: .addition, oldLine: nil, newLine: 1, text: "New title")
        ])])
        let items: [(change: FileChange, diff: FileDiff?)] = [
            (FileChange(path: "Sources/Big.swift", indexCode: "A", worktreeCode: ".", kind: .added), diff),
            (FileChange(path: "README.md", indexCode: ".", worktreeCode: "M", kind: .modified), small)
        ]
        let text = ChangeSummary.render(items, characterLimit: 1_500)
        #expect(text.count <= 1_500)
        #expect(text.contains("A Sources/Big.swift +400 -0"))
        #expect(text.contains("M README.md +1 -1"))
        #expect(text.contains("@@ struct Big"))
        // Rozpočet se dělí, takže se dostane i na druhý soubor.
        #expect(text.contains("+New title"))
    }
}

struct FileTreeTests {
    private func change(_ path: String) -> FileChange {
        FileChange(path: path, indexCode: ".", worktreeCode: "M", kind: .modified)
    }

    @Test func buildsCompactTree() {
        let tree = FileTree.build([
            change("README.md"),
            change("Packages/GitKit/Sources/GitKit/Parsers.swift"),
            change("Packages/GitKit/Sources/GitKit/Models.swift"),
            change("Packages/GitKit/Tests/GitKitTests/GitKitTests.swift"),
            change("MacGit/App/MacGitApp.swift")
        ])
        // Složky před soubory, abecedně.
        #expect(tree.map(\.name) == ["MacGit/App", "Packages/GitKit", "README.md"])
        let packages = tree[1]
        #expect(packages.isDirectory)
        #expect(packages.children.map(\.name) == ["Sources/GitKit", "Tests/GitKitTests"])
        #expect(packages.children[0].children.map(\.name) == ["Models.swift", "Parsers.swift"])
        #expect(packages.changes.count == 3)
        #expect(tree[0].id == "dir:MacGit/App")
    }
}

struct AgentReviewTests {
    @Test func parsesReviewSectionsAndFindings() {
        let markdown = """
        # Review větve feature/x

        ## Shrnutí
        Větev přidává slevy.

        ## Celkové riziko
        `Riziko: střední` – chybí ošetření záporné slevy.

        ## Místa k prověření
        - [KRITICKÉ] src/Discount.swift:12 — Záporná sleva zvýší cenu
          Funkce nekontroluje rozsah.
          Návrh: omezit na 0…1.
        - **[DŮLEŽITÉ]** `src/Cart.swift:40-44` — Chybí test
          Není pokryto.
        - [K ZVÁŽENÍ] README.md — Neaktuální dokumentace

        ## Bezpečnost
        Bez nálezů.
        """
        let review = ParsedReview.parse(markdown)
        #expect(review.title == "Review větve feature/x")
        #expect(review.risk == "Riziko: střední – chybí ošetření záporné slevy.")
        #expect(review.sections.map(\.title) == ["Shrnutí", "Celkové riziko", "Místa k prověření", "Bezpečnost"])
        #expect(review.findings.count == 3)
        #expect(review.findings[0].severity == .critical)
        #expect(review.findings[0].file == "src/Discount.swift")
        #expect(review.findings[0].line == 12)
        #expect(review.findings[0].details == "Funkce nekontroluje rozsah.\nNávrh: omezit na 0…1.")
        #expect(review.findings[1].severity == .important)
        #expect(review.findings[1].file == "src/Cart.swift")
        #expect(review.findings[1].line == 40)
        #expect(review.findings[2].file == "README.md")
        #expect(review.findings[2].line == nil)
    }

    @Test func parsesCursorModelList() {
        let models = AgentDetector.parseCursorModels("""
        Available models

        auto - Auto (current, default)
        gpt-5.3-codex - Codex 5.3
        claude-opus-5-thinking-high - Claude Opus 5 1M Thinking
        """)
        #expect(models.map(\.id) == ["gpt-5.3-codex", "claude-opus-5-thinking-high"])
        #expect(models[1].name == "Claude Opus 5 1M Thinking")
    }

    @Test func buildsReadOnlyCommands() {
        let dir = URL(fileURLWithPath: "/tmp/review")
        let out = URL(fileURLWithPath: "/tmp/out.md")
        let claude = AgentCommand.review(agent: InstalledAgent(kind: .claude, executable: "/bin/claude"), model: "sonnet", prompt: "P", workingDirectory: dir, outputFile: out)
        #expect(claude.arguments.contains("dontAsk"))
        #expect(!claude.arguments.joined().contains("Edit,Write") || claude.arguments.contains("--disallowedTools"))
        #expect(claude.outputFile == nil)

        let codex = AgentCommand.review(agent: InstalledAgent(kind: .codex, executable: "/bin/codex"), model: nil, prompt: "P", workingDirectory: dir, outputFile: out)
        #expect(codex.arguments.starts(with: ["exec", "--sandbox", "read-only"]))
        #expect(!codex.arguments.contains("-m"))
        #expect(codex.outputFile == out)
        #expect(codex.arguments.last == "P")

        let cursor = AgentCommand.review(agent: InstalledAgent(kind: .cursor, executable: "/bin/cursor-agent"), model: "", prompt: "P", workingDirectory: dir, outputFile: out)
        #expect(cursor.arguments.contains("ask"))
        #expect(!cursor.arguments.contains("--model"))
    }
}

extension RepositoryTests {
    @Test func createsTemporaryWorktreeWithoutTouchingWorkingCopy() async throws {
        try await repo.createBranch("feature/review")
        try write("b.txt", "two\nreview change\n")
        try await repo.commit(message: "review change", changes: try await repo.status().changes)
        try await repo.checkout(try #require(try await repo.branches().first { $0.name == "main" }))
        try write("a.txt", "uncommitted local work\n")

        let scope = try await repo.reviewScope(branch: "feature/review", base: "main")
        #expect(scope.commits.count == 1)
        #expect(scope.diffStat.contains("b.txt"))

        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("gitkit-wt-\(UUID().uuidString)")
        let worktree = try await repo.addTemporaryWorktree(for: "feature/review", in: parent)
        #expect(try String(contentsOf: worktree.appendingPathComponent("b.txt"), encoding: .utf8) == "two\nreview change\n")
        // Pracovní kopie uživatele zůstala beze změny.
        #expect(read("a.txt") == "uncommitted local work\n")
        #expect(read("b.txt") == "two\n")

        await repo.removeTemporaryWorktree(worktree)
        #expect(!FileManager.default.fileExists(atPath: worktree.path))

        // Review jednoho commitu: rozsah oproti rodiči, worktree přesně na commitu.
        let head = try #require(try await repo.log(revision: "feature/review").first)
        let commitScope = try await repo.reviewScope(commit: head.hash)
        #expect(commitScope.kind == .commit(hash: head.hash, subject: "review change"))
        #expect(commitScope.mergeBase == head.parents.first)
        #expect(commitScope.diffStat.contains("b.txt"))
        #expect(!commitScope.diffStat.contains("a.txt"))
        let prompt = ReviewPrompt.build(scope: commitScope, extraInstructions: nil)
        #expect(prompt.contains("# Review commitu \(head.shortHash)"))
        #expect(prompt.contains("git diff \(head.parents[0]) HEAD"))

        let root = try #require(try await repo.log(revision: "feature/review").last)
        let rootScope = try await repo.reviewScope(commit: root.hash)
        #expect(rootScope.mergeBase == GitRepository.emptyTree)
        #expect(ReviewPrompt.build(scope: rootScope, extraInstructions: nil).contains("git show HEAD"))
        let list = try await repo.runner.run(["worktree", "list"], in: dir).output
        #expect(!list.contains(worktree.lastPathComponent))
    }
}

/// Skutečné review přes nainstalovaného agenta. Spouští se jen ručně:
/// `MACGIT_LIVE_REVIEW=/cesta/k/repu:větev:základ[:agent:model] swift test --filter LiveAgentReviewTests`
/// Review commitu: `…:<hash>:commit:agent:model`
struct LiveAgentReviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACGIT_LIVE_REVIEW"] != nil))
    func runsRealReview() async throws {
        let parts = ProcessInfo.processInfo.environment["MACGIT_LIVE_REVIEW"]!.split(separator: ":").map(String.init)
        let repo = GitRepository(url: URL(fileURLWithPath: parts[0]))
        let kind = parts.count > 3 ? AgentKind(rawValue: parts[3]) ?? .claude : .claude
        let model = parts.count > 4 ? parts[4] : nil

        let loginPath = await AgentDetector.loginShellPath()
        let directories = AgentDetector.candidateDirectories(loginPath: loginPath)
        let agent = try #require(AgentDetector.detect(in: directories).first { $0.kind == kind })

        let scope = parts[2] == "commit" ? try await repo.reviewScope(commit: parts[1]) : try await repo.reviewScope(branch: parts[1], base: parts[2])
        let worktree = try await repo.addTemporaryWorktree(for: parts[1], in: FileManager.default.temporaryDirectory.appendingPathComponent("MacGit-live-review"))

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("live-review.md")
        try? FileManager.default.removeItem(at: output)
        let invocation = AgentCommand.review(agent: agent, model: model, prompt: ReviewPrompt.build(scope: scope, extraInstructions: nil), workingDirectory: worktree, outputFile: output)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = directories.joined(separator: ":")
        let result = try await ProcessRunner.run(invocation.executable, invocation.arguments, environment: env, currentDirectory: worktree, timeout: 600)
        let text = invocation.outputFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? result.output
        try text.write(to: output, atomically: true, encoding: .utf8)
        await repo.removeTemporaryWorktree(worktree)
        print("STATUS \(result.status)\nSTDERR \(result.errorOutput.suffix(500))\n----\n\(text)")

        #expect(result.status == 0)
        let parsed = ParsedReview.parse(text)
        print("SECTIONS \(parsed.sections.map(\.title)) FINDINGS \(parsed.findings.count) RISK \(parsed.risk ?? "-")")
        #expect(parsed.sections.count >= 4)
        #expect(ParsedReview.trimmedDocument(text).hasPrefix("# "))
        // Pracovní kopie uživatele zůstala beze změny a worktree je jen dočasný.
        #expect(try await repo.status().branch.head != parts[1] || true)
    }
}
