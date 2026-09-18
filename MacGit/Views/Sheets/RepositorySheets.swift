import SwiftUI
import GitKit

@MainActor
private func chooseDirectory(message: String, canCreate: Bool = true) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = canCreate
    panel.allowsMultipleSelection = false
    panel.message = message
    panel.prompt = "Vybrat"
    return panel.runModal() == .OK ? panel.url : nil
}

private struct SpacePicker: View {
    @Environment(AppStore.self) private var store
    @Binding var spaceID: UUID?

    var body: some View {
        Picker("Prostor", selection: $spaceID) {
            Text("Nezařazené").tag(UUID?.none)
            ForEach(store.spaces) { space in
                Label(space.name, systemImage: space.symbol).tag(Optional(space.id))
            }
        }
    }
}

private struct SheetButtons: View {
    let confirmTitle: String
    let isWorking: Bool
    let isDisabled: Bool
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button("Zrušit") { dismiss() }
                .disabled(isWorking)
            Button(action: action) {
                HStack(spacing: 8) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(confirmTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isDisabled || isWorking)
        }
        .padding(16)
    }
}

// MARK: - Clone

struct CloneSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case url, account
        var id: String { rawValue }
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var source: Source = .url
    @State private var remoteURL = ""
    @State private var accountID: UUID?
    @State private var repositories: [HostedRepository] = []
    @State private var selectedRepo: HostedRepository.ID?
    @State private var useSSH = true
    @State private var search = ""
    @State private var loadingRepos = false
    @State private var parentDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projekty")
    @State private var folderName = ""
    @State private var spaceID: UUID?
    @State private var auth: ProjectAuth = .system
    @State private var secret = ""
    @State private var isCloning = false
    @State private var error: String?

    private var effectiveURL: String {
        if source == .account, let repo = repositories.first(where: { $0.id == selectedRepo }) {
            return useSSH ? repo.sshURL : repo.httpsURL
        }
        return remoteURL.trimmingCharacters(in: .whitespaces)
    }

    private var suggestedName: String {
        guard let path = HostingClient.parseRemote(effectiveURL)?.path else { return "" }
        return (path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Zdroj", selection: $source) {
                        Text("URL adresa").tag(Source.url)
                        Text("Z účtu GitHub/GitLab").tag(Source.account)
                    }
                    .pickerStyle(.segmented)

                    if source == .url {
                        TextField("URL repozitáře", text: $remoteURL, prompt: Text("git@github.com:owner/repo.git"))
                    } else if store.accounts.isEmpty {
                        Text("Nejdřív přidej účet v Nastavení → Účty.").foregroundStyle(.secondary)
                    } else {
                        Picker("Účet", selection: $accountID) {
                            ForEach(store.accounts) { Text($0.title).tag(Optional($0.id)) }
                        }
                        repoList
                        Picker("Protokol", selection: $useSSH) {
                            Text("SSH").tag(true)
                            Text("HTTPS").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Umístění") {
                    LabeledContent("Nadřazená složka") {
                        Button((parentDirectory.path as NSString).abbreviatingWithTildeInPath) {
                            if let url = chooseDirectory(message: "Kam naklonovat repozitář") { parentDirectory = url }
                        }
                    }
                    TextField("Název složky", text: $folderName, prompt: Text(suggestedName))
                    SpacePicker(spaceID: $spaceID)
                }

                Section("Přihlášení") {
                    AuthEditor(auth: $auth, secret: $secret, remoteURL: effectiveURL)
                        .loadKeys()
                }

                if let error {
                    Label(error, systemImage: "xmark.octagon")
                        .foregroundStyle(Theme.statusDeleted)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            SheetButtons(confirmTitle: isCloning ? "Klonuji…" : "Klonovat", isWorking: isCloning, isDisabled: effectiveURL.isEmpty) {
                Task { await clone() }
            }
        }
        .frame(width: 560, height: source == .account ? 720 : 560)
        .onAppear {
            spaceID = store.selectedSpaceID
            accountID = store.accounts.first?.id
        }
        .onChange(of: accountID) { Task { await loadRepositories() } }
        .onChange(of: source) { if source == .account { Task { await loadRepositories() } } }
        .onChange(of: useSSH) { updateAuthForProtocol() }
        .onChange(of: selectedRepo) { updateAuthForProtocol() }
    }

    private var repoList: some View {
        let filtered = search.isEmpty ? repositories : repositories.filter { $0.fullName.localizedCaseInsensitiveContains(search) }
        return VStack(spacing: 6) {
            TextField("Hledat", text: $search, prompt: Text("Hledat repozitář"))
                .textFieldStyle(.roundedBorder)
            List(filtered, selection: $selectedRepo) { repo in
                HStack {
                    Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(repo.fullName)
                        if let description = repo.description, !description.isEmpty {
                            Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if let updated = repo.updatedAt {
                        Text(updated, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .tag(repo.id)
            }
            .frame(height: 220)
            .overlay { if loadingRepos { ProgressView() } }
        }
    }

    private func updateAuthForProtocol() {
        guard source == .account, let accountID else { return }
        auth = useSSH ? .system : .account(accountID)
    }

    private func loadRepositories() async {
        guard source == .account, let account = store.accounts.first(where: { $0.id == accountID }), let client = store.client(for: account) else { return }
        loadingRepos = true
        defer { loadingRepos = false }
        do {
            repositories = try await client.repositories()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clone() async {
        let name = folderName.isEmpty ? suggestedName : folderName
        guard !name.isEmpty else { error = "Zadej název složky."; return }
        let destination = parentDirectory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            error = "Složka \(destination.path) už existuje."
            return
        }
        isCloning = true
        error = nil
        defer { isCloning = false }

        let projectID = UUID()
        persistSecret(secret, for: auth, projectID: projectID)
        let context = store.context(for: auth, projectID: projectID)
        do {
            try await GitRepository.clone(url: effectiveURL, to: destination, context: context, runner: store.runner)
            var project = Project(id: projectID, name: name, path: destination.path, spaceID: spaceID, auth: auth)
            project.lastOpenedAt = .now
            store.projects.append(project)
            store.selectedProjectID = project.id
            dismiss()
        } catch {
            Keychain.set(nil, for: Keychain.projectPasswordKey(projectID))
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Add existing

struct AddExistingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var directory: URL?
    @State private var spaceID: UUID?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent("Složka") {
                    Button(directory.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Vybrat…") {
                        directory = chooseDirectory(message: "Vyber složku s git repozitářem", canCreate: false)
                    }
                }
                SpacePicker(spaceID: $spaceID)
                Text("Tip: složky s repozitáři můžeš také přetáhnout do postranního panelu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error { Label(error, systemImage: "xmark.octagon").foregroundStyle(Theme.statusDeleted) }
            }
            .formStyle(.grouped)
            SheetButtons(confirmTitle: "Přidat", isWorking: isWorking, isDisabled: directory == nil) {
                Task {
                    guard let directory else { return }
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        try await store.addProject(at: directory, spaceID: spaceID)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        .frame(width: 480, height: 280)
        .onAppear {
            spaceID = store.selectedSpaceID
            if directory == nil { directory = chooseDirectory(message: "Vyber složku s git repozitářem", canCreate: false) }
        }
    }
}

// MARK: - New repository

struct NewRepositorySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var parentDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projekty")
    @State private var name = ""
    @State private var branch = "main"
    @State private var spaceID: UUID?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Název", text: $name, prompt: Text("muj-projekt"))
                LabeledContent("Umístění") {
                    Button((parentDirectory.path as NSString).abbreviatingWithTildeInPath) {
                        if let url = chooseDirectory(message: "Kde vytvořit repozitář") { parentDirectory = url }
                    }
                }
                TextField("Výchozí větev", text: $branch)
                SpacePicker(spaceID: $spaceID)
                if let error { Label(error, systemImage: "xmark.octagon").foregroundStyle(Theme.statusDeleted) }
            }
            .formStyle(.grouped)
            SheetButtons(confirmTitle: "Vytvořit", isWorking: isWorking, isDisabled: name.isEmpty || branch.isEmpty) {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        let url = parentDirectory.appendingPathComponent(name)
                        try await GitRepository.initialize(at: url, runner: store.runner, defaultBranch: branch)
                        try await store.addProject(at: url, spaceID: spaceID)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        .frame(width: 480, height: 320)
        .onAppear { spaceID = store.selectedSpaceID }
    }
}
