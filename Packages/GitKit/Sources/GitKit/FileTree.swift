import Foundation

/// Uzel stromu složek pro seznam změn.
public struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Složka: `dir:` + cesta, soubor: cesta souboru.
    public var id: String
    public var name: String
    public var path: String
    public var change: FileChange?
    public var children: [FileTreeNode]
    /// Počet souborů v podstromu.
    public private(set) var fileCount: Int
    /// Otisk obsahu podstromu (cesty a stavy) – porovnání uzlů je O(1) i pro tisíce souborů.
    public private(set) var signature: Int

    public init(id: String, name: String, path: String, change: FileChange?, children: [FileTreeNode]) {
        self.id = id
        self.name = name
        self.path = path
        self.change = change
        self.children = children
        var hasher = Hasher()
        hasher.combine(id)
        if let change {
            hasher.combine(change.path)
            hasher.combine(String(change.indexCode))
            hasher.combine(String(change.worktreeCode))
            fileCount = 1
        } else {
            for child in children { hasher.combine(child.signature) }
            fileCount = children.reduce(0) { $0 + $1.fileCount }
        }
        signature = hasher.finalize()
    }

    public var isDirectory: Bool { change == nil }

    /// Všechny změny v podstromu.
    public var changes: [FileChange] {
        var result: [FileChange] = []
        result.reserveCapacity(fileCount)
        collect(into: &result)
        return result
    }

    private func collect(into result: inout [FileChange]) {
        if let change { result.append(change); return }
        for child in children { child.collect(into: &result) }
    }

    public static func == (lhs: FileTreeNode, rhs: FileTreeNode) -> Bool {
        lhs.id == rhs.id && lhs.signature == rhs.signature
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(signature)
    }
}

public enum FileTree {
    /// Postaví strom ze změn. Složky s jediným podadresářem a bez souborů se sloučí do jednoho uzlu (`a/b/c`).
    public static func build(_ changes: [FileChange]) -> [FileTreeNode] {
        final class Folder {
            var folders: [String: Folder] = [:]
            var files: [FileChange] = []
        }
        let root = Folder()
        for change in changes {
            var components = change.path.split(separator: "/").map(String.init)
            components.removeLast()
            var folder = root
            for component in components {
                if let next = folder.folders[component] {
                    folder = next
                } else {
                    let next = Folder()
                    folder.folders[component] = next
                    folder = next
                }
            }
            folder.files.append(change)
        }

        func nodes(of folder: Folder, prefix: String) -> [FileTreeNode] {
            let directories = folder.folders.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name -> FileTreeNode in
                var current = folder.folders[name]!
                var displayName = name
                var path = prefix.isEmpty ? name : prefix + "/" + name
                while current.files.isEmpty, current.folders.count == 1, let (childName, child) = current.folders.first {
                    displayName += "/" + childName
                    path += "/" + childName
                    current = child
                }
                return FileTreeNode(id: "dir:" + path, name: displayName, path: path, change: nil, children: nodes(of: current, prefix: path))
            }
            let files = folder.files
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                .map { FileTreeNode(id: $0.path, name: $0.fileName, path: $0.path, change: $0, children: []) }
            return directories + files
        }
        return nodes(of: root, prefix: "")
    }
}
