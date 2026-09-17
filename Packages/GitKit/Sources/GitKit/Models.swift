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
    /// Commit obsahuje podpis (GPG, SSH nebo X.509) – bez ověření.
    public var isSigned: Bool = false

    public var id: String { hash }
}

/// Výsledek ověření podpisu commitu (`%G?`).
public struct SignatureVerification: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Platný podpis důvěryhodným klíčem.
        case good
        /// Platný podpis, ale klíč není mezi důvěryhodnými (GPG bez důvěry, SSH mimo allowed signers).
        case goodUnknownValidity
        /// Klíč nebo podpis vypršel či byl revokován.
        case expired, revoked
        /// Podpis je neplatný – obsah commitu neodpovídá.
        case bad
        /// Podpis nelze ověřit (chybí klíč / allowed signers).
        case cannotCheck
        case unsigned
    }

    public var status: Status
    /// `%GS` – podepisující (e-mail / jméno).
    public var signer: String
    /// `%GK` – ID nebo otisk klíče.
    public var key: String
    /// `%GF` – otisk klíče.
    public var fingerprint: String

    public init(status: Status, signer: String = "", key: String = "", fingerprint: String = "") {
        self.status = status
        self.signer = signer
        self.key = key
        self.fingerprint = fingerprint
    }

    init(code: Character, signer: String, key: String, fingerprint: String) {
        let status: Status = switch code {
        case "G": .good
        case "U": .goodUnknownValidity
        case "X", "Y": .expired
        case "R": .revoked
        case "B": .bad
        case "E": .cannotCheck
        default: .unsigned
        }
        self.init(status: status, signer: signer, key: key, fingerprint: fingerprint)
    }
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
