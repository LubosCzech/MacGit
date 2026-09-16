import SwiftUI
import GitKit

struct ShelfView: View {
    let model: RepositoryModel
    @State private var selection: Shelf.ID?
    @State private var previewFile: String?
    @State private var shelfToDelete: Shelf?

    private var selected: Shelf? { model.workspace.shelves.first { $0.id == selection } }

    /// Patch rozdělený po souborech pro náhled.
    private var previewDiffs: [String: FileDiff] {
        guard let shelf = selected, let data = model.patchData(for: shelf) else { return [:] }
        let text = String(decoding: data, as: UTF8.self)
        var result: [String: FileDiff] = [:]
        let chunks = text.components(separatedBy: "\ndiff --git ")
        for (index, chunk) in chunks.enumerated() {
            let body = index == 0 ? chunk : "diff --git " + chunk
            guard let firstLine = body.split(separator: "\n").first,
                  let bPath = firstLine.components(separatedBy: " b/").last else { continue }
            result[bPath] = GitParsers.parseDiff(body, path: bPath)
        }
        return result
    }

    var body: some View {
        if model.workspace.shelves.isEmpty {
            EmptyStateView(
                title: "Shelf je prázdný",
                symbol: "archivebox",
                message: "V seznamu změn klikni pravým tlačítkem na soubory nebo changelist a zvol „Odložit do shelfu“."
            )
        } else {
            HSplitView {
                List(model.workspace.shelves, selection: $selection) { shelf in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shelf.name).font(.body.weight(.medium))
                        HStack(spacing: 6) {
                            Text(shelf.createdAt, format: .dateTime.day().month().hour().minute())
                            Text("·")
                            Text("\(shelf.files.count) souborů")
                            if let branch = shelf.branch {
                                Text("·")
                                Label(branch, systemImage: "arrow.triangle.branch")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(shelf.id)
                    .contextMenu {
                        Button("Obnovit a odstranit ze shelfu", systemImage: "tray.and.arrow.up") { Task { await model.unshelve(shelf, keep: false) } }
                        Button("Obnovit a ponechat", systemImage: "doc.on.doc") { Task { await model.unshelve(shelf, keep: true) } }
                        Divider()
                        Button("Smazat…", systemImage: "trash", role: .destructive) { shelfToDelete = shelf }
                    }
                }
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 460, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                if let selected { Task { await model.unshelve(selected, keep: false) } }
                            } label: {
                                Label("Obnovit", systemImage: "tray.and.arrow.up").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            Button {
                                shelfToDelete = selected
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                        .disabled(selected == nil)
                        .padding(12)
                    }
                }

                let diffs = previewDiffs
                VSplitView {
                    List(selected?.files ?? [], id: \.self, selection: $previewFile) { path in
                        Text(path).lineLimit(1).truncationMode(.head).tag(path)
                    }
                    .frame(minHeight: 80, idealHeight: 150, maxHeight: 300)
                    DiffView(diff: previewFile.flatMap { diffs[$0] }, placeholder: "Vyber soubor pro náhled")
                        .frame(minHeight: 200, maxHeight: .infinity)
                }
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { if selection == nil { selection = model.workspace.shelves.first?.id } }
            .onChange(of: selection) { previewFile = selected?.files.first }
            .confirmationDialog("Smazat shelf „\(shelfToDelete?.name ?? "")“?", isPresented: Binding(get: { shelfToDelete != nil }, set: { if !$0 { shelfToDelete = nil } })) {
                Button("Smazat", role: .destructive) {
                    if let shelfToDelete { model.deleteShelf(shelfToDelete) }
                }
            } message: {
                Text("Odložené změny budou nenávratně ztraceny.")
            }
        }
    }
}
