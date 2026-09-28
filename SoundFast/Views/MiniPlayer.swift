import SwiftUI

/// Índice A–Z lateral: se arrastra el dedo para saltar de letra.
struct AZIndex: View {
    /// Letras que tienen canciones. Ya vienen calculadas de la biblioteca.
    let present: Set<String>
    @ObservedObject var az: AZState
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        let letters = Song.indexLetters
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { l in
                    Text(l)
                        .font(.mono(9.5, .bold))
                        .foregroundStyle(
                            l == az.letter ? prefs.accent.color
                                : present.contains(l) ? Color(hex: 0xA9A8AE) : Color(hex: 0x3C3C43)
                        )
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let h = max(1, geo.size.height)
                        let i = min(letters.count - 1, max(0, Int(value.location.y / h * CGFloat(letters.count))))
                        if letters[i] != az.letter {
                            Haptics.tick()
                            az.letter = letters[i]
                        }
                    }
                    .onEnded { _ in az.letter = nil }
            )
        }
        .frame(width: 20)
    }
}

/// La letra grande que aparece en el centro mientras se arrastra el índice.
struct AZBubble: View {
    @ObservedObject var az: AZState
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        if let letter = az.letter {
            Text(letter)
                .font(.montserrat(36, .heavy))
                .foregroundStyle(prefs.accent.color)
                .frame(width: 72, height: 72)
                .background(Color(hex: 0x1F1F24), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(hex: 0x33333A), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
                .padding(.trailing, 40)
                .allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// Reproductor pequeño sobre la barra inferior.
/// Tocar: abre la pantalla completa · Deslizar a los lados: adelantar/retroceder.
struct MiniPlayer: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI
    @ObservedObject var clock: PlaybackClock

    @State private var seekTarget: Double?
    @State private var dragStart: Double = 0
    @State private var axis: Axis?

    var body: some View {
        let song = player.current
        let accent = prefs.accent.color
        let duration = max(1, song?.duration ?? 1)
        let shown = seekTarget ?? clock.position
        let pct = min(1, max(0, shown / duration))

        HStack(spacing: 12) {
            ArtworkView(song: song, size: 46, radius: 10, letterSize: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(song?.title ?? "")
                    .font(.montserrat(14, .semibold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                if seekTarget != nil {
                    HStack(spacing: 6) {
                        Text(Format.time(shown)).font(.mono(13, .bold)).foregroundStyle(prefs.accent.light)
                        Text("/ " + Format.time(duration)).font(.mono(13)).foregroundStyle(Ink.dim)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(Format.time(shown)).font(.mono(12)).foregroundStyle(accent)
                        Text("·")
                        Text(song?.artist ?? "").lineLimit(1)
                    }
                    .font(.montserrat(12))
                    .foregroundStyle(Ink.dim)
                }
            }
            Spacer(minLength: 0)
            Button {
                player.togglePlay()
                Haptics.tap()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Ink.onAccent)
                    .frame(width: 46, height: 46)
                    .background(accent, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproducir")
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Ink.text)
                    .frame(width: 40, height: 46)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Siguiente")
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
        .frame(height: 70)
        .surface(prefs, RoundedRectangle(cornerRadius: 18, style: .continuous), raised: true, border: Ink.border)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(accent).frame(width: geo.size.width * pct)
                    if seekTarget != nil {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: accent.opacity(0.35), radius: 0.1)
                            .overlay(Circle().stroke(prefs.accent.alpha(0.35), lineWidth: 5).frame(width: 30, height: 30))
                            .offset(x: geo.size.width * pct - 10)
                    }
                }
                .frame(height: seekTarget != nil ? 6 : 3)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)
            .padding(.horizontal, 12)
            .padding(.bottom, -2)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { ui.openNowPlaying() }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if axis == nil {
                        axis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                        if axis == .horizontal {
                            dragStart = clock.position
                            seekTarget = clock.position
                            Haptics.soft()
                        }
                    }
                    if axis == .horizontal {
                        let t = dragStart + Double(value.translation.width) * duration / 342
                        seekTarget = min(max(0, t), duration - 0.5)
                    }
                }
                .onEnded { value in
                    if axis == .horizontal, let t = seekTarget {
                        player.seek(to: t)
                        Haptics.tick()
                    } else if axis == .vertical, value.translation.height < -30 {
                        ui.openNowPlaying()
                    }
                    seekTarget = nil
                    axis = nil
                }
        )
        .animation(.easeOut(duration: 0.15), value: seekTarget != nil)
    }
}
