import SwiftUI

/// Pantalla completa de reproducción. Se cierra deslizando hacia abajo.
struct NowPlayingView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var waveforms: WaveformStore
    @ObservedObject var clock: PlaybackClock

    @State private var axis: Axis?
    @State private var dragOnArt = false
    @State private var artFrame: CGRect = .zero
    @State private var artX: CGFloat = 0
    @State private var scrub: Double?
    @State private var scrubStart: Double = 0

    private var accent: Color { prefs.accent.color }

    var body: some View {
        let song = player.current
        GeometryReader { geo in
            let artSize = min(geo.size.width - 48, geo.size.height * 0.42, 380)
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 40, height: 5)
                    .padding(.top, 6)

                topBar(song)
                    .padding(.top, 8)

                artwork(song, size: artSize)
                    .padding(.top, 16)

                Text(prefs.playback.swipeArt ? "‹‹ DESLIZA LA PORTADA PARA CAMBIAR ››" : " ")
                    .font(.mono(10.5))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(height: 14)
                    .padding(.top, 10)

                titleRow(song)
                    .padding(.top, 14)

                seekBar(song)
                    .padding(.top, 14)

                timeLabels(song)
                    .padding(.top, 4)

                Spacer(minLength: 12)

                controls
                bottomRow
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: "np")
            .onPreferenceChange(ArtFrameKey.self) { artFrame = $0 }
            .background {
                RoundedRectangle(cornerRadius: ui.npDrag > 0 ? 44 : 0, style: .continuous)
                    .fill(background(song))
                    .ignoresSafeArea()
            }
            .contentShape(Rectangle())
            .gesture(panelDrag)
        }
        .onAppear { if let song { waveforms.request(song) } }
        .onChange(of: player.currentId) { _, _ in
            if let s = player.current { waveforms.request(s) }
        }
    }

    // MARK: Partes

    private func background(_ song: Song?) -> Color {
        guard let song, prefs.look.npBg != "tema" else { return prefs.theme.bg }
        return prefs.look.npBg == "intenso" ? .oklch(0.3, 0.09, song.hue) : .oklch(0.19, 0.035, song.hue)
    }

    private func topBar(_ song: Song?) -> some View {
        HStack {
            Button {
                ui.closeNowPlaying()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.text)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cerrar")

            Spacer()
            VStack(spacing: 2) {
                Text("REPRODUCIENDO DESDE").eyebrow(10, color: Color.white.opacity(0.55))
                Text(player.ctxName)
                    .font(.sora(13, .semibold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .frame(maxWidth: 220)
            }
            Spacer()

            RoutePicker(tint: Color.white.opacity(0.8), activeTint: accent)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08), in: Circle())
                .accessibilityLabel("Salida de audio")
        }
    }

    private func artwork(_ song: Song?, size: CGFloat) -> some View {
        let radius: CGFloat = {
            switch prefs.look.artShape {
            case "cuadrada": return 8
            case "circulo": return size / 2
            default: return 28
            }
        }()
        return ZStack {
            ArtworkView(song: song, size: size, radius: radius, letterSize: size * 0.53)
            if let song, !song.hasArtwork {
                Text("PORTADA DEL ÁLBUM")
                    .font(.mono(10))
                    .tracking(1)
                    .foregroundStyle(ArtColors.fg(song.hue).opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 16)
                    .padding(.bottom, 14)
                    .opacity(prefs.look.artShape == "circulo" ? 0 : 1)
            }
            if let target = scrub, let song {
                let delta = target - scrubStart
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(0.62))
                VStack(spacing: 4) {
                    Text((delta >= 0 ? "+" : "−") + Format.time(abs(delta)) + (delta >= 0 ? "  ››" : "  ‹‹"))
                        .font(.mono(18, .bold))
                        .foregroundStyle(prefs.accent.light)
                    Text(Format.time(target))
                        .font(.mono(56, .bold))
                        .tracking(-1)
                        .foregroundStyle(Color.white)
                    Text("de " + Format.time(song.duration))
                        .font(.mono(13))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .background {
            GeometryReader { g in
                Color.clear.preference(key: ArtFrameKey.self, value: g.frame(in: .named("np")))
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 30)
        .offset(x: artX)
        .rotationEffect(.degrees(Double(artX / 45)))
        .opacity(max(0, 1 - Double(abs(artX)) / 520))
    }

    private func titleRow(_ song: Song?) -> some View {
        let isFav = song.map { library.isFavorite($0.id) } ?? false
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(song?.title ?? "")
                    .font(.sora(23, .bold))
                    .tracking(-0.23)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text(song?.artist ?? "")
                    .font(.sora(15))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                if let song {
                    library.toggleFavorite(song.id)
                    Haptics.soft()
                }
            } label: {
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isFav ? accent : Color.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel(isFav ? "Quitar de favoritos" : "Añadir a favoritos")
        }
    }

    private func seekBar(_ song: Song?) -> some View {
        let duration = max(1, song?.duration ?? 1)
        let shown = scrub ?? clock.position
        let frac = min(1, max(0, shown / duration))
        return GeometryReader { geo in
            Group {
                if prefs.playback.seekStyle == "onda", let song {
                    let bars = waveforms.bars(for: song)
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(bars.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill((Double(i) + 0.5) / Double(bars.count) <= frac ? accent : Color.white.opacity(0.16))
                                .frame(height: 52 * bars[i])
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 52)
                    .animation(.easeOut(duration: 0.3), value: bars)
                } else {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16)).frame(height: 5)
                        Capsule().fill(accent).frame(width: geo.size.width * frac, height: 5)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                            .offset(x: geo.size.width * frac - 8)
                    }
                    .frame(height: 52)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if scrub == nil {
                            scrubStart = clock.position
                            Haptics.soft()
                        }
                        let x = min(max(0, v.location.x / max(1, geo.size.width)), 1)
                        scrub = x * (duration - 0.5)
                    }
                    .onEnded { _ in
                        if let t = scrub { player.seek(to: t) }
                        scrub = nil
                        Haptics.tick()
                    }
            )
        }
        .frame(height: 52)
        .accessibilityElement()
        .accessibilityLabel("Posición")
        .accessibilityValue(Format.time(shown))
        .accessibilityAdjustableAction { dir in
            player.seek(to: clock.position + (dir == .increment ? 10 : -10))
        }
    }

    private func timeLabels(_ song: Song?) -> some View {
        let shown = scrub ?? clock.position
        let duration = song?.duration ?? 0
        return HStack {
            Text(Format.time(shown)).foregroundStyle(Color.white)
            Spacer()
            Text("-" + Format.time(max(0, duration - shown))).foregroundStyle(Color.white.opacity(0.6))
        }
        .font(.mono(12))
    }

    private var controls: some View {
        HStack {
            modeButton(icon: "shuffle", on: player.shuffle, label: "Aleatorio") { player.toggleShuffle() }
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel("Anterior")
            Spacer()
            Button {
                player.togglePlay()
                Haptics.tap()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Ink.onAccent)
                    .offset(x: player.isPlaying ? 0 : 3)
                    .frame(width: 80, height: 80)
                    .background(accent, in: RoundedRectangle(cornerRadius: prefs.look.playShape == "cuadrado" ? 24 : 40, style: .continuous))
                    .shadow(color: prefs.accent.alpha(0.35), radius: 17, y: 14)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproducir")
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel("Siguiente")
            Spacer()
            modeButton(
                icon: "repeat",
                on: player.repeatMode != .off,
                label: player.repeatMode == .one ? "Repetir una" : "Repetir"
            ) { player.cycleRepeat() }
                .overlay(alignment: .topTrailing) {
                    if player.repeatMode == .one {
                        Text("1")
                            .font(.mono(10, .bold))
                            .foregroundStyle(Ink.onAccent)
                            .frame(width: 15, height: 15)
                            .background(accent, in: Circle())
                            .offset(x: -4, y: 6)
                    }
                }
        }
    }

    private func modeButton(icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                Circle()
                    .fill(on ? accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(on ? accent : Color.white.opacity(0.6))
            .frame(width: 48, height: 56)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityValue(on ? "Activado" : "Desactivado")
    }

    private var bottomRow: some View {
        HStack {
            bottomButton("A LISTA", "text.badge.plus", Color.white.opacity(0.75)) {
                if let id = player.currentId { ui.sheet = .addTo(songId: id) }
            }
            Spacer()
            bottomButton("SONIDO", "slider.horizontal.3", prefs.sound.isModified ? accent : Color.white.opacity(0.75)) {
                ui.soundOpen = true
            }
            Spacer()
            bottomButton("COLA", "list.bullet", Color.white.opacity(0.75)) {
                ui.sheet = .queue
            }
        }
        .padding(.horizontal, 12)
    }

    private func bottomButton(_ label: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                Text(label).font(.mono(9.5)).tracking(0.8)
            }
            .foregroundStyle(color)
            .frame(width: 84, height: 48)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Gestos

    /// Vertical en cualquier parte: cerrar. Horizontal sobre la portada: cambiar canción.
    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("np"))
            .onChanged { v in
                guard scrub == nil else { return }
                if axis == nil {
                    axis = abs(v.translation.width) > abs(v.translation.height) ? .horizontal : .vertical
                    dragOnArt = artFrame.contains(v.startLocation)
                }
                if axis == .vertical {
                    ui.npDrag = max(0, v.translation.height)
                } else if dragOnArt, prefs.playback.swipeArt {
                    artX = v.translation.width
                }
            }
            .onEnded { v in
                defer {
                    axis = nil
                    dragOnArt = false
                }
                if axis == .vertical {
                    let dy = v.translation.height
                    let fast = v.predictedEndTranslation.height - dy > 180
                    if dy > 130 || (fast && dy > 40) {
                        ui.closeNowPlaying()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.npDrag = 0 }
                    }
                } else if dragOnArt, prefs.playback.swipeArt {
                    let dx = artX
                    if dx < -80 {
                        swipe(-1)
                    } else if dx > 80 {
                        swipe(1)
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { artX = 0 }
                    }
                }
            }
    }

    /// Anima la portada hacia afuera, cambia de canción y la trae desde el otro lado.
    private func swipe(_ dir: CGFloat) {
        let out: CGFloat = dir < 0 ? -440 : 440
        withAnimation(.easeIn(duration: 0.18)) { artX = out }
        Task {
            try? await Task.sleep(nanoseconds: 190_000_000)
            if dir < 0 { player.next() } else { player.previousTrack() }
            artX = -out
            try? await Task.sleep(nanoseconds: 16_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { artX = 0 }
        }
    }
}

private struct ArtFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
