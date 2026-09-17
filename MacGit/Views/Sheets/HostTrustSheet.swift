import SwiftUI
import GitKit

/// Ověření otisku SSH serveru při prvním připojení (náhrada terminálové otázky „Are you sure you want to continue connecting?“).
struct HostTrustSheet: View {
    let model: RepositoryModel
    let request: HostTrustRequest

    @Environment(\.dismiss) private var dismiss
    @State private var keys: [HostKey] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: request.problem == .changed ? "exclamationmark.shield.fill" : "server.rack")
                    .font(.system(size: 28))
                    .foregroundStyle(request.problem == .changed ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.problem == .changed ? "Otisk serveru se změnil" : "Neznámý SSH server")
                        .font(.headline)
                    Text(explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if request.problem == .unknown {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Server") {
                        Text(request.endpoint.knownHostsName).font(.body.monospaced()).textSelection(.enabled)
                    }
                    if isLoading {
                        HStack { ProgressView().controlSize(.small); Text("Načítám otisky…").foregroundStyle(.secondary) }
                    } else if keys.isEmpty {
                        Label(error ?? "Server nevrátil žádné klíče.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            ForEach(keys) { key in
                                GridRow {
                                    Text(key.type)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)
                                    Text(key.fingerprint)
                                        .font(.callout.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    }
                    Text("Porovnej otisk s tím, který zveřejňuje správce serveru\(verificationHint). Pokud se liší, nepokračuj.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                if request.problem == .unknown, let url = verificationURL {
                    Link("Otisky na serveru…", destination: url)
                }
                Spacer()
                if request.problem == .changed {
                    Button("Zobrazit known_hosts") {
                        NSWorkspace.shared.activateFileViewerSelecting([HostKeyTrust.knownHostsURL])
                    }
                    Button("Zavřít") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Zrušit", role: .cancel) { dismiss() }
                    Button("Důvěřovat a pokračovat") { trust() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(keys.isEmpty || isWorking)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            guard request.problem == .unknown else { isLoading = false; return }
            do {
                keys = try await HostKeyTrust.scan(request.endpoint)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var explanation: String {
        switch request.problem {
        case .unknown:
            "Připojuješ se k serveru \(request.endpoint.host) poprvé. Aby nešlo o podvržený server, potvrď jeho otisk – uloží se do ~/.ssh/known_hosts a příště se už ptát nebudu."
        case .changed:
            "Server \(request.endpoint.host) se prokazuje jiným klíčem, než jaký je uložený v ~/.ssh/known_hosts. Může jít o přeinstalovaný server, ale i o útok. Ověř změnu u správce a teprve pak starý záznam odstraň (ssh-keygen -R \(request.endpoint.knownHostsName))."
        }
    }

    private var verificationHint: String {
        switch request.endpoint.host {
        case "github.com": " (docs.github.com → GitHub's SSH key fingerprints)"
        case "gitlab.com": " (docs.gitlab.com → SSH host keys fingerprints)"
        default: request.endpoint.host.contains("gitlab") ? " (v GitLabu: Nápověda → Konfigurace instance)" : ""
        }
    }

    private var verificationURL: URL? {
        switch request.endpoint.host {
        case "github.com": URL(string: "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints")
        case "gitlab.com": URL(string: "https://docs.gitlab.com/user/gitlab_com/#ssh-host-keys-fingerprints")
        default: request.endpoint.host.contains("gitlab") ? URL(string: "https://\(request.endpoint.host)/help/instance_configuration") : nil
        }
    }

    private func trust() {
        isWorking = true
        do {
            try HostKeyTrust.trust(keys)
            dismiss()
            Task { await request.retry() }
        } catch {
            self.error = "Nepodařilo se zapsat do known_hosts: \(error.localizedDescription)"
            isWorking = false
        }
    }
}
