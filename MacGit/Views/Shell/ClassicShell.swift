import SwiftUI

/// Kostra okna v klasickém stylu – přesně to, co nabízí systém: `NavigationSplitView`
/// se systémovým postranním panelem, inspektor přes `.inspector`, systémový toolbar s titulkem
/// a podtitulkem a hledání přes `.searchable`. Žádné vlastní plátno ani značkové prvky.
struct ClassicShell: View {
    let model: RepositoryModel?

    @Environment(AppStore.self) private var store
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// Stejné nastavení jako ve stylu Revision, ať ⌃⌘S z menu funguje v obou.
    @AppStorage("sidebarShown") private var sidebarShown = true

    var body: some View {
        @Bindable var store = store

        Group {
            if let model {
                ClassicRepositorySplit(model: model, columnVisibility: $columnVisibility, inspectorShown: $store.inspectorShown)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView()
                        .stableColumnSize()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
                } detail: {
                    WelcomeView()
                        .stableColumnSize()
                }
            }
        }
        .onAppear { columnVisibility = sidebarShown ? .all : .doubleColumn }
        .onChange(of: sidebarShown) { _, shown in
            withAnimation { columnVisibility = shown ? .all : .doubleColumn }
        }
        .onChange(of: columnVisibility) { _, visibility in
            let shown = visibility != .doubleColumn && visibility != .detailOnly
            if shown != sidebarShown { sidebarShown = shown }
        }
    }
}

private struct ClassicRepositorySplit: View {
    @Bindable var model: RepositoryModel
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var inspectorShown: Bool

    @State private var now = Date.now
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .stableColumnSize()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } content: {
            RepositoryContentColumn(model: model)
                .stableColumnSize()
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 520)
        } detail: {
            RepositoryDetailColumn(model: model)
                .stableColumnSize()
        }
        .inspector(isPresented: $inspectorShown) {
            InspectorView(model: model)
                .stableColumnSize(alignment: .top)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .navigationSubtitle(model.statusLine(now: now))
        .searchable(text: $model.searchText, placement: .toolbar, prompt: model.section.searchPrompt)
        .searchFocused($searchFocused)
        .onChange(of: model.isSearchExpanded) { _, requested in
            // ⌘F z menu: v klasickém stylu jen přesune fokus do systémového pole.
            guard requested else { return }
            searchFocused = true
            model.isSearchExpanded = false
        }
        .toolbar { ClassicToolbar(model: model, inspectorShown: $inspectorShown) }
        .task {
            // Relativní čas v podtitulu („před 2 min“) se obnovuje průběžně.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
    }
}

/// Systémový toolbar podle HIG: větev a synchronizace uprostřed, inspektor vpravo
/// (hledání přidává `.searchable`). Každá akce je i v menu baru.
private struct ClassicToolbar: ToolbarContent {
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
