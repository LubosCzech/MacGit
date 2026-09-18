import SwiftUI
import AppKit

/// Sémantické barevné tokeny.
///
/// Ve stylu Revision jde o značkovou paletu, která se sama překlápí mezi světlým a tmavým
/// vzhledem (dynamická `NSColor`). V klasickém stylu vrací systémové sémantické barvy –
/// akcent se pak řídí nastavením macOS, stejně jako u systémových aplikací.
/// Syrová paleta značky je v `Brand`.
enum Theme {
    private static var classic: Bool { InterfaceStyle.current == .classic }

    // MARK: Plochy

    /// Pozadí okna.
    static var canvas: Color { classic ? Color(nsColor: .windowBackgroundColor) : Brandish.canvas }
    /// Karty, hlavičky, commit panel.
    static var surface: Color { classic ? Color(nsColor: .controlBackgroundColor) : Brandish.surface }
    /// Vybraný řádek, vstupní pole.
    static var surfaceRaised: Color { classic ? Color(nsColor: .textBackgroundColor) : Brandish.surfaceRaised }
    /// Jemné plochy uvnitř obsahu (hlavičky hunků, patičky).
    static var surfaceSunken: Color { classic ? Color(nsColor: .labelColor).opacity(0.05) : Brandish.surfaceSunken }

    // MARK: Obrysy a text

    /// Obrysy 0,5 pt.
    static var hairline: Color { classic ? Color(nsColor: .separatorColor) : Brandish.hairline }
    /// Obrys tam, kde je potřeba plocha oddělit výrazněji.
    static var hairlineStrong: Color { classic ? Color(nsColor: .gridColor) : Brandish.hairlineStrong }
    static var textPrimary: Color { classic ? Color(nsColor: .labelColor) : Brandish.textPrimary }
    static var textSecondary: Color { classic ? Color(nsColor: .secondaryLabelColor) : Brandish.textSecondary }

    // MARK: Akcent

    /// Akce, výběr, akcent aplikace. V tmavém režimu Revision zesvětlený kvůli kontrastu proti navy.
    static var accent: Color { classic ? Color(nsColor: .controlAccentColor) : Brandish.accent }
    /// Gradienty a AI prvky.
    static var accentDeep: Color { classic ? Color(nsColor: .controlAccentColor) : Brandish.accentDeep }
    /// Akcent jako text nebo ikona na plátně – tmavší, aby držel kontrast 4,5 : 1.
    static var accentText: Color { classic ? Color(nsColor: .linkColor) : Brandish.accentText }
    /// Akcent jako výplň pod bílým textem (tlačítka, odznaky).
    static var accentFill: Color { classic ? Color(nsColor: .controlAccentColor) : Brandish.accentFill }
    /// Zvýraznění a záře plátna.
    static var highlight: Color { classic ? Color(nsColor: .controlAccentColor) : Brandish.highlight }
    /// Tónování vybraného řádku.
    static var selectionTint: Color { classic ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.25) : Brandish.selectionTint }

    /// Gradient hlavních akcí; v klasickém stylu jednobarevný, systémové aplikace gradienty nepoužívají.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: classic ? [accentFill, accentFill] : [accentFill, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Diff

    static var diffAddBackground: Color { classic ? Color(nsColor: .systemGreen).opacity(0.14) : Brandish.diffAddBackground }
    static var diffAddText: Color { classic ? Color(nsColor: .labelColor) : Brandish.diffAddText }
    static var diffRemoveBackground: Color { classic ? Color(nsColor: .systemRed).opacity(0.12) : Brandish.diffRemoveBackground }
    static var diffRemoveText: Color { classic ? Color(nsColor: .labelColor) : Brandish.diffRemoveText }
    /// Zvýraznění změněného slova uvnitř řádku.
    static var diffWordAdd: Color { classic ? Color(nsColor: .systemGreen).opacity(0.32) : Brandish.diffWordAdd }
    static var diffWordRemove: Color { classic ? Color(nsColor: .systemRed).opacity(0.30) : Brandish.diffWordRemove }

    // MARK: Stavy

    static var statusModified: Color { classic ? Color(nsColor: .systemOrange) : Brandish.statusModified }
    static var statusAdded: Color { classic ? Color(nsColor: .systemGreen) : Brandish.statusAdded }
    static var statusDeleted: Color { classic ? Color(nsColor: .systemRed) : Brandish.statusDeleted }
    static var statusRenamed: Color { classic ? Color(nsColor: .systemBlue) : Brandish.statusRenamed }
    static var statusUntracked: Color { classic ? Color(nsColor: .secondaryLabelColor) : Brandish.statusUntracked }

    /// Ikony nálezů v review a stavové hlášky.
    static var success: Color { classic ? Color(nsColor: .systemGreen) : Brandish.success }
    static var warning: Color { classic ? Color(nsColor: .systemOrange) : Brandish.warning }
    static var info: Color { classic ? Color(nsColor: .systemBlue) : Brandish.info }

    // MARK: Pomocné

    /// Podklad odznaku nebo štítku v barvě stavu.
    static func tintedFill(_ color: Color) -> Color { color.opacity(0.18) }
}

