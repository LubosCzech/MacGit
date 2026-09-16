import SwiftUI
import GitKit

struct DiffView: View {
    let diff: FileDiff?
    var placeholder = "Vyber soubor pro zobrazení rozdílů"

    var body: some View {
        if let diff {
            if diff.isBinary {
                EmptyStateView(title: "Binární soubor", symbol: "doc.zipper", message: "Rozdíly binárních souborů nelze zobrazit.")
            } else if diff.isEmpty {
                EmptyStateView(title: "Žádné textové změny", symbol: "equal.circle", message: "Soubor se liší jen v oprávněních nebo je prázdný.")
            } else {
                DiffContent(diff: diff)
            }
        } else {
            EmptyStateView(title: placeholder, symbol: "doc.text.magnifyingglass")
        }
    }
}

private struct DiffContent: View {
    let diff: FileDiff
    private let font = Font.system(size: 12, design: .monospaced)

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(diff.hunks) { hunk in
                    Text(hunk.header)
                        .font(font)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08))
                    ForEach(hunk.lines) { line in
                        DiffLineRow(line: line, font: font)
                    }
                }
            }
            .padding(.bottom, 24)
            .frame(minWidth: 600, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                Text(diff.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("+\(diff.additions)").foregroundStyle(.green)
                Text("−\(diff.deletions)").foregroundStyle(.red)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(10)
        }
        .textSelection(.enabled)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let font: Font

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(prefix)
                .frame(width: 22)
                .foregroundStyle(accent)
            Text(line.text.isEmpty ? " " : line.text)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(line.kind == .meta ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .font(font)
        .padding(.vertical, 1)
        .background(background)
    }

    private var prefix: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "−"
        default: ""
        }
    }

    private var accent: Color {
        switch line.kind {
        case .addition: .green
        case .deletion: .red
        default: .secondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .addition: .green.opacity(0.13)
        case .deletion: .red.opacity(0.13)
        default: .clear
        }
    }
}
