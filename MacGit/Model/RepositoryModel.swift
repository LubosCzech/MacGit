import Foundation
import AppKit
import GitKit

struct RepositoryConfig: Equatable {
    var localName = ""
    var localEmail = ""
    var effectiveName = ""
    var effectiveEmail = ""
    var signCommits = false
    var signingFormat = "openpgp"
    var signingKey = ""
}

/// Stav jednoho otevřeného repozitáře.
@Observable
final class RepositoryModel {
    enum Section: String, CaseIterable, Identifiable {
        case changes, history, branches, shelf
        var id: String { rawValue }
        var title: String {
            switch self {
            case .changes: "Změny"
            case .history: "Historie"
            case .branches: "Větve"
            case .shelf: "Shelf"
            }
        }
        var symbol: String {
            switch self {
            case .changes: "square.and.pencil"
            case .history: "clock"
            case .branches: "arrow.triangle.branch"
            case .shelf: "archivebox"
            }
        }
        var searchPrompt: String {
            switch self {
            case .changes: "Filtrovat soubory"
            case .history: "Hledat commity"
            case .branches: "Hledat větve"
            case .shelf: "Hledat ve shelfu"
            }
        }
    }

    enum InspectorTab: String, CaseIterable, Identifiable {
        case file, commit, repository
        var id: String { rawValue }
        var title: String {
            switch self {
            case .file: "Soubor"
            case .commit: "Commit"
            case .repository: "Repozitář"
            }
        }
    }

    private(set) var project: Project
    private weak var store: AppStore?
    private(set) var repository: GitRepository
    private var watcher: RepositoryWatcher?

    var section: Section = .changes {
        didSet {
            guard oldValue != section else { return }
            switch section {
            case .changes: if inspectorTab == .commit { inspectorTab = .file }
            case .history: if inspectorTab == .file { inspectorTab = .commit }
            default: break
            }
            if section == .history { Task { await loadHistory() } }
        }
    }
    var inspectorTab: InspectorTab = .file
    /// Filtr z vyhledávacího pole v toolbaru – platí pro aktuální sekci.
    var searchText = ""
    var selectedChangePaths: Set<String> = [] {
        didSet { selectedChangePath = selectedChangePaths.count == 1 ? selectedChangePaths.first : nil }
    }
    var selectedBranchID: String? { didSet { if oldValue != selectedBranchID { Task { await loadBranchCommits() } } } }
    var branchCommits: [Commit] = []
    var selectedShelfID: UUID?
    var status = StatusSnapshot()
    var workspace: ProjectWorkspace { didSet { scheduleWorkspaceSave() } }
    var config = RepositoryConfig()

    var selectedChangePath: String? { didSet { if oldValue != selectedChangePath { Task { await loadDiff() } } } }
    var currentDiff: FileDiff?
    var amend = false { didSet { if amend && workspace.draftMessage.isEmpty { Task { await prefillAmend() } } } }

    var branches: [Branch] = []
    var remotes: [Remote] = []
    var commits: [Commit] = []
    var selectedCommitID: String? { didSet { if oldValue != selectedCommitID { Task { await loadCommitFiles() } } } }
    var commitFiles: [CommitFile] = []
    var selectedCommitFileID: String? { didSet { if oldValue != selectedCommitFileID { Task { await loadCommitDiff() } } } }
    var commitDiff: FileDiff?
    /// Ověření podpisu vybraného commitu (načítá se líně).
    var signatureVerification: SignatureVerification?

    /// Operace selhala kvůli zamčenému SSH klíči – UI se zeptá na passphrase a zkusí to znovu.
    var sshUnlockRequest: SSHUnlockRequest?
    /// Dialog pro zadání textu vyvolaný z toolbaru nebo menu.
    var pendingPrompt: TextPrompt?
    var branchToDelete: Branch?
    /// Cíl (větev/commit), pro který se otevírá dialog AI review.
    var reviewSheetTarget: ReviewTarget?
    var shelfToDelete: Shelf?
    var busyTitle: String?
    var errorMessage: String?
    /// Poslední dokončená operace – zobrazuje se v podtitulu okna.
    var lastActivity: (text: String, date: Date)?
    private(set) var hasLoaded = false
    private var saveTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(project: Project, store: AppStore) {
        self.project = project
        self.store = store
        let url = store.workspaceURL(for: project.id)
        var loaded = (try? JSONDecoder().decode(ProjectWorkspace.self, from: Data(contentsOf: url))) ?? ProjectWorkspace()
        ReviewCenter.markInterrupted(&loaded)
        workspace = loaded
        repository = GitRepository(url: project.url, runner: store.runner, networkContext: store.context(for: project.auth, projectID: project.id))
    }

