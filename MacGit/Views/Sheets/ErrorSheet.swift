import SwiftUI
import GitKit

/// Chybová hláška, která zůstane ovladatelná i u dlouhého výstupu gitu.
struct ErrorItem: Identifiable {
    let message: String
    var id: String { message }
}

struct ErrorSheet: View {
    let message: String
    @Environment(\.dismiss) private var dismiss
    @State private var showDetails = false

    var body: some View {
        let summary = GitErrorSummary.make(from: message)
        let hasMoreDetails = summary.details != summary.explanation

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.warning)
                    .frame(width: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline)
                    ScrollView {
                        Text(summary.explanation)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if hasMoreDetails {
                DisclosureGroup("Výstup gitu", isExpanded: $showDetails) {
                    ScrollView([.vertical, .horizontal]) {
                        Text(summary.details)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 220)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
                }
                .font(.callout)
            }

            HStack {
                Button("Kopírovat výstup") { NSPasteboard.copy(summary.details) }
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

extension View {
    /// Zobrazí chybu z volitelného textu jako list s posuvným obsahem.
    func errorSheet(_ message: Binding<String?>) -> some View {
        sheet(item: Binding(
            get: { message.wrappedValue.map(ErrorItem.init) },
            set: { if $0 == nil { message.wrappedValue = nil } }
        )) { item in
            ErrorSheet(message: item.message)
        }
    }
}
