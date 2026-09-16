import Foundation

/// Operace nad jedním pracovním adresářem repozitáře.
public struct GitRepository: Sendable {
    public static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    public let url: URL
    public var runner: GitRunner
    /// Kontext s přihlašovacími údaji – použije se jen u síťových operací.
    public var networkContext: GitContext

    public init(url: URL, runner: GitRunner = GitRunner(), networkContext: GitContext = .none) {
        self.url = url
        self.runner = runner
        self.networkContext = networkContext
    }

    @discardableResult
    func git(_ args: [String], input: Data? = nil, network: Bool = false, allowFailure: Bool = false) async throws -> GitResult {
        try await runner.run(args, in: url, context: network ? networkContext : .none, input: input, allowFailure: allowFailure)
    }

    // MARK: Discovery

    public static func topLevel(of directory: URL, runner: GitRunner = GitRunner()) async -> URL? {
        guard let result = try? await runner.run(["rev-parse", "--show-toplevel"], in: directory),
              case let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    public static func initialize(at directory: URL, runner: GitRunner = GitRunner(), defaultBranch: String = "main") async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await runner.run(["init", "-b", defaultBranch], in: directory)
    }

    public static func clone(url remoteURL: String, to destination: URL, context: GitContext, runner: GitRunner = GitRunner()) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await runner.run(["clone", "--", remoteURL, destination.path], in: destination.deletingLastPathComponent(), context: context)
    }

    // MARK: Status & diff

    public func status() async throws -> StatusSnapshot {
        let result = try await git(["--no-optional-locks", "status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all", "--find-renames"])
        return GitParsers.parseStatus(result.stdout)
    }

    public func hasHead() async -> Bool {
        (try? await git(["rev-parse", "--verify", "--quiet", "HEAD"]).status == 0) ?? false
    }

    private func baseRevision() async -> String {
        await hasHead() ? "HEAD" : Self.emptyTree
    }

    public func diff(for change: FileChange) async throws -> FileDiff {
        if change.isUntracked {
            let fileURL = url.appendingPathComponent(change.path)
            let data = (try? Data(contentsOf: fileURL, options: .mappedIfSafe)) ?? Data()
            if data.prefix(8000).contains(0) { return FileDiff(path: change.path, isBinary: true) }
            if data.count > 2_000_000 { return FileDiff(path: change.path, isBinary: true) }
            return GitParsers.additionDiff(for: String(decoding: data, as: UTF8.self), path: change.path)
        }
        var paths = [change.path]
        if let original = change.originalPath { paths.insert(original, at: 0) }
        let base = await baseRevision()
        let result = try await git(["diff", base, "--no-ext-diff", "--find-renames", "--"] + paths)
        return GitParsers.parseDiff(result.output, path: change.path)
    }

    // MARK: Commit

    /// Commitne pouze vybrané soubory, ostatní obsah indexu zůstane nedotčen.
    public func commit(message: String, changes: [FileChange], amend: Bool = false, signOff: Bool = false) async throws {
        let untracked = changes.filter(\.isUntracked).map(\.path)
        if !untracked.isEmpty {
            try await git(["add", "--"] + untracked)
        }
        var args = ["commit", "-F", "-"]
        if amend { args.append("--amend") }
        if signOff { args.append("--signoff") }
        let paths = Array(Set(changes.flatMap { [$0.path] + ($0.originalPath.map { [$0] } ?? []) })).sorted()
        if !paths.isEmpty {
            args += ["--only", "--"] + paths
        } else if !amend {
            throw GitError(arguments: args, status: 1, message: "Nejsou vybrány žádné soubory ke commitu.")
        }
        do {
            try await git(args, input: Data(message.utf8))
        } catch {
            if !untracked.isEmpty { _ = try? await git(["reset", "-q", "--"] + untracked, allowFailure: true) }
            throw error
        }
    }

    public func lastCommitMessage() async -> String? {
        guard let result = try? await git(["log", "-1", "--format=%B"]) else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Discard & shelf

    /// Vrátí soubory do stavu v HEAD (nové soubory smaže).
    public func discard(_ changes: [FileChange]) async throws {
        let untracked = changes.filter(\.isUntracked)
        let tracked = changes.filter { !$0.isUntracked }

        for change in untracked {
            _ = try? await git(["rm", "--cached", "-q", "--", change.path], allowFailure: true)
            try? FileManager.default.removeItem(at: url.appendingPathComponent(change.path))
        }
        guard !tracked.isEmpty else { return }

        let newInIndex = tracked.filter { $0.indexCode == "A" }
        for change in newInIndex {
            try await git(["rm", "--cached", "-q", "--force", "--", change.path])
            try? FileManager.default.removeItem(at: url.appendingPathComponent(change.path))
        }
        let rest = tracked.filter { $0.indexCode != "A" }
        let paths = Array(Set(rest.flatMap { [$0.path] + ($0.originalPath.map { [$0] } ?? []) }))
        guard !paths.isEmpty else { return }
        if await hasHead() {
            try await git(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + paths)
        } else {
            try await git(["rm", "--cached", "-q", "--force", "--"] + paths, allowFailure: true)
        }
    }

    /// Vytvoří binární patch vybraných změn (včetně nových souborů).
    public func patch(for changes: [FileChange]) async throws -> Data {
        let untracked = changes.filter(\.isUntracked).map(\.path)
        if !untracked.isEmpty {
            try await git(["add", "--intent-to-add", "--"] + untracked)
        }
        let paths = Array(Set(changes.flatMap { [$0.path] + ($0.originalPath.map { [$0] } ?? []) })).sorted()
        let base = await baseRevision()
        let result = try await git(["diff", base, "--binary", "--no-ext-diff", "--find-renames", "--"] + paths)
        return result.stdout
    }

    /// Odloží změny: vrátí patch a změny z pracovního stromu odstraní.
    public func shelve(_ changes: [FileChange]) async throws -> Data {
        let data = try await patch(for: changes)
        let asTracked = changes.map { change -> FileChange in
            var copy = change
            if change.isUntracked { copy.kind = .added; copy.indexCode = "A" }
            return copy
        }
        try await discard(asTracked)
        return data
    }

    public func apply(patch: Data) async throws {
        let first = try await git(["apply", "--whitespace=nowarn", "-"], input: patch, allowFailure: true)
        if first.status == 0 { return }
        try await git(["apply", "--3way", "--whitespace=nowarn", "-"], input: patch)
    }

    public func checkPatch(_ patch: Data) async -> Bool {
        let result = try? await git(["apply", "--check", "-"], input: patch, allowFailure: true)
        return result?.status == 0
    }

    // MARK: History

    public func log(limit: Int = 300, skip: Int = 0, revision: String? = nil) async throws -> [Commit] {
        guard await hasHead() else { return [] }
        var args = ["log", "--max-count=\(limit)", "--skip=\(skip)", "--date-order", "--pretty=format:\(GitParsers.logFormat)"]
        args.append(revision ?? "HEAD")
        let result = try await git(args)
        return GitParsers.parseLog(result.output)
    }

    public func files(in commit: Commit) async throws -> [CommitFile] {
        let result = try await git(["show", "--name-status", "--format=", "--find-renames", "--first-parent", commit.hash])
        return GitParsers.parseNameStatus(result.output)
    }

    public func diff(of file: CommitFile, in commit: Commit) async throws -> FileDiff {
        var paths = [file.path]
        if let original = file.originalPath { paths.insert(original, at: 0) }
        let result = try await git(["show", "--format=", "--no-ext-diff", "--find-renames", "--first-parent", commit.hash, "--"] + paths)
        return GitParsers.parseDiff(result.output, path: file.path)
    }

    // MARK: Branches

    public func branches() async throws -> [Branch] {
        let result = try await git(["for-each-ref", "--sort=-committerdate", "--format=\(GitParsers.branchFormat)", "refs/heads", "refs/remotes"])
        return GitParsers.parseBranches(result.output)
    }

    public func checkout(_ branch: Branch) async throws {
        if branch.isRemote {
            let locals = try await branches().filter { !$0.isRemote }
            if locals.contains(where: { $0.name == branch.localName }) {
                try await git(["switch", branch.localName])
            } else {
                try await git(["switch", "--track", branch.name])
            }
        } else {
            try await git(["switch", branch.name])
        }
    }

    public func createBranch(_ name: String, from start: String? = nil, checkout: Bool = true) async throws {
        if checkout {
            try await git(["switch", "-c", name] + (start.map { [$0] } ?? []))
        } else {
            try await git(["branch", name] + (start.map { [$0] } ?? []))
        }
    }

    public func deleteBranch(_ branch: Branch, force: Bool = false) async throws {
        if branch.isRemote {
            let parts = branch.name.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            try await git(["push", parts[0], "--delete", parts[1]], network: true)
        } else {
            try await git(["branch", force ? "-D" : "-d", branch.name])
        }
    }

    public func merge(_ branch: Branch) async throws {
        try await git(["merge", "--no-edit", branch.name])
    }

    public func renameBranch(_ branch: Branch, to newName: String) async throws {
        try await git(["branch", "-m", branch.name, newName])
    }

    // MARK: Network

    public func fetch() async throws {
        try await git(["fetch", "--all", "--prune"], network: true)
    }

    public func pull(rebase: Bool) async throws {
        try await git(["pull", rebase ? "--rebase" : "--no-rebase"], network: true)
    }

    public func push(branch: BranchStatus, remote: String = "origin", force: Bool = false) async throws {
        var args = ["push"]
        if force { args.append("--force-with-lease") }
        if branch.upstream == nil, let head = branch.head {
            args += ["--set-upstream", remote, head]
        }
        try await git(args, network: true)
    }

    // MARK: Remotes

    public func remotes() async throws -> [Remote] {
        GitParsers.parseRemotes(try await git(["remote", "-v"]).output)
    }

    public func addRemote(name: String, url remoteURL: String) async throws {
        try await git(["remote", "add", name, remoteURL])
    }

    public func setRemoteURL(name: String, url remoteURL: String) async throws {
        try await git(["remote", "set-url", name, remoteURL])
    }

    public func removeRemote(name: String) async throws {
        try await git(["remote", "remove", name])
    }

    // MARK: Config

    public enum ConfigScope: String, Sendable { case local, global }

    public func config(_ key: String, scope: ConfigScope = .local) async -> String? {
        guard let result = try? await git(["config", "--\(scope.rawValue)", "--get", key], allowFailure: true),
              result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Efektivní hodnota (local → global → system).
    public func effectiveConfig(_ key: String) async -> String? {
        guard let result = try? await git(["config", "--get", key], allowFailure: true), result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func setConfig(_ key: String, _ value: String?, scope: ConfigScope = .local) async throws {
        if let value, !value.isEmpty {
            try await git(["config", "--\(scope.rawValue)", key, value])
        } else {
            try await git(["config", "--\(scope.rawValue)", "--unset", key], allowFailure: true)
        }
    }

    public static func globalConfig(_ key: String, runner: GitRunner = GitRunner()) async -> String? {
        guard let result = try? await runner.run(["config", "--global", "--get", key], in: nil, allowFailure: true),
              result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func setGlobalConfig(_ key: String, _ value: String?, runner: GitRunner = GitRunner()) async throws {
        if let value, !value.isEmpty {
            try await runner.run(["config", "--global", key, value], in: nil)
        } else {
            try await runner.run(["config", "--global", "--unset", key], in: nil, allowFailure: true)
        }
    }
}
