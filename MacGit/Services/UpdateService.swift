import Combine
import Foundation
import Sparkle

/// Aktualizace přes Sparkle.
///
/// Adresu feedu a veřejný klíč vkládá do Info.plist jen `build.sh` pro vydání; vývojové buildy
/// z Xcode je nemají, takže se tu ukážou jako nenakonfigurované a nikdy se samy neaktualizují.
/// Kontroly jsou volitelné (výchozí vypnuto) a stažení i instalaci vždy potvrzuje uživatel.
@Observable
final class UpdateService {
    private(set) var canCheck = false
    private(set) var automaticChecks = false
    private(set) var lastCheck: Date?
    private(set) var configurationMessage: String?

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else {
            configurationMessage = "Tento build nemá nastavené aktualizace – vývojové buildy se neaktualizují. Vydané verze je mají zapnuté."
            return
        }
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticChecks = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] in self?.lastCheck = $0 }
            .store(in: &subscriptions)
        do {
            try updater.start()
        } catch {
            canCheck = false
            configurationMessage = "Aktualizace nelze spustit: \(error.localizedDescription)"
        }
    }

    var isConfigured: Bool { configurationMessage == nil }

    func check() {
        guard canCheck, isConfigured else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isConfigured else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
