import SwiftUI
import GitKit

/// Výběr způsobu přihlášení – používá se v nastavení projektu i při klonování.
struct AuthEditor: View {
    @Environment(AppStore.self) private var store
    @Binding var auth: ProjectAuth
    /// Heslo/token pro `.password` a passphrase pro `.sshKey` – ukládá volající.
    @Binding var secret: String
    var remoteURL: String?

    @State private var keys: [SSHKey] = []

    var body: some View {
        Picker("Metoda", selection: Binding(
            get: { auth.kind },
            set: { kind in
                switch kind {
                case .system: auth = .system
                case .sshKey: auth = .sshKey(path: keys.first?.privateKeyPath ?? "")
                case .account: auth = store.accounts.first.map { .account($0.id) } ?? .system
                case .password: auth = .password(username: "")
                }
                secret = ""
            }
        )) {
            ForEach(ProjectAuth.Kind.allCases) { kind in
                Text(kind.title).tag(kind)
                    .disabled(kind == .account && store.accounts.isEmpty)
            }
        }

        if let warning { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }

        switch auth {
        case .system:
            Text("Použije se ssh-agent, ~/.ssh/config a credential helper z konfigurace gitu.")
                .font(.callout)
                .foregroundStyle(.secondary)

        case let .sshKey(path):
            Picker("Klíč", selection: Binding(get: { path }, set: { auth = .sshKey(path: $0) })) {
                if keys.isEmpty { Text("V ~/.ssh nejsou žádné klíče").tag("") }
                ForEach(keys) { key in
                    Text("\(key.name) (\(key.type.replacingOccurrences(of: "ssh-", with: "")))").tag(key.privateKeyPath)
                }
                if !path.isEmpty, !keys.contains(where: { $0.privateKeyPath == path }) {
                    Text((path as NSString).lastPathComponent).tag(path)
                }
            }
            SecureField("Passphrase (pokud je klíč chráněný)", text: $secret)

        case let .account(accountID):
            Picker("Účet", selection: Binding(get: { accountID }, set: { auth = .account($0) })) {
                ForEach(store.accounts) { account in
                    Label(account.title, systemImage: account.kind.symbol).tag(account.id)
                }
            }

        case let .password(username):
            TextField("Uživatel", text: Binding(get: { username }, set: { auth = .password(username: $0) }))
            SecureField("Heslo nebo token", text: $secret)
        }
    }

    private var warning: String? {
        guard let remoteURL, !remoteURL.isEmpty else { return nil }
        let isSSH = !remoteURL.hasPrefix("http")
        switch auth {
        case .sshKey where !isSSH:
            return "Remote používá HTTPS – SSH klíč se neuplatní."
        case .account, .password:
            if isSSH { return "Remote používá SSH – token/heslo se neuplatní." }
            if case .password = auth, remoteURL.contains("github.com") {
                return "GitHub nepodporuje heslo pro git – zadej Personal Access Token."
            }
            return nil
        default:
            return nil
        }
    }
}

extension AuthEditor {
    func loadKeys() -> some View {
        onAppear { keys = SSHKeyManager.listKeys() }
    }
}

extension View {
    /// Uloží tajný údaj k metodě přihlášení do Klíčenky.
    @MainActor
    func persistSecret(_ secret: String, for auth: ProjectAuth, projectID: UUID) {
        switch auth {
        case let .sshKey(path) where !path.isEmpty:
            if !secret.isEmpty { Keychain.set(secret, for: Keychain.sshPassphraseKey(path)) }
        case .password:
            if !secret.isEmpty { Keychain.set(secret, for: Keychain.projectPasswordKey(projectID)) }
        default:
            break
        }
    }
}
