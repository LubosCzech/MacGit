import Foundation
import SwiftUI
import GitKit

enum SpaceColor: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray
    var id: String { rawValue }

    var color: Color {
        switch self {
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
        Space(name: "", symbol: suggestedSymbols.randomElement()!, color: SpaceColor.allCases.randomElement()!)
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
}

struct SSHUnlockRequest: Identifiable {
    let id = UUID()
    var message: String
    var suggestedKeyPath: String?
    var retry: () async -> Void
}