    func projectDidChange(_ project: Project) {
        let pathChanged = project.path != self.project.path
        self.project = project
        refreshCredentials()
        if pathChanged {
            repository = GitRepository(url: project.url, runner: repository.runner, networkContext: repository.networkContext)
            deactivate()
            activate()
        }
    }

    func refreshCredentials() {
        guard let store else { return }
        repository.networkContext = store.context(for: project.auth, projectID: project.id)
    }

    // MARK: Lifecycle

    func activate() {
        if watcher == nil {
            watcher = RepositoryWatcher(url: project.url) { [weak self] in
                self?.scheduleRefresh()
            }
            watcher?.start()
        }
        scheduleRefresh()
    }

    func deactivate() {
        watcher?.stop()
        watcher = nil
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }

    func refresh() async {
        guard project.exists else {
            errorMessage = "Repozitář \(project.path) nebyl nalezen."
            return
        }
        do {
            async let statusResult = repository.status()
            async let branchResult = repository.branches()
            async let remoteResult = repository.remotes()
            let (newStatus, newBranches, newRemotes) = try await (statusResult, branchResult, remoteResult)
            guard !Task.isCancelled else { return }
            status = newStatus
            branches = newBranches
            remotes = newRemotes
            pruneWorkspace()
            let currentPaths = Set(newStatus.changes.map(\.path))
            if !selectedChangePaths.isSubset(of: currentPaths) {
                selectedChangePaths = selectedChangePaths.intersection(currentPaths)
            }
            if let path = selectedChangePath, !currentPaths.contains(path) {
                selectedChangePath = nil
                currentDiff = nil
            } else if selectedChangePath != nil {
                await loadDiff()
            }
            if !hasLoaded {
                hasLoaded = true
                await loadConfig()
            }
            if section == .history || commits.isEmpty { await loadHistory() }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    // MARK: Workspace persistence

    private func scheduleWorkspaceSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, let store = self.store else { return }
            let data = try? JSONEncoder().encode(self.workspace)
            try? data?.write(to: store.workspaceURL(for: self.project.id), options: .atomic)
        }
    }

    /// Odstraní přiřazení souborů, které už nejsou změněné.
    private func pruneWorkspace() {
        let paths = Set(status.changes.map(\.path))
        let staleAssignments = workspace.assignments.keys.filter { !paths.contains($0) }
        let staleExcluded = workspace.excludedPaths.subtracting(paths)
        let staleIncluded = workspace.includedPaths.subtracting(paths)
        guard !staleAssignments.isEmpty || !staleExcluded.isEmpty || !staleIncluded.isEmpty else { return }
        for key in staleAssignments { workspace.assignments[key] = nil }
        workspace.excludedPaths.subtract(staleExcluded)
        workspace.includedPaths.subtract(staleIncluded)
    }

    // MARK: Changelists

    var activeChangelist: Changelist {
        workspace.changelists.first { $0.id == workspace.activeChangelistID } ?? workspace.changelists[0]
    }

    func changelistID(for path: String) -> UUID {
        if let id = workspace.assignments[path], workspace.changelists.contains(where: { $0.id == id }) { return id }
        return workspace.activeChangelistID
    }

    func changes(in changelist: Changelist) -> [FileChange] {
        status.changes.filter { changelistID(for: $0.path) == changelist.id }
    }

    func isIncluded(_ change: FileChange) -> Bool {
        if changelistID(for: change.path) == workspace.activeChangelistID {
            return !workspace.excludedPaths.contains(change.path)
        }
        return workspace.includedPaths.contains(change.path)
    }

    func setIncluded(_ included: Bool, for changes: [FileChange]) {
        for change in changes {
            if changelistID(for: change.path) == workspace.activeChangelistID {
                if included { workspace.excludedPaths.remove(change.path) } else { workspace.excludedPaths.insert(change.path) }
            } else {
                if included { workspace.includedPaths.insert(change.path) } else { workspace.includedPaths.remove(change.path) }
            }
        }
    }

