import Foundation
import GitKit

/// Spouští AI review větví přes CLI agenty a hlídá běžící procesy.
@Observable
final class ReviewCenter {
    private(set) var agents: [InstalledAgent] = []
    private(set) var isDetecting = false
    private(set) var modelsByAgent: [AgentKind: [AgentModel]] = [:]
    private(set) var loadingModels: Set<AgentKind> = []

    private var loginPath: String?
    private var processes: [UUID: Process] = [:]
    private weak var store: AppStore?

    /// Výstupy review – Caches, systém je smí při nedostatku místa smazat.
    let outputDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("cz.svetik.MacGit/Reviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Dočasné pracovní kopie větví.
    let worktreeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacGit-reviews", isDirectory: true)

    init(store: AppStore) {
        self.store = store
        Task { await detectAgents() }
    }

    func isRunning(_ id: UUID) -> Bool { processes[id] != nil }

    // MARK: Detekce

    func detectAgents() async {
        isDetecting = true
        defer { isDetecting = false }
        if loginPath == nil { loginPath = await AgentDetector.loginShellPath() }
        let directories = AgentDetector.candidateDirectories(loginPath: loginPath)
        agents = await Task.detached { AgentDetector.detect(in: directories) }.value
    }

    func agent(_ kind: AgentKind) -> InstalledAgent? {
        agents.first { $0.kind == kind }
    }

    func loadModels(for kind: AgentKind, force: Bool = false) async {
        guard let agent = agent(kind), force || modelsByAgent[kind] == nil, !loadingModels.contains(kind) else { return }
        loadingModels.insert(kind)
        defer { loadingModels.remove(kind) }
        let models = await AgentDetector.models(for: agent, environment: environment())
        modelsByAgent[kind] = models.isEmpty ? kind.fallbackModels : models
    }

    /// Prostředí pro agenty: PATH z přihlašovacího shellu, bez barev a interaktivních prvků.
    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = AgentDetector.candidateDirectories(loginPath: loginPath)
        env["PATH"] = extra.joined(separator: ":")
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        env["CI"] = "1"
        return env
    }

    // MARK: Spuštění

