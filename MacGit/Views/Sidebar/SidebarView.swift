import SwiftUI

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var projectToRemove: Project?

    private var visibleSpaces: [Space?] {
        if let id = store.selectedSpaceID, let space = store.space(id) { return [space] }
        let unassigned = store.projects.contains { $0.spaceID == nil }
        return store.spaces.map(Optional.some) + (unassigned ? [nil] : [])
    }

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedProjectID) {
            ForEach(visibleSpaces, id: \.?.id) { space in
                Section {
                    let projects = store.projects(in: space?.id)
                    if projects.isEmpty {
                        Text("Žádné repozitáře")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                    }
                    ForEach(projects) { project in
                        ProjectRow(project: project, space: space)
                            .tag(project.id)
                            .contextMenu { contextMenu(for: project) }
                            .draggable(project.id.uuidString)
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
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SpaceFilterBar()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Menu {
                    Button("Klonovat repozitář…", systemImage: "square.and.arrow.down") { store.presentedSheet = .clone }
                    Button("Přidat existující…", systemImage: "folder.badge.plus") { store.presentedSheet = .addExisting }
                    Button("Nový repozitář…", systemImage: "plus.square.dashed") { store.presentedSheet = .newRepository }
                } label: {
                    Label("Přidat", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(.glass)
                .help("Spravovat prostory a účty")
            }
            .padding(10)
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                for url in urls {
                    do { try await store.addProject(at: url, spaceID: store.selectedSpaceID) } catch { store.globalError = error.localizedDescription }
                }
            }
            return true
        }
        .confirmationDialog("Odebrat \(projectToRemove?.name ?? "") ze seznamu?", isPresented: Binding(get: { projectToRemove != nil }, set: { if !$0 { projectToRemove = nil } })) {
            Button("Odebrat", role: .destructive) {
                if let projectToRemove { store.remove(projectToRemove) }
            }
        } message: {
            Text("Soubory na disku zůstanou beze změny.")
        }
    }

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        Menu("Přesunout do prostoru") {
            ForEach(store.spaces) { space in
                Button {
                    store.move(project, to: space.id)
                } label: {
                    Label(space.name, systemImage: space.symbol)
                }
                .disabled(project.spaceID == space.id)
            }
            Divider()
            Button("Nezařazené") { store.move(project, to: nil) }
                .disabled(project.spaceID == nil)
        }
        Divider()
        Button("Zobrazit ve Finderu", systemImage: "folder") { store.model(for: project).revealInFinder() }
        Button("Otevřít v Terminálu", systemImage: "terminal") { store.model(for: project).openInTerminal() }
        Divider()
        Button("Odebrat ze seznamu…", systemImage: "minus.circle", role: .destructive) { projectToRemove = project }
    }
}

private struct SpaceHeader: View {
    let space: Space?

    var body: some View {
        HStack(spacing: 6) {
            if let space {
                Image(systemName: space.symbol).foregroundStyle(space.color.color)
                Text(space.name)
            } else {
                Image(systemName: "tray")
                Text("Nezařazené")
            }
        }
    }
}

private struct ProjectRow: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let space: Space?

    var body: some View {
        let model = store.model(for: project)
        HStack(spacing: 10) {
            Image(systemName: project.exists ? "externaldrive.connected.to.line.below" : "exclamationmark.triangle.fill")
                .foregroundStyle(project.exists ? (space?.color.color ?? .secondary) : .orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).lineLimit(1)
                if model.hasLoaded, let head = model.status.branch.head {
                    Label(head, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text((project.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            if model.hasLoaded, !model.status.changes.isEmpty {
                Text("\(model.status.changes.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.18), in: .capsule)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Přepínač prostorů – kapsle z tekutého skla.
private struct SpaceFilterBar: View {
    @Environment(AppStore.self) private var store
    @Namespace private var glass

    var body: some View {
        // Obal s nulovou ideální šířkou – jinak by ScrollView roztáhl celý sloupec postranního panelu.
        Color.clear
            .frame(height: 36)
            .overlay(alignment: .leading) { chips }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    chip(title: "Vše", symbol: "square.stack.3d.up.fill", color: .accentColor, id: nil)
                    ForEach(store.spaces) { space in
                        chip(title: space.name, symbol: space.symbol, color: space.color.color, id: space.id)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func chip(title: String, symbol: String, color: Color, id: UUID?) -> some View {
        let selected = store.selectedSpaceID == id
        return Button {
            withAnimation(.smooth) { store.selectedSpaceID = id }
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(color).interactive() : .regular.interactive(), in: .capsule)
        .glassEffectID(id?.uuidString ?? "all", in: glass)
    }
}
