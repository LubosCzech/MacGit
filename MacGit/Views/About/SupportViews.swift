import SwiftUI

/// Občasný dotaz na podporu – poprvé po týdnu, pak nanejvýš jednou za měsíc.
struct SupportPromptView: View {
    // Předané přímo, ne z prostředí: list obsah prostředí prezentujícího pohledu nedědí spolehlivě.
    let support: SupportService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Slouží ti Revision dobře?")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Revision dělá nezávislé studio – bez reklam, bez účtu a bez odesílání tvých dat. Když ti šetří čas, můžeš nás pozvat na kávu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button { support.support() } label: {
                Label("Koupit kávu", systemImage: "cup.and.saucer")
            }
            .adaptiveButtonStyle(prominent: true)
            .controlSize(.large)

            VStack(spacing: 6) {
                Button("Už jsem přispěl") { support.acknowledge() }
                    .buttonStyle(.link)
                Button("Teď ne, zeptejte se později") { support.postpone() }
                    .buttonStyle(.link)
            }
            Text("Zeptáme se nanejvýš jednou za měsíc. Po tvém potvrzení už nikdy.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 380)
        .onDisappear { support.isPrompting = false }
    }
}

/// Záložka Nastavení → Aktualizace: Sparkle a podpora vývoje.
struct UpdateSettingsView: View {
    let updates: UpdateService

    var body: some View {
        Form {
            Section("Aktualizace") {
                if let message = updates.configurationMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Toggle("Automaticky kontrolovat aktualizace", isOn: Binding(
                        get: { updates.automaticChecks },
                        set: { updates.setAutomaticChecks($0) }
                    ))
                    Text("Kontrola jednou denně. Stažení a instalaci vždy potvrdíš v dialogu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let date = updates.lastCheck {
                        LabeledContent("Poslední kontrola", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Button("Zkontrolovat aktualizace…") { updates.check() }
                    .disabled(!updates.canCheck)
            }

            Section("Podpora") {
                LabeledContent("Buy Me a Coffee") {
                    Link(destination: SupportLink.page) {
                        Label("Kávu pro vývojáře", systemImage: "cup.and.saucer")
                    }
                }
                Text("Revision je zdarma a bez reklam. Příspěvek pomáhá dalšímu vývoji.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
