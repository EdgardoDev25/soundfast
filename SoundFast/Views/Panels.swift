import SwiftUI

// MARK: - Cerrar un panel arrastrando

/// Lo que hace el encabezado de un panel al arrastrarlo o tocar "cerrar".
struct PanelDismiss {
    var changed: (CGFloat) -> Void = { _ in }
    var ended: (_ distance: CGFloat, _ velocity: CGFloat) -> Void = { _, _ in }
    var close: () -> Void = {}
}

private struct PanelDismissKey: EnvironmentKey {
    static let defaultValue = PanelDismiss()
}

extension EnvironmentValues {
    var panelDismiss: PanelDismiss {
        get { self[PanelDismissKey.self] }
        set { self[PanelDismissKey.self] = newValue }
    }
}

/// Panel que sube desde abajo (Sonido, Ajustes). Se cierra con el botón o
/// arrastrando el encabezado hacia abajo; el minirreproductor queda visible encima.
struct SlidingPanel<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var drag: CGFloat = 0

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Solo se recorta el fondo, con esquinas redondeadas simples. Antes
            // el panel entero iba con máscara y una sombra grande: el iPhone tenía
            // que dibujarlo aparte en cada cuadro del deslizamiento (el tirón al cerrar).
            .background {
                ThemeBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .ignoresSafeArea()
            }
            .offset(y: drag)
            .environment(\.panelDismiss, PanelDismiss(
                changed: { drag = $0 },
                ended: { distance, velocity in
                    if distance > 130 || (velocity > 700 && distance > 30) {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { drag = 0 }
                    }
                },
                close: onClose
            ))
    }
}

/// Agarradera + cerrar + título + acción opcional. Arrastrarlo hacia abajo cierra el panel.
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.panelDismiss) private var panel

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 40, height: 5)
                .padding(.top, 6)
            HStack {
                Button { panel.close() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Ink.text)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Cerrar")
                Spacer()
                Text(title).font(.montserrat(17, .bold)).foregroundStyle(Ink.text)
                Spacer()
                trailing()
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { v in panel.changed(max(0, v.translation.height)) }
                .onEnded { v in panel.ended(v.translation.height, v.velocity.height) }
        )
    }
}
