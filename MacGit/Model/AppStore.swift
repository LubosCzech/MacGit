import Foundation
import SwiftUI
import GitKit

/// Globální stav aplikace: prostory, projekty, účty. Ukládá se do Application Support.
@Observable
final class AppStore {
    private struct PersistedState: Codable {
        var spaces: [Space]
        var projects: [Project]
        var accounts: [HostingAccount]
        var selectedSpaceID: UUID?
        var selectedProjectID: UUID?
    }

    var spaces: [Space] = [] { didSet { save() } }
    var projects: [Project] = [] { didSet { save() } }
    var accounts: [HostingAccount] = [] { didSet { save() } }
    /// `nil` = zobrazit všechny prostory.
    var selectedSpaceID: UUID? { didSet { save() } }
    var selectedProjectID: UUID? {
        didSet {
            save()
            if let id = selectedProjectID, let index = projects.firstIndex(where: { $0.id == id }) {
                projects[index].lastOpenedAt = .now
            }
        }
    }

    var presentedSheet: SheetKind?
    /// Sbalené skupiny v postranním panelu (id prostoru nebo „unassigned“).
    var collapsedGroups: Set<String> = []
    /// Viditelnost inspektoru – sdílí ji toolbar, menu i formulář commitu.
    var inspectorShown = UserDefaults.standard.bool(forKey: "inspectorShown") {
        didSet { UserDefaults.standard.set(inspectorShown, forKey: "inspectorShown") }
    }
    var globalError: String?

    enum SheetKind: Identifiable, Hashable {
        case clone, addExisting, newRepository, newSpace
        case editSpace(Space)
        var id: Self { self }
    }

