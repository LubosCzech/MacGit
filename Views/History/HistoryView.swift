import SwiftUI
import GitKit

struct HistoryView: View {
    @Bindable var model: RepositoryModel
    @State private var search = ""

    private var filtered: [Commit] {
        guard !search.isEmpty else { return model.commits }
        return model.commits.filter {
            $0.subject.localizedCaseInsensitiveContains(search)
                || $0.authorName.localizedCaseInsensitiveContains(search)
                || $0.hash.hasPrefix(search.lowercased())
        }
    }

    var body: some View {
        HSplitView {
            List(filtered, selection: $model.selectedCommitID) { commit in
                CommitRow(commit: commit)
                    .tag(commit.id)
                    .contextMenu {
                        Button("Kopírovat hash", systemImage: "number") { copy(commit.hash) }
                        Button("Kopírovat zprávu", systemImage: "text.quote") { copy(commit.subject) }
                    }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchField(text: $search, prompt: "Hledat v historii")
            }
            .frame(minWidth: 280, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
            .overlay {
                if model.commits.isEmpty { EmptyStateView(title: "Zatím žádné commity", symbol: "clock") }
            }

            VStack(spacing: 0) {
                if let commit = model.selectedCommit {
                    CommitDetailHeader(commit: commit)
                    VSplitView {
                        List(model.commitFiles, selection: $model.selectedCommitFileID) { file in
                            FileLabel(path: file.path, kind: file.kind).tag(file.id)
                        }
                        .frame(minHeight: 80, idealHeight: 150, maxHeight: 300)
                        DiffView(diff: model.commitDiff)
                            .frame(minHeight: 200, maxHeight: .infinity)
                    }
                } else {
                    EmptyStateView(title: "Vyber commit", symbol: "point.3.connected.trianglepath.dotted")
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct CommitRow: View {
    let commit: Commit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(commit.subject)
                    .lineLimit(1)
                    .font(.body.weight(.medium))
                if commit.isSigned {
                    Image(systemName: commit.signature == "G" ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(commit.signature == "G" ? .green : .secondary)
                        .help(commit.signature == "G" ? "Platný podpis" : "Podepsáno (neověřeno)")
                }
            }
            HStack(spacing: 6) {
                ForEach(commit.refs.prefix(3), id: \.self) { ref in
                    Text(ref.replacingOccurrences(of: "HEAD -> ", with: ""))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(refColor(ref).opacity(0.2), in: .capsule)
                        .foregroundStyle(refColor(ref))
                        .lineLimit(1)
                }
                Text(commit.authorName)
                Text("·")
                Text(commit.date, format: .relative(presentation: .named))
                Spacer()
                Text(commit.shortHash).monospaced()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func refColor(_ ref: String) -> Color {
        if ref.hasPrefix("HEAD") { return .accentColor }
        if ref.hasPrefix("tag:") { return .orange }
        if ref.contains("/") { return .purple }
        return .green
    }
}

private struct CommitDetailHeader: View {
    let commit: Commit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commit.subject)
                .font(.title3.bold())
                .textSelection(.enabled)
            if !commit.body.isEmpty {
                Text(commit.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
            HStack(spacing: 14) {
                Label("\(commit.authorName) <\(commit.authorEmail)>", systemImage: "person")
                Label(commit.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label(commit.shortHash, systemImage: "number").monospaced()
                if commit.parents.count > 1 {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding([.horizontal, .top], 10)
        .padding(.bottom, 6)
    }
}
