import SwiftUI
import GitKit

struct ShelfList: View {
    @Bindable var model: RepositoryModel

    var body: some View {
        let shelves = model.workspace.shelves.filter {
            model.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(model.searchText)
                || $0.files.contains { $0.localizedCaseInsensitiveContains(model.searchText) }
        }
        List(shelves, selection: $model.selectedShelfID) { shelf in
            VStack(alignment: .leading, spacing: 3) {
                Text(shelf.name).lineLimit(1)
                Text(subtitle(shelf))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .tag(shelf.id)
        }
        .contextMenu(forSelectionType: Shelf.ID.self) { ids in
            if let id = ids.first, let shelf = model.workspace.shelves.first(where: { $0.id == id }) {
                Button("Obnovit") { Task { await model.unshelve(shelf, keep: false) } }
                Button("Obnovit a ponechat ve shelfu") { Task { await model.unshelve(shelf, keep: true) } }
                Divider()
                Button("Smazat…", role: .destructive) { model.shelfToDelete = shelf }
            }
        } primaryAction: { ids in
            if let id = ids.first, let shelf = model.workspace.shelves.first(where: { $0.id == id }) {
                Task { await model.unshelve(shelf, keep: false) }
            }
        }
        .overlay {
            if model.workspace.shelves.isEmpty {
                EmptyStateView(title: "Shelf je prázdný", symbol: "archivebox", message: "Rozpracované změny odložíš z kontextového menu v seznamu Změny.")
            } else if shelves.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .onAppear {
            if model.selectedShelfID == nil { model.selectedShelfID = model.workspace.shelves.first?.id }
        }
    }

    private func subtitle(_ shelf: Shelf) -> String {
        var parts = [shelf.createdAt.formatted(.relative(presentation: .named)), "\(shelf.files.count) souborů"]
        if let branch = shelf.branch { parts.append(branch) }
        return parts.joined(separator: " · ")
    }
}

struct ShelfDetail: View {
    let model: RepositoryModel
    @State private var selectedFile: String?

    var body: some View {
        if let shelf = model.workspace.shelves.first(where: { $0.id == model.selectedShelfID }) {
            let diffs = Self.diffs(model.patchData(for: shelf))
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shelf.name).font(.title2.weight(.semibold))
                        Text("Odloženo \(shelf.createdAt.formatted(date: .abbreviated, time: .shortened))\(shelf.branch.map { " na větvi \($0)" } ?? "")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Smazat…", role: .destructive) { model.shelfToDelete = shelf }
                    Menu {
                        Button("Obnovit a ponechat ve shelfu") { Task { await model.unshelve(shelf, keep: true) } }
                    } label: {
                        Text("Obnovit")
                    } primaryAction: {
                        Task { await model.unshelve(shelf, keep: false) }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
                }
                .padding(20)

                Divider()

                ResizableSplit(id: "shelfFiles", defaultHeight: 160) {
                    List(shelf.files, id: \.self, selection: $selectedFile) { path in
                        FileNameLabel(path: path).tag(path)
                    }
                } bottom: {
                    DiffView(diff: selectedFile.flatMap { diffs[$0] }, placeholder: "Vyber soubor", placeholderMessage: nil)
                }
            }
            .onChange(of: shelf.id, initial: true) { selectedFile = shelf.files.first }
        } else {
            EmptyStateView(title: "Vyber odložené změny", symbol: "archivebox")
        }
    }

    /// Patch rozdělený po souborech.
    static func diffs(_ data: Data?) -> [String: FileDiff] {
        guard let data else { return [:] }
        let text = String(decoding: data, as: UTF8.self)
        var result: [String: FileDiff] = [:]
        for (index, chunk) in text.components(separatedBy: "\ndiff --git ").enumerated() {
            let body = index == 0 ? chunk : "diff --git " + chunk
            guard let firstLine = body.split(separator: "\n").first,
                  let path = firstLine.components(separatedBy: " b/").last else { continue }
            result[path] = GitParsers.parseDiff(body, path: path)
        }
        return result
    }
}
