import CommonCrypto
import CryptoKit
import Foundation

/// Záloha konfigurace Revision v jednom souboru (`.revisionbackup`, JSON).
///
/// Obsahuje soubory z Application Support (stav, workspaces, shelf), vybrané předvolby
/// a volitelně tajné údaje z Klíčenky – ty jen zašifrované heslem uživatele.
public struct ConfigBackup: Codable, Sendable, Equatable {
    public static let fileExtension = "revisionbackup"
    public static let currentFormat = 1

    public var format: Int
    public var createdAt: Date
    public var appVersion: String
    /// Relativní cesta v Application Support/Revision → obsah souboru.
    public var files: [String: Data]
    public var preferences: [String: PreferenceValue]
    /// Hesla a tokeny – `nil`, když se záloha dělala bez nich.
    public var secrets: EncryptedSecrets?

    public init(createdAt: Date = .now, appVersion: String, files: [String: Data],
                preferences: [String: PreferenceValue], secrets: EncryptedSecrets? = nil) {
        self.format = Self.currentFormat
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.files = files
        self.preferences = preferences
        self.secrets = secrets
    }

    public enum PreferenceValue: Codable, Sendable, Equatable {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case date(Date)

        /// Hodnota z UserDefaults; nepodporované typy se do zálohy nedostanou.
        public init?(_ value: Any) {
            switch value {
            case let date as Date: self = .date(date)
            case let string as String: self = .string(string)
            case let number as NSNumber:
                // NSNumber z UserDefaults neříká, jestli jde o Bool – CFBoolean ano.
                if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
                else if CFNumberIsFloatType(number) { self = .double(number.doubleValue) }
                else { self = .int(number.intValue) }
            default: return nil
            }
        }

        public var value: Any {
            switch self {
            case let .bool(value): value
            case let .int(value): value
            case let .double(value): value
            case let .string(value): value
            case let .date(value): value
            }
        }
    }

    // MARK: Soubor

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ConfigBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: ConfigBackup
        do {
            backup = try decoder.decode(ConfigBackup.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        guard backup.format <= currentFormat else { throw BackupError.newerFormat(backup.format) }
        for path in backup.files.keys where !isAllowedPath(path) {
            throw BackupError.unsafePath(path)
        }
        return backup
    }

    /// Obnovit se smí jen to, co Revision sám ukládá – nikdy cesta mimo jeho složku.
    /// Brání tomu, aby podvržený soubor zálohy zapsal třeba do ~/.ssh.
    public static func isAllowedPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return false }
        switch parts.first {
        case "state.json": return parts.count == 1
        case "workspaces": return parts.count == 2 && parts[1].hasSuffix(".json")
        case "shelves": return parts.count == 3
        default: return false
        }
    }

    /// Klíče Klíčenky, které záloha smí obnovit (tokeny účtů, hesla projektů, passphrase SSH klíčů).
    public static func isAllowedSecretKey(_ key: String) -> Bool {
        let uuid = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        let patterns = ["^account\\.\(uuid)$", "^project\\.\(uuid)\\.password$", "^ssh\\./.+$"]
        return patterns.contains { key.range(of: $0, options: .regularExpression) != nil }
    }
}

public enum BackupError: LocalizedError, Equatable {
    case notABackup
    case newerFormat(Int)
    case unsafePath(String)
    case wrongPassword
    case emptyPassword

    public var errorDescription: String? {
        switch self {
        case .notABackup: "Soubor není záloha Revision, nebo je poškozený."
        case let .newerFormat(format): "Zálohu vytvořila novější verze Revision (formát \(format)). Aktualizuj aplikaci a zkus to znovu."
        case let .unsafePath(path): "Záloha obsahuje nepovolenou cestu „\(path)“ a nebude obnovena."
        case .wrongPassword: "Heslo k zašifrovaným údajům nesouhlasí, nebo je záloha poškozená."
        case .emptyPassword: "Zadej heslo pro zašifrování hesel a tokenů."
        }
    }
}

/// Tajné údaje zašifrované heslem: PBKDF2-SHA256 → klíč pro AES-256-GCM.
public struct EncryptedSecrets: Codable, Sendable, Equatable {
    public static let defaultIterations = 600_000

    public var salt: Data
    public var iterations: Int
    /// AES-GCM „combined“: nonce + šifrovaný text + tag.
    public var sealed: Data

    public static func seal(_ secrets: [String: String], password: String, iterations: Int = defaultIterations) throws -> EncryptedSecrets {
        guard !password.isEmpty else { throw BackupError.emptyPassword }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw BackupError.wrongPassword }
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let plain = try JSONEncoder().encode(secrets)
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw BackupError.wrongPassword }
        return EncryptedSecrets(salt: salt, iterations: iterations, sealed: combined)
    }

    public func open(password: String) throws -> [String: String] {
        let key = try Self.deriveKey(password: password, salt: salt, iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plain = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode([String: String].self, from: plain)
        } catch {
            throw BackupError.wrongPassword
        }
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard iterations >= 100_000, iterations <= 10_000_000 else { throw BackupError.wrongPassword }
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)
        let result = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard result == kCCSuccess else { throw BackupError.wrongPassword }
        return SymmetricKey(data: derived)
    }
}
