import SwiftUI

/// Postranní panel: prostory (sbalitelné sekce) → repozitáře. Nejvýš dvě úrovně podle HIG.
struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @State private var filter = ""
    @State private var projectToRemove: Project?
    @State private var spaceToDelete: Space?

    private var groups: [Space?] {
        let unassigned = store.projects.contains { $0.spaceID == nil }
        return store.spaces.map(Optional.some) + (unassigned ? [nil] : [])
    }

    private func projects(in space: Space?) -> [Project] {
        store.projects(in: space?.id).filter {
            filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedProjectID) {
            ForEach(groups, id: \.?.id) { space in
                let projects = projects(in: space)
                if filter.isEmpty || !projects.isEmpty {
                    Section(isExpanded: expansion(for: space)) {
                        ForEach(projects) { project in
                            ProjectRow(project: project)
                                .tag(project.id)
                                .draggable(project.id.uuidString)
                                .contextMenu { projectMenu(project) }
                        }
                    } header: {
                        SpaceHeader(space: space)
                            .dropDestination(for: String.self) { items, _ in
                                for item in items {
                                    if let id = UUID(uuidString: item), let project = store.project(id) {
                                        store.move(project, to: space?.id)
                                    }
                                }
                                return true
                            }
                            .contextMenu { if let space { spaceMenu(space) } }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $filter, placement: .sidebar, prompt: "Filtrovat")
        .overlay {
            if store.projects.isEmpty {
                ContentUnavailableView {
                    Label("Žádné repozitáře", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("Přetáhni sem složku s repozitářem.")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Menu {
                    Button("Klonovat repozitář…") { store.presentedSheet = .clone }
                    Button("Přidat existující repozitář…") { store.presentedSheet = .addExisting }
                    Button("Nový repozitář…") { store.presentedSheet = .newRepository }
                    Divider()
                    Button("Nový prostor…") { store.presentedSheet = .newSpace }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Přidat")
                .help("Přidat repozitář nebo prostor")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                for url in urls {
                    do { try await store.addProject(at: url, spaceID: nil) } catch { store.globalError = error.localizedDescription }
                }
            }
            return true
        }
        .confirmationDialog(
            "Odebrat \(projectToRemove?.name ?? "") ze seznamu?",
            isPresented: Binding(get: { projectToRemove != nil }, set: { if !$0 { projectToRemove = nil } })
        ) {
            Button("Odebrat", role: .destructive) {
                if let projectToRemove { store.remove(projectToRemove) }
            }
        } message: {
            Text("Soubory na disku zůstanou beze změny.")
        }
        .confirmationDialog(
            "Smazat prostor „\(spaceToDelete?.name ?? "")“?",
            isPresented: Binding(get: { spaceToDelete != nil }, set: { if !$0 { spaceToDelete = nil } })
        ) {
            Button("Smazat prostor", role: .destructive) {
                if let spaceToDelete { store.deleteSpace(spaceToDelete) }
            }
        } message: {
            Text("Repozitáře se přesunou do Nezařazených.")
        }
    }

    private func expansion(for space: Space?) -> Binding<Bool> {
        let key = space?.id.uuidString ?? "unassigned"
        return Binding(
            get: { !store.collapsedGroups.contains(key) },
            set: { expanded in
                if expanded { store.collapsedGroups.remove(key) } else { store.collapsedGroups.insert(key) }
            }
        )
    }

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        Menu("Přesunout do prostoru") {
            ForEach(store.spaces) { space in
                Button(space.name) { store.move(project, to: space.id) }
                    .disabled(project.spaceID == space.id)
            }
            Divider()
            Button("Nezařazené") { store.move(project, to: nil) }
                .disabled(project.spaceID == nil)
        }
        Divider()
        Button("Zobrazit ve Finderu") { store.model(for: project).revealInFinder() }
        Button("Otevřít v Terminálu") { store.model(for: project).openInTerminal() }
        Divider()
        Button("Odebrat ze seznamu…", role: .destructive) { projectToRemove = project }
    }

    @ViewBuilder
    private func spaceMenu(_ space: Space) -> some View {
        Button("Upravit prostor…") { store.presentedSheet = .editSpace(space) }
        Divider()
        Button("Smazat prostor…", role: .destructive) { spaceToDelete = space }
    }
}

private struct SpaceHeader: View {
    let space: Space?

    var body: some View {
        if let space {
            Label {
                Text(space.name)
            } icon: {
                Image(systemName: space.symbol)
                    .foregroundStyle(space.color.color)
            }
        } else {
            Label("Nezařazené", systemImage: "tray")
        }
    }
}

private struct ProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        let model = store.model(for: project)
        Label {
            Text(project.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: project.exists ? "arrow.triangle.branch" : "exclamationmark.triangle.fill")
                .foregroundStyle(project.exists ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
        }
        .badge(model.hasLoaded ? model.status.changes.count : 0)
        .help(helpText(model))
    }

    private func helpText(_ model: RepositoryModel) -> String {
        var lines = [(project.path as NSString).abbreviatingWithTildeInPath]
        if !project.exists { lines.append("Složka nebyla nalezena") }
        if model.hasLoaded, let head = model.status.branch.head { lines.append("Větev \(head)") }
        return lines.joined(separator: "\n")
    }
}
