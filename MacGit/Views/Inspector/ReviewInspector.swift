import SwiftUI
import GitKit

/// Záložka Review v inspektoru: souhrn nálezů posledního dokončeného review
/// pro vybraný commit (Historie) nebo pro aktuální větev (Změny).
struct ReviewInspector: View {
    let model: RepositoryModel
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    @State private var findings: [ReviewFinding] = []
    @State private var parsedTitle: String?

    private var target: ReviewTarget? {
        switch model.section {
        case .history, .branches:
            if let commit = model.selectedCommit { return .commit(commit) }
            return currentBranchTarget
        case .changes, .shelf:
            return currentBranchTarget
        }
    }

    private var currentBranchTarget: ReviewTarget? {
        model.branches.first { $0.isCurrent }.map(ReviewTarget.branch)
    }

    private var reviews: [ReviewRecord] {
        guard let target else { return [] }
        return model.workspace.reviews.filter { review in
            switch target {
            case let .branch(branch): !review.isCommitReview && review.branch == branch.name
            case let .commit(commit): review.commitHash == commit.hash
            }
        }
    }

    private var latestCompleted: ReviewRecord? {
        reviews.first { $0.status == .completed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let target {
                    summaryCard(target)
                    if !reviews.isEmpty {
                        ReviewsSection(model: model, target: target, horizontalPadding: 0)
                    }
                } else {
                    EmptyStateView(title: "Není co recenzovat", symbol: "sparkle.magnifyingglass", message: "Vyber commit nebo větev.")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .task(id: latestCompleted?.id) { await loadFindings() }
    }

    // MARK: Karta souhrnu

    @ViewBuilder
    private func summaryCard(_ target: ReviewTarget) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.accentGradient, in: .rect(cornerRadius: 7))
                    .accessibilityHidden(true)
                Text("AI Review")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !findings.isEmpty {
                    Text("\(findings.count)")
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.accentFill, in: .capsule)
                }
                Spacer(minLength: 0)
                Text(targetTitle(target))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            if let record = latestCompleted {
                if findings.isEmpty {
                    finding(symbol: "checkmark.circle", color: Theme.success, title: "Bez nálezů", detail: parsedTitle ?? "Agent nenašel nic, co by vyžadovalo zásah.")
                } else {
                    ForEach(findings.prefix(4)) { item in
                        finding(
                            symbol: item.severity.symbol,
                            color: item.severity.color,
                            title: item.title,
                            detail: item.file.map { file in item.line.map { "\(file):\($0)" } ?? file } ?? firstLine(item.details)
                        )
                    }
                    if findings.count > 4 {
                        Text("a dalších \(findings.count - 4) nálezů")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Button {
                    openWindow(value: ReviewWindowValue(projectID: model.project.id, reviewID: record.id))
                } label: {
                    Text("Zobrazit detailní analýzu")
                        .font(.system(size: 11.5))
                        .frame(maxWidth: .infinity)
                }
                .adaptiveButtonStyle()
            } else if reviews.contains(where: { $0.status == .running }) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Review probíhá…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("Agent projde změny ve zvláštní kopii repozitáře, tvoje pracovní složka zůstane nedotčená.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.reviewSheetTarget = target
                } label: {
                    Label("Spustit AI review…", systemImage: "sparkles")
                        .font(.system(size: 11.5))
                        .frame(maxWidth: .infinity)
                }
                .adaptiveButtonStyle()
            }
        }
        .padding(12)
        .adaptiveCard(cornerRadius: 16, tint: Theme.accent.opacity(0.10))
    }

    private func finding(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text((try? AttributedString(markdown: title)) ?? AttributedString(title))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func targetTitle(_ target: ReviewTarget) -> String {
        switch target {
        case let .branch(branch): branch.name
        case let .commit(commit): commit.shortHash
        }
    }

    private func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? ""
    }

    private func loadFindings() async {
        guard let record = latestCompleted else {
            findings = []
            parsedTitle = nil
            return
        }
        let path = record.outputPath
        let parsed = await Task.detached { () -> ParsedReview? in
            guard let markdown = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            return ParsedReview.parse(markdown)
        }.value
        findings = parsed?.findings ?? []
        parsedTitle = parsed.flatMap { $0.risk.map { "Riziko: \($0)" } ?? $0.title }
    }
}

extension ReviewFinding.Severity {
    var symbol: String {
        switch self {
        case .critical: "exclamationmark.octagon"
        case .important: "exclamationmark.triangle"
        case .consider: "info.circle"
        }
    }
}
