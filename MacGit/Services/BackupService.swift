import AppKit
import Foundation
import GitKit

/// Zálohy konfigurace: ruční export/obnovení a automatická denní záloha.
///
/// Co v záloze je: prostory, projekty, účty (state.json), workspaces (changelisty, rozepsané
/// zprávy, historie review), shelf a vybrané předvolby. Hesla a tokeny jen na vyžádání
/// a zašifrované heslem. SSH klíče samotné (~/.ssh) záloha neobsahuje.
@Observable
final class BackupService {
    /// Předvolby, které patří k „mé konfiguraci“. Šířky oken a podobné drobnosti ano,
    /// cesta ke složce záloh ne – ta je vázaná na konkrétní Mac.
    static let preferenceKeys = [
        "revisionAppearance", InterfaceStyle.storageKey, "changesAsTree", "diffLayoutMode",
        "sidebarShown", "sidebarWidth", "contentWidth", "inspectorWidth", "inspectorShown",
        "pushToIncludesTags", "review.agent", "review.model",
        SupportService.Key.firstLaunch, SupportService.Key.lastPrompt, SupportService.Key.supported
    ]
    static let keepAutomaticBackups = 14
    private static let automaticPrefix = "Revision-auto-"

    enum Key {
        static let automatic = "backup.automatic"
        static let folder = "backup.folder"
        static let lastAutomatic = "backup.lastAutomatic"
    }

    struct Summary {
        var url: URL
        var backup: ConfigBackup
        var spaces: Int
        var projects: Int
        var accounts: Int
        var shelves: Int
        var hasSecrets: Bool { backup.secrets != nil }
    }

    private(set) var lastAutomaticBackup: Date?
    private(set) var lastError: String?

    var automaticBackups: Bool {
        didSet { defaults.set(automaticBackups, forKey: Key.automatic) }
    }

    var folder: URL {
        didSet { defaults.set(folder.path, forKey: Key.folder) }
    }

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let defaults = UserDefaults.standard

