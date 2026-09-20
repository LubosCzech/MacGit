import SwiftUI

/// Styl rozhraní – volí se v Nastavení → Vzhled.
///
/// - `revision`: značkový vzhled Revision – jedno plátno s nasvícením, vlastní kostra okna,
///   putující kapsle, skleněné karty.
/// - `classic`: čistý Apple Liquid Glass podle HIG, jako by šlo o systémovou aplikaci –
///   `NavigationSplitView`, systémový postranní panel, toolbar, segmentové přepínače a
///   systémové barvy včetně akcentu z nastavení macOS.
enum InterfaceStyle: String, CaseIterable, Identifiable {
    case revision, classic

    static let storageKey = "interfaceStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .revision: "Revision"
        case .classic: "Klasický"
        }
    }

    var summary: String {
        switch self {
        case .revision: "Značkový vzhled s nasvíceným plátnem, putujícími kapslemi a skleněnými kartami."
        case .classic: "Čistý Liquid Glass podle Apple HIG – vypadá a chová se jako systémová aplikace, akcent se řídí nastavením macOS."
        }
    }

    /// Styl, podle kterého se právě kreslí. Nastavuje ho `RevisionApp` z uloženého nastavení
    /// a okna se při změně přestaví (`.id`), takže tokeny v `Theme` jsou vždy aktuální.
    @MainActor static var current: InterfaceStyle = .stored

    static var stored: InterfaceStyle {
        InterfaceStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .revision
    }
}

extension EnvironmentValues {
    @Entry var interfaceStyle: InterfaceStyle = .revision
}

// MARK: - Přizpůsobivé prvky

extension View {
    /// Tlačítko v obsahu: v Revision skleněné, v klasickém stylu systémové `.bordered`.
    func adaptiveButtonStyle(prominent: Bool = false) -> some View {
        modifier(AdaptiveButtonStyle(prominent: prominent))
    }

    /// Karta nad obsahem: v Revision skleněná, v klasickém stylu tichá systémová plocha s linkou.
    func adaptiveCard(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(AdaptiveCard(cornerRadius: cornerRadius, tint: tint))
    }
}

private struct AdaptiveButtonStyle: ViewModifier {
    let prominent: Bool
    @Environment(\.interfaceStyle) private var style

    func body(content: Content) -> some View {
        switch (style, prominent) {
        case (.revision, false): content.buttonStyle(.glass)
        case (.revision, true): content.buttonStyle(.glassProminent)
        case (.classic, false): content.buttonStyle(.bordered)
        case (.classic, true): content.buttonStyle(.borderedProminent)
        }
    }
}

private struct AdaptiveCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    @Environment(\.interfaceStyle) private var style

    func body(content: Content) -> some View {
        switch style {
        case .revision:
            content.glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
        case .classic:
            content
                .background((tint ?? .clear).opacity(0.08), in: .rect(cornerRadius: cornerRadius))
                .background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator) }
        }
    }
}

// MARK: - Skleněná lišta nad rolovaným obsahem

extension View {
    /// Lišta nad rolovaným obsahem (hlavička seznamu, diffu, inspektoru).
    ///
    /// Revision: lišta přes celou šířku jako toolbar v Mailu – bez vlastního pozadí, obsah pod ni
    /// zajíždí a systémový scroll edge effect ho rozostří; skleněné jsou jen ovládací prvky.
    /// Klasický styl: lišta stojí pevně nad obsahem jako v systémových aplikacích.
    ///
    /// Obsah musí být přímo rolovací pohled (List, ScrollView), aby dostal správné odsazení.
    func glassHeader<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(GlassHeader(bar: bar()))
    }
}

private struct GlassHeader<Bar: View>: ViewModifier {
    let bar: Bar
    @Environment(\.interfaceStyle) private var style

    func body(content: Content) -> some View {
        switch style {
        case .revision:
            // Systémový „scroll edge effect“ jako v Mailu: lišta nemá vlastní pozadí, obsah pod ni
            // zajíždí a macOS ho progresivně rozostří – bez materiálu a bez jakéhokoli tónu.
            content
                .safeAreaBar(edge: .top, spacing: 0) {
                    bar.frame(maxWidth: .infinity)
                }
                // Obě hrany najednou: pozdější `scrollEdgeEffectStyle` pro jednu hranu by
                // nastavení druhé přebil a spodní lišta by dostala tvrdý okraj s linkou.
                .scrollEdgeEffectStyle(.soft, for: .vertical)
        case .classic:
            VStack(spacing: 0) {
                bar
                content
            }
        }
    }
}

// MARK: - Lišta pod rolovaným obsahem

extension View {
    /// Lišta pod rolovaným obsahem (commit panel). Revision: bez vlastního pozadí, obsah pod ni
    /// zajíždí a systémový scroll edge effect ho u spodního okraje rozostří – stejně jako lišta
    /// nahoře. Klasický styl: lišta stojí pevně pod obsahem.
    func glassFooter<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(GlassFooter(bar: bar()))
    }

    /// Vstupní pole na liště: v Revision skleněné, v klasickém stylu systémová plocha s linkou.
    func adaptiveFieldBackground(cornerRadius: CGFloat = 10) -> some View {
        modifier(AdaptiveFieldBackground(cornerRadius: cornerRadius))
    }
}

private struct GlassFooter<Bar: View>: ViewModifier {
    let bar: Bar
    @Environment(\.interfaceStyle) private var style
    @State private var barHeight: CGFloat = 0

    func body(content: Content) -> some View {
        switch style {
        case .revision:
            // Systémový okraj rolování na spodní hraně macOS kreslí vždy „tvrdě“ – rovnoměrné
            // rozmazání s linkou, i když je nastavený měkký styl. Místo něj obsah u spodní lišty
            // plynule vybledne do plátna: bez čáry a bez tónu, stejně jako měkký okraj nahoře.
            content
                .scrollEdgeEffectHidden(true, for: .bottom)
                .mask { fadeMask }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bar
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                }
        case .classic:
            content
                .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        }
    }

    /// Maska obsahu (její rámec končí u horní hrany lišty): plná, a posledních pár bodů
    /// nad lištou plynule do ztracena. Pod lištou pak obsah není vidět vůbec.
    @ViewBuilder
    private var fadeMask: some View {
        if barHeight > 1 {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
            }
        } else {
            Rectangle()
        }
    }
}

private struct AdaptiveFieldBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.interfaceStyle) private var style

    func body(content: Content) -> some View {
        switch style {
        case .revision:
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        case .classic:
            content
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.hairline) }
        }
    }
}
