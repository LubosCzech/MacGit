import Foundation

/// Uzel stromu složek pro seznam změn.
public struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Složka: `dir:` + cesta, soubor: cesta souboru.
    public var id: String
    public var name: String
    public var path: String
    public var change: FileChange?
    public var children: [FileTreeNode]

    public var isDirectory: Bool { change == nil }

    /// Všechny změny v podstromu.
    public var changes: [FileChange] {
        if let change { return [change] }
        return children.flatMap(\.changes)
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
