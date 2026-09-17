import SwiftUI

/// Formulář commitu pod seznamem změn – shrnutí, popis, autor, podpis, Commit / Commit a Push.
struct CommitComposer: View {
    @Bindable var model: RepositoryModel
    @Environment(AppStore.self) private var store

    private static let summaryLimit = 72

    var body: some View {
        let included = model.includedChanges.count
        let summaryLength = model.draftSummary.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Shrnutí", text: $model.draftSummary)
                    .textFieldStyle(.roundedBorder)
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
                .textFieldStyle(.roundedBorder)
                .disabled(model.isSuggestingMessage)
                .lineLimit(2...8)
                .accessibilityLabel("Popis commitu")

            HStack(spacing: 6) {
                Button {
                    model.inspectorTab = .repository
                    store.inspectorShown = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.config.signCommits ? "signature" : "person.crop.circle")
                            .foregroundStyle(model.config.signCommits ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        Text(authorName)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(signatureHelp)

                Spacer()

                Toggle("Amend", isOn: $model.amend)
                    .toggleStyle(.checkbox)
                    .help("Upravit poslední commit")
            }
            .font(.callout)

            HStack(spacing: 8) {
                Text(model.amend ? "Úprava posledního commitu" : "\(included) z \(model.status.changes.count) souborů")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Menu {
                    Button(model.amend ? "Amend a Push" : "Commit a Push") {
                        Task { await model.commit(andPush: true) }
                    }
                } label: {
                    Text(model.amend ? "Amend" : "Commit")
                } primaryAction: {
                    Task { await model.commit(andPush: false) }
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .disabled(!model.canCommit)
                .help("Commit (⌘↩), Commit a Push (⌥⌘↩)")
            }
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var authorName: String {
        let name = model.config.effectiveName.isEmpty ? "Neznámý autor" : model.config.effectiveName
        return model.config.signCommits ? "\(name) · podepsáno" : name
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

    var body: some View {
        let status = CommitMessageGenerator.status
        Button {
            if model.isSuggestingMessage { model.cancelSuggestion() } else { model.suggestCommitMessage() }
        } label: {
            if model.isSuggestingMessage {
                Image(systemName: "stop.circle")
                    .symbolEffect(.pulse)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
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
