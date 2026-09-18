import SwiftUI

/// Formulář commitu pod seznamem změn – shrnutí, popis, autor, podpis, Commit / Commit a Push.
struct CommitComposer: View {
    @Bindable var model: RepositoryModel
    @Environment(AppStore.self) private var store

    private static let summaryLimit = 72

    /// Po úspěšném commitu se tlačítko na chvíli promění ve fajfku.
    @State private var justCommitted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let included = model.includedChanges.count
        let summaryLength = model.draftSummary.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Shrnutí", text: $model.draftSummary)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(9)
                    .background(Theme.surfaceRaised.opacity(0.85), in: .rect(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline) }
                    .disabled(model.isSuggestingMessage)
                    .accessibilityLabel("Shrnutí commitu")
                SuggestMessageButton(model: model)
                Text("\(summaryLength)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(summaryLength > Self.summaryLimit ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 20, alignment: .trailing)
                    .help("Shrnutí by mělo mít nejvýš \(Self.summaryLimit) znaků")
            }

            TextField("Popis (nepovinný)", text: $model.draftDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(9)
                .background(Theme.surfaceRaised.opacity(0.85), in: .rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline) }
                .disabled(model.isSuggestingMessage)
                .lineLimit(2...8)
                .accessibilityLabel("Popis commitu")

            HStack(spacing: 6) {
                Button {
                    model.inspectorTab = .repository
                    store.inspectorShown = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.config.signCommits ? "signature" : "person.crop.circle")
                            .foregroundStyle(model.config.signCommits ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.textSecondary))
                        Text(authorName)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.textSecondary)
                .help(signatureHelp)

                Spacer()

                Toggle("Amend", isOn: $model.amend)
                    .toggleStyle(.checkbox)
                    .help("Upravit poslední commit")
            }
            .font(.callout)

            // Hlavní akce a její menu jsou dvě tlačítka ve společném skle – jen tak se dá
            // roztáhnout přes celou šířku panelu (Menu se vždy zmenší na obsah).
            GlassEffectContainer(spacing: 2) {
                HStack(spacing: 2) {
                    Button { commit(andPush: false) } label: {
                        Group {
                            if justCommitted {
                                Label("Hotovo", systemImage: "checkmark").labelStyle(.titleAndIcon)
                            } else {
                                Text(model.amend ? "Upravit poslední commit" : "Commit \(included) souborů")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(justCommitted ? Theme.success : Theme.accentFill)
                    .disabled(!model.canCommit && !justCommitted)

                    Menu {
                        Button(model.amend ? "Amend a Push" : "Commit a Push") { commit(andPush: true) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 30, height: 32)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glassProminent)
                    .tint(justCommitted ? Theme.success : Theme.accentFill)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(!model.canCommit)
                    .accessibilityLabel("Další možnosti commitu")
                }
            }
            .help("Commit (⌘↩), Commit a Push (⌥⌘↩)")
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(10)
    }

    private var authorName: String {
        let name = model.config.effectiveName.isEmpty ? "Neznámý autor" : model.config.effectiveName
        return model.config.signCommits ? "\(name) · podepsáno" : name
    }

    /// Commit a krátké potvrzení v tlačítku.
    private func commit(andPush push: Bool) {
        Task {
            await model.commit(andPush: push)
            guard model.errorMessage == nil else { return }
            withAnimation(reduceMotion ? nil : .bouncy(duration: 0.35)) { justCommitted = true }
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { justCommitted = false }
        }
    }

    private var signatureHelp: String {
        let email = model.config.effectiveEmail.isEmpty ? "" : " <\(model.config.effectiveEmail)>"
        let signing = model.config.signCommits ? "Commity se podepisují (\(model.config.signingFormat))." : "Commity se nepodepisují."
        return "\(model.config.effectiveName)\(email)\n\(signing)\nKliknutím otevřeš nastavení repozitáře."
    }
}

/// Tlačítko s jiskrou: navrhne zprávu z vybraných změn, během generování ho jde zastavit.
private struct SuggestMessageButton: View {
    let model: RepositoryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = CommitMessageGenerator.status
        Button {
            if model.isSuggestingMessage { model.cancelSuggestion() } else { model.suggestCommitMessage() }
        } label: {
            if model.isSuggestingMessage {
                Image(systemName: "stop.circle")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.glass)
        .tint(Theme.accentDeep)
        .disabled(!model.isSuggestingMessage && !model.canSuggestMessage)
        .help(helpText(status))
        .accessibilityLabel(model.isSuggestingMessage ? "Zastavit návrh zprávy" : "Navrhnout zprávu commitu")
    }

    private func helpText(_ status: CommitMessageGenerator.Status) -> String {
        if model.isSuggestingMessage { return "Zastavit návrh" }
        switch status {
        case .available:
            return model.includedChanges.isEmpty ? "Vyber soubory, ze kterých se má zpráva navrhnout" : "Navrhnout zprávu z vybraných změn (⌥⌘G)"
        case let .unavailable(reason):
            return "Návrh zprávy vyžaduje Apple Intelligence. \(reason)"
        }
    }
}
