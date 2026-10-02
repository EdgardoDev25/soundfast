import SwiftUI

/// Presentación al abrir la app desde cero: ícono, nombre y autor. Dura menos de
/// un segundo y se funde con la app. El fondo es el mismo color de la pantalla de
/// arranque de iOS, así el paso entre las dos no se nota.
struct SplashView: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 14) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                Text("SoundFast")
                    .font(.montserrat(28, .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Ink.text)
            }
            .scaleEffect(shown ? 1 : 0.94)
            .opacity(shown ? 1 : 0)

            Text("Desarrollado y diseñado por Edgardo Rocha")
                .font(.montserrat(13, .medium))
                .foregroundStyle(Ink.dim)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { shown = true }
        }
        .accessibilityElement(children: .combine)
    }
}
