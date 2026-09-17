import SwiftUI

@main
struct MacGitApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("MacGit", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 600)
                #if DEBUG
                .onAppear { DebugSnapshots.runIfRequested(store: store) }
                #endif
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands { MacGitCommands(store: store) }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

/// Každá akce z toolbaru má i položku v menu (HIG).
struct MacGitCommands: Commands {
    let store: AppStore
    @FocusedValue(\.repositoryModel) private var model

    var body: some Commands {
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
            ForEach(Array(RepositoryModel.Section.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model?.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(model == nil)
            }
            Divider()
            Button(store.inspectorShown ? "Skrýt inspektor" : "Zobrazit inspektor") { store.inspectorShown.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(model == nil)
            Divider()
        }

        CommandMenu("Repozitář") {
            Button("Obnovit") { model?.scheduleRefresh() }
                .keyboardShortcut("r")
            Divider()
            Button("Commit") { if let model, model.canCommit { Task { await model.commit(andPush: false) } } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(model?.canCommit ?? false))
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
            Button("Force push (with lease)") { if let model { Task { await model.push(force: true) } } }
            Divider()
            Button("Nová větev…") { model?.promptNewBranch(from: nil) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
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
