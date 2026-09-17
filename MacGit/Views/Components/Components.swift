import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GitKit

extension ChangeKind {
    var color: Color {
        switch self {
        case .added, .untracked: .green
        case .modified, .typeChanged: .orange
        case .deleted: .red
        case .renamed, .copied: .purple
        case .conflicted: .pink
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
        case .untracked: "Nový, nesledovaný"
        case .conflicted: "Konflikt"
        case .ignored: "Ignorován"
        }
    }
}

/// Písmeno stavu vpravo v řádku (jako v Xcode).
struct StatusLetter: View {
    let kind: ChangeKind

    var body: some View {
        Text(kind.letter)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(kind.color)
            .frame(width: 14)
            .help(kind.title)
            .accessibilityLabel(kind.title)
    }
}

/// Systémová ikona typu souboru podle přípony.
struct FileIcon: View {
    let path: String
    var size: CGFloat = 16

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Image(nsImage: Self.icon(for: (path as NSString).pathExtension))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @MainActor static func icon(for ext: String) -> NSImage {
        if let cached = cache[ext] { return cached }
        let type = UTType(filenameExtension: ext) ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        cache[ext] = image
        return image
    }
}

/// Název souboru + šedá cesta ke složce.
struct FileNameLabel: View {
    let path: String
    var originalPath: String? = nil
    var isDeleted = false

    var body: some View {
        HStack(spacing: 6) {
            FileIcon(path: path)
            Text((path as NSString).lastPathComponent)
                .strikethrough(isDeleted, color: .secondary)
                .lineLimit(1)
                .layoutPriority(1)
            let dir = (path as NSString).deletingLastPathComponent
            if let originalPath {
                let originalName = (originalPath as NSString).lastPathComponent
                let originalDir = (originalPath as NSString).deletingLastPathComponent
                Text("← \(originalName == (path as NSString).lastPathComponent ? (originalDir.isEmpty ? "/" : originalDir + "/") : originalName)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !dir.isEmpty {
                Text(dir)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title).font(.headline)
            if let message = prompt.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(prompt.placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                Button(prompt.confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 380)
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
            .accessibilityHidden(true)
    }
}

/// Dvojice popisek–hodnota v inspektoru.
struct InspectorRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            content
                .gridColumnAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Nadpis sekce v inspektoru.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

extension NSPasteboard {
    static func copy(_ string: String) {
        general.clearContents()
        general.setString(string, forType: .string)
    }
}
