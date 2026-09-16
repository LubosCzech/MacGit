import SwiftUI

struct CommitPanel: View {
    @Bindable var model: RepositoryModel
    @FocusState private var messageFocused: Bool

    var body: some View {
        let included = model.includedChanges.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: model.config.signCommits ? "signature" : "person.crop.circle")
                    .foregroundStyle(model.config.signCommits ? .green : .secondary)
                Text(identity)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    model.section = .settings
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Upravit identitu a podpis")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(model.config.signCommits ? "Commity budou podepsány (\(model.config.signingFormat))" : "Commity nebudou podepsány")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.workspace.draftMessage)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($messageFocused)
                    .frame(minHeight: 64, maxHeight: 140)
                if model.workspace.draftMessage.isEmpty {
                    Text("Zpráva commitu")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .background(.background.opacity(0.5), in: .rect(cornerRadius: 12))

            HStack(spacing: 8) {
                Toggle("Amend", isOn: $model.amend)
                    .toggleStyle(.checkbox)
                    .help("Upravit poslední commit")
                Spacer()
                Text("\(included) z \(model.status.changes.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        Task { await model.commit(andPush: false) }
                    } label: {
                        Text(model.amend ? "Amend" : "Commit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)

                    Button {
                        Task { await model.commit(andPush: true) }
                    } label: {
                        Label("a Push", systemImage: "arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
                .disabled(!model.canCommit)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(10)
    }

    private var identity: String {
        let name = model.config.effectiveName.isEmpty ? "Neznámý autor" : model.config.effectiveName
        let email = model.config.effectiveEmail.isEmpty ? "" : " <\(model.config.effectiveEmail)>"
        return name + email
    }
}