    var includedChanges: [FileChange] {
        status.changes.filter(isIncluded)
    }

    func move(paths: [String], to changelistID: UUID) {
        for path in paths {
            workspace.assignments[path] = changelistID
            workspace.excludedPaths.remove(path)
            workspace.includedPaths.remove(path)
        }
    }

    @discardableResult
    func addChangelist(named name: String) -> Changelist {
        let list = Changelist(name: name)
        workspace.changelists.append(list)
        return list
    }

    func setActive(_ changelist: Changelist) {
        // Soubory bez explicitního přiřazení patří aktivnímu listu – zafixujeme je u původního.
        let previous = workspace.activeChangelistID
        for change in status.changes where workspace.assignments[change.path] == nil {
            workspace.assignments[change.path] = previous
        }
        workspace.activeChangelistID = changelist.id
        workspace.excludedPaths.removeAll()
        workspace.includedPaths.removeAll()
    }

    func rename(_ changelist: Changelist, to name: String) {
        guard let index = workspace.changelists.firstIndex(where: { $0.id == changelist.id }) else { return }
        workspace.changelists[index].name = name
    }

    func delete(_ changelist: Changelist) {
        guard workspace.changelists.count > 1 else { return }
        let fallback = workspace.changelists.first { $0.id != changelist.id }!
        for (path, id) in workspace.assignments where id == changelist.id {
            workspace.assignments[path] = fallback.id
        }
        workspace.changelists.removeAll { $0.id == changelist.id }
        if workspace.activeChangelistID == changelist.id { workspace.activeChangelistID = fallback.id }
    }

    // MARK: Diff

    var selectedChange: FileChange? {
        status.changes.first { $0.path == selectedChangePath }
    }

    func loadDiff() async {
        guard let change = selectedChange else { currentDiff = nil; return }
        currentDiff = try? await repository.diff(for: change)
    }

    // MARK: Operations

    private func perform(_ title: String, success: String? = nil, _ work: @escaping () async throws -> Void) async {
        busyTitle = title
        do {
            try await work()
            busyTitle = nil
            if let success { showToast(success) }
        } catch {
            busyTitle = nil
            if SSHKeyManager.isKeyUnavailable(error), let request = makeUnlockRequest(error: error, title: title, success: success, work: work) {
                sshUnlockRequest = request
            } else {
                errorMessage = error.localizedDescription
            }
        }
        await refresh()
    }

    private func makeUnlockRequest(error: Error, title: String, success: String?, work: @escaping () async throws -> Void) -> SSHUnlockRequest? {
        let keyPath: String?
        switch project.auth {
        case .system: keyPath = nil
        case let .sshKey(path): keyPath = path
        case .account, .password:
            // Podepisování commitů SSH klíčem selže i při HTTPS přihlášení.
            guard config.signCommits, config.signingFormat == "ssh" else { return nil }
            keyPath = nil
        }
        let signingKey = config.signCommits && config.signingFormat == "ssh" && config.signingKey.hasSuffix(".pub")
            ? String(config.signingKey.dropLast(4)) : nil
        return SSHUnlockRequest(
            message: error.localizedDescription,
            suggestedKeyPath: keyPath ?? signingKey,
            retry: { [weak self] in await self?.perform(title, success: success, work) }
        )
    }

    /// Odemkne klíč (ssh-agent + Klíčenka macOS) a zopakuje původní operaci.
    func unlock(_ request: SSHUnlockRequest, keyPath: String, passphrase: String, storeInKeychain: Bool) async throws {
        guard let store else { return }
        try await SSHKeyManager.addToAgent(keyPath, passphrase: passphrase, askpassPath: store.askpassPath, storeInKeychain: storeInKeychain)
        if case let .sshKey(path) = project.auth, path == keyPath {
            Keychain.set(passphrase, for: Keychain.sshPassphraseKey(path))
            refreshCredentials()
        }
        sshUnlockRequest = nil
        await request.retry()
    }

    func showToast(_ message: String) {
        lastActivity = (message, .now)
    }

