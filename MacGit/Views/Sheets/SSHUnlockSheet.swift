import SwiftUI
import GitKit

/// Zeptá se na passphrase SSH klíče, přidá ho do ssh-agenta a zopakuje operaci.
struct SSHUnlockSheet: View {
    let model: RepositoryModel
    let request: SSHUnlockRequest

    @Environment(\.dismiss) private var dismiss
    @State private var keys: [SSHKey] = []
    @State private var keyPath = ""
    @State private var passphrase = ""
    @State private var storeInKeychain = true
    @State private var isWorking = false
    @State private var error: String?
    @State private var keyIsEncrypted = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "key.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.2)), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH klíč je zamčený").font(.title3.bold())
                    Text("Git se nemohl přihlásit, protože klíč chráněný passphrase není načtený v ssh-agentovi. Zadej passphrase – klíč se přidá do agenta a operace se zopakuje.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding([.horizontal, .top], 20)

            Form {
                Picker("Klíč", selection: $keyPath) {
                    ForEach(keys) { key in
                        Text("\(key.name) (\(key.type.replacingOccurrences(of: "ssh-", with: "")))").tag(key.privateKeyPath)
                    }
                }
                if keyIsEncrypted {
                    SecureField("Passphrase", text: $passphrase)
                        .onSubmit(unlock)
                    Toggle("Uložit passphrase do Klíčenky macOS", isOn: $storeInKeychain)
                } else {
                    Label("Tento klíč passphrase nemá – GitHub/GitLab ho pravděpodobně nezná. Nahraj veřejný klíč v Nastavení → SSH klíče.", systemImage: "info.circle")
                        .foregroundStyle(.orange)
                }
                DisclosureGroup("Výstup gitu") {
                    Text(request.message)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let error {
                    Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                    .buttonStyle(.glass)
                    .disabled(isWorking)
                Button(action: unlock) {
                    HStack(spacing: 8) {
                        if isWorking { ProgressView().controlSize(.small) }
                        Text("Odemknout a zkusit znovu")
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(keyPath.isEmpty || !keyIsEncrypted || passphrase.isEmpty || isWorking)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 520)
        .task {
            keys = SSHKeyManager.listKeys()
            keyPath = request.suggestedKeyPath.flatMap { path in keys.first { $0.privateKeyPath == path }?.privateKeyPath } ?? ""
            if keyPath.isEmpty {
                // Výchozí volba: první klíč chráněný passphrase.
                for key in keys where await SSHKeyManager.isEncrypted(key.privateKeyPath) {
                    keyPath = key.privateKeyPath
                    break
                }
                if keyPath.isEmpty { keyPath = keys.first?.privateKeyPath ?? "" }
            }
        }
        .onChange(of: keyPath) {
            Task { keyIsEncrypted = keyPath.isEmpty ? true : await SSHKeyManager.isEncrypted(keyPath) }
        }
    }

    private func unlock() {
        guard !passphrase.isEmpty, !keyPath.isEmpty else { return }
        isWorking = true
        error = nil
        Task {
            do {
                try await model.unlock(request, keyPath: keyPath, passphrase: passphrase, storeInKeychain: storeInKeychain)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }
}
