import Foundation

/// Přenos dat z doby, kdy se aplikace jmenovala MacGit.
enum AppMigration {
    static let legacyBundleID = "cz.svetik.MacGit"

    /// Přesune Application Support/MacGit na Application Support/Revision.
    static func moveLegacySupportDirectory(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    /// Zkopíruje nastavení (poslední volby v UI) ze starého bundle ID.
    static func copyLegacyDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromMacGit"), let legacy = UserDefaults(suiteName: legacyBundleID) else { return }
        for (key, value) in legacy.persistentDomain(forName: legacyBundleID) ?? [:] where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: "migratedFromMacGit")
    }
}
