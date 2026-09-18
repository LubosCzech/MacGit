import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    private var model: RepositoryModel? {
        store.project(store.selectedProjectID).map(store.model(for:))
    }

    var body: some View {
        @Bindable var store = store

        Group {
            if let model {
                RepositoryWindow(model: model)
            } else {
                WindowShell(model: nil)
                    .navigationTitle("Revision")
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
        .errorSheet($store.globalError)
    }
}

/// Okno s otevřeným repozitářem: společná kostra + chování repozitáře (dialogy, průběh, obnova).
private struct RepositoryWindow: View {
    @Bindable var model: RepositoryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WindowShell(model: model)
        .overlay(alignment: .bottom) {
            if let busy = model.busyTitle {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(busy)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.busyTitle)
        // Titulek zůstává kvůli Mission Control a menu Okno; v toolbaru se nezobrazuje.
        .navigationTitle(model.project.name)
        .focusedSceneValue(\.repositoryModel, model)
        .errorSheet($model.errorMessage)
        .sheet(item: $model.sshUnlockRequest) { request in
            SSHUnlockSheet(model: model, request: request)
        }
        .sheet(item: $model.hostTrustRequest) { request in
            HostTrustSheet(model: model, request: request)
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
                Text("Revision").font(.largeTitle.weight(.semibold))
                Text("See changes. Build with confidence.")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text(store.projects.isEmpty ? "Přidej první repozitář a roztřiď ho do prostoru." : "Vyber repozitář v postranním panelu.")
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Klonovat repozitář…") { store.presentedSheet = .clone }
                        .buttonStyle(.glassProminent)
                    Button("Přidat existující…") { store.presentedSheet = .addExisting }
                        .buttonStyle(.glass)
                    Button("Nový repozitář…") { store.presentedSheet = .newRepository }
                        .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Minimální velikost sloupce nezávislá na obsahu. Jinak se při změně obsahu (např. odebrání remotu)
    /// může AppKit zacyklit v přepočtu omezení NSSplitView a aplikaci ukončit.
    func stableColumnSize(alignment: Alignment = .center) -> some View {
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: alignment)
    }
}

extension FocusedValues {
    @Entry var repositoryModel: RepositoryModel?
}
