import SwiftUI

// MARK: - Superficies (color sólido o vidrio según el tema)

/// Fondo de tarjetas, botones y barras. Con el tema Cristal es vidrio esmerilado
/// con un borde de luz; con los demás, el color de superficie del tema.
struct Surface<S: Shape>: ViewModifier {
    let theme: AppTheme
    let shape: S
    var raised = false
    var border: Color?

    func body(content: Content) -> some View {
        if theme.glass {
            content
                .background(Color.white.opacity(raised ? 0.07 : 0.035), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.32), Color.white.opacity(0.05), Color.white.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        } else {
            content
                .background(raised ? theme.surf2 : theme.surf, in: shape)
                .overlay {
                    if let border { shape.stroke(border, lineWidth: 1) }
                }
        }
    }
}

extension View {
    @MainActor
    func surface<S: Shape>(_ prefs: Preferences, _ shape: S, raised: Bool = false, border: Color? = nil) -> some View {
        modifier(Surface(theme: prefs.theme, shape: shape, raised: raised, border: border))
    }
}

// MARK: - Fondo de pantalla

/// Fondo de las pantallas. Con Cristal agrega manchas de color difusas
/// (tomadas del acento) para que el vidrio tenga algo que "esmerilar".
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
}
