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
