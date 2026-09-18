import SwiftUI
import AppKit

/// Kostra hlavního okna podle návrhu: jedno plátno pro celé okno, nahoře jeden toolbar přes
/// celou šířku a pod ním sloupce panel │ seznam │ detail │ inspektor oddělené jen vlasovými linkami.
///
/// Záměrně bez `NavigationSplitView`: ten dává každému sloupci vlastní pozadí a toolbar
/// rozseká podle sloupců, takže okno nikdy nepůsobí jako jeden celek.
struct WindowShell: View {
    let model: RepositoryModel?

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sidebarShown") private var sidebarShown = true
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 236
    @AppStorage("contentWidth") private var contentWidth: Double = 324
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 288

    /// Detail musí zůstat použitelný; na úzkém okně se inspektor schová sám.
    private static let detailMinWidth: Double = 360

    var body: some View {
        @Bindable var store = store

        GeometryReader { proxy in
            let fixed = (sidebarShown ? sidebarWidth : 0) + contentWidth
            let showsInspector = model != nil && store.inspectorShown
                && proxy.size.width - fixed - inspectorWidth >= Self.detailMinWidth

            VStack(spacing: 0) {
            // Linka pod toolbarem je skutečný 1pt pohled, ne overlay: sloupce pak nesousedí
            // s oblastí toolbaru a seznamy nedostávají jeho odsazení navíc (prázdná díra nad obsahem).
            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 0) {
                if sidebarShown {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    ColumnDivider(width: $sidebarWidth, range: 200...320)
                }

                if let model {
                    RepositoryContentColumn(model: model)
                        .frame(width: contentWidth)
                    ColumnDivider(width: $contentWidth, range: 280...460)
                    RepositoryDetailColumn(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showsInspector {
                        ColumnDivider(width: $inspectorWidth, range: 260...380, growsLeading: true)
                        InspectorView(model: model)
                            .frame(width: inspectorWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                } else {
                    WelcomeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: sidebarShown)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: showsInspector)
        }
        .background { RevisionSurface().ignoresSafeArea() }
        .toolbar {
            WindowToolbar(model: model, sidebarShown: $sidebarShown, inspectorShown: $store.inspectorShown)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// Toolbar přes celou šířku okna – stejné pořadí jako v návrhu:
/// panel │ větev │ fetch · pull · push ……… hledání │ inspektor │ účet.
/// Jak zobrazit seznam nebo diff se nastavuje u nich samotných, ne tady.
struct WindowToolbar: ToolbarContent {
    let model: RepositoryModel?
    @Binding var sidebarShown: Bool
    @Binding var inspectorShown: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                sidebarShown.toggle()
            } label: {
                Label(sidebarShown ? "Skrýt postranní panel" : "Zobrazit postranní panel", systemImage: "sidebar.leading")
            }
            .help(sidebarShown ? "Skrýt postranní panel (⌃⌘S)" : "Zobrazit postranní panel (⌃⌘S)")
        }

        if let model {
            ToolbarSpacer(.fixed, placement: .navigation)

            ToolbarItem(placement: .navigation) {
                BranchMenu(model: model)
            }

            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await model.fetch() }
                } label: {
                    Label("Fetch", systemImage: "arrow.trianglehead.2.clockwise")
                        .symbolEffect(.rotate, isActive: model.busyTitle?.hasPrefix("Fetch") == true)
                }
                .help("Fetch ze všech remotů (⌥⌘F)")

                Button {
                    Task { await model.pull() }
                } label: {
                    Label("Pull", systemImage: "arrow.down")
                        .symbolEffect(.bounce, value: model.status.branch.behind)
                }
                .badge(model.status.branch.behind)
                .help("Pull (⌘T)")

                Button {
                    Task { await model.push() }
                } label: {
                    Label("Push", systemImage: "arrow.up")
                        .symbolEffect(.bounce, value: model.status.branch.ahead)
                }
                .badge(model.status.branch.ahead)
                .help(model.status.branch.upstream == nil ? "Push a nastavit upstream (⇧⌘K)" : "Push do \(model.status.branch.upstream ?? "") (⇧⌘K)")
            }

            // Pravá skupina patří k pravému okraji okna, ne hned za synchronizaci.
            ToolbarSpacer(.flexible)

            ToolbarItem(placement: .primaryAction) {
                SearchOrb(model: model)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorShown.toggle()
                } label: {
                    Label("Inspektor", systemImage: "sidebar.trailing")
                }
                .help(inspectorShown ? "Skrýt inspektor (⌥⌘I)" : "Zobrazit inspektor (⌥⌘I)")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            AccountMenu()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Vlasová linka mezi sloupci; tažením mění šířku sousedního sloupce.
struct ColumnDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// U inspektoru (vpravo) se sloupec zvětšuje tažením doleva.
    var growsLeading = false

    @State private var startWidth: Double?
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != isHovering else { return }
                        isHovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? width
                                startWidth = start
                                let delta = growsLeading ? -value.translation.width : value.translation.width
                                width = min(max(start + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            }
            .accessibilityHidden(true)
    }
}

/// Účet u hostingu: iniciály, stav přihlášení a rychlá cesta do nastavení.
struct AccountMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            if store.accounts.isEmpty {
                Text("Žádný účet")
            } else {
                ForEach(store.accounts) { account in
                    Label(account.title, systemImage: account.kind.symbol)
                }
            }
            Divider()
            Button("Nastavení účtů…") { openSettings() }
        } label: {
            Group {
                if let account = store.accounts.first {
                    Text(initials(account))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentGradient, in: .circle)
                        .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(store.accounts.first?.title ?? "Účet")
        .help(store.accounts.first?.title ?? "Přidat účet GitHub nebo GitLab")
    }

    private func initials(_ account: HostingAccount) -> String {
        let source = account.displayName ?? account.login
        let parts = source.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." })
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? String(source.prefix(2)).uppercased() : String(letters).uppercased()
    }
}
