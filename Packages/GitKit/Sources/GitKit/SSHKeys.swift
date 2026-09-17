import Foundation

public struct SSHKey: Identifiable, Hashable, Sendable {
    public var privateKeyPath: String
    public var publicKey: String
    public var type: String
    public var comment: String

    public var id: String { privateKeyPath }
    public var name: String { (privateKeyPath as NSString).lastPathComponent }
    public var publicKeyPath: String { privateKeyPath + ".pub" }
}

public enum SSHKeyManager {
    public static var sshDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    }

    /// Najde páry klíčů v ~/.ssh (soubor `x` + `x.pub`).
    public static func listKeys() -> [SSHKey] {
        let dir = sshDirectory
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".pub") }.sorted().compactMap { pub in
            let privatePath = dir.appendingPathComponent(String(pub.dropLast(4))).path
            guard FileManager.default.fileExists(atPath: privatePath),
                  let content = try? String(contentsOfFile: dir.appendingPathComponent(pub).path, encoding: .utf8)
            else { return nil }
            let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 2).map(String.init)
            return SSHKey(
                privateKeyPath: privatePath,
                publicKey: content.trimmingCharacters(in: .whitespacesAndNewlines),
                type: parts.first ?? "",
                comment: parts.count > 2 ? parts[2] : ""
            )
        }
    }

    /// Obsah souboru `allowed_signers` pro ověřování SSH podpisů commitů.
    /// Každý klíč je důvěryhodný pro všechny zadané identity (e-maily).
    public static func allowedSigners(emails: [String], publicKeys: [String]) -> String {
        let principals = Array(Set(emails.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.contains(" ") })).sorted()
        guard !principals.isEmpty else { return "" }
        return publicKeys.map { key -> String in
            // Veřejný klíč: "typ base64 [komentář]" – komentář do allowed_signers nepatří.
            let parts = key.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            guard parts.count >= 2 else { return "" }
            return "\(principals.joined(separator: ",")) namespaces=\"git\" \(parts[0]) \(parts[1])"
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n") + "\n"
    }

    /// Je privátní klíč chráněný passphrase?
    public static func isEncrypted(_ privateKeyPath: String) async -> Bool {
        let result = try? await run("/usr/bin/ssh-keygen", ["-y", "-P", "", "-f", privateKeyPath])
        return result?.0 != 0
    }

    /// Přidá klíč do ssh-agenta a passphrase uloží do Klíčenky macOS,
    /// takže ho pak použije git v aplikaci i v terminálu (včetně podepisování commitů).
    public static func addToAgent(_ privateKeyPath: String, passphrase: String, askpassPath: String, storeInKeychain: Bool) async throws {
        let args = (storeInKeychain ? ["--apple-use-keychain"] : []) + [privateKeyPath]
        let env = [
            "SSH_ASKPASS": askpassPath,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": ":0",
            "MACGIT_SECRET": passphrase
        ]
        let (status, message) = try await run("/usr/bin/ssh-add", args, environment: env)
        guard status == 0 else {
            let text = message.isEmpty || message.localizedCaseInsensitiveContains("passphrase")
                ? "Nesprávná passphrase." : message
            throw GitError(arguments: ["ssh-add"], status: status, message: text)
        }
    }

    /// Načte do agenta klíče, jejichž passphrase je uložená v Klíčence macOS.
    public static func loadKeychainKeys() async {
        _ = try? await run("/usr/bin/ssh-add", ["--apple-load-keychain", "-q"])
    }

    /// Chyba gitu způsobená tím, že SSH klíč není k dispozici (zamčený passphrase, není v agentovi).
    public static func isKeyUnavailable(_ error: Error) -> Bool {
        guard let error = error as? GitError else { return false }
        let message = error.message
        return message.contains("Permission denied (publickey")
            || message.contains("incorrect passphrase")
            || message.contains("Load key")
            || (message.contains("ssh-keygen") && message.contains("sign"))
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) async throws -> (Int32, String) {
        var env = ProcessInfo.processInfo.environment
        env.merge(environment) { _, new in new }
        let finalEnv = env
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = finalEnv
                process.standardInput = FileHandle.nullDevice
                let err = Pipe()
                process.standardError = err
                process.standardOutput = err
                do {
                    try process.run()
                    let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    process.waitUntilExit()
                    continuation.resume(returning: (process.terminationStatus, message.trimmingCharacters(in: .whitespacesAndNewlines)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func generate(name: String, comment: String, passphrase: String) async throws -> SSHKey {
        let path = sshDirectory.appendingPathComponent(name).path
        guard !FileManager.default.fileExists(atPath: path) else {
            throw GitError(arguments: ["ssh-keygen"], status: 1, message: "Klíč \(name) už existuje.")
        }
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let status = try await run("/usr/bin/ssh-keygen", ["-t", "ed25519", "-C", comment, "-N", passphrase, "-f", path, "-q"])
        guard status.0 == 0, let key = listKeys().first(where: { $0.privateKeyPath == path }) else {
            throw GitError(arguments: ["ssh-keygen"], status: status.0, message: status.1)
        }
        return key
    }
}
