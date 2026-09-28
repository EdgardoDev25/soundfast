import SwiftUI

// MARK: - Color OKLCH (el prototipo define todo el color así)

extension Color {
    /// Convierte OKLCH a sRGB. `l` 0…1, `c` croma, `h` grados.
    static func oklch(_ l: Double, _ c: Double, _ h: Double, _ alpha: Double = 1) -> Color {
        let rgb = OKLCH.toSRGB(l: l, c: c, h: h)
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: alpha)
    }

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

enum OKLCH {
    static func toSRGB(l L: Double, c C: Double, h: Double) -> (r: Double, g: Double, b: Double) {
        let a = C * cos(h * .pi / 180)
        let b = C * sin(h * .pi / 180)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func gamma(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return (gamma(r), gamma(g), gamma(bl))
    }
}

// MARK: - Acentos y temas (idénticos al prototipo)

struct Accent: Identifiable, Equatable {
    let id: String
    let name: String
    let l: Double, c: Double, h: Double

    var color: Color { .oklch(l, c, h) }
    /// Variante un poco más clara (accL2 en el prototipo).
    var light: Color { .oklch(min(0.96, l + 0.05), c, h) }
    func alpha(_ a: Double) -> Color { .oklch(l, c, h, a) }

    static let all: [Accent] = [
        Accent(id: "ambar", name: "Ámbar", l: 0.76, c: 0.16, h: 55),
        Accent(id: "coral", name: "Coral", l: 0.72, c: 0.17, h: 25),
        Accent(id: "rosa", name: "Rosa", l: 0.74, c: 0.16, h: 350),
        Accent(id: "violeta", name: "Violeta", l: 0.72, c: 0.15, h: 300),
        Accent(id: "azul", name: "Azul", l: 0.72, c: 0.14, h: 250),
        Accent(id: "turquesa", name: "Turquesa", l: 0.78, c: 0.12, h: 190),
        Accent(id: "lima", name: "Lima", l: 0.84, c: 0.17, h: 130),
        Accent(id: "blanco", name: "Blanco", l: 0.94, c: 0, h: 0),
    ]

    static func named(_ id: String) -> Accent { all.first { $0.id == id } ?? all[0] }
}

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let bg: Color, surf: Color, surf2: Color, tab: Color

    static let all: [AppTheme] = [
        AppTheme(id: "oled", name: "OLED", bg: Color(hex: 0x000000), surf: Color(hex: 0x111113), surf2: Color(hex: 0x1A1A1D), tab: Color(hex: 0x000000, alpha: 0.94)),
        AppTheme(id: "grafito", name: "Grafito", bg: Color(hex: 0x0B0B0D), surf: Color(hex: 0x16161A), surf2: Color(hex: 0x1C1C21), tab: Color(hex: 0x0E0E10, alpha: 0.94)),
        AppTheme(id: "noche", name: "Noche", bg: .oklch(0.16, 0.03, 262), surf: .oklch(0.21, 0.035, 262), surf2: .oklch(0.25, 0.035, 262), tab: .oklch(0.17, 0.03, 262, 0.94)),
        AppTheme(id: "calido", name: "Cálido", bg: .oklch(0.16, 0.012, 60), surf: .oklch(0.21, 0.016, 60), surf2: .oklch(0.25, 0.018, 60), tab: .oklch(0.17, 0.012, 60, 0.94)),
    ]

    static func named(_ id: String) -> AppTheme { all.first { $0.id == id } ?? all[1] }
}

// MARK: - Colores fijos

enum Ink {
    static let text = Color(hex: 0xF2F1EE)
    static let dim = Color(hex: 0x8D8C93)
    static let faint = Color(hex: 0x5F5E66)
    static let muted = Color(hex: 0x6F6E75)
    static let chipText = Color(hex: 0xB9B8BE)
    static let border = Color(hex: 0x2A2A30)
    static let cardBorder = Color(hex: 0x232328)
    static let chipBorder = Color(hex: 0x2E2E35)
    static let track = Color(hex: 0x26262C)
    static let switchOff = Color(hex: 0x3A3A40)
    static let onAccent = Color(hex: 0x140C05)
    static let danger = Color.oklch(0.68, 0.19, 25)
    static let dangerFill = Color.oklch(0.62, 0.2, 25)
    static let tabOff = Color(hex: 0x7A7980)
}

/// Colores de la "portada" generada a partir de un tono (cuando la canción no trae imagen).
enum ArtColors {
    static func bg(_ hue: Double) -> Color { .oklch(0.42, 0.11, hue) }
    static func fg(_ hue: Double) -> Color { .oklch(0.86, 0.09, hue) }
}
