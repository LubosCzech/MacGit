import SwiftUI
import GitKit

/// Seznam review větve (v detailu větve) nebo commitu (v inspektoru).
struct ReviewsSection: View {
    let model: RepositoryModel
    let target: ReviewTarget
    var horizontalPadding: CGFloat = 20
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let reviews = model.workspace.reviews.filter { review in
            switch target {
            case let .branch(branch): !review.isCommitReview && review.branch == branch.name
            case let .commit(commit): review.commitHash == commit.hash
            }
        }
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI review")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(reviews) { review in
                    HStack(spacing: 6) {
                        ReviewRow(review: review)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            if review.status == .running {
                                Button("Zastavit") { store.reviews.cancel(review.id) }
                            }
                            Button(review.status == .running ? "Průběh" : "Otevřít") { open(review) }
                        }
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { open(review) }
                    .contextMenu {
                        Button("Otevřít") { open(review) }
                        if review.status == .running {
                            Button("Zastavit") { store.reviews.cancel(review.id) }
                        }
                        Button("Zobrazit ve Finderu") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: review.outputPath)])
                        }
                        Divider()
                        Button("Smazat", role: .destructive) { store.reviews.delete(review, in: model) }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 12)
        }
    }

    private func open(_ review: ReviewRecord) {
        openWindow(value: ReviewWindowValue(projectID: model.project.id, reviewID: review.id))
    }
}

private struct ReviewRow: View {
    let review: ReviewRecord

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(review.agent.title) · \(review.modelTitle)")
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(review.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .help(review.errorMessage ?? "")
    }

    @ViewBuilder private var statusIcon: some View {
        switch review.status {
        case .running: ProgressView().controlSize(.small)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let date = review.startedAt.formatted(.relative(presentation: .named))
        switch review.status {
        case .running: return "Probíhá · spuštěno \(date) · proti \(review.baseBranch)"
        case .completed: return "Dokončeno \(date) · proti \(review.baseBranch) · \(review.headCommit)"
        case .failed: return review.errorMessage?.split(separator: "\n").last.map(String.init) ?? "Selhalo"
        case .cancelled: return "Zastaveno \(date)"
        }
    }
}

/// Okno s výsledkem review.
struct ReviewWindow: View {
    let value: ReviewWindowValue?
    @Environment(AppStore.self) private var store

    var body: some View {
        if let value, let project = store.project(value.projectID),
           let review = store.model(for: project).workspace.reviews.first(where: { $0.id == value.reviewID }) {
            ReviewDocument(model: store.model(for: project), review: review)
                .navigationTitle(review.isCommitReview ? "Review · commit \(review.headCommit)" : "Review · \(review.branch)")
                .navigationSubtitle("\(project.name) · \(review.agent.title) · \(review.modelTitle)")
        } else {
            EmptyStateView(title: "Review nebylo nalezeno", symbol: "doc.questionmark", message: "Mohlo být smazáno nebo systém vyčistil dočasné soubory.")
        }
    }
}

private struct ReviewDocument: View {
    let model: RepositoryModel
    let review: ReviewRecord
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var severityFilter: ReviewFinding.Severity?
    @State private var showRaw = false

