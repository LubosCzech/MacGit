import AppKit
import Foundation

/// Kdy se zeptat na podporu – oddělené od ukládání i rozhraní, aby šlo ověřit bez kalendáře.
enum SupportSchedule {
    /// Poprvé po týdnu, pak jednou za měsíc.
    static let firstDelay = DateComponents(day: 7)
    static let repeatDelay = DateComponents(month: 1)

    static func dueDate(firstLaunch: Date, lastPrompt: Date?, calendar: Calendar = .current) -> Date {
        guard let lastPrompt else {
            return calendar.date(byAdding: firstDelay, to: firstLaunch) ?? firstLaunch
        }
        return calendar.date(byAdding: repeatDelay, to: lastPrompt) ?? lastPrompt
    }

    static func shouldPrompt(now: Date, firstLaunch: Date, lastPrompt: Date?,
                             hasSupported: Bool, calendar: Calendar = .current) -> Bool {
        guard !hasSupported else { return false }
        // Posunuté hodiny nesmějí vést k opakovanému dotazu: čas před posledním
        // dotazem znamená počkat, ne ptát se znovu.
        if let lastPrompt, now < lastPrompt { return false }
        if now < firstLaunch { return false }
        return now >= dueDate(firstLaunch: firstLaunch, lastPrompt: lastPrompt, calendar: calendar)
    }
}

/// Drobná prosba o podporu, ne prodejní trychtýř.
///
/// Jestli někdo opravdu přispěl, se aplikace nedozví – Buy Me a Coffee jí nic nehlásí.
/// „Podpořeno“ je proto jen tvrzení uživatele a jakmile ho jednou vysloví, Revision se
/// už nikdy neozve.
@Observable
final class SupportService {
    enum Key {
        static let firstLaunch = "supportFirstLaunchDate"
        static let lastPrompt = "supportLastPromptDate"
        static let supported = "supportAcknowledged"
    }

    /// Nastavitelné: zavření listu klávesou Escape má stejný význam jako „teď ne“.
    var isPrompting = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(now(), forKey: Key.firstLaunch)
        }
    }

    var hasSupported: Bool { defaults.bool(forKey: Key.supported) }
    private var firstLaunch: Date { defaults.object(forKey: Key.firstLaunch) as? Date ?? now() }
    private var lastPrompt: Date? { defaults.object(forKey: Key.lastPrompt) as? Date }

    /// Volá se po startu, až když má uživatel okno před sebou.
    func promptIfDue() {
        guard SupportSchedule.shouldPrompt(now: now(), firstLaunch: firstLaunch,
                                           lastPrompt: lastPrompt, hasSupported: hasSupported)
        else { return }
        defaults.set(now(), forKey: Key.lastPrompt)
        isPrompting = true
    }

    /// Otevření stránky bereme jako vyřízené – ptát se dál někoho, kdo na ni odešel,
    /// by bylo dotěrné, a ověřit platbu stejně nejde.
    func support() {
        NSWorkspace.shared.open(SupportLink.page)
        acknowledge()
    }

    func acknowledge() {
        defaults.set(true, forKey: Key.supported)
        isPrompting = false
    }

    func postpone() { isPrompting = false }
}

enum SupportLink {
    static let page = URL(string: "https://buymeacoffee.com/svtkdev")!
    static let studio = URL(string: "https://svtk.dev")!
}