    func startReview(in model: RepositoryModel, target: ReviewTarget, base: String, agentKind: AgentKind, modelID: String?, instructions: String) async {
        guard let agent = agent(agentKind) else {
            model.errorMessage = "\(agentKind.title) není nainstalovaný."
            return
        }
        let repository = model.repository
        let scope: ReviewScope
        let checkoutRevision: String
        do {
            switch target {
            case let .branch(branch):
                scope = try await repository.reviewScope(branch: branch.name, base: base)
                checkoutRevision = branch.fullName
                guard !scope.commits.isEmpty else {
                    model.errorMessage = "Větev \(branch.name) neobsahuje oproti \(base) žádné commity."
                    return
                }
            case let .commit(commit):
                scope = try await repository.reviewScope(commit: commit.hash)
                checkoutRevision = commit.hash
            }
        } catch {
            model.errorMessage = "Nepodařilo se určit rozsah review: \(error.localizedDescription)"
            return
        }

        let id = UUID()
        let projectDirectory = outputDirectory.appendingPathComponent(model.project.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        var record = ReviewRecord(
            id: id,
            branch: scope.branch,
            baseBranch: scope.baseBranch,
            headCommit: {
                switch target {
                case let .branch(branch): branch.shortHash
                case let .commit(commit): commit.shortHash
                }
            }(),
            agent: agentKind,
            model: modelID,
            outputPath: projectDirectory.appendingPathComponent("\(id.uuidString).md").path,
            logPath: projectDirectory.appendingPathComponent("\(id.uuidString).log").path
        )
        if case let .commit(commit) = target {
            record.commitHash = commit.hash
            record.commitSubject = commit.subject
        }
        model.workspace.reviews.insert(record, at: 0)

        let worktree: URL
        do {
            worktree = try await repository.addTemporaryWorktree(for: checkoutRevision, in: worktreeDirectory)
        } catch {
            record.status = .failed
            record.errorMessage = "Nepodařilo se připravit dočasnou kopii: \(error.localizedDescription)"
            record.finishedAt = .now
            update(record, in: model)
            return
        }

        let prompt = ReviewPrompt.build(scope: scope, extraInstructions: instructions)
        let invocation = AgentCommand.review(agent: agent, model: modelID, prompt: prompt, workingDirectory: worktree, outputFile: URL(fileURLWithPath: record.outputPath))

        FileManager.default.createFile(atPath: record.outputPath, contents: nil)
        FileManager.default.createFile(atPath: record.logPath, contents: nil)
        guard let stdout = FileHandle(forWritingAtPath: invocation.outputFile == nil ? record.outputPath : record.logPath),
              let stderr = FileHandle(forWritingAtPath: record.logPath) else { return }
        if invocation.outputFile != nil { stdout.seekToEndOfFile() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = worktree
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        let projectID = model.project.id
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            try? stdout.close()
            try? stderr.close()
            Task { @MainActor in
                await self?.finish(reviewID: id, projectID: projectID, status: status, reason: reason, worktree: worktree)
            }
        }

        do {
            try process.run()
            processes[id] = process
        } catch {
            await repository.removeTemporaryWorktree(worktree)
            record.status = .failed
            record.errorMessage = "Nepodařilo se spustit \(agent.kind.title): \(error.localizedDescription)"
            record.finishedAt = .now
            update(record, in: model)
        }
    }

    func cancel(_ id: UUID) {
        guard let process = processes[id] else { return }
        cancelled.insert(id)
        process.terminate()
        // Agenti spouštějí podprocesy – když nereaguje na SIGTERM, po chvíli ho ukončíme natvrdo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private var cancelled: Set<UUID> = []

    private func finish(reviewID: UUID, projectID: UUID, status: Int32, reason: Process.TerminationReason, worktree: URL) async {
        processes[reviewID] = nil
        guard let store, let project = store.project(projectID) else { return }
        let model = store.model(for: project)
        await model.repository.removeTemporaryWorktree(worktree)
        guard var record = model.workspace.reviews.first(where: { $0.id == reviewID }) else { return }

        record.finishedAt = .now
        let output = (try? String(contentsOfFile: record.outputPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cancelled.remove(reviewID) != nil {
            record.status = .cancelled
        } else if status == 0 && !output.isEmpty {
            record.status = .completed
        } else {
            record.status = .failed
            let log = (try? String(contentsOfFile: record.logPath, encoding: .utf8)) ?? ""
            let tail = log.split(separator: "\n").suffix(6).joined(separator: "\n")
            record.errorMessage = tail.isEmpty ? "Agent skončil s kódem \(status) a nevrátil žádný výstup." : tail
        }
        update(record, in: model)
        if record.status == .completed { model.showToast("AI review – \(record.targetTitle) dokončeno") }
    }

    private func update(_ record: ReviewRecord, in model: RepositoryModel) {
        if let index = model.workspace.reviews.firstIndex(where: { $0.id == record.id }) {
            model.workspace.reviews[index] = record
        }
    }

    func delete(_ record: ReviewRecord, in model: RepositoryModel) {
        cancel(record.id)
        try? FileManager.default.removeItem(atPath: record.outputPath)
        try? FileManager.default.removeItem(atPath: record.logPath)
        model.workspace.reviews.removeAll { $0.id == record.id }
    }

    /// Review, která běžela při ukončení aplikace, označí jako přerušená.
    static func markInterrupted(_ workspace: inout ProjectWorkspace) {
        for index in workspace.reviews.indices where workspace.reviews[index].status == .running {
            workspace.reviews[index].status = .failed
            workspace.reviews[index].errorMessage = "Review bylo přerušeno ukončením aplikace."
        }
    }
}
