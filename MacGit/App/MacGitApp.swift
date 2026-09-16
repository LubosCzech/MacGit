import SwiftUI

@main
struct MacGitApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("MacGit", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 1260, minHeight: 680)
        }
        .defaultSize(width: 1360, height: 860)
        .windowToolbarStyle(.unified)
        .commands { MacGitCommands(store: store) }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

struct MacGitCommands: Commands {
    let store: AppStore

    private var model: RepositoryModel? {
        store.project(store.selectedProjectID).map(store.model(for:))
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Klonovat repozitář…") { store.presentedSheet = .clone }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Přidat existující repozitář…") { store.presentedSheet = .addExisting }
                .keyboardShortcut("o")
            Button("Nový repozitář…") { store.presentedSheet = .newRepository }
        }
        CommandMenu("Repozitář") {
            Button("Obnovit") { model?.scheduleRefresh() }
                .keyboardShortcut("r")
            Divider()
            Button("Commit") { if let model, model.canCommit { Task { await model.commit(andPush: false) } } }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Commit a Push") { if let model, model.canCommit { Task { await model.commit(andPush: true) } } }
                .keyboardShortcut(.return, modifiers: [.command, .option])
            Divider()
            Button("Fetch") { if let model { Task { await model.fetch() } } }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Pull") { if let model { Task { await model.pull() } } }
                .keyboardShortcut("t", modifiers: .command)
            Button("Push") { if let model { Task { await model.push() } } }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            ForEach(Array(RepositoryModel.Section.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model?.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
        }
    }
}
