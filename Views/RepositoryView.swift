import SwiftUI
import GitKit

struct RepositoryView: View {
    @Bindable var model: RepositoryModel
    @Environment(AppStore.self) private var store
    @State private var branchPrompt: TextPrompt?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(model.project.name)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if let busy = model.busyTitle {
                        BusyIndicator(title: busy)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let toast = model.toast {
                        ToastView(message: toast)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 18)
                .animation(.smooth, value: model.busyTitle)
                .animation(.smooth, value: model.toast)
            }
            .alert("Git hlásí chybu", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .textPrompt($branchPrompt)
            .onAppear { model.activate() }
            .onChange(of: model.section) { _, section in
                if section == .history { Task { await model.loadHistory() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .changes: ChangesView(model: model)
        case .history: HistoryView(model: model)
        case .branches: BranchesView(model: model)
        case .shelf: ShelfView(model: model)
        case .settings: ProjectSettingsView(model: model)
        }
    }

    private var subtitle: String {
        let branch = model.status.branch
        var parts: [String] = []
        if let space = store.space(model.project.spaceID) { parts.append(space.name) }
        if branch.ahead > 0 { parts.append("↑\(branch.ahead)") }
        if branch.behind > 0 { parts.append("↓\(branch.behind)") }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            BranchMenu(model: model, branchPrompt: $branchPrompt)
        }

        ToolbarItem(placement: .principal) {
            Picker("Sekce", selection: $model.section) {
                ForEach(RepositoryModel.Section.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .fixedSize()
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await model.fetch() }
            } label: {
                Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Stáhnout novinky ze všech remotů")

            Button {
                Task { await model.pull() }
            } label: {
                Label("Pull", systemImage: "arrow.down")
                    .badge(model.status.branch.behind)
            }
            .help("Pull (merge)")
            .contextMenu {
                Button("Pull s rebase") { Task { await model.pull(rebase: true) } }
            }

            Button {
                Task { await model.push() }
            } label: {
                Label("Push", systemImage: "arrow.up")
                    .badge(model.status.branch.ahead)
            }
            .help(model.status.branch.upstream == nil ? "Push a nastavit upstream" : "Push do \(model.status.branch.upstream ?? "")")
            .contextMenu {
                Button("Force push (with lease)") { Task { await model.push(force: true) } }
            }
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let url = model.pullRequestURL {
                    Button(model.pullRequestTitle, systemImage: "arrow.triangle.pull") { NSWorkspace.shared.open(url) }
                    Divider()
                }
                Button("Zobrazit ve Finderu", systemImage: "folder") { model.revealInFinder() }
                Button("Otevřít v Terminálu", systemImage: "terminal") { model.openInTerminal() }
                Divider()
                Button("Obnovit", systemImage: "arrow.clockwise") { model.scheduleRefresh() }
            } label: {
                Label("Další", systemImage: "ellipsis")
            }
        }
    }
}

private struct BranchMenu: View {
    let model: RepositoryModel
    @Binding var branchPrompt: TextPrompt?

    var body: some View {
        let local = model.branches.filter { !$0.isRemote }
        Menu {
            Section("Lokální větve") {
                ForEach(local) { branch in
                    Button {
                        Task { await model.checkout(branch) }
                    } label: {
                        if branch.isCurrent {
                            Label(branch.name, systemImage: "checkmark")
                        } else {
                            Text(branch.name)
                        }
                    }
                    .disabled(branch.isCurrent)
                }
            }
            Divider()
            Button("Nová větev…", systemImage: "plus") {
                branchPrompt = TextPrompt(title: "Nová větev", message: "Vytvoří se z aktuálního HEAD a přepne se na ni.", placeholder: "feature/nazev", confirmTitle: "Vytvořit") { name in
                    Task { await model.createBranch(name, from: nil, checkout: true) }
                }
            }
            Button("Všechny větve…", systemImage: "arrow.triangle.branch") { model.section = .branches }
        } label: {
            Label(model.status.branch.head ?? "odpojený HEAD", systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
        }
        .help("Aktuální větev")
    }
}
