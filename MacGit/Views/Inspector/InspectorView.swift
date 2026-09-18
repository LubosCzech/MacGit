import SwiftUI
import GitKit

/// Inspektor: vlastnosti vybraného souboru, commitu nebo celého repozitáře.
struct InspectorView: View {
    @Bindable var model: RepositoryModel

    var body: some View {
        VStack(spacing: 0) {
            RevisionTabPicker(values: model.inspectorTabs, selection: $model.inspectorTab) { tab in
                Text(tab.title).lineLimit(1)
            }
            .padding(12)

            switch model.inspectorTab {
            case .file: FileInspector(model: model)
            case .commit: CommitInspector(model: model)
            case .review: ReviewInspector(model: model)
            case .repository: RepositoryInspector(model: model)
            }
        }
    }
}

private struct FileInspector: View {
    let model: RepositoryModel

    var body: some View {
        if let change = model.selectedChange {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            FileIcon(path: change.path, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(change.fileName)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Text(change.directory.isEmpty ? "/" : change.directory)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }

                        HStack(spacing: 8) {
                            StatusLetter(kind: change.kind)
                            Text(change.kind.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        if let diff = model.currentDiff, diff.path == change.path, !diff.isBinary {
                            DiffStatBar(additions: diff.additions, deletions: diff.deletions)
                        }
                    }
                    .padding(16)

                    Divider()

                    InspectorSection(title: "Umístění") {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                            InspectorRow(label: "Složka") {
                                Text(change.directory.isEmpty ? "/" : change.directory)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            if let original = change.originalPath {
                                InspectorRow(label: "Původně") {
                                    Text(original).lineLimit(2).truncationMode(.middle)
                                }
                            }
                        }
                    }

                    Divider()

                    InspectorSection(title: "Commit") {
                        Toggle("Zahrnout do commitu", isOn: Binding(
                            get: { model.isIncluded(change) },
                            set: { model.setIncluded($0, for: [change]) }
                        ))
                        Picker("Changelist", selection: Binding(
                            get: { model.changelistID(for: change.path) },
                            set: { model.move(paths: [change.path], to: $0) }
                        )) {
                            ForEach(model.workspace.changelists) { Text($0.name).tag($0.id) }
                        }
                    }

                    Divider()

                    InspectorSection(title: "Akce") {
                        Button { model.revealInFinder(change.path) } label: {
                            Label("Zobrazit ve Finderu", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        HStack {
                            Button("Otevřít") { NSWorkspace.shared.open(model.project.url.appendingPathComponent(change.path)) }
                                .frame(maxWidth: .infinity)
                            Button("Odložit…") { model.promptShelve([change], suggestedName: change.fileName) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glass)
                }
            }
        } else {
            EmptyStateView(title: "Žádný vybraný soubor", symbol: "doc")
        }
    }
}

private struct CommitInspector: View {
    let model: RepositoryModel

    var body: some View {
        if let commit = model.selectedCommit {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(commit.subject)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if !commit.body.isEmpty {
                            Text(commit.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)

                    if commit.isSigned {
                        Divider()
                        InspectorSection(title: "Podpis") {
                            SignatureCard(verification: model.signatureVerification)
                        }
                    }

                    Divider()

                    InspectorSection(title: "Podrobnosti") {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                            InspectorRow(label: "Autor") {
                                Text(commit.authorName).help(commit.authorEmail)
                            }
                            InspectorRow(label: "E-mail") {
                                Text(commit.authorEmail).lineLimit(1).truncationMode(.middle)
                            }
                            InspectorRow(label: "Datum") {
                                Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                            }
                            InspectorRow(label: "Commit") {
                                Text(commit.shortHash).font(.body.monospaced()).textSelection(.enabled)
                            }
                            if !commit.parents.isEmpty {
                                InspectorRow(label: commit.parents.count > 1 ? "Rodiče" : "Rodič") {
                                    Text(commit.parents.map { String($0.prefix(7)) }.joined(separator: ", "))
                                        .font(.body.monospaced())
                                }
                            }
                            if !commit.refs.isEmpty {
                                InspectorRow(label: "Odkazy") {
                                    Text(commit.refs.map { $0.replacingOccurrences(of: "HEAD -> ", with: "") }.joined(separator: ", "))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Divider()

                    ReviewsSection(model: model, target: .commit(commit), horizontalPadding: 16)
                        .padding(.top, 12)

                    InspectorSection(title: "Akce") {
                        Button {
                            model.reviewSheetTarget = .commit(commit)
                        } label: {
                            Label("AI review commitu…", systemImage: "sparkle.magnifyingglass")
                        }
                        HStack {
                            Button("Kopírovat hash") { NSPasteboard.copy(commit.hash) }
                            if let url = model.webURL(for: commit) {
                                Button("Otevřít v prohlížeči") { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                }
            }
        } else {
            EmptyStateView(title: "Žádný vybraný commit", symbol: "clock")
        }
    }
}