    /// Podtitul okna: probíhající operace, jinak poslední výsledek.
    func statusLine(now: Date) -> String {
        if let busyTitle { return busyTitle }
        var parts: [String] = []
        let branch = status.branch
        if branch.ahead > 0 { parts.append("↑\(branch.ahead)") }
        if branch.behind > 0 { parts.append("↓\(branch.behind)") }
        if let activity = lastActivity {
            let relative = activity.date.formatted(.relative(presentation: .named, unitsStyle: .wide))
            parts.append(now.timeIntervalSince(activity.date) < 60 ? "\(activity.text) právě teď" : "\(activity.text) \(relative)")
        } else if !status.changes.isEmpty {
            parts.append("\(status.changes.count) změn")
        } else if hasLoaded {
            parts.append("Bez změn")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Commit message

    /// Shrnutí = první řádek zprávy.
    var draftSummary: String {
        get { workspace.draftMessage.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "" }
        set { workspace.draftMessage = Self.composeMessage(summary: newValue.replacingOccurrences(of: "\n", with: " "), description: draftDescription) }
    }

    /// Popis = zbytek zprávy za prázdným řádkem.
    var draftDescription: String {
        get {
            let parts = workspace.draftMessage.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count > 1 else { return "" }
            return String(parts[1].drop { $0 == "\n" })
        }
        set { workspace.draftMessage = Self.composeMessage(summary: draftSummary, description: newValue) }
    }

    static func composeMessage(summary: String, description: String) -> String {
        description.isEmpty ? summary : summary + "\n\n" + description
    }

    var canCommit: Bool {
        !draftSummary.trimmingCharacters(in: .whitespaces).isEmpty
            && (!includedChanges.isEmpty || amend)
            && busyTitle == nil
    }

    func commit(andPush: Bool) async {
        let message = workspace.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let changes = includedChanges
        let isAmend = amend
        await perform(andPush ? "Commit a push…" : "Commit…", success: andPush ? "Commitnuto a pushnuto" : "Commitnuto \(changes.count) souborů") { [self] in
            try await repository.commit(message: message, changes: changes, amend: isAmend)
            workspace.draftMessage = ""
            amend = false
            if andPush {
                let branch = try await repository.status().branch
                try await repository.push(branch: branch, force: isAmend && branch.ahead == 0)
            }
        }
    }

    // MARK: AI návrh zprávy

    var isSuggestingMessage = false
    private var suggestionTask: Task<Void, Never>?

    var canSuggestMessage: Bool {
        !isSuggestingMessage && !includedChanges.isEmpty && CommitMessageGenerator.status == .available
    }

    /// Navrhne shrnutí a popis z vybraných změn (Apple Intelligence na zařízení).
    func suggestCommitMessage() {
        let changes = includedChanges
        guard !changes.isEmpty, !isSuggestingMessage else { return }
        if case let .unavailable(reason) = CommitMessageGenerator.status {
            errorMessage = reason
            return
        }
        let previous = workspace.draftMessage
        isSuggestingMessage = true
        suggestionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSuggestingMessage = false }
            let summary = await repository.changeSummary(for: changes, characterLimit: CommitMessageGenerator.summaryCharacterLimit)
            let subjects = await repository.recentSubjects()
            do {
                let result = try await CommitMessageGenerator.suggest(summary: summary, branch: status.branch.head, recentSubjects: subjects) { [weak self] partialSummary, partialBody in
                    guard let self, !Task.isCancelled else { return }
                    self.workspace.draftMessage = Self.composeMessage(summary: partialSummary, description: partialBody)
                }
                guard !Task.isCancelled else { return }
                workspace.draftMessage = result.summary.isEmpty ? previous : Self.composeMessage(summary: result.summary, description: result.body)
            } catch is CancellationError {
                workspace.draftMessage = previous
            } catch {
                workspace.draftMessage = previous
                errorMessage = CommitMessageGenerator.message(for: error)
            }
        }
    }

    func cancelSuggestion() {
        suggestionTask?.cancel()
    }

    private func prefillAmend() async {
        if let message = await repository.lastCommitMessage(), workspace.draftMessage.isEmpty {
            workspace.draftMessage = message
        }
    }

    func discard(_ changes: [FileChange]) async {
        await perform("Zahazuji změny…", success: "Změny zahozeny") { [self] in
            try await repository.discard(changes)
        }
    }

    func shelve(_ changes: [FileChange], name: String) async {
        guard let store else { return }
        await perform("Odkládám do shelfu…", success: "Uloženo do shelfu „\(name)“") { [self] in
            let shelf = Shelf(name: name, branch: status.branch.head, files: changes.map(\.path))
            let patch = try await repository.patch(for: changes)
            try patch.write(to: store.shelfDirectory(for: project.id).appendingPathComponent(shelf.patchFileName))
            let untrackedAsAdded = changes.map { change -> FileChange in
                var copy = change
                if change.isUntracked { copy.kind = .added; copy.indexCode = "A" }
                return copy
            }
            try await repository.discard(untrackedAsAdded)
            workspace.shelves.insert(shelf, at: 0)
        }
    }

