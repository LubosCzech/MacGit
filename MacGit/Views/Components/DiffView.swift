import SwiftUI
import GitKit

enum DiffLayoutMode: String, CaseIterable, Identifiable {
    case unified, split
    var id: String { rawValue }
    var title: String { self == .unified ? "Jednotný" : "Vedle sebe" }
}

/// Diff souboru: hlavička s přepínačem zobrazení a obsah.
struct DiffView: View {
    let diff: FileDiff?
    var subtitle: String? = nil
    var placeholder = "Vyber soubor"
    var placeholderMessage: String? = "Rozdíly vybraného souboru se zobrazí tady."

    @AppStorage("diffLayoutMode") private var mode: DiffLayoutMode = .unified

    var body: some View {
        if let diff {
            VStack(spacing: 0) {
                header(diff)
                Divider()
                Group {
                if diff.isBinary {
                    EmptyStateView(title: "Binární soubor", symbol: "doc.zipper", message: "Rozdíly binárních souborů nelze zobrazit.")
                } else if diff.isEmpty {
                    EmptyStateView(title: "Žádné textové změny", symbol: "equal.circle", message: "Soubor se liší jen v oprávněních nebo je prázdný.")
                } else if mode == .unified {
                    UnifiedDiffContent(rows: DiffLayout.unified(diff))
                } else {
                    SplitDiffContent(rows: DiffLayout.split(diff))
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            EmptyStateView(title: placeholder, symbol: "doc.text.magnifyingglass", message: placeholderMessage)
        }
    }

    private func header(_ diff: FileDiff) -> some View {
        HStack(spacing: 8) {
            FileIcon(path: diff.path)
            Text((diff.path as NSString).lastPathComponent)
                .font(.headline)
                .lineLimit(1)
            Text(subtitle ?? (diff.path as NSString).deletingLastPathComponent)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !diff.isBinary {
                Text("+\(diff.additions)")
                    .foregroundStyle(.green)
                Text("−\(diff.deletions)")
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 12)
            Picker("Zobrazení rozdílů", selection: $mode) {
                ForEach(DiffLayoutMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.horizontal, 16)
        .frame(height: 38)
    }
}

// MARK: - Layout

enum DiffLayout {
    struct UnifiedRow: Identifiable {
        enum Kind { case hunk, context, addition, deletion, meta }
        let id: Int
        let kind: Kind
        let oldLine: Int?
        let newLine: Int?
        let text: AttributedString
    }

    struct SplitRow: Identifiable {
        struct Side {
            let line: Int
            let kind: UnifiedRow.Kind
            let text: AttributedString
        }
        let id: Int
        let isHunk: Bool
        let header: String
        let left: Side?
        let right: Side?
    }

    static func unified(_ diff: FileDiff) -> [UnifiedRow] {
        var rows: [UnifiedRow] = []
        var id = 0
        for hunk in diff.hunks {
            rows.append(UnifiedRow(id: id, kind: .hunk, oldLine: nil, newLine: nil, text: AttributedString(hunk.header)))
            id += 1
            for block in blocks(hunk.lines) {
                switch block {
                case let .single(line):
                    rows.append(UnifiedRow(id: id, kind: kind(line.kind), oldLine: line.oldLine, newLine: line.newLine, text: AttributedString(line.text)))
                    id += 1
                case let .change(deleted, added):
                    let highlights = wordHighlights(deleted, added)
                    for (index, line) in deleted.enumerated() {
                        rows.append(UnifiedRow(id: id, kind: .deletion, oldLine: line.oldLine, newLine: nil, text: highlights.old[index]))
                        id += 1
                    }
                    for (index, line) in added.enumerated() {
                        rows.append(UnifiedRow(id: id, kind: .addition, oldLine: nil, newLine: line.newLine, text: highlights.new[index]))
                        id += 1
                    }
                }
            }
        }
        return rows
    }

    static func split(_ diff: FileDiff) -> [SplitRow] {
        var rows: [SplitRow] = []
        var id = 0
        for hunk in diff.hunks {
            rows.append(SplitRow(id: id, isHunk: true, header: hunk.header, left: nil, right: nil))
            id += 1
            for block in blocks(hunk.lines) {
                switch block {
                case let .single(line):
                    guard line.kind == .context else { continue }
                    let text = AttributedString(line.text)
                    rows.append(SplitRow(id: id, isHunk: false, header: "",
                                         left: line.oldLine.map { SplitRow.Side(line: $0, kind: .context, text: text) },
                                         right: line.newLine.map { SplitRow.Side(line: $0, kind: .context, text: text) }))
                    id += 1
                case let .change(deleted, added):
                    let highlights = wordHighlights(deleted, added)
                    for index in 0..<max(deleted.count, added.count) {
                        let left = index < deleted.count ? SplitRow.Side(line: deleted[index].oldLine ?? 0, kind: .deletion, text: highlights.old[index]) : nil
                        let right = index < added.count ? SplitRow.Side(line: added[index].newLine ?? 0, kind: .addition, text: highlights.new[index]) : nil
                        rows.append(SplitRow(id: id, isHunk: false, header: "", left: left, right: right))
                        id += 1
                    }
                }
            }
        }
        return rows
    }

    private enum Block {
        case single(DiffLine)
        case change(deleted: [DiffLine], added: [DiffLine])
    }

    /// Seskupí po sobě jdoucí smazané a přidané řádky do jednoho bloku změny.
    private static func blocks(_ lines: [DiffLine]) -> [Block] {
        var result: [Block] = []
        var deleted: [DiffLine] = [], added: [DiffLine] = []
        func flush() {
            if !deleted.isEmpty || !added.isEmpty { result.append(.change(deleted: deleted, added: added)) }
            deleted = []; added = []
        }
        for line in lines {
            switch line.kind {
            case .deletion:
                if !added.isEmpty { flush() }
                deleted.append(line)
            case .addition:
                added.append(line)
            default:
                flush()
                result.append(.single(line))
            }
        }
        flush()
        return result
    }

    private static func kind(_ kind: DiffLine.Kind) -> UnifiedRow.Kind {
        switch kind {
        case .context: .context
        case .addition: .addition
        case .deletion: .deletion
        case .meta: .meta
        }
    }

    /// Zvýrazní změněnou část řádku (mezi společným začátkem a koncem).
    private static func wordHighlights(_ deleted: [DiffLine], _ added: [DiffLine]) -> (old: [AttributedString], new: [AttributedString]) {
        var old = deleted.map { AttributedString($0.text) }
        var new = added.map { AttributedString($0.text) }
        guard deleted.count == added.count else { return (old, new) }
        for index in deleted.indices {
            let a = Array(deleted[index].text), b = Array(added[index].text)
            var prefix = 0
            while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
            let changedOld = a.count - prefix - suffix, changedNew = b.count - prefix - suffix
            // Zvýrazňujeme jen dílčí změny; přepsaný celý řádek by byl jen šum.
            guard max(changedOld, changedNew) > 0,
                  Double(changedOld) < Double(a.count) * 0.7 || Double(changedNew) < Double(b.count) * 0.7 else { continue }
            highlight(&old[index], text: a, from: prefix, length: changedOld, color: .red)
            highlight(&new[index], text: b, from: prefix, length: changedNew, color: .green)
        }
        return (old, new)
    }

    private static func highlight(_ string: inout AttributedString, text: [Character], from start: Int, length: Int, color: Color) {
        guard length > 0 else { return }
        let lower = string.characters.index(string.startIndex, offsetBy: start)
        let upper = string.characters.index(lower, offsetBy: length)
        string[lower..<upper].backgroundColor = color.opacity(0.28)
    }
}

// MARK: - Rendering

private let diffFont = Font.system(size: 12, design: .monospaced)

private func diffBackground(for kind: DiffLayout.UnifiedRow.Kind) -> Color {
    switch kind {
    case .addition: .green.opacity(0.11)
    case .deletion: .red.opacity(0.09)
    case .hunk: .accentColor.opacity(0.07)
    default: .clear
    }
}

private struct UnifiedDiffContent: View {
    let rows: [DiffLayout.UnifiedRow]
    @State private var viewportWidth: CGFloat = 640

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    if row.kind == .hunk {
                        Text(row.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                            .frame(minWidth: viewportWidth, minHeight: 26, alignment: .leading)
                            .background(diffBackground(for: .hunk))
                    } else {
                        HStack(spacing: 0) {
                            Text(row.oldLine.map(String.init) ?? "")
                                .frame(width: 46, alignment: .trailing)
                                .foregroundStyle(.tertiary)
                            Text(row.newLine.map(String.init) ?? "")
                                .frame(width: 46, alignment: .trailing)
                                .foregroundStyle(.tertiary)
                            Text(row.kind == .addition ? "+" : row.kind == .deletion ? "−" : "")
                                .frame(width: 22)
                                .foregroundStyle(row.kind == .addition ? .green : .red)
                            Text(row.text)
                                .foregroundStyle(row.kind == .meta ? .secondary : .primary)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 16)
                        }
                        .font(diffFont)
                        .frame(minWidth: viewportWidth, minHeight: 20, alignment: .leading)
                        .background(diffBackground(for: row.kind))
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .textSelection(.enabled)
    }
}

private struct SplitDiffContent: View {
    let rows: [DiffLayout.SplitRow]

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    if row.isHunk {
                        Text(row.header)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                            .background(diffBackground(for: .hunk))
                    } else {
                        HStack(spacing: 0) {
                            side(row.left)
                            Divider()
                            side(row.right)
                        }
                        .font(diffFont)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .textSelection(.enabled)
    }

    private func side(_ side: DiffLayout.SplitRow.Side?) -> some View {
        HStack(spacing: 0) {
            Text(side.map { String($0.line) } ?? "")
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(side?.text ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 20)
        .background(side.map { diffBackground(for: $0.kind) } ?? Color.secondary.opacity(0.05))
    }
}
