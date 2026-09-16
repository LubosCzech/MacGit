import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var store = store

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 400)
        } detail: {
            if let project = store.project(store.selectedProjectID) {
                RepositoryView(model: store.model(for: project))
                    .id(project.id)
            } else {
                WelcomeView()
            }
        }
        .sheet(item: $store.presentedSheet) { kind in
            switch kind {
            case .clone: CloneSheet()
            case .addExisting: AddExistingSheet()
            case .newRepository: NewRepositorySheet()
            }
        }
        .alert("Chyba", isPresented: Binding(get: { store.globalError != nil }, set: { if !$0 { store.globalError = nil } })) {
            Button("OK") { store.globalError = nil }
        } message: {
            Text(store.globalError ?? "")
        }
    }
}

struct WelcomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 130, height: 130)
                .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 34))

            VStack(spacing: 6) {
                Text("Vítej v MacGitu").font(.largeTitle.bold())
                Text(store.projects.isEmpty ? "Přidej první repozitář a roztřiď ho do prostoru." : "Vyber repozitář v postranním panelu.")
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button { store.presentedSheet = .clone } label: {
                        Label("Klonovat", systemImage: "square.and.arrow.down")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.glassProminent)

                    Button { store.presentedSheet = .addExisting } label: {
                        Label("Přidat existující", systemImage: "folder.badge.plus")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.glass)

                    Button { store.presentedSheet = .newRepository } label: {
                        Label("Nový repozitář", systemImage: "plus.square.dashed")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
