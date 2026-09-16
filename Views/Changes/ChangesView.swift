import SwiftUI
import GitKit

struct ChangesView: View {
    @Bindable var model: RepositoryModel
    @State private var selection: Set<String> = []
    @State private var prompt: TextPrompt?
    @State private var pendingDiscard: [FileChange] = []

    var body: some View {
        HSplitView {
            changesList
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 460, maxHeight: .infinity)
            DiffView(diff: model.currentDiff)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .textPrompt($prompt)
        .onChange(of: selection) { _, newValue in
            model.selectedChangePath = newValue.count == 1 ? newValue.first : nil
        }
        .confirmationDialog(
            "Zahodit změny v \(pendingDiscard.count) souborech?",
            isPresented: Binding(get: { !pendingDiscard.isEmpty }, set: { if !$0 { pendingDiscard = [] } })
        ) {
            Button("Zahodit", role: .destructive) {
                let changes = pendingDiscard
                Task { await model.discard(changes) }
            }
        } message: {
            Text("Tuto akci nelze vrátit. Nové soubory budou smazány. Pokud si změny chceš schovat, použij Shelf.")
        }
    }

    private var changesList: some View {
        List(selection: $selection) {
            if model.status.changes.isEmpty && model.hasLoaded {
                EmptyStateView(title: "Pracovní strom je čistý", symbol: "checkmark.seal", message: "Žádné změny ke commitu.")
                    .listRowSeparator(.hidden)
            }
            ForEach(model.workspace.changelists) { changelist in
                let changes = model.changes(in: changelist)
                if !changes.isEmpty || changelist.id == model.workspace.activeChangelistID || model.workspace.changelists.count > 1 {
                    Section {
                        ForEach(changes) { change in
                            ChangeRow(model: model, change: change)
                                .tag(change.path)
                                .draggable(change.path)
                        }
                    } header: {
                        ChangelistHeader(model: model, changelist: changelist, changes: changes, prompt: $prompt)
                            .dropDestination(for: String.self) { paths, _ in
                                model.move(paths: paths, to: changelist.id)
                                return true
                            }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            contextMenu(for: paths)
        }
        .onDeleteCommand {
            pendingDiscard = model.status.changes.filter { selection.contains($0.path) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CommitPanel(model: model)
        }
    }

    @ViewBuilder
    private func contextMenu(for paths: Set<String>) -> some View {
        let changes = model.status.changes.filter { paths.contains($0.path) }
        if !changes.isEmpty {
            Button("Zahrnout do commitu", systemImage: "checkmark.square") { model.setIncluded(true, for: changes) }
            Button("Vyřadit z commitu", systemImage: "square") { model.setIncluded(false, for: changes) }
            Divider()
            Menu("Přesunout do changelistu") {
                ForEach(model.workspace.changelists) { list in
                    Button(list.name) { model.move(paths: Array(paths), to: list.id) }
                }
                Divider()
                Button("Nový changelist…") {
                    prompt = TextPrompt(title: "Nový changelist", placeholder: "Název", confirmTitle: "Vytvořit") { name in
                        let list = model.addChangelist(named: name)
                        model.move(paths: Array(paths), to: list.id)
                    }
                }
            }
            Button("Odložit do shelfu…", systemImage: "archivebox") {
                prompt = TextPrompt(title: "Odložit do shelfu", message: "Změny se uloží jako patch a z pracovního stromu zmizí.", placeholder: "Název", initialValue: model.activeChangelist.name, confirmTitle: "Odložit") { name in
                    Task { await model.shelve(changes, name: name) }
                }
            }
            Divider()
            Button("Zobrazit ve Finderu", systemImage: "folder") { model.revealInFinder(changes[0].path) }
            Button("Kopírovat cestu", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(changes.map(\.path).joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Zahodit změny…", systemImage: "arrow.uturn.backward", role: .destructive) { pendingDiscard = changes }
        }
    }
}

private struct ChangeRow: View {
    let model: RepositoryModel
    let change: FileChange

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { model.isIncluded(change) },
                set: { model.setIncluded($0, for: [change]) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            FileLabel(path: change.path, kind: change.kind)
            if let original = change.originalPath {
                Text("← \((original as NSString).lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(change.path)
    }
}

private struct ChangelistHeader: View {
    let model: RepositoryModel
    let changelist: Changelist
    let changes: [FileChange]
    @Binding var prompt: TextPrompt?

    private var isActive: Bool { changelist.id == model.workspace.activeChangelistID }

    var body: some View {
        let includedCount = changes.filter(model.isIncluded).count
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { !changes.isEmpty && includedCount == changes.count },
                set: { model.setIncluded($0, for: changes) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(changes.isEmpty)

            Text(changelist.name)
                .font(.headline)
                .foregroundStyle(.primary)
            if isActive {
                Text("aktivní")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.35)), in: .capsule)
            }
            Spacer()
            Text("\(changes.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Menu {
                Button("Nastavit jako aktivní", systemImage: "star") { model.setActive(changelist) }
                    .disabled(isActive)
                Button("Přejmenovat…", systemImage: "pencil") {
                    prompt = TextPrompt(title: "Přejmenovat changelist", placeholder: "Název", initialValue: changelist.name, confirmTitle: "Uložit") { model.rename(changelist, to: $0) }
                }
                Button("Nový changelist…", systemImage: "plus") {
                    prompt = TextPrompt(title: "Nový changelist", placeholder: "Název", confirmTitle: "Vytvořit") { model.addChangelist(named: $0) }
                }
                Divider()
                Button("Odložit celý do shelfu…", systemImage: "archivebox") {
                    prompt = TextPrompt(title: "Odložit do shelfu", placeholder: "Název", initialValue: changelist.name, confirmTitle: "Odložit") { name in
                        Task { await model.shelve(changes, name: name) }
                    }
                }
                .disabled(changes.isEmpty)
                Divider()
                Button("Smazat changelist", systemImage: "trash", role: .destructive) { model.delete(changelist) }
                    .disabled(model.workspace.changelists.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}
