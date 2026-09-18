import SwiftUI
import GitKit

/// Seznam změněných souborů seskupený do changelistů + formulář commitu.
struct ChangesList: View {
    @Bindable var model: RepositoryModel
    @State private var pendingDiscard: [FileChange] = []
    @AppStorage("changesAsTree") private var asTree = false
    /// Složky, jejichž rozbalení uživatel změnil oproti výchozímu stavu.
    @State private var toggledFolders: Set<String> = []

    private func filtered(_ changes: [FileChange]) -> [FileChange] {
        guard !model.searchText.isEmpty else { return changes }
        return changes.filter { $0.path.localizedCaseInsensitiveContains(model.searchText) }
    }

    var body: some View {
        List(selection: $model.selectedChangePaths) {
            ForEach(model.workspace.changelists) { changelist in
                let changes = filtered(model.changes(in: changelist))
                let isActive = changelist.id == model.workspace.activeChangelistID
                if !changes.isEmpty || isActive || model.workspace.changelists.count > 1 {
                    Section {
                        if asTree {
                            FileTreeRows(model: model, nodes: model.fileTree(for: changes), toggled: $toggledFolders, discard: { pendingDiscard = $0 })
                        } else {
                            ForEach(changes) { change in
                                ChangeRow(model: model, change: change)
                                    .tag(change.path)
                                    .draggable(change.path)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                            }
                        }
                    } header: {
                        ChangelistHeader(model: model, changelist: changelist, changes: changes)
                            .dropDestination(for: String.self) { paths, _ in
                                model.move(paths: paths, to: changelist.id)
                                return true
                            }
                    }
                }
            }
        }
        .overlay {
            if model.hasLoaded && model.status.changes.isEmpty {
                EmptyStateView(title: "Žádné změny", symbol: "checkmark.circle", message: "Pracovní složka odpovídá poslednímu commitu.")
            } else if !model.searchText.isEmpty && filtered(model.status.changes).isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            contextMenu(for: paths)
        } primaryAction: { paths in
            if let path = paths.first { NSWorkspace.shared.open(model.project.url.appendingPathComponent(path)) }
        }
        .onDeleteCommand {
            pendingDiscard = model.status.changes.filter { model.selectedChangePaths.contains($0.path) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.suggestsGitignore {
                GitignoreBanner(model: model)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.status.changes.isEmpty || model.amend {
                CommitComposer(model: model)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .confirmationDialog(
            pendingDiscard.count == 1 ? "Zahodit změny v souboru \(pendingDiscard[0].fileName)?" : "Zahodit změny v \(pendingDiscard.count) souborech?",
            isPresented: Binding(get: { !pendingDiscard.isEmpty }, set: { if !$0 { pendingDiscard = [] } })
        ) {
            Button("Zahodit změny", role: .destructive) {
                let changes = pendingDiscard
                Task { await model.discard(changes) }
            }
        } message: {
            Text("Tuto akci nelze vrátit. Nové soubory budou smazány. Chceš-li si změny schovat, použij Odložit do shelfu.")
        }
    }

    @ViewBuilder
    private func contextMenu(for paths: Set<String>) -> some View {
        let changes = model.status.changes.filter { paths.contains($0.path) }
        if !changes.isEmpty {
            Button("Zahrnout do commitu") { model.setIncluded(true, for: changes) }
            Button("Vyřadit z commitu") { model.setIncluded(false, for: changes) }
            Menu("Přesunout do changelistu") {
                ForEach(model.workspace.changelists) { list in
                    Button(list.name) { model.move(paths: Array(paths), to: list.id) }
                }
                Divider()
                Button("Nový changelist…") {
                    model.pendingPrompt = TextPrompt(title: "Nový changelist", placeholder: "Název", confirmTitle: "Vytvořit") { name in
                        let list = model.addChangelist(named: name)
                        model.move(paths: Array(paths), to: list.id)
                    }
                }
            }
            Divider()
            Button("Odložit do shelfu…") { model.promptShelve(changes, suggestedName: model.activeChangelist.name) }
            Divider()
            Button("Zobrazit ve Finderu") { model.revealInFinder(changes[0].path) }
            Button("Kopírovat cestu") { NSPasteboard.copy(changes.map(\.path).joined(separator: "\n")) }
            Divider()
            Button("Zahodit změny…", role: .destructive) { pendingDiscard = changes }
        }
    }
}

private struct ChangeRow: View {
    let model: RepositoryModel
    let change: FileChange
    var showsDirectory = true

    var body: some View {
        HStack(spacing: 9) {
            Toggle("Zahrnout do commitu", isOn: Binding(
                get: { model.isIncluded(change) },
                set: { model.setIncluded($0, for: [change]) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            FileIcon(path: change.path, size: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(change.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.isIncluded(change) ? Theme.textPrimary : Theme.textSecondary)
                    .strikethrough(change.kind == .deleted)
                    .lineLimit(1)
                if showsDirectory && !change.directory.isEmpty {
                    Text(change.directory)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let original = change.originalPath {
                    Text("← " + original)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            StatusLetter(kind: change.kind)
        }
        // Ve stromu je řádek jednořádkový – stejně vysoký jako řádek složky.
        .padding(.vertical, showsDirectory ? 6 : 2)
        .help(change.path)
    }
}

private struct ChangelistHeader: View {
    let model: RepositoryModel
    let changelist: Changelist
    let changes: [FileChange]

    private var isActive: Bool { changelist.id == model.workspace.activeChangelistID }

    var body: some View {
        let includedCount = changes.filter(model.isIncluded).count
        HStack(spacing: 6) {
            Toggle("Zahrnout celý changelist", isOn: Binding(
                get: { !changes.isEmpty && includedCount == changes.count },
                set: { model.setIncluded($0, for: changes) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(changes.isEmpty)

            Text(changelist.name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if isActive {
                Text("aktivní")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.tintedFill(Theme.accent), in: .capsule)
            }
            Spacer()
            Text("\(changes.count) souborů")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
            Menu {
                Button("Nastavit jako aktivní") { model.setActive(changelist) }
                    .disabled(isActive)
                Button("Přejmenovat…") {
                    model.pendingPrompt = TextPrompt(title: "Přejmenovat changelist", placeholder: "Název", initialValue: changelist.name, confirmTitle: "Přejmenovat") { model.rename(changelist, to: $0) }
                }
                Button("Nový changelist…") {
                    model.pendingPrompt = TextPrompt(title: "Nový changelist", placeholder: "Název", confirmTitle: "Vytvořit") { model.addChangelist(named: $0) }
                }
                Divider()
                Button("Odložit do shelfu…") { model.promptShelve(changes, suggestedName: changelist.name) }
                    .disabled(changes.isEmpty)
                Divider()
                Button("Smazat changelist", role: .destructive) { model.delete(changelist) }
                    .disabled(model.workspace.changelists.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Akce changelistu \(changelist.name)")
        }
    }
}

/// Detail: diff vybraného souboru.
struct ChangeDetail: View {
    let model: RepositoryModel

    var body: some View {
        if model.selectedChangePaths.count > 1 {
            let changes = model.status.changes.filter { model.selectedChangePaths.contains($0.path) }
            ContentUnavailableView {
                Label("Vybráno \(changes.count) souborů", systemImage: "doc.on.doc")
            } description: {
                Text("Pro zobrazení rozdílů vyber jeden soubor.")
            } actions: {
                Button("Zahrnout do commitu") { model.setIncluded(true, for: changes) }
                Button("Odložit do shelfu…") { model.promptShelve(changes, suggestedName: model.activeChangelist.name) }
            }
        } else if model.status.changes.isEmpty && model.hasLoaded {
            EmptyStateView(title: "Vše je commitnuté", symbol: "checkmark.seal", message: model.status.branch.ahead > 0 ? "Na push čeká \(model.status.branch.ahead) commitů." : nil)
        } else {
            DiffView(diff: model.currentDiff)
        }
    }
}

/// Rekurzivní řádky stromu složek.
private struct FileTreeRows: View {
    static let autoCollapseThreshold = 150

    let model: RepositoryModel
    let nodes: [FileTreeNode]
    /// Uzly, u kterých uživatel přepnul výchozí rozbalení.
    @Binding var toggled: Set<String>
    let discard: ([FileChange]) -> Void

    var body: some View {
        ForEach(nodes) { node in
            if let change = node.change {
                ChangeRow(model: model, change: change, showsDirectory: false)
                    .tag(change.path)
                    .draggable(change.path)
                    .listRowSeparator(.hidden)
            } else {
                // Velké složky (typicky build výstupy) jsou ve výchozím stavu sbalené.
                let expandedByDefault = node.fileCount <= Self.autoCollapseThreshold
                DisclosureGroup(isExpanded: Binding(
                    get: { toggled.contains(node.id) ? !expandedByDefault : expandedByDefault },
                    set: { expanded in
                        if expanded == expandedByDefault { toggled.remove(node.id) } else { toggled.insert(node.id) }
                    }
                )) {
                    FileTreeRows(model: model, nodes: node.children, toggled: $toggled, discard: discard)
                } label: {
                    // Řádek složky nemá tag, takže se nedá vybrat – výběr souborů pod ním ale musí fungovat.
                    FolderRow(model: model, node: node, discard: discard)
                }
                .listRowSeparator(.hidden)
            }
        }
    }
}

private struct FolderRow: View {
    let model: RepositoryModel
    let node: FileTreeNode
    let discard: ([FileChange]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Dva zdroje (všechny/některé zahrnuté) stačí na smíšený stav – bez vazby na každý soubor.
            let changes = node.changes
            let included = changes.lazy.filter(model.isIncluded).count
            Toggle(sources: [
                Binding(get: { included == changes.count && !changes.isEmpty }, set: { model.setIncluded($0, for: changes) }),
                Binding(get: { included > 0 }, set: { model.setIncluded($0, for: changes) })
            ], isOn: \.self) {
                Text("Zahrnout složku \(node.name)")
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(node.name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(node.fileCount)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .help(node.path)
        .contextMenu {
            let changes = node.changes
            Button("Zahrnout do commitu") { model.setIncluded(true, for: changes) }
            Button("Vyřadit z commitu") { model.setIncluded(false, for: changes) }
            Menu("Přesunout do changelistu") {
                ForEach(model.workspace.changelists) { list in
                    Button(list.name) { model.move(paths: changes.map(\.path), to: list.id) }
                }
            }
            Divider()
            Button("Odložit do shelfu…") { model.promptShelve(changes, suggestedName: (node.path as NSString).lastPathComponent) }
            Button("Zobrazit ve Finderu") { model.revealInFinder(node.path) }
            Divider()
            Button("Zahodit změny ve složce…", role: .destructive) { discard(changes) }
        }
    }
}

/// Nabídka vytvoření .gitignore, když repozitář obsahuje tisíce nesledovaných souborů.
private struct GitignoreBanner: View {
    let model: RepositoryModel

    var body: some View {
        let untracked = model.status.changes.lazy.filter(\.isUntracked).count
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.badge.gearshape")
                .font(.title3)
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Repozitář nemá .gitignore")
                    .fontWeight(.semibold)
                Text("Git vidí \(untracked) nesledovaných souborů – nejspíš build výstupy. Soubor .gitignore je z repozitáře vyřadí.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Vytvořit .gitignore") { model.createGitignore() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Theme.warning.opacity(0.22)), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}