/// Značková paleta Revision jako dynamické barvy (světlý/tmavý vzhled se překlápí sám).
private enum Brandish {
    static let canvas = dynamic(light: 0xEAF3FF, dark: 0x0E1630)
    static let surface = dynamic(light: 0xFFFFFF, lightAlpha: 0.92, dark: 0x141C33)
    static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x182140)
    static let surfaceSunken = dynamic(light: 0x101828, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05)

    static let hairline = dynamic(light: 0xD8E2F0, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let hairlineStrong = dynamic(light: 0x101828, lightAlpha: 0.18, dark: 0xFFFFFF, darkAlpha: 0.18)
    static let textPrimary = dynamic(light: 0x111827, dark: 0xECF2FF)
    static let textSecondary = dynamic(light: 0x111827, lightAlpha: 0.62, dark: 0xECF2FF, darkAlpha: 0.60)

    static let accent = dynamic(light: 0x197BFF, dark: 0x4C9DFF)
    static let accentDeep = dynamic(light: 0x0F52E8, dark: 0x3F44F4)
    static let accentText = dynamic(light: 0x0F52E8, dark: 0x4C9DFF)
    static let accentFill = dynamic(light: 0x0F52E8, dark: 0x1A6FE0)
    static let highlight = dynamic(light: 0x63D7FF, dark: 0x63D7FF)
    static let selectionTint = dynamic(light: 0x197BFF, lightAlpha: 0.16, dark: 0x4C9DFF, darkAlpha: 0.24)

    static let diffAddBackground = dynamic(light: 0xE4F7EA, dark: 0x16351F)
    static let diffAddText = dynamic(light: 0x14612F, dark: 0x7EE2A0)
    static let diffRemoveBackground = dynamic(light: 0xFDEAEC, dark: 0x3A1A20)
    static let diffRemoveText = dynamic(light: 0x96222F, dark: 0xFF9AA5)
    static let diffWordAdd = dynamic(light: 0x9FE4B6, dark: 0x2E9E55, darkAlpha: 0.55)
    static let diffWordRemove = dynamic(light: 0xF7B9BF, dark: 0xD6404E, darkAlpha: 0.50)

    static let statusModified = dynamic(light: 0x8A5A00, dark: 0xE8B45C)
    static let statusAdded = dynamic(light: 0x17683A, dark: 0x7EE2A0)
    static let statusDeleted = dynamic(light: 0x96222F, dark: 0xFF9AA5)
    static let statusRenamed = dynamic(light: 0x17417E, dark: 0x9CC9FF)
    static let statusUntracked = dynamic(light: 0x111827, lightAlpha: 0.55, dark: 0xECF2FF, darkAlpha: 0.60)

    static let success = dynamic(light: 0x1B7F3B, dark: 0x5ED28A)
    static let warning = dynamic(light: 0x8A5A00, dark: 0xE8B45C)
    static let info = dynamic(light: 0x0F52E8, dark: 0x63D7FF)

    static func dynamic(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32, alpha: Double) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

/// Plátno aplikace – JEDNO pro celé okno. Značkové pozadí se dvěma měkkými zářemi, které se
/// velmi pomalu posouvají, takže sklo nad nimi má co lámat. Sloupce nemají vlastní pozadí,
/// oddělují je jen vlasové linky. Pohyb i průhlednost respektují zpřístupnění.
struct RevisionSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private var animates: Bool {
        !reduceMotion && !reduceTransparency && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @Environment(\.interfaceStyle) private var style

    var body: some View {
        if style == .classic {
            Color.clear
        } else {
            brandedCanvas
        }
    }

    private var brandedCanvas: some View {
        ZStack {
            Theme.canvas
            if !reduceTransparency {
                GeometryReader { proxy in
                    let size = proxy.size
                    let span = max(size.width, size.height)
                    ZStack {
                        RadialGradient(
                            colors: [Theme.accent.opacity(0.22), .clear],
                            center: UnitPoint(x: drift ? 0.10 : 0.02, y: drift ? 0.02 : 0.10),
                            startRadius: 0,
                            endRadius: span * 0.62
                        )
                        RadialGradient(
                            colors: [Theme.highlight.opacity(0.16), .clear],
                            center: UnitPoint(x: drift ? 0.92 : 1.0, y: drift ? 1.0 : 0.92),
                            startRadius: 0,
                            endRadius: span * 0.55
                        )
                    }
                }
                .blendMode(.plusLighter)
                .opacity(0.9)
            }
        }
        .task {
            guard animates, !drift else { return }
            withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
