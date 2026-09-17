import SwiftUI
import GitKit

/// Dialog pro spuštění AI review větve nebo commitu: agent, model, základní větev, vlastní pokyny.
struct StartReviewSheet: View {
    let model: RepositoryModel
    let target: ReviewTarget

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("review.agent") private var agentRaw = AgentKind.claude.rawValue
    @AppStorage("review.model") private var storedModels = "{}"
    @State private var base = ""
    @State private var modelID = ""
    @State private var instructions = ""
    @State private var isStarting = false

    private var center: ReviewCenter { store.reviews }
    private var agentKind: AgentKind { AgentKind(rawValue: agentRaw) ?? .claude }
    private var isCommit: Bool { if case .commit = target { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    switch target {
                    case let .branch(branch):
                        LabeledContent("Větev") {
                            Text(branch.name).fontWeight(.medium)
                        }
                        Picker("Porovnat s", selection: $base) {
                            ForEach(model.branches.filter { $0.name != branch.name }) { candidate in
                                Text(candidate.name).tag(candidate.name)
                            }
                        }
                    case let .commit(commit):
                        LabeledContent("Commit") {
                            Text(commit.shortHash).font(.body.monospaced()).fontWeight(.medium)
                        }
                        LabeledContent("Zpráva") {
                            Text(commit.subject).lineLimit(2).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Rozsah") {
                            Text(commit.parents.isEmpty ? "Celý první commit" : "Změny oproti rodiči \(String(commit.parents[0].prefix(7)))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("Agent", selection: $agentRaw) {
                        ForEach(AgentKind.allCases) { kind in
                            if center.agent(kind) != nil {
                                Text(kind.title).tag(kind.rawValue)
                            } else {
                                Text("\(kind.title) – není nainstalovaný").tag(kind.rawValue)
                                    .selectionDisabled()
                            }
                        }
                    }
                    .disabled(center.agents.isEmpty)

                    if center.agent(agentKind) != nil {
                        Picker("Model", selection: $modelID) {
                            Text("Výchozí model agenta").tag("")
                            let models = center.modelsByAgent[agentKind] ?? agentKind.fallbackModels
                            if !models.isEmpty { Divider() }
                            ForEach(models) { Text($0.name).tag($0.id) }
                            if !modelID.isEmpty, !models.contains(where: { $0.id == modelID }) {
                                Text(modelID).tag(modelID)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if center.loadingModels.contains(agentKind) {
                                ProgressView().controlSize(.small).padding(.trailing, 28)
                            }
                        }
                    }
                } header: {
                    Text("Agent")
                } footer: {
                    if center.isDetecting {
                        Text("Hledám nainstalované agenty…")
                    } else if center.agents.isEmpty {
                        Text("Nenašel jsem žádného CLI agenta (claude, codex, cursor-agent, grok). Nainstaluj některého a zkus to znovu.")
                    } else if let agent = center.agent(agentKind) {
                        Text(agent.executable).textSelection(.enabled)
                    }
                }

                Section {
                    TextField("Na co se zaměřit (nepovinné)", text: $instructions, prompt: Text("např. výkon databázových dotazů"), axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("\(isCommit ? "Commit" : "Větev") se připraví do dočasné složky, takže tvoje pracovní kopie zůstane beze změny. Agent běží jen pro čtení a využívá tvůj účet u daného poskytovatele.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Znovu vyhledat agenty") {
                    Task { await center.detectAgents() }
                }
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                Button("Spustit review") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(center.agent(agentKind) == nil || (!isCommit && base.isEmpty) || isStarting)
            }
            .padding(16)
        }
        .frame(width: 500)
        .task {
            if center.agents.isEmpty { await center.detectAgents() }
            if center.agent(agentKind) == nil, let first = center.agents.first { agentRaw = first.kind.rawValue }
            if case let .branch(branch) = target, base.isEmpty {
                let preferred = await model.repository.defaultBaseBranch()
                base = preferred.flatMap { name in model.branches.first { $0.name == name }?.name }
                    ?? model.branches.first { $0.name != branch.name && !$0.isRemote }?.name ?? ""
            }
        }
        .task(id: agentRaw) {
            modelID = rememberedModel(for: agentKind)
            await center.loadModels(for: agentKind)
        }
    }

    private func rememberedModel(for kind: AgentKind) -> String {
        let map = (try? JSONDecoder().decode([String: String].self, from: Data(storedModels.utf8))) ?? [:]
        return map[kind.rawValue] ?? ""
    }

    private func remember(model: String, for kind: AgentKind) {
        var map = (try? JSONDecoder().decode([String: String].self, from: Data(storedModels.utf8))) ?? [:]
        map[kind.rawValue] = model
        storedModels = String(decoding: (try? JSONEncoder().encode(map)) ?? Data("{}".utf8), as: UTF8.self)
    }

    private func start() {
        isStarting = true
        remember(model: modelID, for: agentKind)
        let kind = agentKind, chosenModel = modelID.isEmpty ? nil : modelID, text = instructions, baseBranch = base
        Task {
            await center.startReview(in: model, target: target, base: baseBranch, agentKind: kind, modelID: chosenModel, instructions: text)
            dismiss()
        }
    }
}
