import SwiftUI
import GitKit

/// Tlačítko Push v toolbaru: klik pošle větev do upstreamu, šipka nabídne „Push do…“
/// libovolného remotu (např. občasná verze do zrcadla na GitLabu).
struct PushToolbarButton: View {
    let model: RepositoryModel
    /// Revision animuje symbol při změně počtu commitů napřed; klasický styl ne.
    var animatesSymbol = false

    var body: some View {
        Menu {
            PushToMenuItems(model: model)
        } label: {
            if animatesSymbol {
                Label("Push", systemImage: "arrow.up")
                    .symbolEffect(.bounce, value: model.status.branch.ahead)
            } else {
                Label("Push", systemImage: "arrow.up")
            }
        } primaryAction: {
            Task { await model.push() }
        }
        .menuIndicator(model.remotes.count > 1 ? .visible : .hidden)
        .badge(model.status.branch.ahead)
        .help(helpText)
    }

    private var helpText: String {
        let main = model.status.branch.upstream == nil
            ? "Push a nastavit upstream (⇧⌘K)"
            : "Push do \(model.status.branch.upstream ?? "") (⇧⌘K)"
        return model.remotes.count > 1 ? main + " · podržením nebo šipkou Push do jiného remotu" : main
    }
}

/// Položky „Push do…“ – sdílí je toolbar i menu Repozitář.
struct PushToMenuItems: View {
    let model: RepositoryModel
    @AppStorage("pushToIncludesTags") private var includeTags = false

    var body: some View {
        let head = model.status.branch.head
        Section(head.map { "Push větve \($0) do…" } ?? "Push do…") {
            if model.remotes.isEmpty {
                Text("Repozitář nemá žádný remote")
            }
            ForEach(model.remotes) { remote in
                Button {
                    Task { await model.push(to: remote, includeTags: includeTags) }
                } label: {
                    Text(title(for: remote))
                }
                .disabled(head == nil)
            }
        }
        Toggle("Přibalit tagy", isOn: $includeTags)
            .disabled(model.remotes.isEmpty)
    }

    private func title(for remote: Remote) -> String {
        let host = HostingClient.parseRemote(remote.pushURL)?.host
        let suffix = remote.name == model.upstreamRemoteName ? " · upstream" : ""
        return [remote.name, host].compactMap { $0 }.joined(separator: " — ") + suffix
    }
}