    var body: some View {
        let parsed = ParsedReview.parse(text)
        Group {
            if review.status == .running {
                RunningReviewView(review: review)
            } else if text.isEmpty {
                EmptyStateView(
                    title: review.status == .cancelled ? "Review bylo zastaveno" : "Review nemá výstup",
                    symbol: "exclamationmark.bubble",
                    message: review.errorMessage
                )
            } else if showRaw || parsed.sections.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(parsed)
                        findings(parsed)
                        ForEach(parsed.sections.filter { !isFindingsSection($0) && !$0.title.localizedCaseInsensitiveContains("riziko") && !$0.title.localizedCaseInsensitiveContains("shrnutí") }) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title).font(.title3.weight(.semibold))
                                MarkdownBlock(text: section.body)
                            }
                        }
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showRaw) {
                    Label("Markdown", systemImage: "text.alignleft")
                }
                .help("Zobrazit původní výstup agenta")
                .disabled(text.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Kopírovat výstup") { NSPasteboard.copy(text) }
                    Button("Zobrazit soubor ve Finderu") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: review.outputPath)])
                    }
                    Button("Zobrazit log agenta") { NSWorkspace.shared.open(URL(fileURLWithPath: review.logPath)) }
                } label: {
                    Label("Další", systemImage: "ellipsis")
                }
            }
        }
        .task(id: review.status) { load() }
    }

    private var metadataLine: String {
        let date = (review.finishedAt ?? review.startedAt).formatted(date: .abbreviated, time: .shortened)
        let target = review.isCommitReview
            ? "commit \(review.headCommit) „\(review.commitSubject ?? "")“ oproti \(review.baseBranch)"
            : "\(review.branch) → \(review.baseBranch) · commit \(review.headCommit)"
        return "\(target) · \(review.agent.title), \(review.modelTitle) · \(date)"
    }

    private func load() {
        text = ParsedReview.trimmedDocument((try? String(contentsOfFile: review.outputPath, encoding: .utf8)) ?? "")
    }

    private func isFindingsSection(_ section: ReviewSection) -> Bool {
        section.title.localizedCaseInsensitiveContains("prověření")
    }

    private func header(_ parsed: ParsedReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(parsed.title ?? "Review – \(review.targetTitle)")
                .font(.largeTitle.weight(.semibold))
            Text(metadataLine)
                .foregroundStyle(.secondary)
            if let summary = parsed.sections.first(where: { $0.title.localizedCaseInsensitiveContains("shrnutí") }) {
                MarkdownBlock(text: summary.body)
            }
            HStack(spacing: 8) {
                if let risk = parsed.risk {
                    RiskBadge(text: risk)
                }
                ForEach(ReviewFinding.Severity.allCases, id: \.self) { severity in
                    let count = parsed.findings.filter { $0.severity == severity }.count
                    if count > 0 {
                        SeverityBadge(severity: severity, count: count)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func findings(_ parsed: ParsedReview) -> some View {
        if let section = parsed.sections.first(where: isFindingsSection) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(section.title).font(.title3.weight(.semibold))
                    Spacer()
                    if !parsed.findings.isEmpty {
                        Picker("Závažnost", selection: $severityFilter) {
                            Text("Vše").tag(ReviewFinding.Severity?.none)
                            ForEach(ReviewFinding.Severity.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if parsed.findings.isEmpty {
                    MarkdownBlock(text: section.body)
                } else {
                    ForEach(parsed.findings.filter { severityFilter == nil || $0.severity == severityFilter }) { finding in
                        FindingCard(finding: finding, repositoryURL: model.project.url)
                    }
                }
            }
        }
    }
}

private struct RunningReviewView: View {
    let review: ReviewRecord
    @Environment(AppStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ContentUnavailableView {
                Label("Probíhá review", systemImage: "sparkle.magnifyingglass")
            } description: {
                Text("\(review.agent.title) prochází \(review.targetTitle) oproti \(review.baseBranch).\nUplynulo \(Duration.seconds(context.date.timeIntervalSince(review.startedAt)).formatted(.time(pattern: .minuteSecond))). Okno můžeš zavřít, review poběží dál.")
            } actions: {
                Button("Zastavit review") { store.reviews.cancel(review.id) }
            }
        }
    }
}

private struct FindingCard: View {
    let finding: ReviewFinding
    let repositoryURL: URL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(finding.severity.color)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SeverityBadge(severity: finding.severity, count: nil)
                    Text((try? AttributedString(markdown: finding.title)) ?? AttributedString(finding.title))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let file = finding.file {
                    let url = repositoryURL.appendingPathComponent(file)
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(finding.line.map { "\(file):\($0)" } ?? file, systemImage: "doc.text")
                            .font(.callout.monospaced())
                    }
                    .buttonStyle(.link)
                    .disabled(!FileManager.default.fileExists(atPath: url.path))
                    .help("Otevřít soubor ve výchozím editoru")
                }
                if !finding.details.isEmpty {
                    MarkdownBlock(text: finding.details)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(finding.severity.color.opacity(0.07), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

private struct SeverityBadge: View {
    let severity: ReviewFinding.Severity
    let count: Int?

    var body: some View {
        Text(count.map { "\(severity.title) \($0)" } ?? severity.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(severity.color)
            .background(severity.color.opacity(0.15), in: .capsule)
    }
}

private struct RiskBadge: View {
    let text: String

    var body: some View {
        let lower = text.lowercased()
        let color: Color = lower.contains("vysoké") ? .red : lower.contains("střední") ? .orange : .green
        Label(text, systemImage: "gauge.with.dots.needle.33percent")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: .capsule)
            .lineLimit(2)
    }
}

/// Jednoduché vykreslení Markdownu (inline formátování, zachované řádky).
private struct MarkdownBlock: View {
    let text: String

    var body: some View {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        Text(attributed)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ReviewFinding.Severity {
    var title: String {
        switch self {
        case .critical: "Kritické"
        case .important: "Důležité"
        case .consider: "K zvážení"
        }
    }

    var color: Color {
        switch self {
        case .critical: .red
        case .important: .orange
        case .consider: .blue
        }
    }
}
