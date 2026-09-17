import SwiftUI
import GitKit

/// Nastavení repozitáře v inspektoru: projekt, přihlášení, identita, podpis, remoty.
struct RepositoryInspector: View {
    let model: RepositoryModel
    @Environment(AppStore.self) private var store

    @State private var project: Project?
    @State private var config = RepositoryConfig()
    @State private var secret = ""
    @State private var keys: [SSHKey] = []
    @State private var remoteDrafts: [String: String] = [:]
    @State private var newRemoteName = ""
    @State private var newRemoteURL = ""
    @State private var remoteToRemove: Remote?

    var body: some View {
        Form {
            if let binding = Binding($project) {
                Section("Projekt") {
                    TextField("Název", text: binding.name)
                    LabeledContent("Umístění") {
                        Text((binding.wrappedValue.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(binding.wrappedValue.path)
                    }
                    Picker("Prostor", selection: binding.spaceID) {
                        Text("Nezařazené").tag(UUID?.none)
                        ForEach(store.spaces) { space in
                            Label(space.name, systemImage: space.symbol).tag(Optional(space.id))
                        }
                    }
                    HStack {
                        Button("Zobrazit ve Finderu") { model.revealInFinder() }
                        Button("Terminál") { model.openInTerminal() }
                    }
                }

                Section {
                    AuthEditor(auth: binding.auth, secret: $secret, remoteURL: model.remotes.first?.fetchURL)
                        .loadKeys()
                } header: {
                    Text("Přihlášení k remotu")
                } footer: {
                    Text("Tokeny, hesla a passphrase se ukládají do Klíčenky.")
                }
            }

            Section {
                TextField("Jméno", text: $config.localName, prompt: Text(globalHint(config.effectiveName, local: config.localName)))
                TextField("E-mail", text: $config.localEmail, prompt: Text(globalHint(config.effectiveEmail, local: config.localEmail)))
                if !store.accounts.isEmpty {
                    Menu("Převzít z účtu") {
                        ForEach(store.accounts) { account in
                            Button(account.title) {
                                config.localName = account.displayName ?? account.login
                                if let email = account.email { config.localEmail = email }
                            }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Identita autora")
            } footer: {
                Text("Prázdná pole = použije se globální nastavení gitu.")
            }

            Section("Podepisování commitů") {
                Toggle("Podepisovat commity", isOn: $config.signCommits)
                if config.signCommits {
                    Picker("Formát", selection: $config.signingFormat) {
                        Text("GPG (OpenPGP)").tag("openpgp")
                        Text("SSH klíč").tag("ssh")
                        Text("X.509 (S/MIME)").tag("x509")
                    }
                    if config.signingFormat == "ssh" {
                        Picker("Klíč", selection: $config.signingKey) {
                            Text("Vyber klíč").tag("")
                            ForEach(keys) { key in
                                Text(key.name).tag(key.publicKeyPath)
                            }
                            if !config.signingKey.isEmpty, !keys.contains(where: { $0.publicKeyPath == config.signingKey }) {
                                Text(config.signingKey).tag(config.signingKey)
                            }
                        }
                    } else {
                        TextField("ID klíče", text: $config.signingKey, prompt: Text(config.signingFormat == "openpgp" ? "např. 3AA5C34371567BD2" : "ID certifikátu"))
                        Text(config.signingFormat == "openpgp" ? "Vyžaduje nainstalované gpg a pinentry-mac (brew install gnupg pinentry-mac)." : "Vyžaduje gpgsm nebo smimesign.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Remoty") {
                ForEach(model.remotes) { remote in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(remote.name).fontWeight(.medium)
                            Spacer()
                            if let draft = remoteDrafts[remote.name], draft != remote.fetchURL {
                                Button("Uložit") {
                                    Task {
                                        await model.saveRemote(name: remote.name, url: draft, isNew: false)
                                        remoteDrafts[remote.name] = nil
                                    }
                                }
                                .controlSize(.small)
                            }
                            Button {
                                remoteToRemove = remote
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Odebrat remote \(remote.name)")
                        }
                        TextField("URL", text: Binding(
                            get: { remoteDrafts[remote.name] ?? remote.fetchURL },
                            set: { remoteDrafts[remote.name] = $0 }
                        ))
                        .labelsHidden()
                        .font(.callout.monospaced())
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Název", text: $newRemoteName, prompt: Text("origin"))
                    TextField("URL", text: $newRemoteURL, prompt: Text("git@github.com:owner/repo.git"))
                    HStack {
                        Spacer()
                        Button("Přidat remote") {
                            let name = newRemoteName.isEmpty ? "origin" : newRemoteName
                            Task {
                                await model.saveRemote(name: name, url: newRemoteURL, isNew: true)
                                newRemoteName = ""
                                newRemoteURL = ""
                            }
                        }
                        .disabled(newRemoteURL.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasChanges {
                HStack {
                    Spacer()
                    Button("Vrátit") { load() }
                    Button("Uložit") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                }
                .padding(12)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .confirmationDialog("Odebrat remote \(remoteToRemove?.name ?? "")?", isPresented: Binding(get: { remoteToRemove != nil }, set: { if !$0 { remoteToRemove = nil } })) {
            Button("Odebrat", role: .destructive) {
                if let remoteToRemove { Task { await model.removeRemote(remoteToRemove) } }
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.config) { config = model.config }
    }

    private var hasChanges: Bool {
        project != model.project || config != model.config || !secret.isEmpty
    }

    private func globalHint(_ effective: String, local: String) -> String {
        local.isEmpty && !effective.isEmpty ? "\(effective) (globální)" : ""
    }

    private func load() {
        project = model.project
        config = model.config
        secret = ""
        keys = SSHKeyManager.listKeys()
        Task { await model.loadConfig() }
    }

    private func save() {
        if let project {
            persistSecret(secret, for: project.auth, projectID: project.id)
            store.update(project)
        }
        secret = ""
        if config != model.config {
            let newConfig = config
            Task { await model.saveConfig(newConfig) }
        } else {
            model.showToast("Nastavení uloženo")
        }
    }
}