    func patchData(for shelf: Shelf) -> Data? {
        guard let store else { return nil }
        return try? Data(contentsOf: store.shelfDirectory(for: project.id).appendingPathComponent(shelf.patchFileName))
    }

    func unshelve(_ shelf: Shelf, keep: Bool) async {
        guard let data = patchData(for: shelf) else {
            errorMessage = "Patch pro shelf „\(shelf.name)“ chybí."
            return
        }
        await perform("Obnovuji ze shelfu…", success: "Obnoveno „\(shelf.name)“") { [self] in
            try await repository.apply(patch: data)
            // Obnovené soubory vrátíme do changelistu se jménem shelfu.
            let list = workspace.changelists.first { $0.name == shelf.name } ?? addChangelist(named: shelf.name)
            move(paths: shelf.files, to: list.id)
            if !keep { deleteShelf(shelf) }
        }
    }

    func deleteShelf(_ shelf: Shelf) {
        if let store {
            try? FileManager.default.removeItem(at: store.shelfDirectory(for: project.id).appendingPathComponent(shelf.patchFileName))
        }
        workspace.shelves.removeAll { $0.id == shelf.id }
    }

    func fetch() async {
        refreshCredentials()
        await perform("Fetch…", success: "Fetch dokončen") { [self] in try await repository.fetch() }
    }

    func pull(rebase: Bool = false) async {
        refreshCredentials()
        await perform("Pull…", success: "Pull dokončen") { [self] in try await repository.pull(rebase: rebase) }
    }

    func push(force: Bool = false) async {
        refreshCredentials()
        await perform("Push…", success: "Push dokončen") { [self] in
            try await repository.push(branch: status.branch, force: force)
        }
    }

    func checkout(_ branch: Branch) async {
        await perform("Přepínám na \(branch.localName)…", success: "Přepnuto na \(branch.localName)") { [self] in
            try await repository.checkout(branch)
        }
    }

    func createBranch(_ name: String, from start: String?, checkout: Bool) async {
        await perform("Vytvářím větev…", success: "Větev \(name) vytvořena") { [self] in
            try await repository.createBranch(name, from: start, checkout: checkout)
        }
    }

    func promptNewBranch(from start: Branch?) {
        pendingPrompt = TextPrompt(
            title: "Nová větev",
            message: start.map { "Vytvoří se z větve \($0.name) a přepne se na ni." } ?? "Vytvoří se z aktuálního HEAD a přepne se na ni.",
            placeholder: "feature/nazev",
            confirmTitle: "Vytvořit"
        ) { [weak self] name in
            Task { await self?.createBranch(name, from: start?.name, checkout: true) }
        }
    }

    func promptShelve(_ changes: [FileChange], suggestedName: String) {
        pendingPrompt = TextPrompt(
            title: "Odložit do shelfu",
            message: "Změny v \(changes.count) souborech se uloží stranou a z pracovní složky zmizí.",
            placeholder: "Název",
            initialValue: suggestedName,
            confirmTitle: "Odložit"
        ) { [weak self] name in
            Task { await self?.shelve(changes, name: name) }
        }
    }

    func deleteBranch(_ branch: Branch, force: Bool) async {
        refreshCredentials()
        await perform("Mažu větev…", success: "Větev \(branch.name) smazána") { [self] in
            try await repository.deleteBranch(branch, force: force)
        }
    }

    func merge(_ branch: Branch) async {
        await perform("Merguji \(branch.name)…", success: "Merge dokončen") { [self] in
            try await repository.merge(branch)
        }
    }

    func renameBranch(_ branch: Branch, to name: String) async {
        await perform("Přejmenovávám větev…") { [self] in try await repository.renameBranch(branch, to: name) }
    }

    // MARK: History

