import SwiftUI
import GitKit

struct BranchesList: View {
    @Bindable var model: RepositoryModel

    private func matches(_ branch: Branch) -> Bool {
        model.searchText.isEmpty || branch.name.localizedCaseInsensitiveContains(model.searchText)
    }

    var body: some View {
        let local = model.branches.filter { !$0.isRemote && matches($0) }
        let remote = model.branches.filter { $0.isRemote && matches($0) }

        List(selection: $model.selectedBranchID) {
            Section("Lokální") {
                ForEach(local) { branch in
                    BranchRow(branch: branch).tag(branch.id)
                }
            }
            if !remote.isEmpty {
                Section("Vzdálené") {
                    ForEach(remote) { branch in
                        BranchRow(branch: branch).tag(branch.id)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: Branch.ID.self) { ids in
            if let id = ids.first, let branch = model.branches.first(where: { $0.id == id }) {
                BranchActions(model: model, branch: branch)
            }
        } primaryAction: { ids in
            if let id = ids.first, let branch = model.branches.first(where: { $0.id == id }), !branch.isCurrent {
                Task { await model.checkout(branch) }
            }
        }
        .overlay {
            if !model.searchText.isEmpty && local.isEmpty && remote.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                GlassEffectContainer {
                    Button {
                        model.promptNewBranch(from: model.branches.first { $0.id == model.selectedBranchID })
                    } label: {
                        Label("Nová větev", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                    .help("Nová větev… (⇧⌘B)")
                }
                Spacer()
            }
            .padding(12)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onAppear {
            if model.selectedBranchID == nil { model.selectedBranchID = model.branches.first(where: \.isCurrent)?.id }
        }
    }
}

private struct BranchRow: View {
    let branch: Branch

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"))
                .foregroundStyle(branch.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
                .accessibilityLabel(branch.isCurrent ? "Aktuální větev" : "")
            Text(branch.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let track = trackSummary {
                Text(track)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .help(branch.upstream.map { "\(branch.name) → \($0)" } ?? branch.name)
    }

    /// `[ahead 2, behind 1]` → `↑2 ↓1`
    private var trackSummary: String? {
        let text = branch.track.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !text.isEmpty else { return nil }
        if text == "gone" { return "upstream smazán" }
        return text.replacingOccurrences(of: "ahead ", with: "↑").replacingOccurrences(of: "behind ", with: "↓").replacingOccurrences(of: ",", with: "")
    }
}

/// Akce nad větví – sdílené kontextovým menu a detailem.
struct BranchActions: View {
    let model: RepositoryModel
    let branch: Branch

    var body: some View {
        Button("Checkout") { Task { await model.checkout(branch) } }
            .disabled(branch.isCurrent)
        Button("Merge do \(model.status.branch.head ?? "aktuální větve")") { Task { await model.merge(branch) } }
            .disabled(branch.isCurrent)
        Button("Nová větev odsud…") { model.promptNewBranch(from: branch) }
        Button("AI review…") { model.reviewSheetTarget = .branch(branch) }
        if !branch.isRemote {
            Button("Přejmenovat…") {
                model.pendingPrompt = TextPrompt(title: "Přejmenovat větev", placeholder: "Název", initialValue: branch.name, confirmTitle: "Přejmenovat") { name in
                    Task { await model.renameBranch(branch, to: name) }
                }
            }
        }
        Divider()
        Button("Kopírovat název") { NSPasteboard.copy(branch.localName) }
        Divider()
        Button(branch.isRemote ? "Smazat na serveru…" : "Smazat…", role: .destructive) { model.branchToDelete = branch }
            .disabled(branch.isCurrent)
    }
}

struct BranchDetail: View {
    @Bindable var model: RepositoryModel

    var body: some View {
        if let branch = model.branches.first(where: { $0.id == model.selectedBranchID }) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        Text(branch.name)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                        if branch.isCurrent {
                            Text("aktuální")
                                .font(.callout)
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(summary(branch))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Checkout") { Task { await model.checkout(branch) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(branch.isCurrent)
                        Button("Merge do \(model.status.branch.head ?? "aktuální")") { Task { await model.merge(branch) } }
                            .disabled(branch.isCurrent)
                        Button("Nová větev…") { model.promptNewBranch(from: branch) }
                        Button {
                            model.reviewSheetTarget = .branch(branch)
                        } label: {
                            Label("AI review…", systemImage: "sparkle.magnifyingglass")
                        }
                        .help("Nechat větev zkontrolovat CLI agentem (Claude, Codex, Cursor, Grok)")
                        Spacer()
                        Button(role: .destructive) { model.branchToDelete = branch } label: {
                            Text(branch.isRemote ? "Smazat na serveru…" : "Smazat…")
                        }
                        .disabled(branch.isCurrent)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)

                ReviewsSection(model: model, target: .branch(branch))

                Divider()

                List(model.branchCommits, selection: $model.selectedCommitID) { commit in
                    HStack(spacing: 8) {
                        Text(commit.subject).lineLimit(1)
                        Spacer()
                        Text(commit.date.formatted(.relative(presentation: .named)))
                            .foregroundStyle(.secondary)
                        Text(commit.shortHash)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .tag(commit.id)
                }
                .overlay {
                    if model.branchCommits.isEmpty { ProgressView() }
                }
            }
        } else {
            EmptyStateView(title: "Vyber větev", symbol: "arrow.triangle.branch")
        }
    }

    private func summary(_ branch: Branch) -> String {
        var parts = ["Poslední commit \(branch.shortHash)"]
        if let upstream = branch.upstream { parts.append("sleduje \(upstream)") }
        let track = branch.track.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if !track.isEmpty {
            parts.append(track.replacingOccurrences(of: "ahead", with: "napřed o").replacingOccurrences(of: "behind", with: "pozadu o"))
        }
        return parts.joined(separator: " · ")
    }
}
