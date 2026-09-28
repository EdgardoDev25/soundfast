import CoreText
import SwiftUI
import UIKit

/// Registra las fuentes incluidas en la app. No depende de la lista del Info.plist:
/// busca todos los .ttf del paquete y los registra al arrancar.
enum FontRegistry {
    private(set) static var montserratAvailable = false
    private(set) static var monoAvailable = false

    static func registerAll() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            // Si ya estaba registrada (por el Info.plist) devuelve error; no importa.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        montserratAvailable = UIFont(name: "Montserrat-Bold", size: 12) != nil
        monoAvailable = UIFont(name: "JetBrainsMono-Regular", size: 12) != nil
    }

    /// Para mostrar en Ajustes → Acerca de.
    static var status: String {
        montserratAvailable ? "Montserrat" : "Sistema (SF Pro)"
    }
}

/// Tipografías de la app. Si una fuente no cargara, se usa la del sistema.
extension Font {
    enum BrandWeight: String {
        case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold", heavy = "ExtraBold"

        var system: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }
    }

    enum MonoWeight: String {
        case regular = "Regular", medium = "Medium", bold = "Bold"

        var system: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .bold: return .bold
            }
        }
    }

    /// Montserrat: la fuente principal.
    static func montserrat(_ size: CGFloat, _ weight: BrandWeight = .regular) -> Font {
        FontRegistry.montserratAvailable
            ? .custom("Montserrat-\(weight.rawValue)", fixedSize: size)
            : .system(size: size, weight: weight.system)
    }

    static func mono(_ size: CGFloat, _ weight: MonoWeight = .regular) -> Font {
        FontRegistry.monoAvailable
            ? .custom("JetBrainsMono-\(weight.rawValue)", fixedSize: size)
            : .system(size: size, weight: weight.system, design: .monospaced)
    }
}

extension Text {
    /// Etiqueta con espaciado ancho (ej. "SoundFast - Edgardo Rocha").
    func eyebrow(_ size: CGFloat = 11, color: Color) -> some View {
        self.font(.mono(size))
            .tracking(size * 0.14)
            .foregroundStyle(color)
    }
}
