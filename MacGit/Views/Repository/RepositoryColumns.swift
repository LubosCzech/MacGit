import SwiftUI
import GitKit

/// Prostřední sloupec: hlavička repozitáře, přepínač sekcí a seznam (změny, commity, větve, shelf).
///
/// Hlavička a seznam jsou pod sebou ve VStacku, ne přes `safeAreaInset`: seznam jinak sahá
/// až k toolbaru a dostane k odsazení hlavičky ještě odsazení toolbaru – nad soubory pak
/// zůstává prázdná díra.
struct RepositoryContentColumn: View {
    @Bindable var model: RepositoryModel
    @AppStorage("changesAsTree") private var changesAsTree = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepositoryHeader(model: model)
            SectionSwitcher(model: model, changesAsTree: $changesAsTree)

            Group {
                switch model.section {
                case .changes: ChangesList(model: model)
                case .history: HistoryList(model: model)
                case .branches: BranchesList(model: model)
                case .shelf: ShelfList(model: model)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Hlavička sloupce: které repo je otevřené a akce, které se týkají jeho a tohoto seznamu.
private struct RepositoryHeader: View {
    let model: RepositoryModel
    @Environment(AppStore.self) private var store
    @AppStorage("changesAsTree") private var changesAsTree = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text((model.project.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(model.project.path)
            }
            Spacer(minLength: 0)
            Menu {
                Section("Seznam změn") {
                    Picker("Zobrazení", selection: Binding(
                        get: { changesAsTree },
                        set: { value in withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { changesAsTree = value } }
                    )) {
                        Label("Seznam", systemImage: "list.bullet").tag(false)
                        Label("Strom složek", systemImage: "list.bullet.indent").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Repozitář") {
                    Button("Zobrazit ve Finderu") { model.revealInFinder() }
                    Button("Otevřít v Terminálu") { model.openInTerminal() }
                    Button("Kopírovat cestu") { NSPasteboard.copy(model.project.path) }
                    Divider()
                    Button("Nastavení repozitáře…") {
                        model.inspectorTab = .repository
                        store.inspectorShown = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .glassEffect(.regular.interactive(), in: .circle)
            .fixedSize()
            .accessibilityLabel("Možnosti seznamu a repozitáře")
            .help("Zobrazení seznamu a akce repozitáře")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// Plovoucí skleněný přepínač sekcí. Vybraná položka je skleněná „kapka“, která při přepnutí
/// přejde na novou pozici a popisky zůstávají čitelné.
private struct SectionSwitcher: View {
    @Bindable var model: RepositoryModel
    @Binding var changesAsTree: Bool

    var body: some View {
        HStack(spacing: 6) {
            RevisionTabPicker(values: RepositoryModel.Section.allCases, selection: $model.section) { section in
                HStack(spacing: 5) {
                    Text(section.title).lineLimit(1).fixedSize()
                    if let count = count(for: section) {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .fixedSize()
                            .foregroundStyle(model.section == section ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.textSecondary))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                model.section == section ? AnyShapeStyle(.black.opacity(0.22)) : AnyShapeStyle(.quaternary),
                                in: .capsule
                            )
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func count(for section: RepositoryModel.Section) -> Int? {
        switch section {
        case .changes: model.status.changes.isEmpty ? nil : model.status.changes.count
        case .shelf: model.workspace.shelves.isEmpty ? nil : model.workspace.shelves.count
        default: nil
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
