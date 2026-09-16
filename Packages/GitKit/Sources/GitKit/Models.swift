import Foundation

public enum ChangeKind: String, Sendable, Codable {
    case added, modified, deleted, renamed, copied, typeChanged, untracked, conflicted, ignored

    public var letter: String {
        switch self {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .typeChanged: "T"
        case .untracked: "?"
        case .conflicted: "U"
        case .ignored: "!"
        }
    }

    init(code: Character) {
        switch code {
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "U": self = .conflicted
        default: self = .modified
        }
    }
}

public struct FileChange: Identifiable, Hashable, Sendable {
    public var path: String
    public var originalPath: String?
    /// Stav v indexu (`.` = beze změny).
    public var indexCode: Character
    /// Stav v pracovním adresáři (`.` = beze změny).
    public var worktreeCode: Character
    public var kind: ChangeKind

    public var id: String { path }
    public var fileName: String { (path as NSString).lastPathComponent }
    public var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
    public var isStaged: Bool { indexCode != "." && indexCode != "?" }
    public var isUntracked: Bool { kind == .untracked }

    public init(path: String, originalPath: String? = nil, indexCode: Character, worktreeCode: Character, kind: ChangeKind) {
        self.path = path
        self.originalPath = originalPath
        self.indexCode = indexCode
        self.worktreeCode = worktreeCode
        self.kind = kind
    }
}

public struct BranchStatus: Sendable, Equatable {
    public var head: String?
    public var oid: String?
    public var upstream: String?
    public var ahead: Int = 0
    public var behind: Int = 0

    public var isDetached: Bool { head == nil }
    public init() {}
}

public struct StatusSnapshot: Sendable {
    public var branch: BranchStatus
    public var changes: [FileChange]

    public init(branch: BranchStatus = BranchStatus(), changes: [FileChange] = []) {
        self.branch = branch
        self.changes = changes
    }
}

public struct Commit: Identifiable, Hashable, Sendable {
    public var hash: String
    public var shortHash: String
    public var parents: [String]
    public var authorName: String
    public var authorEmail: String
    public var date: Date
    public var subject: String
    public var body: String
    public var refs: [String]
    /// `%G?` – G/U/X/Y/R/E/B/N
    public var signature: Character

    public var id: String { hash }
    public var isSigned: Bool { signature != "N" }
}

public struct Branch: Identifiable, Hashable, Sendable {
    public var fullName: String
    public var name: String
    public var shortHash: String
    public var upstream: String?
    public var isCurrent: Bool
    public var isRemote: Bool
    public var track: String

    public var id: String { fullName }
    /// U remote větve jméno bez prefixu remotu (`origin/feature/x` → `feature/x`).
    public var localName: String {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

public struct Remote: Identifiable, Hashable, Sendable {
    public var name: String
    public var fetchURL: String
    public var pushURL: String
    public var id: String { name }
}

public struct DiffLine: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case context, addition, deletion, meta }
    public var id: Int
    public var kind: Kind
    public var oldLine: Int?
    public var newLine: Int?
    public var text: String
}

public struct DiffHunk: Identifiable, Hashable, Sendable {
    public var id: Int
    public var header: String
    public var lines: [DiffLine]
}

public struct FileDiff: Sendable, Hashable {
    public var path: String
    public var hunks: [DiffHunk]
    public var isBinary: Bool
    public var additions: Int
    public var deletions: Int

    public init(path: String, hunks: [DiffHunk] = [], isBinary: Bool = false) {
        self.path = path
        self.hunks = hunks
        self.isBinary = isBinary
        self.additions = hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count }
        self.deletions = hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count }
    }

    public var isEmpty: Bool { hunks.isEmpty && !isBinary }
}

public struct CommitFile: Identifiable, Hashable, Sendable {
    public var path: String
    public var originalPath: String?
    public var kind: ChangeKind
    public var id: String { path }
}
