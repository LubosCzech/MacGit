import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var model: RepositoryModel? {
        store.project(store.selectedProjectID).map(store.model(for:))
    }

    var body: some View {
        @Bindable var store = store

        Group {
            if let model {
                RepositoryWindow(model: model, columnVisibility: $columnVisibility, inspectorShown: $store.inspectorShown)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
                } detail: {
                    WelcomeView()
                }
                .navigationTitle("MacGit")
            }
        }
        .sheet(item: $store.presentedSheet) { kind in
            switch kind {
            case .clone: CloneSheet()
            case .addExisting: AddExistingSheet()
            case .newRepository: NewRepositorySheet()
            case .newSpace: SpaceEditor(space: Space.new()) { store.spaces.append($0) }
            case let .editSpace(space):
                SpaceEditor(space: space) { saved in
                    if let index = store.spaces.firstIndex(where: { $0.id == saved.id }) { store.spaces[index] = saved }
                }
            }
        }
        .alert("Chyba", isPresented: Binding(get: { store.globalError != nil }, set: { if !$0 { store.globalError = nil } })) {
            Button("OK") { store.globalError = nil }
        } message: {
            Text(store.globalError ?? "")
        }
    }
}

/// Okno s otevřeným repozitářem: postranní panel │ seznam │ detail │ inspektor.
private struct RepositoryWindow: View {
    @Bindable var model: RepositoryModel
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var inspectorShown: Bool
    @State private var now = Date.now

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } content: {
            RepositoryContentColumn(model: model)
                .navigationSplitViewColumnWidth(min: 300, ideal: 370, max: 540)
        } detail: {
            RepositoryDetailColumn(model: model)
        }
        .inspector(isPresented: $inspectorShown) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 440)
        }
        .navigationTitle(model.project.name)
        .navigationSubtitle(model.statusLine(now: now))
        .searchable(text: $model.searchText, placement: .toolbar, prompt: model.section.searchPrompt)
        .toolbar { RepositoryToolbar(model: model, inspectorShown: $inspectorShown) }
        .focusedSceneValue(\.repositoryModel, model)
        .alert("Git hlásí chybu", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: $model.sshUnlockRequest) { request in
            SSHUnlockSheet(model: model, request: request)
        }
        .textPrompt($model.pendingPrompt)
        .sheet(item: $model.reviewSheetTarget) { target in
            StartReviewSheet(model: model, target: target)
        }
        .confirmationDialog(
            model.branchToDelete.map { $0.isRemote ? "Smazat větev \($0.name) na serveru?" : "Smazat větev \($0.name)?" } ?? "",
            isPresented: Binding(get: { model.branchToDelete != nil }, set: { if !$0 { model.branchToDelete = nil } }),
            presenting: model.branchToDelete
        ) { branch in
            Button(branch.isRemote ? "Smazat na serveru" : "Smazat", role: .destructive) {
                Task { await model.deleteBranch(branch, force: false) }
            }
            if !branch.isRemote {
                Button("Smazat i nesloučenou", role: .destructive) {
                    Task { await model.deleteBranch(branch, force: true) }
                }
            }
        } message: { branch in
            Text(branch.isRemote ? "Větev zmizí ze serveru pro všechny." : "Commity, které nejsou v jiné větvi, se ztratí.")
        }
        .confirmationDialog(
            "Smazat odložené změny „\(model.shelfToDelete?.name ?? "")“?",
            isPresented: Binding(get: { model.shelfToDelete != nil }, set: { if !$0 { model.shelfToDelete = nil } }),
            presenting: model.shelfToDelete
        ) { shelf in
            Button("Smazat", role: .destructive) { model.deleteShelf(shelf) }
        } message: { _ in
            Text("Tuto akci nelze vrátit.")
        }
        .onChange(of: model.project.id, initial: true) { model.activate() }
        .task {
            // Relativní čas v podtitulu („před 2 min“) se obnovuje průběžně.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
    }
}

struct WelcomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("MacGit").font(.largeTitle.weight(.semibold))
                Text(store.projects.isEmpty ? "Přidej první repozitář a roztřiď ho do prostoru." : "Vyber repozitář v postranním panelu.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Klonovat repozitář…") { store.presentedSheet = .clone }
                    .buttonStyle(.borderedProminent)
                Button("Přidat existující…") { store.presentedSheet = .addExisting }
                Button("Nový repozitář…") { store.presentedSheet = .newRepository }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension FocusedValues {
    @Entry var repositoryModel: RepositoryModel?
}