    init(store: AppStore) {
        self.store = store
        automaticBackups = defaults.object(forKey: Key.automatic) as? Bool ?? true
        folder = defaults.string(forKey: Key.folder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? store.supportURL.appendingPathComponent("Backups", isDirectory: true)
        lastAutomaticBackup = defaults.object(forKey: Key.lastAutomatic) as? Date
    }

    var defaultFolder: URL { store.supportURL.appendingPathComponent("Backups", isDirectory: true) }

    // MARK: Vytvoření

    func makeBackup(includeSecrets: Bool, password: String?) throws -> ConfigBackup {
        store.flushPendingSaves()
        let secrets: EncryptedSecrets?
        if includeSecrets {
            guard let password, !password.isEmpty else { throw BackupError.emptyPassword }
            secrets = try EncryptedSecrets.seal(collectSecrets(), password: password)
        } else {
            secrets = nil
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return ConfigBackup(appVersion: version, files: try collectFiles(), preferences: collectPreferences(), secrets: secrets)
    }

    func export(to url: URL, includeSecrets: Bool, password: String?) throws {
        let data = try makeBackup(includeSecrets: includeSecrets, password: password).encoded()
        try write(data, to: url)
    }

    /// Denní záloha bez hesel; nejstarší automatické zálohy nad limit se smažou.
    func runAutomaticBackupIfDue(now: Date = .now) {
        guard automaticBackups else { return }
        if let last = lastAutomaticBackup, now.timeIntervalSince(last) < 23 * 3600 { return }
        do {
            let url = folder.appendingPathComponent("\(Self.automaticPrefix)\(Self.stamp(now)).\(ConfigBackup.fileExtension)")
            try export(to: url, includeSecrets: false, password: nil)
            lastAutomaticBackup = now
            defaults.set(now, forKey: Key.lastAutomatic)
            lastError = nil
            pruneAutomaticBackups()
        } catch {
            lastError = "Automatická záloha se nepodařila: \(error.localizedDescription)"
        }
    }

    func backupNow() throws -> URL {
        let url = folder.appendingPathComponent("Revision-\(Self.stamp(.now)).\(ConfigBackup.fileExtension)")
        try export(to: url, includeSecrets: false, password: nil)
        lastError = nil
        return url
    }

    // MARK: Obnovení

    func summary(of url: URL) throws -> Summary {
        let backup = try ConfigBackup.decode(try Data(contentsOf: url))
        func count(_ key: String) -> Int {
            guard let data = backup.files["state.json"],
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = object[key] as? [Any] else { return 0 }
            return items.count
        }
        let shelves = backup.files.keys.filter { $0.hasPrefix("shelves/") }.count
        return Summary(url: url, backup: backup, spaces: count("spaces"), projects: count("projects"),
                       accounts: count("accounts"), shelves: shelves)
    }

    /// Nahradí současnou konfiguraci zálohou a restartuje aplikaci. Předtím uloží zálohu
    /// současného stavu, aby šlo obnovení vrátit.
    func restore(_ backup: ConfigBackup, password: String?) throws {
        // Hesla rozšifrujeme jako první: se špatným heslem se nesmí přepsat nic.
        var secrets: [String: String] = [:]
        if let sealed = backup.secrets, let password, !password.isEmpty {
            secrets = try sealed.open(password: password)
        }

        let safety = folder.appendingPathComponent("Revision-pred-obnovou-\(Self.stamp(.now)).\(ConfigBackup.fileExtension)")
        try export(to: safety, includeSecrets: false, password: nil)

        store.suspendPersistence()
        let fm = FileManager.default
        let base = store.supportURL
        for directory in ["workspaces", "shelves"] {
            let url = base.appendingPathComponent(directory, isDirectory: true)
            try? fm.removeItem(at: url)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        for (path, data) in backup.files where ConfigBackup.isAllowedPath(path) {
            let url = base.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        for (key, value) in backup.preferences where Self.preferenceKeys.contains(key) {
            defaults.set(value.value, forKey: key)
        }
        for (key, value) in secrets where ConfigBackup.isAllowedSecretKey(key) {
            Keychain.set(value, for: key)
        }
        Self.relaunch()
    }

    // MARK: Sběr dat

    private func collectFiles() throws -> [String: Data] {
        let base = store.supportURL
        var files: [String: Data] = [:]
        if let state = try? Data(contentsOf: base.appendingPathComponent("state.json")) {
            files["state.json"] = state
        }
        let fm = FileManager.default
        for directory in ["workspaces", "shelves"] {
            let root = base.appendingPathComponent(directory, isDirectory: true)
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                let relative = directory + "/" + url.path.dropFirst(root.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard ConfigBackup.isAllowedPath(relative) else { continue }
                files[relative] = try Data(contentsOf: url)
            }
        }
        return files
    }

    private func collectPreferences() -> [String: ConfigBackup.PreferenceValue] {
        var result: [String: ConfigBackup.PreferenceValue] = [:]
        for key in Self.preferenceKeys {
            if let object = defaults.object(forKey: key), let value = ConfigBackup.PreferenceValue(object) {
                result[key] = value
            }
        }
        return result
    }

    private func collectSecrets() -> [String: String] {
        var keys = Set(store.accounts.map(\.keychainKey))
        for project in store.projects {
            switch project.auth {
            case .password: keys.insert(Keychain.projectPasswordKey(project.id))
            case let .sshKey(path): keys.insert(Keychain.sshPassphraseKey(path))
            default: break
            }
        }
        // Passphrase klíčů uložené v Nastavení → SSH klíče.
        if let names = try? FileManager.default.contentsOfDirectory(atPath: SSHKeyManager.sshDirectory.path) {
            for name in names where !name.hasSuffix(".pub") {
                keys.insert(Keychain.sshPassphraseKey(SSHKeyManager.sshDirectory.appendingPathComponent(name).path))
            }
        }
        var secrets: [String: String] = [:]
        for key in keys {
            if let value = Keychain.get(key) { secrets[key] = value }
        }
        return secrets
    }

    // MARK: Pomocné

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        // Záloha obsahuje cesty k projektům a případně šifrovaná hesla – jen pro vlastníka.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func pruneAutomaticBackups() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        let automatic = names.filter { $0.hasPrefix(Self.automaticPrefix) && $0.hasSuffix("." + ConfigBackup.fileExtension) }.sorted()
        for name in automatic.dropLast(Self.keepAutomaticBackups) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// Restart po obnovení: nejjistější způsob, jak načíst obnovený stav do všech oken.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
