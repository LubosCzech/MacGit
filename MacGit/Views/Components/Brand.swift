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
