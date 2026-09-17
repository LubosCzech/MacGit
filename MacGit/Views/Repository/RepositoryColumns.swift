import SwiftUI
import GitKit

/// Prostřední sloupec: přepínač sekcí a seznam (změny, commity, větve, shelf).
struct RepositoryContentColumn: View {
    @Bindable var model: RepositoryModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Zobrazení", selection: $model.section) {
                ForEach(RepositoryModel.Section.allCases) { section in
                    Text(title(for: section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)

            Group {
                switch model.section {
                case .changes: ChangesList(model: model)
                case .history: HistoryList(model: model)
                case .branches: BranchesList(model: model)
                case .shelf: ShelfList(model: model)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func title(for section: RepositoryModel.Section) -> String {
        switch section {
        case .changes where !model.status.changes.isEmpty: "\(section.title) \(model.status.changes.count)"
        case .shelf where !model.workspace.shelves.isEmpty: "\(section.title) \(model.workspace.shelves.count)"
        default: section.title
        }
    }
}

/// Pravý sloupec: detail výběru.
struct RepositoryDetailColumn: View {
    let model: RepositoryModel

    var body: some View {
        switch model.section {
        case .changes: ChangeDetail(model: model)
        case .history: CommitDetail(model: model)
        case .branches: BranchDetail(model: model)
        case .shelf: ShelfDetail(model: model)
        }
    }
}

/// Toolbar podle HIG: větev a synchronizace uprostřed, inspektor vpravo (hledání přidává `.searchable`).
struct RepositoryToolbar: ToolbarContent {
    let model: RepositoryModel
    @Binding var inspectorShown: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            BranchMenu(model: model)
        }

        ToolbarSpacer(.fixed, placement: .principal)

        ToolbarItemGroup(placement: .principal) {
            Button {
                Task { await model.fetch() }
            } label: {
                Label("Fetch", systemImage: "arrow.trianglehead.2.clockwise")
            }
            .help("Fetch ze všech remotů (⌥⌘F)")

            Button {
                Task { await model.pull() }
            } label: {
                Label("Pull", systemImage: "arrow.down")
            }
            .badge(model.status.branch.behind)
            .help("Pull (⌘T)")

            Button {
                Task { await model.push() }
            } label: {
                Label("Push", systemImage: "arrow.up")
            }
            .badge(model.status.branch.ahead)
            .help(model.status.branch.upstream == nil ? "Push a nastavit upstream (⇧⌘K)" : "Push do \(model.status.branch.upstream ?? "") (⇧⌘K)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                inspectorShown.toggle()
            } label: {
                Label("Inspektor", systemImage: "sidebar.trailing")
            }
            .help(inspectorShown ? "Skrýt inspektor (⌥⌘I)" : "Zobrazit inspektor (⌥⌘I)")
        }
    }
}

struct BranchMenu: View {
    let model: RepositoryModel

    var body: some View {
        let local = model.branches.filter { !$0.isRemote }
        Menu {
            Section("Lokální větve") {
                ForEach(local) { branch in
                    Toggle(isOn: Binding(get: { branch.isCurrent }, set: { _ in Task { await model.checkout(branch) } })) {
                        Text(branch.name)
                    }
                    .disabled(branch.isCurrent)
                }
            }
            Divider()
            Button("Nová větev…") { model.promptNewBranch(from: nil) }
            Button("Zobrazit všechny větve") { model.section = .branches }
        } label: {
            Label(model.status.branch.head ?? "Odpojený HEAD", systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
        }
        .help("Aktuální větev")
    }
}
