import SwiftUI

/// Tipografías del prototipo, incluidas en la app (Resources/Fonts).
extension Font {
    enum BrandWeight: String {
        case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold", heavy = "ExtraBold"
    }

    enum MonoWeight: String {
        case regular = "Regular", medium = "Medium", bold = "Bold"
    }

    /// Montserrat: la fuente principal.
    static func montserrat(_ size: CGFloat, _ weight: BrandWeight = .regular) -> Font {
        .custom("Montserrat-\(weight.rawValue)", fixedSize: size)
    }

    static func mono(_ size: CGFloat, _ weight: MonoWeight = .regular) -> Font {
        .custom("JetBrainsMono-\(weight.rawValue)", fixedSize: size)
    }
}

extension Text {
    /// Etiqueta en mayúsculas con espaciado ancho (ej. "BIBLIOTECA").
    func eyebrow(_ size: CGFloat = 11, color: Color) -> some View {
        self.font(.mono(size))
            .tracking(size * 0.14)
            .foregroundStyle(color)
    }
}
