import SwiftUI
import GitKit

extension ChangeKind {
    var color: Color {
        switch self {
        case .added, .untracked: .green
        case .modified, .typeChanged: .blue
        case .deleted: .red
        case .renamed, .copied: .purple
        case .conflicted: .orange
        case .ignored: .gray
        }
    }

    var title: String {
        switch self {
        case .added: "Přidán"
        case .modified: "Změněn"
        case .deleted: "Smazán"
        case .renamed: "Přejmenován"
        case .copied: "Zkopírován"
        case .typeChanged: "Změna typu"
        case .untracked: "Nový"
        case .conflicted: "Konflikt"
        case .ignored: "Ignorován"
        }
    }
}

struct StatusBadge: View {
    let kind: ChangeKind

    var body: some View {
        Text(kind.letter)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(kind.color)
            .frame(width: 18, height: 18)
            .background(kind.color.opacity(0.16), in: .rect(cornerRadius: 5))
            .help(kind.title)
    }
}

struct FileLabel: View {
    let path: String
    var kind: ChangeKind

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(kind: kind)
            let name = (path as NSString).lastPathComponent
            let dir = (path as NSString).deletingLastPathComponent
            Text(name)
                .strikethrough(kind == .deleted, color: .secondary)
                .lineLimit(1)
            if !dir.isEmpty {
                Text(dir)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}

/// Plovoucí oznámení ve stylu Liquid Glass.
struct ToastView: View {
    let message: String
    var symbol = "checkmark.circle.fill"

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(.green.opacity(0.25)), in: .capsule)
    }
}

struct BusyIndicator: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(title).font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

struct EmptyStateView: View {
    let title: String
    let symbol: String
    var message: String? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        }
    }
}

/// Jednoduchý dialog pro zadání textu (jméno changelistu, větve, shelfu…).
struct TextPrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String? = nil
    var placeholder: String
    var initialValue: String = ""
    var confirmTitle: String = "OK"
    var action: (String) -> Void
}

struct TextPromptSheet: View {
    let prompt: TextPrompt
    @State private var value = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.title).font(.title3.bold())
            if let message = prompt.message {
                Text(message).foregroundStyle(.secondary)
            }
            TextField(prompt.placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                Button(prompt.confirmTitle, action: confirm)
                    .buttonStyle(.glassProminent)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
        .onAppear { value = prompt.initialValue }
    }

    private func confirm() {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        prompt.action(trimmed)
        dismiss()
    }
}

extension View {
    func textPrompt(_ prompt: Binding<TextPrompt?>) -> some View {
        sheet(item: prompt) { TextPromptSheet(prompt: $0) }
    }
}

struct SpaceIcon: View {
    let space: Space
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: space.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(space.color.color.gradient, in: .rect(cornerRadius: size * 0.28))
    }
}

/// Vyhledávací pole v kapsli z tekutého skla nad seznamem.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
