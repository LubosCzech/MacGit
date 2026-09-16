import Foundation

/// Způsob autentizace vůči remote repozitáři.
public enum GitCredential: Sendable, Equatable {
    /// Výchozí chování gitu – ssh-agent, ~/.ssh/config, osxkeychain helper.
    case system
    /// Konkrétní SSH klíč, volitelně s passphrase.
    case sshKey(path: String, passphrase: String?)
    /// HTTPS s uživatelem a heslem nebo tokenem.
    case https(username: String, secret: String)
}

/// Doplňkové proměnné prostředí a `-c` volby pro jedno spuštění gitu.
public struct GitContext: Sendable {
    public var environment: [String: String]
    public var configArguments: [String]

    public init(environment: [String: String] = [:], configArguments: [String] = []) {
        self.environment = environment
        self.configArguments = configArguments
    }

    public static let none = GitContext()

    /// - Parameter askpassPath: spustitelný skript, který vrací `MACGIT_USERNAME` / `MACGIT_SECRET`.
    public static func credential(_ credential: GitCredential, askpassPath: String) -> GitContext {
        switch credential {
        case .system:
            return .none

        case let .sshKey(path, passphrase):
            let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            var env = [
                "GIT_SSH_COMMAND": "ssh -i \(quoted) -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
            ]
            if let passphrase, !passphrase.isEmpty {
                env["SSH_ASKPASS"] = askpassPath
                env["SSH_ASKPASS_REQUIRE"] = "force"
                env["DISPLAY"] = ":0"
                env["MACGIT_SECRET"] = passphrase
            } else {
                env["GIT_SSH_COMMAND"]! += " -o BatchMode=yes"
            }
            return GitContext(environment: env)

        case let .https(username, secret):
            return GitContext(
                environment: [
                    "GIT_ASKPASS": askpassPath,
                    "MACGIT_USERNAME": username,
                    "MACGIT_SECRET": secret
                ],
                // Prázdný helper vynuluje osxkeychain, aby nepodstrčil staré údaje.
                configArguments: ["-c", "credential.helper="]
            )
        }
    }

    public static let askpassScript = """
    #!/bin/sh
    case "$1" in
      *"ad passphrase"*|*"try again"*) exit 1 ;;
      *[Uu]sername*) printf '%s\\n' "$MACGIT_USERNAME" ;;
      *) printf '%s\\n' "$MACGIT_SECRET" ;;
    esac
    """
}
