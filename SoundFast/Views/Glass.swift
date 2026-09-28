import SwiftUI

// MARK: - Superficies (color sólido o vidrio según el tema)

/// Fondo de tarjetas, botones y barras.
/// - Tema Cristal en iOS 26: Liquid Glass de Apple (el de WhatsApp/Instagram);
///   en los botones, con la "gota" que reacciona al tocar.
/// - Tema Cristal en iOS anteriores: vidrio esmerilado con borde de luz.
/// - Demás temas: el color de superficie del tema.
struct Surface<S: Shape>: ViewModifier {
    let theme: AppTheme
    /// 0 = transparente … 1 = muy esmerilado.
    let blur: Double
    let shape: S
    var raised = false
    var border: Color?
    var interactive = false

    func body(content: Content) -> some View {
        if theme.glass {
            glass(content)
        } else {
            content
                .background(raised ? theme.surf2 : theme.surf, in: shape)
                .overlay {
                    if let border { shape.stroke(border, lineWidth: 1) }
                }
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(liquidGlass, in: shape)
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var liquidGlass: Glass {
        var g: Glass = blur < 0.3 ? .clear : .regular
        if blur > 0.6 { g = g.tint(Color.white.opacity(0.1 * (blur - 0.6) / 0.4)) }
        return interactive ? g.interactive() : g
    }
    #endif

    private var material: Material {
        switch blur {
        case ..<0.25: return .ultraThin
        case ..<0.5: return .thin
        case ..<0.75: return .regular
        default: return .thick
        }
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(Color.white.opacity((raised ? 0.07 : 0.035) * (0.5 + blur)), in: shape)
            .background(material, in: shape)
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), Color.white.opacity(0.05), Color.white.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
    }
}

extension View {
    @MainActor
    func surface<S: Shape>(_ prefs: Preferences, _ shape: S, raised: Bool = false,
                           border: Color? = nil, interactive: Bool = false) -> some View {
        modifier(Surface(theme: prefs.theme, blur: prefs.look.glassBlur, shape: shape,
                         raised: raised, border: border, interactive: interactive))
    }
}

// MARK: - Fondo de pantalla

/// Fondo de las pantallas. Con Cristal agrega manchas de color difusas
/// (tomadas del acento) para que el vidrio tenga algo que refractar.
struct ThemeBackground: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        ZStack {
            prefs.theme.bg
            if prefs.theme.glass {
                GlassBlobs(accent: prefs.accent)
            }
        }
        .ignoresSafeArea()
    }
}

private struct GlassBlobs: View {
    let accent: Accent

    var body: some View {
        let h = accent.c < 0.02 ? 260 : accent.h
        GeometryReader { geo in
            let w = geo.size.width, ht = geo.size.height
            ZStack {
                blob(.oklch(0.55, 0.17, h), size: w * 1.1)
                    .position(x: w * 0.1, y: ht * 0.12)
                blob(.oklch(0.5, 0.16, h + 70), size: w * 1.0)
                    .position(x: w * 0.95, y: ht * 0.48)
                blob(.oklch(0.45, 0.15, h - 60), size: w * 1.2)
                    .position(x: w * 0.2, y: ht * 0.9)
            }
            .blur(radius: 70)
            .opacity(0.75)
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

extension View {
    /// Fondo de las hojas (cola, listas, efectos).
    @MainActor
    func sheetBackground(_ prefs: Preferences) -> some View {
        Group {
            if prefs.theme.glass {
                self.presentationBackground(.ultraThinMaterial)
            } else {
                self.presentationBackground(prefs.theme.surf2)
            }
        }
    }

    /// Fondo de la barra de pestañas.
    @MainActor
    func barBackground(_ prefs: Preferences) -> some View {
        self.background {
            if prefs.theme.glass {
                Rectangle()
                    .fill(prefs.look.glassBlur < 0.4 ? Material.ultraThin : Material.regular)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                prefs.theme.tab.ignoresSafeArea(edges: .bottom)
            }
        }
    }
}
