import SwiftUI
import GitKit

/// Seznam commitů s jednoduchou linií grafu.
struct HistoryList: View {
    @Bindable var model: RepositoryModel

    private var filtered: [Commit] {
        let query = model.searchText
        guard !query.isEmpty else { return model.commits }
        return model.commits.filter {
            $0.subject.localizedCaseInsensitiveContains(query)
                || $0.authorName.localizedCaseInsensitiveContains(query)
                || $0.hash.hasPrefix(query.lowercased())
        }
    }

    var body: some View {
        let commits = filtered
        List(selection: $model.selectedCommitID) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                CommitRow(commit: commit, isFirst: index == 0, isLast: index == commits.count - 1, isAhead: index < model.status.branch.ahead)
                    .tag(commit.id)
                    .contextMenu {
                        Button("Kopírovat hash") { NSPasteboard.copy(commit.hash) }
                        Button("Kopírovat zprávu") { NSPasteboard.copy(commit.subject) }
                        if let url = model.webURL(for: commit) {
                            Button("Otevřít v prohlížeči") { NSWorkspace.shared.open(url) }
                        }
                        Divider()
                        Button("Nová větev z tohoto commitu…") {
                            model.pendingPrompt = TextPrompt(title: "Nová větev", message: "Z commitu \(commit.shortHash)", placeholder: "feature/nazev", confirmTitle: "Vytvořit") { name in
                                Task { await model.createBranch(name, from: commit.hash, checkout: true) }
                            }
                        }
                    }
            }
        }
        .overlay {
            if model.hasLoaded && model.commits.isEmpty {
                EmptyStateView(title: "Zatím žádné commity", symbol: "clock")
            } else if !model.searchText.isEmpty && commits.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }
}

private struct CommitRow: View {
    let commit: Commit
    let isFirst: Bool
    let isLast: Bool
    /// Commit ještě není na serveru.
    let isAhead: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            GraphNode(isFirst: isFirst, isLast: isLast, isMerge: commit.parents.count > 1, isHollow: isAhead)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(commit.subject)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(commit.shortHash)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    ForEach(commit.refs.prefix(3), id: \.self) { ref in
                        RefChip(ref: ref)
                    }
                    Text("\(commit.authorName) · \(commit.date.formatted(.relative(presentation: .named)))")
                        .lineLimit(1)
                    if commit.isSigned {
                        Image(systemName: "signature")
                            .help("Podepsaný commit")
                            .accessibilityLabel("Podepsáno")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct GraphNode: View {
    let isFirst: Bool
    let isLast: Bool
    let isMerge: Bool
    let isHollow: Bool

    var body: some View {
        Canvas { context, size in
            let x = size.width / 2, y = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: x, y: isFirst ? y : -8))
            line.addLine(to: CGPoint(x: x, y: isLast ? y : size.height + 8))
            context.stroke(line, with: .color(.accentColor), lineWidth: 2)
            let radius: CGFloat = isMerge ? 3.5 : 4.5
            let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(isHollow ? Color(nsColor: .controlBackgroundColor) : .accentColor))
            context.stroke(dot, with: .color(.accentColor), lineWidth: 2)
        }
        .frame(width: 14, height: 34)
        .accessibilityHidden(true)
    }
}

struct RefChip: View {
    let ref: String

    var body: some View {
        let name = ref.replacingOccurrences(of: "HEAD -> ", with: "").replacingOccurrences(of: "tag: ", with: "")
        Text(name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: .rect(cornerRadius: 4))
    }

    private var color: Color {
        if ref.hasPrefix("tag:") { return .orange }
        if ref.hasPrefix("HEAD") || !ref.contains("/") { return .accentColor }
        return .purple
    }
}

/// Detail commitu: soubory nahoře, diff dole. Metadata jsou v inspektoru.
struct CommitDetail: View {
    @Bindable var model: RepositoryModel

    var body: some View {
        if model.selectedCommit != nil {
            ResizableSplit(id: "commitFiles") {
                List(model.commitFiles, selection: $model.selectedCommitFileID) { file in
                    HStack(spacing: 6) {
                        FileNameLabel(path: file.path, originalPath: file.originalPath, isDeleted: file.kind == .deleted)
                        Spacer(minLength: 4)
                        StatusLetter(kind: file.kind)
                    }
                    .tag(file.id)
                }
            } bottom: {
                DiffView(diff: model.commitDiff, placeholder: "Vyber soubor", placeholderMessage: nil)
            }
        } else {
            EmptyStateView(title: "Vyber commit", symbol: "clock", message: "Soubory a rozdíly commitu se zobrazí tady.")
        }
    }
}

/// Karta s výsledkem ověření podpisu (inspektor).
struct SignatureCard: View {
    let verification: SignatureVerification?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if verification == nil {
                    ProgressView().controlSize(.small)
                    Text("Ověřuji podpis…").foregroundStyle(.secondary)
                } else {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).fontWeight(.semibold).foregroundStyle(color)
                        Text(help).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: .rect(cornerRadius: 10))

            if let verification, !verification.signer.isEmpty || !verification.fingerprint.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    if !verification.signer.isEmpty {
                        InspectorRow(label: "Podepsal") { Text(verification.signer).lineLimit(1).truncationMode(.middle) }
                    }
                    if !verification.fingerprint.isEmpty {
                        InspectorRow(label: "Otisk") {
                            Text(verification.fingerprint)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var status: SignatureVerification.Status { verification?.status ?? .cannotCheck }

    private var title: String {
        switch status {
        case .good: "Ověřený podpis"
        case .goodUnknownValidity: "Neznámý klíč"
        case .expired: "Podpis nebo klíč vypršel"
        case .revoked: "Klíč byl revokován"
        case .bad: "Neplatný podpis"
        case .cannotCheck: "Nelze ověřit"
        case .unsigned: "Nepodepsáno"
        }
    }

    private var symbol: String {
        switch status {
        case .good: "checkmark.seal.fill"
        case .goodUnknownValidity, .cannotCheck: "questionmark.diamond.fill"
        case .expired, .revoked: "exclamationmark.triangle.fill"
        case .bad: "xmark.seal.fill"
        case .unsigned: "seal"
        }
    }

    private var color: Color {
        switch status {
        case .good: .green
        case .goodUnknownValidity, .cannotCheck, .expired: .orange
        case .revoked, .bad: .red
        case .unsigned: .secondary
        }
    }

    private var help: String {
        switch status {
        case .good: "Klíč patří mezi tvoje klíče nebo důvěryhodné GPG klíče."
        case .goodUnknownValidity: "Podpis sedí, ale klíč neznáš."
        case .cannotCheck: "Chybí veřejný klíč nebo nástroj pro ověření."
        case .bad: "Obsah commitu neodpovídá podpisu."
        case .expired: "Platnost podpisu nebo klíče skončila."
        case .revoked: "Klíč už není platný."
        case .unsigned: "Commit nemá podpis."
        }
    }
}
