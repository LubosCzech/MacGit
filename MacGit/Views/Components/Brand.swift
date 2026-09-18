import SwiftUI

/// Barevná paleta značky Revision (viz Design/ColorPalette.png).
enum Brand {
    /// Hlavní akce a zvýraznění – shodná s akcentovou barvou aplikace.
    static let primaryBlue = Color(hex: 0x197BFF)
    static let cobalt = Color(hex: 0x0F52E8)
    static let indigo = Color(hex: 0x3F44F4)
    /// Doplňkové zvýraznění (stavy, jemné plochy).
    static let cyanAccent = Color(hex: 0x63D7FF)
    static let midnightNavy = Color(hex: 0x0E1630)
    static let frostedSurface = Color(hex: 0xEAF3FF)
    static let mistGray = Color(hex: 0xD8E2F0)
    static let textDark = Color(hex: 0x111827)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Persisted across every window, including settings and review windows.
enum RevisionAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Podle systému"
        case .light: "Světlý"
        case .dark: "Tmavý"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct RevisionIdentity: View {
    var size: CGFloat = 40
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Přepínač se skleněnou drážkou a barevnou kapslí výběru, která mezi položkami přejíždí.
/// Kapsle leží POD popisky (ne jako glassEffect nad nimi), takže text je čitelný po celou dobu.
struct RevisionTabPicker<Value: Hashable, Label: View>: View {
    let values: [Value]
    @Binding var selection: Value
    @ViewBuilder var label: (Value) -> Label
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.interfaceStyle) private var style

    var body: some View {
        switch style {
        case .revision: branded
        case .classic:
            Picker("", selection: $selection) {
                ForEach(values, id: \.self) { value in label(value).tag(value) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var branded: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
                        selection = value
                    }
                } label: {
                    tabLabel(value)
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: value, in: pill, isSource: true)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .background {
            Capsule()
                .fill(Theme.accentGradient)
                .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1) }
                .shadow(color: Theme.accentFill.opacity(0.35), radius: 8, y: 3)
                .matchedGeometryEffect(id: selection, in: pill, isSource: false)
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    private func tabLabel(_ value: Value) -> some View {
        label(value)
            .font(.system(size: 12, weight: selection == value ? .semibold : .medium))
            .foregroundStyle(selection == value ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.textSecondary))
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
    }
}
