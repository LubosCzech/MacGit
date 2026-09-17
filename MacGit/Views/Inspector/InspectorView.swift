import SwiftUI
import GitKit

/// Inspektor: vlastnosti vybraného souboru, commitu nebo celého repozitáře.
struct InspectorView: View {
    @Bindable var model: RepositoryModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspektor", selection: $model.inspectorTab) {
                ForEach(RepositoryModel.InspectorTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch model.inspectorTab {
            case .file: FileInspector(model: model)
            case .commit: CommitInspector(model: model)
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
                    HStack(spacing: 10) {
                        FileIcon(path: change.path, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.fileName)
                                .font(.headline)
                                .lineLimit(2)
                            Text(change.kind.title)
                                .foregroundStyle(change.kind.color)
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
                        HStack {
                            Button("Zobrazit ve Finderu") { model.revealInFinder(change.path) }
                            Button("Otevřít") { NSWorkspace.shared.open(model.project.url.appendingPathComponent(change.path)) }
                        }
                        Button("Odložit do shelfu…") { model.promptShelve([change], suggestedName: change.fileName) }
                    }
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

                    InspectorSection(title: "Akce") {
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
