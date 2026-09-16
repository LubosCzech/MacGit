import SwiftUI
import GitKit

struct BranchesView: View {
    let model: RepositoryModel
    @State private var selection: Branch.ID?
    @State private var prompt: TextPrompt?
    @State private var branchToDelete: Branch?
    @State private var search = ""

    private func matches(_ branch: Branch) -> Bool {
        search.isEmpty || branch.name.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        let local = model.branches.filter { !$0.isRemote && matches($0) }
        let remote = model.branches.filter { $0.isRemote && matches($0) }

        List(selection: $selection) {
            Section("Lokální (\(local.count))") {
                ForEach(local) { branch in
                    BranchRow(branch: branch).tag(branch.id)
                        .contextMenu { menu(for: branch) }
                }
            }
            Section("Vzdálené (\(remote.count))") {
                ForEach(remote) { branch in
                    BranchRow(branch: branch).tag(branch.id)
                        .contextMenu { menu(for: branch) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchField(text: $search, prompt: "Hledat větev")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        .textPrompt($prompt)
        .confirmationDialog("Smazat větev \(branchToDelete?.name ?? "")?", isPresented: Binding(get: { branchToDelete != nil }, set: { if !$0 { branchToDelete = nil } })) {
            if let branch = branchToDelete {
                Button(branch.isRemote ? "Smazat na serveru" : "Smazat", role: .destructive) {
                    Task { await model.deleteBranch(branch, force: false) }
                }
                if !branch.isRemote {
                    Button("Vynutit smazání (i nemergnutou)", role: .destructive) {
                        Task { await model.deleteBranch(branch, force: true) }
                    }
                }
            }
        }
        .onChange(of: model.branches) { _, branches in
            if selection == nil { selection = branches.first(where: \.isCurrent)?.id }
        }
    }

    private var selected: Branch? { model.branches.first { $0.id == selection } }

    private var actionBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button("Checkout", systemImage: "arrow.right.circle") {
                    if let selected { Task { await model.checkout(selected) } }
                }
                .disabled(selected == nil || selected?.isCurrent == true)

                Button("Merge do aktuální", systemImage: "arrow.triangle.merge") {
                    if let selected { Task { await model.merge(selected) } }
                }
                .disabled(selected == nil || selected?.isCurrent == true)

                Spacer()

                Button("Nová větev", systemImage: "plus") {
                    newBranch(from: selected)
                }
                .buttonStyle(.glassProminent)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(12)
        }
    }

    @ViewBuilder
    private func menu(for branch: Branch) -> some View {
        Button("Checkout", systemImage: "arrow.right.circle") { Task { await model.checkout(branch) } }
            .disabled(branch.isCurrent)
        Button("Merge do aktuální větve", systemImage: "arrow.triangle.merge") { Task { await model.merge(branch) } }
            .disabled(branch.isCurrent)
        Button("Nová větev odsud…", systemImage: "plus") { newBranch(from: branch) }
        if !branch.isRemote {
            Button("Přejmenovat…", systemImage: "pencil") {
                prompt = TextPrompt(title: "Přejmenovat větev", placeholder: "Název", initialValue: branch.name, confirmTitle: "Přejmenovat") { name in
                    Task { await model.renameBranch(branch, to: name) }
                }
            }
        }
        Divider()
        Button("Kopírovat název", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch.localName, forType: .string)
        }
        Divider()
        Button("Smazat…", systemImage: "trash", role: .destructive) { branchToDelete = branch }
            .disabled(branch.isCurrent)
    }

    private func newBranch(from start: Branch?) {
        prompt = TextPrompt(
            title: "Nová větev",
            message: start.map { "Z větve \($0.name)" } ?? "Z aktuálního HEAD",
            placeholder: "feature/nazev",
            confirmTitle: "Vytvořit a přepnout"
        ) { name in
            Task { await model.createBranch(name, from: start?.name, checkout: true) }
        }
    }
}

private struct BranchRow: View {
    let branch: Branch

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"))
                .foregroundStyle(branch.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 18)
            Text(branch.name)
                .fontWeight(branch.isCurrent ? .semibold : .regular)
            if let upstream = branch.upstream {
                Text("→ \(upstream)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !branch.track.isEmpty {
                Text(branch.track.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.18), in: .capsule)
            }
            Text(branch.shortHash)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
