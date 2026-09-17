import SwiftUI
import GitKit

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Prostory", systemImage: "square.grid.2x2") { SpacesSettings() }
            Tab("Účty", systemImage: "person.crop.circle") { AccountsSettings() }
            Tab("SSH klíče", systemImage: "key") { SSHKeysSettings() }
            Tab("Git", systemImage: "arrow.triangle.branch") { GitSettings() }
        }
        .frame(width: 640, height: 520)
    }
}

extension HostingKind {
    var symbol: String {
        switch self {
        case .github: "chevron.left.forwardslash.chevron.right"
        case .gitlab: "square.stack.3d.up.fill"
        }
    }

    var tint: Color {
        switch self {
        case .github: .primary
        case .gitlab: .orange
        }
    }
}

// MARK: - Spaces

private struct SpacesSettings: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Space?
    @State private var spaceToDelete: Space?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            List {
                ForEach(store.spaces) { space in
                    HStack(spacing: 12) {
                        SpaceIcon(space: space, size: 28)
                        VStack(alignment: .leading) {
                            Text(space.name).font(.body.weight(.medium))
                            Text("\(store.projects(in: space.id).count) repozitářů")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Upravit") { editing = space }
                        Button(role: .destructive) { spaceToDelete = space } label: { Image(systemName: "trash") }
                    }
                    .padding(.vertical, 4)
                }
                .onMove { store.spaces.move(fromOffsets: $0, toOffset: $1) }
            }
            HStack {
                Text("Prostory řaď přetažením. Repozitáře do nich přesuneš v postranním panelu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Nový prostor", systemImage: "plus") {
                    editing = Space(name: "", symbol: Space.suggestedSymbols.randomElement()!, color: SpaceColor.allCases.randomElement()!)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .sheet(item: $editing) { space in
            SpaceEditor(space: space) { saved in
                if let index = store.spaces.firstIndex(where: { $0.id == saved.id }) {
                    store.spaces[index] = saved
                } else {
                    store.spaces.append(saved)
                }
            }
        }
        .confirmationDialog("Smazat prostor „\(spaceToDelete?.name ?? "")“?", isPresented: Binding(get: { spaceToDelete != nil }, set: { if !$0 { spaceToDelete = nil } })) {
            Button("Smazat", role: .destructive) { if let spaceToDelete { store.deleteSpace(spaceToDelete) } }
        } message: {
            Text("Repozitáře se přesunou do Nezařazených.")
        }
    }
}

struct SpaceEditor: View {
    @State var space: Space
    let onSave: (Space) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                SpaceIcon(space: space, size: 48)
                TextField("Název prostoru", text: $space.name, prompt: Text("např. Práce"))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            Text("Barva").font(.headline)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(SpaceColor.allCases) { color in
                        Button {
                            space.color = color
                        } label: {
                            Circle()
                                .fill(color.color.gradient)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if space.color == color {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .overlay(Circle().strokeBorder(.separator))
                    }
                }
            }

            Text("Ikona").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 8), spacing: 8) {
                ForEach(Space.suggestedSymbols, id: \.self) { symbol in
                    Button {
                        space.symbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 36, height: 36)
                            .foregroundStyle(space.symbol == symbol ? .white : .primary)
                            .background(space.symbol == symbol ? AnyShapeStyle(space.color.color.gradient) : AnyShapeStyle(.quaternary), in: .rect(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Uložit") {
                    onSave(space)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(space.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Accounts

private struct AccountsSettings: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var accountToDelete: HostingAccount?

    var body: some View {
        VStack(spacing: 0) {
            List {
                if store.accounts.isEmpty {
                    EmptyStateView(title: "Žádné účty", symbol: "person.crop.circle.badge.plus", message: "Přidej GitHub nebo GitLab účet pomocí Personal Access Tokenu – umožní procházet a klonovat repozitáře a přihlašovat se přes HTTPS.")
                }
                ForEach(store.accounts) { account in
                    HStack(spacing: 12) {
                        Image(systemName: account.kind.symbol)
                            .foregroundStyle(account.kind.tint)
                            .frame(width: 34, height: 34)
                            .background(.quaternary, in: .circle)
                        VStack(alignment: .leading) {
                            Text(account.displayName ?? account.login).font(.body.weight(.medium))
                            Text("\(account.kind.title) · \(account.login) @ \(account.host)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { accountToDelete = account } label: { Image(systemName: "trash") }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Spacer()
                Button("Přidat účet", systemImage: "plus") { showAdd = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .sheet(isPresented: $showAdd) { AddAccountSheet() }
        .confirmationDialog("Odebrat účet \(accountToDelete?.title ?? "")?", isPresented: Binding(get: { accountToDelete != nil }, set: { if !$0 { accountToDelete = nil } })) {
            Button("Odebrat", role: .destructive) {
                guard let account = accountToDelete else { return }
                Keychain.set(nil, for: account.keychainKey)
                store.accounts.removeAll { $0.id == account.id }
                for index in store.projects.indices where store.projects[index].auth == .account(account.id) {
                    store.projects[index].auth = .system
                }
            }
        }
    }
}

private struct AddAccountSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: HostingKind = .github
    @State private var host = ""
    @State private var token = ""
    @State private var isVerifying = false
    @State private var error: String?

    var body: some View {
        Form {
            Picker("Služba", selection: $kind) {
                ForEach(HostingKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Server", text: $host, prompt: Text(kind.defaultHost))
            SecureField("Personal Access Token", text: $token)
            Text(tokenHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let tokenURL {
                Link("Vytvořit token…", destination: tokenURL)
            }
            if let error {
                Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button {
                    Task { await verify() }
                } label: {
                    if isVerifying { ProgressView().controlSize(.small) } else { Text("Ověřit a přidat") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty || isVerifying)
            }
            .controlSize(.large)
            .padding(14)
        }
        .frame(width: 480, height: 360)
    }

    private var effectiveHost: String { host.isEmpty ? kind.defaultHost : host }

    private var tokenHelp: String {
        switch kind {
        case .github: "Potřebná oprávnění: repo, read:user, user:email; pro nahrávání SSH klíčů write:public_key."
        case .gitlab: "Potřebná oprávnění (scopes): api, read_user, read_repository, write_repository."
        }
    }

    private var tokenURL: URL? {
        switch kind {
        case .github: URL(string: "https://\(effectiveHost)/settings/tokens/new?scopes=repo,read:user,user:email,write:public_key&description=MacGit")
        case .gitlab: URL(string: "https://\(effectiveHost)/-/user_settings/personal_access_tokens?name=MacGit&scopes=api,read_user,read_repository,write_repository")
        }
    }

    private func verify() async {
        isVerifying = true
        error = nil
        defer { isVerifying = false }
        do {
            let user = try await HostingClient(kind: kind, host: effectiveHost, token: token).currentUser()
            let account = HostingAccount(kind: kind, host: effectiveHost, login: user.login, displayName: user.name, email: user.email)
            Keychain.set(token, for: account.keychainKey)
            store.accounts.append(account)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - SSH keys

private struct SSHKeysSettings: View {
    @Environment(AppStore.self) private var store
    @State private var keys: [SSHKey] = []
    @State private var showGenerate = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                if keys.isEmpty {
                    EmptyStateView(title: "Žádné SSH klíče", symbol: "key", message: "V ~/.ssh nebyl nalezen žádný pár klíčů.")
                }
                ForEach(keys) { key in
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.tint)
                            .frame(width: 34, height: 34)
                            .background(.quaternary, in: .circle)
                        VStack(alignment: .leading) {
                            Text(key.name).font(.body.weight(.medium))
                            Text("\(key.type) · \(key.comment)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Kopírovat veřejný") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(key.publicKey, forType: .string)
                            message = "Veřejný klíč \(key.name) zkopírován."
                        }
                        if !store.accounts.isEmpty {
                            Menu("Nahrát") {
                                ForEach(store.accounts) { account in
                                    if account.kind == .github {
                                        Menu(account.title) {
                                            Button("Pro přihlášení (push/pull)") { Task { await upload(key, to: account, purpose: .authentication) } }
                                            Button("Pro podepisování commitů") { Task { await upload(key, to: account, purpose: .signing) } }
                                        }
                                    } else {
                                        Button("\(account.title) – přihlášení i podpisy") { Task { await upload(key, to: account, purpose: .authentication) } }
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Vygenerovat klíč", systemImage: "plus") { showGenerate = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .onAppear { keys = SSHKeyManager.listKeys() }
        .sheet(isPresented: $showGenerate, onDismiss: { keys = SSHKeyManager.listKeys() }) {
            GenerateKeySheet()
        }
    }

    private func upload(_ key: SSHKey, to account: HostingAccount, purpose: HostingClient.SSHKeyPurpose) async {
        guard let client = store.client(for: account) else { return }
        do {
            try await client.uploadSSHKey(title: "MacGit – \(Host.current().localizedName ?? "Mac")", publicKey: key.publicKey, purpose: purpose)
            message = purpose == .signing ? "Podpisový klíč nahrán na \(account.host)." : "Klíč nahrán na \(account.host)."
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct GenerateKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "id_ed25519_macgit"
    @State private var comment = "\(NSUserName())@\(Host.current().localizedName ?? "mac")"
    @State private var passphrase = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Soubor v ~/.ssh", text: $name)
            TextField("Komentář", text: $comment)
            SecureField("Passphrase (volitelné)", text: $passphrase)
            if let error { Label(error, systemImage: "xmark.octagon").foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Vygenerovat Ed25519") {
                    Task {
                        do {
                            _ = try await SSHKeyManager.generate(name: name, comment: comment, passphrase: passphrase)
                            if !passphrase.isEmpty {
                                Keychain.set(passphrase, for: Keychain.sshPassphraseKey(SSHKeyManager.sshDirectory.appendingPathComponent(name).path))
                            }
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 440, height: 280)
    }
}

// MARK: - Git

private struct GitSettings: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var email = ""
    @State private var defaultBranch = ""
    @State private var gitVersion = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Globální identita (~/.gitconfig)") {
                TextField("Jméno", text: $name)
                TextField("E-mail", text: $email)
                TextField("Výchozí větev", text: $defaultBranch, prompt: Text("main"))
            }
            Section("Git") {
                LabeledContent("Spustitelný soubor", value: store.runner.gitPath)
                LabeledContent("Verze", value: gitVersion)
                LabeledContent("Data aplikace") {
                    Button((store.supportURL.path as NSString).abbreviatingWithTildeInPath) {
                        NSWorkspace.shared.open(store.supportURL)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if saved { Label("Uloženo", systemImage: "checkmark").foregroundStyle(.green) }
                Spacer()
                Button("Uložit") {
                    Task {
                        try? await GitRepository.setGlobalConfig("user.name", name, runner: store.runner)
                        try? await GitRepository.setGlobalConfig("user.email", email, runner: store.runner)
                        try? await GitRepository.setGlobalConfig("init.defaultBranch", defaultBranch, runner: store.runner)
                        saved = true
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .task {
            name = await GitRepository.globalConfig("user.name", runner: store.runner) ?? ""
            email = await GitRepository.globalConfig("user.email", runner: store.runner) ?? ""
            defaultBranch = await GitRepository.globalConfig("init.defaultBranch", runner: store.runner) ?? ""
            gitVersion = (try? await store.runner.run(["--version"], in: nil).output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "?"
        }
    }
}