    let runner = GitRunner()
    let supportURL: URL
    let askpassPath: String
    private var models: [UUID: RepositoryModel] = [:]
    @ObservationIgnored private(set) lazy var reviews = ReviewCenter(store: self)
    private var isLoading = true

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportURL = base.appendingPathComponent("Revision", isDirectory: true)
        AppMigration.moveLegacySupportDirectory(from: base.appendingPathComponent("MacGit", isDirectory: true), to: supportURL)
        AppMigration.copyLegacyDefaults()
        askpassPath = supportURL.appendingPathComponent("askpass.sh").path
        try? FileManager.default.createDirectory(at: supportURL.appendingPathComponent("workspaces"), withIntermediateDirectories: true)
        installAskpass()
        load()
        // Klíče s passphrase uloženou v Klíčence macOS načteme do agenta, aby je git z GUI viděl.
        Task { await SSHKeyManager.loadKeychainKeys() }
        isLoading = false
    }

    // MARK: Persistence

    private var stateURL: URL { supportURL.appendingPathComponent("state.json") }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            spaces = [
                Space(name: "Práce", symbol: "briefcase.fill", color: .blue),
                Space(name: "Soukromé", symbol: "house.fill", color: .green)
            ]
            return
        }
        spaces = state.spaces
        projects = state.projects
        accounts = state.accounts
        selectedSpaceID = state.selectedSpaceID
        selectedProjectID = state.selectedProjectID
    }

    private func save() {
        guard !isLoading else { return }
        let state = PersistedState(spaces: spaces, projects: projects, accounts: accounts, selectedSpaceID: selectedSpaceID, selectedProjectID: selectedProjectID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func installAskpass() {
        let data = Data(GitContext.askpassScript.utf8)
        if (try? Data(contentsOf: URL(fileURLWithPath: askpassPath))) != data {
            FileManager.default.createFile(atPath: askpassPath, contents: data, attributes: [.posixPermissions: 0o700])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassPath)
    }

    func workspaceURL(for projectID: UUID) -> URL {
        supportURL.appendingPathComponent("workspaces/\(projectID.uuidString).json")
    }

    func shelfDirectory(for projectID: UUID) -> URL {
        let url = supportURL.appendingPathComponent("shelves/\(projectID.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Projects

    func project(_ id: UUID?) -> Project? {
        projects.first { $0.id == id }
    }

    func projects(in spaceID: UUID?) -> [Project] {
        projects.filter { $0.spaceID == spaceID }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func model(for project: Project) -> RepositoryModel {
        if let model = models[project.id] { return model }
        let model = RepositoryModel(project: project, store: self)
        models[project.id] = model
        return model
    }

    @discardableResult
    func addProject(at directory: URL, spaceID: UUID?, auth: ProjectAuth = .system) async throws -> Project {
        guard let top = await GitRepository.topLevel(of: directory, runner: runner) else {
            throw GitError(arguments: [], status: 1, message: "Složka \(directory.lastPathComponent) není git repozitář.")
        }
        if let existing = projects.first(where: { $0.path == top.path }) {
            selectedProjectID = existing.id
            return existing
        }
        let project = Project(name: top.lastPathComponent, path: top.path, spaceID: spaceID, auth: auth)
        projects.append(project)
        selectedProjectID = project.id
        return project
    }

    func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        models[project.id]?.projectDidChange(project)
    }

    func remove(_ project: Project) {
        models[project.id]?.deactivate()
        models[project.id] = nil
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id { selectedProjectID = nil }
        Keychain.set(nil, for: Keychain.projectPasswordKey(project.id))
        try? FileManager.default.removeItem(at: workspaceURL(for: project.id))
    }

    func move(_ project: Project, to spaceID: UUID?) {
        var copy = project
        copy.spaceID = spaceID
        update(copy)
    }

    // MARK: Spaces

    func deleteSpace(_ space: Space) {
        for index in projects.indices where projects[index].spaceID == space.id {
            projects[index].spaceID = nil
        }
        spaces.removeAll { $0.id == space.id }
        if selectedSpaceID == space.id { selectedSpaceID = nil }
    }

    func space(_ id: UUID?) -> Space? {
        spaces.first { $0.id == id }
    }

    // MARK: Credentials

    func context(for auth: ProjectAuth, projectID: UUID?) -> GitContext {
        GitContext.credential(credential(for: auth, projectID: projectID), askpassPath: askpassPath)
    }

    func credential(for auth: ProjectAuth, projectID: UUID?) -> GitCredential {
        switch auth {
        case .system:
            return .system
        case let .sshKey(path):
            return .sshKey(path: path, passphrase: Keychain.get(Keychain.sshPassphraseKey(path)))
        case let .account(accountID):
            guard let account = accounts.first(where: { $0.id == accountID }),
                  let token = Keychain.get(account.keychainKey) else { return .system }
            return .https(username: account.kind.httpsUsername(for: account.login), secret: token)
        case let .password(username):
            guard let projectID else { return .system }
            return .https(username: username, secret: Keychain.get(Keychain.projectPasswordKey(projectID)) ?? "")
        }
    }

    /// Soubor `allowed_signers` pro ověřování SSH podpisů: tvoje klíče z ~/.ssh
    /// jsou důvěryhodné pro tvoje e-maily (globální git, účty, identita repozitáře).
    func allowedSignersFile(extraEmails: [String]) async -> String {
        let url = supportURL.appendingPathComponent("allowed_signers")
        var emails = extraEmails + accounts.compactMap(\.email)
        if let global = await GitRepository.globalConfig("user.email", runner: runner) { emails.append(global) }
        let content = SSHKeyManager.allowedSigners(emails: emails, publicKeys: SSHKeyManager.listKeys().map(\.publicKey))
        if (try? String(contentsOf: url, encoding: .utf8)) != content {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        return url.path
    }

    func client(for account: HostingAccount) -> HostingClient? {
        guard let token = Keychain.get(account.keychainKey) else { return nil }
        return HostingClient(kind: account.kind, host: account.host, token: token)
    }

    /// Najde účet odpovídající hostu remotu, případně odhadne typ hostingu.
    func hostingKind(forRemote remote: String) -> HostingKind? {
        guard let host = HostingClient.parseRemote(remote)?.host else { return nil }
        if let account = accounts.first(where: { $0.host == host }) { return account.kind }
        if host.contains("github") { return .github }
        if host.contains("gitlab") { return .gitlab }
        return nil
    }
}
