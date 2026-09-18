import SwiftUI

/// Postranní panel: prostory (sbalitelné sekce) → repozitáře. Nejvýš dvě úrovně podle HIG.
/// Výběr je tónovaná skleněná kapsle, která se mezi řádky stěhuje.
struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter = ""
    @State private var projectToRemove: Project?
    @State private var spaceToDelete: Space?
    @State private var isRefreshingAll = false
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionGlass

    private var groups: [Space?] {
        let unassigned = store.projects.contains { $0.spaceID == nil }
        return store.spaces.map(Optional.some) + (unassigned ? [nil] : [])
    }

    private func projects(in space: Space?) -> [Project] {
        store.projects(in: space?.id).filter(matchesFilter)
    }

    private func matchesFilter(_ project: Project) -> Bool {
        filter.isEmpty
            || project.name.localizedCaseInsensitiveContains(filter)
            || project.path.localizedCaseInsensitiveContains(filter)
    }

    /// Pořadí řádků pro pohyb šipkami – jen to, co je opravdu vidět.
    private var navigableProjects: [Project] {
        groups.flatMap { space in isExpanded(space) ? projects(in: space) : [] }
    }

    @Environment(\.interfaceStyle) private var style

    var body: some View {
        Group {
            switch style {
            case .revision: brandedLayout
            case .classic: classicList
            }
        }
        .onChange(of: store.sidebarSearchFocusRequests) { searchFocused = true }
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

    // MARK: Revision

    private var brandedLayout: some View {
        VStack(spacing: 0) {
            identity
            searchField
            content
            footer
        }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
    }

    // MARK: Klasický – systémový postranní panel

    private var classicList: some View {
        List(selection: Binding(get: { store.selectedProjectID }, set: { store.selectedProjectID = $0 })) {
            ForEach(groups, id: \.?.id) { space in
                let projects = projects(in: space)
                if filter.isEmpty || !projects.isEmpty {
                    Section(isExpanded: expansion(for: space)) {
                        ForEach(projects) { project in
                            ClassicProjectRow(project: project)
                                .tag(project.id)
                                .draggable(project.id.uuidString)
                                .contextMenu { projectMenu(project) }
                        }
                    } header: {
                        Label {
                            Text(space?.name ?? "Nezařazené")
                        } icon: {
                            Image(systemName: space?.symbol ?? "tray")
                                .foregroundStyle(space?.color.color ?? .secondary)
                        }
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
        .searchFocused($searchFocused)
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
                addMenu
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Klonovat repozitář…") { store.presentedSheet = .clone }
            Button("Přidat existující repozitář…") { store.presentedSheet = .addExisting }
            Button("Nový repozitář…") { store.presentedSheet = .newRepository }
            Divider()
            Button("Nový prostor…") { store.presentedSheet = .newSpace }
        } label: {
            Label("Přidat", systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Přidat")
        .help("Přidat repozitář nebo prostor")
    }

    // MARK: Části

    private var identity: some View {
        HStack(spacing: 10) {
            RevisionIdentity(size: 32)
            Text("Revision")
                .font(.system(size: 17, weight: .bold))
                .kerning(-0.3)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField("Filtrovat…", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .accessibilityLabel("Filtrovat repozitáře")
                .onKeyPress(.escape) {
                    guard !filter.isEmpty else { return .ignored }
                    filter = ""
                    return .handled
                }
            if filter.isEmpty {
                Text("⌘K")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
            } else {
                Button {
                    filter = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Vymazat filtr")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GlassEffectContainer(spacing: 14) {
                    // VStack (ne Lazy): řádků jsou desítky a jen tak se skleněná kapsle
                    // výběru dokáže mezi nimi opravdu přestěhovat.
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(groups, id: \.?.id) { space in
                            let projects = projects(in: space)
                            if filter.isEmpty || !projects.isEmpty {
                                SpaceHeader(space: space, isExpanded: expansion(for: space))
                                    .dropDestination(for: String.self) { items, _ in
                                        for item in items {
                                            if let id = UUID(uuidString: item), let project = store.project(id) {
                                                store.move(project, to: space?.id)
                                            }
                                        }
                                        return true
                                    }
                                    .contextMenu { if let space { spaceMenu(space) } }

                                if isExpanded(space) {
                                    ForEach(projects) { project in
                                        ProjectRow(
                                            project: project,
                                            isSelected: project.id == store.selectedProjectID
                                        ) {
                                            select(project.id)
                                        }
                                        .matchedGeometryEffect(id: project.id, in: selectionGlass, isSource: true)
                                        .id(project.id)
                                        .draggable(project.id.uuidString)
                                        .contextMenu { projectMenu(project) }
                                    }
                                }
                            }
                        }
                    }
                    // Skleněná kapsle výběru leží POD řádky, takže se text nikdy neztratí ve skle,
                    // a přes matchedGeometryEffect se mezi řádky plynule přestěhuje.
                    .background(alignment: .topLeading) {
                        if let id = store.selectedProjectID, navigableProjects.contains(where: { $0.id == id }) {
                            // Tónovaná kapsle, ne glassEffect: sklo se skládá NAD obsah a popisek by zmizel.
                            SelectionCapsule()
                                .matchedGeometryEffect(id: id, in: selectionGlass, isSource: false)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: store.selectedProjectID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay {
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("Žádné repozitáře", systemImage: "arrow.triangle.branch")
                    } description: {
                        Text("Přetáhni sem složku s repozitářem.")
                    }
                } else if !filter.isEmpty && navigableProjects.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Klonovat repozitář…") { store.presentedSheet = .clone }
                Button("Přidat existující repozitář…") { store.presentedSheet = .addExisting }
                Button("Nový repozitář…") { store.presentedSheet = .newRepository }
                Divider()
                Button("Nový prostor…") { store.presentedSheet = .newSpace }
            } label: {
                Label("Přidat repozitář", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Přidat")
            .help("Přidat repozitář nebo prostor")

            Spacer(minLength: 0)

            Button {
                refreshAll()
            } label: {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .symbolEffect(.rotate, isActive: isRefreshingAll)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(store.projects.isEmpty)
            .accessibilityLabel("Obnovit všechny repozitáře")
            .help("Načíst stav všech repozitářů znovu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: Akce

    private func select(_ id: UUID) {
        guard store.selectedProjectID != id else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
            store.selectedProjectID = id
        }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let projects = navigableProjects
        guard !projects.isEmpty else { return .ignored }
        guard let current = projects.firstIndex(where: { $0.id == store.selectedProjectID }) else {
            select(projects[0].id)
            return .handled
        }
        let next = current + offset
        guard projects.indices.contains(next) else { return .handled }
        select(projects[next].id)
        return .handled
    }

    private func refreshAll() {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        Task {
            for project in store.projects where project.exists {
                await store.model(for: project).refresh()
            }
            isRefreshingAll = false
        }
    }

    private func isExpanded(_ space: Space?) -> Bool {
        !store.collapsedGroups.contains(key(for: space))
    }

    private func key(for space: Space?) -> String { space?.id.uuidString ?? "unassigned" }

    private func expansion(for space: Space?) -> Binding<Bool> {
        let key = key(for: space)
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

/// Hlavička prostoru – sbalovací tlačítko se symbolem a barvou prostoru.
private struct SpaceHeader: View {
    let space: Space?
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: space?.symbol ?? "tray")
                    .font(.system(size: 11))
                    .foregroundStyle(space?.color.color ?? Theme.textSecondary)
                Text(space?.name ?? "Nezařazené")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(space?.name ?? "Nezařazené")
        .accessibilityValue(isExpanded ? "rozbaleno" : "sbaleno")
    }
}

private struct ProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        let model = store.model(for: project)
        let count = model.hasLoaded ? model.status.changes.count : 0

        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: project.exists ? "arrow.triangle.branch" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(project.exists ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.orange))
                Text(project.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.textSecondary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(isSelected ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(.quaternary), in: .capsule)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .background {
            if !isSelected && isHovering {
                RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.4))
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(helpText(model))
    }

    private func helpText(_ model: RepositoryModel) -> String {
        var lines = [(project.path as NSString).abbreviatingWithTildeInPath]
        if !project.exists { lines.append("Složka nebyla nalezena") }
        if model.hasLoaded, let head = model.status.branch.head { lines.append("Větev \(head)") }
        return lines.joined(separator: "\n")
    }
}

/// Kapsle výběru podle návrhu: tónovaná výplň, jemný obrys a horní odlesk jako u skla.
struct SelectionCapsule: View {
    var cornerRadius: CGFloat = 9

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.selectionTint)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), Theme.accent.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            }
            .shadow(color: Theme.accent.opacity(0.22), radius: 8, y: 3)
    }
}

/// Řádek repozitáře v klasickém postranním panelu – systémový `Label` s odznakem.
private struct ClassicProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        let model = store.model(for: project)
        Label {
            Text(project.name).lineLimit(1)
        } icon: {
            Image(systemName: project.exists ? "arrow.triangle.branch" : "exclamationmark.triangle.fill")
                .foregroundStyle(project.exists ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
        }
        .badge(model.hasLoaded ? model.status.changes.count : 0)
        .help((project.path as NSString).abbreviatingWithTildeInPath)
    }
}
