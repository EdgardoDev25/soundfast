import SwiftUI

/// Colores del prototipo (tema "Grafito", acento "Ámbar").
enum Theme {
    static let bg = Color(hex: 0x0B0B0D)
    static let surf = Color(hex: 0x16161A)
    static let surf2 = Color(hex: 0x1C1C21)
    static let border = Color(hex: 0x2A2A30)
    static let text = Color(hex: 0xF2F1EE)
    static let textDim = Color(hex: 0x8D8C93)
    static let textFaint = Color(hex: 0x5F5E66)
    /// oklch(0.76 0.16 55)
    static let accent = Color(hex: 0xFD923E)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
