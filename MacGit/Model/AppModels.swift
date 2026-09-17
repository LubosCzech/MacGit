import Foundation
import SwiftUI
import GitKit

enum SpaceColor: String, Codable, CaseIterable, Identifiable {
    case brand, cobalt, indigo, cyan
    case blue, purple, pink, red, orange, yellow, green, teal, gray
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .brand: Brand.primaryBlue
        case .cobalt: Brand.cobalt
        case .indigo: Brand.indigo
        case .cyan: Brand.cyanAccent
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .gray: .gray
        }
    }
}

/// Uživatelem definovaný prostor (Práce, Soukromé, …).
struct Space: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var color: SpaceColor

    static func new() -> Space {
        Space(name: "", symbol: suggestedSymbols.randomElement()!, color: .brand)
    }

    static let suggestedSymbols = [
        "briefcase.fill", "house.fill", "person.fill", "star.fill", "hammer.fill", "graduationcap.fill",
        "gamecontroller.fill", "building.2.fill", "heart.fill", "leaf.fill", "flask.fill", "globe.europe.africa.fill",
        "shippingbox.fill", "sparkles", "terminal.fill", "archivebox.fill"
    ]
}

/// Jak se projekt přihlašuje k remotu.
enum ProjectAuth: Codable, Hashable {
    /// ssh-agent, ~/.ssh/config, osxkeychain – výchozí chování gitu.
    case system
    /// Konkrétní SSH klíč; passphrase je v Klíčence.
    case sshKey(path: String)
    /// Token z uloženého účtu GitHub/GitLab.
    case account(UUID)
    /// Uživatel + heslo/token uložené v Klíčence u projektu.
    case password(username: String)

    enum Kind: String, CaseIterable, Identifiable {
        case system, sshKey, account, password
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: "Systémové (ssh-agent / Klíčenka)"
            case .sshKey: "SSH klíč"
            case .account: "Token účtu GitHub/GitLab"
            case .password: "Uživatel a heslo"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .system: .system
        case .sshKey: .sshKey
        case .account: .account
        case .password: .password
        }
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var spaceID: UUID?
    var auth: ProjectAuth = .system
    var addedAt = Date()
    var lastOpenedAt: Date?

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) }
}

/// Účet u GitHubu nebo GitLabu (token je v Klíčence).
struct HostingAccount: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: HostingKind
    var host: String
    var login: String
    var displayName: String?
    var email: String?

    var title: String { "\(login) @ \(host)" }
    var keychainKey: String { "account.\(id.uuidString)" }
}

struct Changelist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var comment: String = ""
}

struct Shelf: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var branch: String?
    var files: [String]
    var patchFileName: String { "\(id.uuidString).patch" }
}

/// Stav projektu, který git sám neukládá – changelisty, rozepsaná zpráva, shelf.
struct ProjectWorkspace: Codable {
    static let defaultChangelistID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var changelists: [Changelist] = [Changelist(id: defaultChangelistID, name: "Změny")]
    var activeChangelistID: UUID = defaultChangelistID
    /// Cesta souboru → changelist. Nepřiřazené soubory patří do aktivního changelistu.
    var assignments: [String: UUID] = [:]
    var shelves: [Shelf] = []
    var draftMessage: String = ""
    /// Soubory, které uživatel odškrtl (nebudou v commitu).
    var excludedPaths: Set<String> = []
    /// Soubory z neaktivních changelistů, které uživatel zaškrtl.
    var includedPaths: Set<String> = []
    /// Historie AI review větví.
    var reviews: [ReviewRecord] = []

    init() {}

    /// Tolerantní dekódování – nové klíče chybí ve starších uložených souborech.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProjectWorkspace()
        changelists = try c.decodeIfPresent([Changelist].self, forKey: .changelists) ?? defaults.changelists
        activeChangelistID = try c.decodeIfPresent(UUID.self, forKey: .activeChangelistID) ?? defaults.activeChangelistID
        assignments = try c.decodeIfPresent([String: UUID].self, forKey: .assignments) ?? [:]
        shelves = try c.decodeIfPresent([Shelf].self, forKey: .shelves) ?? []
        draftMessage = try c.decodeIfPresent(String.self, forKey: .draftMessage) ?? ""
        excludedPaths = try c.decodeIfPresent(Set<String>.self, forKey: .excludedPaths) ?? []
        includedPaths = try c.decodeIfPresent(Set<String>.self, forKey: .includedPaths) ?? []
        reviews = try c.decodeIfPresent([ReviewRecord].self, forKey: .reviews) ?? []
    }
}

/// Jedno AI review větve.
struct ReviewRecord: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        case running, completed, failed, cancelled
    }

    var id = UUID()
    var branch: String
    var baseBranch: String
    var headCommit: String
    var agent: AgentKind
    var model: String?
    var startedAt = Date()
    var finishedAt: Date?
    var status: Status = .running
    /// Markdown s výstupem agenta (v Caches – dočasné úložiště).
    var outputPath: String
    var logPath: String
    var errorMessage: String?
    /// Vyplněno u review jednoho commitu (plný hash a předmět).
    var commitHash: String?
    var commitSubject: String?

    var modelTitle: String { model.flatMap { $0.isEmpty ? nil : $0 } ?? "výchozí model" }
    var isCommitReview: Bool { commitHash != nil }
    /// „větev feature/x“ nebo „commit abc1234“.
    var targetTitle: String { isCommitReview ? "commit \(headCommit)" : "větev \(branch)" }
}

/// Operace selhala, protože SSH server není mezi známými (known_hosts).
struct HostTrustRequest: Identifiable {
    let id = UUID()
    var endpoint: SSHEndpoint
    var problem: HostKeyTrust.Problem
    var message: String
    var retry: () async -> Void
}

/// Co se má zrevidovat.
enum ReviewTarget: Identifiable, Hashable {
    case branch(Branch)
    case commit(Commit)

    var id: String {
        switch self {
        case let .branch(branch): "branch:" + branch.id
        case let .commit(commit): "commit:" + commit.id
        }
    }
}

/// Hodnota pro otevření okna s review.
struct ReviewWindowValue: Codable, Hashable {
    var projectID: UUID
    var reviewID: UUID
}

struct SSHUnlockRequest: Identifiable {
    let id = UUID()
    var message: String
    var suggestedKeyPath: String?
    var retry: () async -> Void
}