    func loadHistory() async {
        do {
            commits = try await repository.log(limit: 500)
            if selectedCommitID == nil { selectedCommitID = commits.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var selectedCommit: Commit? { commits.first { $0.id == selectedCommitID } ?? branchCommits.first { $0.id == selectedCommitID } }

    private func loadBranchCommits() async {
        guard let branch = branches.first(where: { $0.id == selectedBranchID }) else { branchCommits = []; return }
        branchCommits = (try? await repository.log(limit: 30, revision: branch.fullName)) ?? []
    }

    /// Odkaz na commit ve webovém rozhraní GitHubu/GitLabu.
    func webURL(for commit: Commit) -> URL? {
        guard let remote = remotes.first(where: { $0.name == "origin" }) ?? remotes.first,
              let kind = store?.hostingKind(forRemote: remote.fetchURL),
              let (host, path) = HostingClient.parseRemote(remote.fetchURL) else { return nil }
        return URL(string: kind == .gitlab ? "https://\(host)/\(path)/-/commit/\(commit.hash)" : "https://\(host)/\(path)/commit/\(commit.hash)")
    }

    private func loadCommitFiles() async {
        guard let commit = selectedCommit else { commitFiles = []; signatureVerification = nil; return }
        signatureVerification = nil
        commitFiles = (try? await repository.files(in: commit)) ?? []
        selectedCommitFileID = commitFiles.first?.id
        await loadCommitDiff()
        await verifySignature(of: commit)
    }

    private func verifySignature(of commit: Commit) async {
        guard commit.isSigned, let store else { return }
        let signers = await store.allowedSignersFile(extraEmails: [config.effectiveEmail, config.localEmail])
        let result = await repository.verifySignature(of: commit, allowedSignersFile: signers)
        if selectedCommitID == commit.id { signatureVerification = result }
    }

    private func loadCommitDiff() async {
        guard let commit = selectedCommit, let file = commitFiles.first(where: { $0.id == selectedCommitFileID }) else {
            commitDiff = nil
            return
        }
        commitDiff = try? await repository.diff(of: file, in: commit)
    }

    // MARK: Config

    func loadConfig() async {
        var c = RepositoryConfig()
        c.localName = await repository.config("user.name") ?? ""
        c.localEmail = await repository.config("user.email") ?? ""
        c.effectiveName = await repository.effectiveConfig("user.name") ?? ""
        c.effectiveEmail = await repository.effectiveConfig("user.email") ?? ""
        c.signCommits = await repository.effectiveConfig("commit.gpgsign") == "true"
        c.signingFormat = await repository.effectiveConfig("gpg.format") ?? "openpgp"
        c.signingKey = await repository.effectiveConfig("user.signingkey") ?? ""
        config = c
    }

    func saveConfig(_ newConfig: RepositoryConfig) async {
        await perform("Ukládám nastavení…", success: "Nastavení uloženo") { [self] in
            try await repository.setConfig("user.name", newConfig.localName)
            try await repository.setConfig("user.email", newConfig.localEmail)
            try await repository.setConfig("commit.gpgsign", newConfig.signCommits ? "true" : "false")
            try await repository.setConfig("gpg.format", newConfig.signCommits && newConfig.signingFormat != "openpgp" ? newConfig.signingFormat : nil)
            try await repository.setConfig("user.signingkey", newConfig.signCommits ? newConfig.signingKey : nil)
            await loadConfig()
        }
    }

    func saveRemote(name: String, url: String, isNew: Bool) async {
        await perform("Ukládám remote…") { [self] in
            if isNew { try await repository.addRemote(name: name, url: url) } else { try await repository.setRemoteURL(name: name, url: url) }
        }
    }

    func removeRemote(_ remote: Remote) async {
        await perform("Odebírám remote…") { [self] in try await repository.removeRemote(name: remote.name) }
    }

    // MARK: Hosting

    var pullRequestURL: URL? {
        guard let head = status.branch.head, let remote = remotes.first(where: { $0.name == "origin" }) ?? remotes.first,
              let kind = store?.hostingKind(forRemote: remote.pushURL) else { return nil }
        return HostingClient.newPullRequestURL(remoteURL: remote.pushURL, branch: head, kind: kind)
    }

    var pullRequestTitle: String {
        guard let remote = remotes.first, let kind = store?.hostingKind(forRemote: remote.pushURL) else { return "Pull request" }
        return kind == .gitlab ? "Vytvořit merge request" : "Vytvořit pull request"
    }

    func revealInFinder(_ path: String? = nil) {
        let url = path.map { project.url.appendingPathComponent($0) } ?? project.url
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([project.url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
