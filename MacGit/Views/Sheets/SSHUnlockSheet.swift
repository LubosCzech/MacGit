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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Odemknout SSH klíč")
                        .font(.headline)
                    Text("Git se nemohl přihlásit, protože klíč chráněný passphrase není načtený. Po odemčení se operace zopakuje.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Klíč:").gridColumnAlignment(.trailing)
                    Picker("Klíč", selection: $keyPath) {
                        ForEach(keys) { key in
                            Text("\(key.name) (\(key.type.replacingOccurrences(of: "ssh-", with: "").uppercased()))").tag(key.privateKeyPath)
                        }
                    }
                    .labelsHidden()
                }
                if keyIsEncrypted {
                    GridRow {
                        Text("Passphrase:").gridColumnAlignment(.trailing)
                        SecureField("Passphrase", text: $passphrase)
                            .labelsHidden()
                            .onSubmit(unlock)
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Toggle("Uložit do Klíčenky macOS", isOn: $storeInKeychain)
                    }
                } else {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("Tento klíč nemá passphrase – server ho nejspíš nezná. Nahraj veřejný klíč v Nastavení → SSH klíče.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            DisclosureGroup("Podrobnosti chyby") {
                Text(request.message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)

            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                    .disabled(isWorking)
                Button(action: unlock) {
                    if isWorking { ProgressView().controlSize(.small) } else { Text("Odemknout") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keyPath.isEmpty || !keyIsEncrypted || passphrase.isEmpty || isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
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
