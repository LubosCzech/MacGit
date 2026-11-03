import SwiftUI

@main
struct RevisionApp: App {
    @State private var store: AppStore
    @State private var backups: BackupService
    @State private var updates = UpdateService()
    @State private var support = SupportService()

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _backups = State(initialValue: BackupService(store: store))
    }
    @AppStorage("revisionAppearance") private var appearance: RevisionAppearance = .system
    @AppStorage(InterfaceStyle.storageKey) private var interfaceStyle: InterfaceStyle = .revision

    var body: some Scene {
        // Tokeny v `Theme` čtou aktuální styl; okna se při změně přestaví přes `.id`.
        let _ = { InterfaceStyle.current = interfaceStyle }()

        WindowGroup("Revision", id: "main") {
            RootView()
                .environment(store)
                .environment(\.interfaceStyle, interfaceStyle)
                .id(interfaceStyle)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .frame(minWidth: 1040, minHeight: 620)
                .sheet(isPresented: Binding(get: { support.isPrompting }, set: { support.isPrompting = $0 })) {
                    SupportPromptView(support: support)
                }
                .task {
                    // Až když má uživatel okno před sebou, ne hned při startu.
                    try? await Task.sleep(for: .seconds(3))
                    support.promptIfDue()
                }
                .task {
                    // Denní záloha konfigurace: hned po startu a pak se každou hodinu ověří, jestli je čas.
                    try? await Task.sleep(for: .seconds(10))
                    while !Task.isCancelled {
                        backups.runAutomaticBackupIfDue()
                        try? await Task.sleep(for: .seconds(3600))
                    }
                }
                #if DEBUG
                .onAppear { DebugSnapshots.runIfRequested(store: store) }
                #endif
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands { RevisionCommands(store: store, updates: updates) }

        WindowGroup("AI review", id: "review", for: ReviewWindowValue.self) { $value in
            ReviewWindow(value: value)
                .environment(store)
                .environment(\.interfaceStyle, interfaceStyle)
                .id(interfaceStyle)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
        .defaultSize(width: 900, height: 820)

        Settings {
            SettingsView()
                .environment(store)
                .environment(updates)
                .environment(backups)
                .environment(\.interfaceStyle, interfaceStyle)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}

/// Každá akce z toolbaru má i položku v menu (HIG).
struct RevisionCommands: Commands {
    let store: AppStore
    let updates: UpdateService
    @FocusedValue(\.repositoryModel) private var model
    @AppStorage("changesAsTree") private var changesAsTree = false
    @AppStorage("diffLayoutMode") private var diffMode: DiffLayoutMode = .unified
    @AppStorage("sidebarShown") private var sidebarShown = true

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("O aplikaci Revision") { AboutWindow.shared.show() }
        }
        CommandGroup(after: .appInfo) {
            Button("Zkontrolovat aktualizace…") { updates.check() }
                .disabled(!updates.canCheck)
        }
        CommandGroup(replacing: .help) {
            Link("Kávu pro vývojáře…", destination: SupportLink.page)
            Link("svtk.dev", destination: SupportLink.studio)
        }

        CommandGroup(after: .newItem) {
            Button("Klonovat repozitář…") { store.presentedSheet = .clone }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Přidat existující repozitář…") { store.presentedSheet = .addExisting }
                .keyboardShortcut("o")
            Button("Nový repozitář…") { store.presentedSheet = .newRepository }
            Divider()
            Button("Nový prostor…") { store.presentedSheet = .newSpace }
        }

        CommandGroup(after: .sidebar) {
            Button(sidebarShown ? "Skrýt postranní panel" : "Zobrazit postranní panel") { sidebarShown.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            ForEach(Array(RepositoryModel.Section.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model?.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(model == nil)
            }
            Toggle("Změny jako strom složek", isOn: $changesAsTree)
                .keyboardShortcut("l", modifiers: [.command, .option])
            Picker("Rozdíly", selection: $diffMode) {
                ForEach(DiffLayoutMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button(store.inspectorShown ? "Skrýt inspektor" : "Zobrazit inspektor") { store.inspectorShown.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(model == nil)
            Divider()
        }

        CommandGroup(after: .textEditing) {
            Button("Hledat") {
                model?.isSearchExpanded = true
            }
            .keyboardShortcut("f")
            .disabled(model == nil)

            Button("Filtrovat repozitáře") { store.sidebarSearchFocusRequests += 1 }
                .keyboardShortcut("k")
        }

        CommandMenu("Repozitář") {
            Button("Obnovit") { model?.scheduleRefresh() }
                .keyboardShortcut("r")
            Divider()
            Button("Commit") { if let model, model.canCommit { Task { await model.commit(andPush: false) } } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(model?.canCommit ?? false))
            Button("Navrhnout zprávu commitu") { model?.suggestCommitMessage() }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(!(model?.canSuggestMessage ?? false))
            Button("Commit a Push") { if let model, model.canCommit { Task { await model.commit(andPush: true) } } }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(!(model?.canCommit ?? false))
            Divider()
            Button("Fetch") { if let model { Task { await model.fetch() } } }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Pull") { if let model { Task { await model.pull() } } }
                .keyboardShortcut("t", modifiers: .command)
            Button("Pull s rebase") { if let model { Task { await model.pull(rebase: true) } } }
            Button("Push") { if let model { Task { await model.push() } } }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Menu("Push do") {
                if let model { PushToMenuItems(model: model) }
            }
            .disabled(model == nil)
            Button("Force push (with lease)") { if let model { Task { await model.push(force: true) } } }
            Divider()
            Button("Nová větev…") { model?.promptNewBranch(from: nil) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button(model?.section == .history ? "AI review commitu…" : "AI review větve…") {
                guard let model else { return }
                if model.section == .history, let commit = model.selectedCommit {
                    model.reviewSheetTarget = .commit(commit)
                } else if let branch = (model.section == .branches ? model.branches.first { $0.id == model.selectedBranchID } : nil)
                            ?? model.branches.first(where: \.isCurrent) {
                    model.reviewSheetTarget = .branch(branch)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            if let model, let url = model.pullRequestURL {
                Button(model.pullRequestTitle + "…") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Zobrazit ve Finderu") { model?.revealInFinder() }
            Button("Otevřít v Terminálu") { model?.openInTerminal() }
            Divider()
            Button("Nastavení repozitáře…") {
                model?.inspectorTab = .repository
                store.inspectorShown = true
            }
        }
    }
}
