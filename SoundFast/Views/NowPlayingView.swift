import SwiftUI

/// Estado de un arrastre en curso. Vive en una clase a propósito: si fuera `@State`
/// normal, empezar o terminar el gesto obligaría a redibujar toda la pantalla
/// justo en el primer cuadro del movimiento (ahí se sentía el tirón).
final class DragState {
    var axis: Axis?
}

/// Posición elegida mientras se arrastra la barra de progreso. Solo la miran la
/// portada y la barra; el resto de la pantalla no se entera.
final class ScrubState: ObservableObject {
    @Published var target: Double?
    var start: Double = 0
}

/// Cerrar deslizando hacia abajo. Lo comparten el fondo de la pantalla y la portada.
@MainActor
enum NowPlayingClose {
    static func track(_ dy: CGFloat, _ motion: SheetMotion) {
        // Hacia arriba ofrece un poco de resistencia en vez de quedarse trabado.
        motion.drag = dy >= 0 ? dy : -pow(-dy, 0.7)
    }

    static func finish(_ dy: CGFloat, speed: CGFloat, _ ui: AppUI) {
        if dy > 140 || (speed > 700 && dy > 30) {
            ui.closeNowPlaying(velocity: speed)
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { ui.motion.drag = 0 }
        }
    }
}

/// Pantalla completa de reproducción. Se cierra deslizando hacia abajo.
///
/// Está partida en piezas (fondo, portada, título, barra, controles) a propósito:
/// cada una recibe solo lo que muestra, así un cambio de canción o el tic del
/// reloj redibuja lo justo y no las catorce superficies de vidrio de la pantalla.
struct NowPlayingView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var artwork: ArtworkStore
    /// Sin `@ObservedObject`: la posición solo la mira la barra de progreso.
    let clock: PlaybackClock
    @ObservedObject var presence: NowPlayingPresence

    /// Colores dominantes de la portada actual.
    @State private var artColors: [Color] = []
    @State private var scrub = ScrubState()
    @State private var gesture = DragState()

    var body: some View {
        let song = player.current
        let open = presence.open
        GeometryReader { geo in
            let artSize = min(geo.size.width - 48, geo.size.height * 0.42, 380)
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 40, height: 5)
                    .padding(.top, 6)

                NPTopBar(ctxName: player.ctxName, ui: ui)
                    .padding(.top, 8)

                ArtStage(song: song, size: artSize, scrub: scrub, player: player, ui: ui)
                    .padding(.top, 16)

                Text(prefs.playback.swipeArt ? "‹‹ DESLIZA LA PORTADA PARA CAMBIAR ››" : " ")
                    .font(.mono(10.5))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(height: 14)
                    .padding(.top, 10)

                TitleRow(song: song, ui: ui)
                    .padding(.top, 14)

                SeekSection(song: song, clock: clock, scrub: scrub, open: open)
                    .padding(.top, 14)

                Spacer(minLength: 12)

                TransportControls(
                    isPlaying: player.isPlaying,
                    shuffle: player.shuffle,
                    repeatMode: player.repeatMode,
                    player: player
                )
                NPBottomRow(player: player, ui: ui)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                Backdrop(
                    song: song,
                    artColors: artColors,
                    visible: open,
                    focus: CGPoint(x: geo.size.width / 2, y: geo.safeAreaInsets.top + 75 + artSize / 2),
                    artRadius: artSize / 2
                )
            }
            .contentShape(Rectangle())
            .gesture(closeDrag)
        }
        .task(id: player.currentId) {
            if let s = player.current {
                artColors = await artwork.palette(s)
            } else {
                artColors = []
            }
        }
        // El analizador solo trabaja si algo en pantalla lo usa.
        .onChange(of: analyzerNeeded, initial: true) { _, on in
            player.analyzer.isActive = on
        }
    }

    private var analyzerNeeded: Bool {
        presence.open && player.isPlaying
            && ((prefs.visuals.enabled && prefs.visuals.reactive) || prefs.playback.seekStyle == "onda")
    }

    /// Arrastre del fondo: solo cierra. El horizontal es cosa de la portada.
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                guard scrub.target == nil else { return }
                if gesture.axis == nil {
                    gesture.axis = abs(v.translation.width) > abs(v.translation.height) ? .horizontal : .vertical
                }
                if gesture.axis == .vertical {
                    NowPlayingClose.track(v.translation.height, ui.motion)
                }
            }
            .onEnded { v in
                let axis = gesture.axis
                gesture.axis = nil
                guard axis == .vertical else { return }
                NowPlayingClose.finish(v.translation.height, speed: v.velocity.height, ui)
            }
    }
}

// MARK: - Barras de botones

/// Cerrar, "Reproduciendo desde" y salida de audio. Solo cambia con el contexto.
private struct NPTopBar: View {
    let ctxName: String
    let ui: AppUI

    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        GlassGroup {
            HStack {
                Button {
                    ui.closeNowPlaying()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Ink.text)
                        .frame(width: 40, height: 40)
                        .glassSurface(prefs, Circle(), interactive: true)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Cerrar")

                Spacer()
                VStack(spacing: 2) {
                    Text("REPRODUCIENDO DESDE").eyebrow(10, color: Color.white.opacity(0.55))
                    Text(ctxName)
                        .font(.montserrat(13, .semibold))
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                        .frame(maxWidth: 220)
                }
                Spacer()

                RoutePicker(tint: Color.white.opacity(0.8), activeTint: prefs.accent.color)
                    .frame(width: 40, height: 40)
                    .glassSurface(prefs, Circle(), interactive: true)
                    .accessibilityLabel("Salida de audio")
            }
        }
    }
}

/// Aleatorio, anterior, reproducir, siguiente y repetir. Al cambiar de canción
/// no se redibuja: solo depende de la pausa y los modos.
private struct TransportControls: View {
    let isPlaying: Bool
    let shuffle: Bool
    let repeatMode: PlayerController.RepeatMode
    let player: PlayerController

    @EnvironmentObject private var prefs: Preferences

    private var accent: Color { prefs.accent.color }

    var body: some View {
        GlassGroup {
            HStack {
                modeButton(icon: "shuffle", on: shuffle, label: "Aleatorio") { player.toggleShuffle() }
                Spacer()
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white)
                        .frame(width: 60, height: 60)
                        .glassSurface(prefs, Circle(), interactive: true)
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .accessibilityLabel("Anterior")
                Spacer()
                Button {
                    player.togglePlay()
                    Haptics.tap()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Ink.onAccent)
                        .offset(x: isPlaying ? 0 : 3)
                        .frame(width: 80, height: 80)
                        .background(accent, in: RoundedRectangle(cornerRadius: prefs.look.playShape == "cuadrado" ? 24 : 40, style: .continuous))
                        .shadow(color: prefs.accent.alpha(0.35), radius: 17, y: 14)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityLabel(isPlaying ? "Pausar" : "Reproducir")
                Spacer()
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white)
                        .frame(width: 60, height: 60)
                        .glassSurface(prefs, Circle(), interactive: true)
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .accessibilityLabel("Siguiente")
                Spacer()
                modeButton(
                    icon: "repeat",
                    on: repeatMode != .off,
                    label: repeatMode == .one ? "Repetir una" : "Repetir"
                ) { player.cycleRepeat() }
                    .overlay(alignment: .topTrailing) {
                        if repeatMode == .one {
                            Text("1")
                                .font(.mono(10, .bold))
                                .foregroundStyle(Ink.onAccent)
                                .frame(width: 15, height: 15)
                                .background(accent, in: Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
            }
        }
    }

    private func modeButton(icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? accent : Color.white.opacity(0.7))
                .frame(width: 48, height: 48)
                .glassSurface(prefs, Circle(), interactive: true)
                .overlay(Circle().stroke(on ? accent.opacity(0.7) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityValue(on ? "Activado" : "Desactivado")
    }
}

/// A lista, Sonido, Efectos y Cola. No depende de la canción que suena.
private struct NPBottomRow: View {
    let player: PlayerController
    let ui: AppUI

    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        let accent = prefs.accent.color
        GlassGroup {
            HStack {
                bottomButton("A lista", "text.badge.plus", Color.white.opacity(0.75)) {
                    if let id = player.currentId { ui.sheet = .addTo(songId: id) }
                }
                Spacer()
                bottomButton("Sonido", "slider.horizontal.3", prefs.sound.isModified ? accent : Color.white.opacity(0.75)) {
                    ui.closeNowPlaying()
                    ui.openSound()
                }
                Spacer()
                bottomButton("Efectos", "sparkles", prefs.visuals.enabled ? accent : Color.white.opacity(0.75)) {
                    ui.sheet = .effects
                }
                Spacer()
                bottomButton("Cola", "list.bullet", Color.white.opacity(0.75)) {
                    ui.sheet = .queue
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func bottomButton(_ label: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(label).font(.montserrat(11, .semibold))
            }
            .foregroundStyle(color)
            .frame(width: 78, height: 56)
            .glassSurface(prefs, RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Fondo

/// Color del tema + efectos visuales. Aparte para que el fondo no se vuelva a
/// armar cada vez que se mueve el dedo o avanza el reloj.
private struct Backdrop: View {
    let song: Song?
    let artColors: [Color]
    let visible: Bool
    let focus: CGPoint
    let artRadius: CGFloat

    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ZStack {
            base
                // El color de fondo sigue a la portada con un fundido, no de golpe.
                .animation(.easeInOut(duration: 0.45), value: song?.id)
            if prefs.visuals.enabled, let s = song {
                NowPlayingEffects(
                    settings: prefs.visuals,
                    colors: EffectPalette.colors(
                        option: prefs.visuals.palette, artwork: artColors,
                        hue: s.hue, accent: prefs.accent
                    ),
                    analyzer: player.analyzer,
                    playing: player.isPlaying,
                    visible: visible,
                    focus: focus,
                    artRadius: artRadius
                )
                // Oscurece un poco abajo para que los controles se lean bien.
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.45)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
        // Queda oculto bajo las esquinas de la pantalla cuando está abierta;
        // se ve al arrastrar hacia abajo.
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .ignoresSafeArea()
    }

    private var base: Color {
        guard let s = song, prefs.look.npBg != "tema" else { return prefs.theme.bg }
        return prefs.look.npBg == "intenso" ? .oklch(0.3, 0.09, s.hue) : .oklch(0.19, 0.035, s.hue)
    }
}

// MARK: - Portada

/// La portada que se va al deslizar: conserva su imagen mientras sale.
private struct Outgoing {
    let song: Song
    let token: Int
}

/// Portada con sus dos gestos: vertical cierra, horizontal cambia de canción.
/// Guarda su propio desplazamiento, así deslizarla no redibuja la pantalla entera.
///
/// Al soltar, la portada vieja sigue su camino desvaneciéndose y la nueva aparece
/// en el centro con un fundido (ya precargada, así no hay espera de disco).
private struct ArtStage: View {
    let song: Song?
    let size: CGFloat
    @ObservedObject var scrub: ScrubState
    /// Sin observar: solo para acciones.
    let player: PlayerController
    let ui: AppUI

    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var artwork: ArtworkStore

    /// Desplazamiento de la portada actual bajo el dedo.
    @State private var x: CGFloat = 0
    @State private var outgoing: Outgoing?
    @State private var outX: CGFloat = 0
    @State private var outOpacity: Double = 0
    /// 0 → 1 mientras entra la portada nueva.
    @State private var reveal: Double = 1
    @State private var token = 0
    @State private var gesture = DragState()

    private var radius: CGFloat {
        switch prefs.look.artShape {
        case "cuadrada": return 8
        case "circulo": return size / 2
        default: return 28
        }
    }

    var body: some View {
        ZStack {
            if let outgoing {
                cover(outgoing.song)
                    .scaleEffect(0.94)
                    .offset(x: outX)
                    .rotationEffect(.degrees(Double(outX / 45)))
                    .opacity(outOpacity)
                    .allowsHitTesting(false)
            }
            ZStack {
                cover(song)
                scrubOverlay
            }
            .scaleEffect((1 - min(0.08, abs(x) / 2500)) * (0.92 + 0.08 * reveal))
            .offset(x: x)
            .rotationEffect(.degrees(Double(x / 45)))
            .opacity(max(0, 1 - Double(abs(x)) / 520) * reveal)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        // Gesto propio de la portada: tiene prioridad sobre el del fondo.
        .highPriorityGesture(drag)
        // La anterior y la siguiente quedan listas en memoria.
        .task(id: song?.id) {
            try? await Task.sleep(nanoseconds: 450_000_000)   // después de la animación
            guard !Task.isCancelled else { return }
            await artwork.prefetch(player.neighbors, size: size)
        }
    }

    private func cover(_ s: Song?) -> some View {
        ZStack {
            ArtworkView(song: s, size: size, radius: radius, letterSize: size * 0.53)
            if let s, !s.hasArtwork {
                Text("PORTADA DEL ÁLBUM")
                    .font(.mono(10))
                    .tracking(1)
                    .foregroundStyle(ArtColors.fg(s.hue).opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 16)
                    .padding(.bottom, 14)
                    .opacity(prefs.look.artShape == "circulo" ? 0 : 1)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 30, y: 30)
    }

    @ViewBuilder
    private var scrubOverlay: some View {
        if let target = scrub.target, let s = song {
            let delta = target - scrub.start
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
                Text("de " + Format.time(s.duration))
                    .font(.mono(13))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    /// En coordenadas globales, porque la portada se mueve con el dedo.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                guard scrub.target == nil else { return }
                if gesture.axis == nil {
                    gesture.axis = abs(v.translation.width) > abs(v.translation.height) ? .horizontal : .vertical
                }
                if gesture.axis == .vertical {
                    NowPlayingClose.track(v.translation.height, ui.motion)
                } else if prefs.playback.swipeArt {
                    x = v.translation.width
                }
            }
            .onEnded { v in
                let axis = gesture.axis
                gesture.axis = nil
                if axis == .vertical {
                    NowPlayingClose.finish(v.translation.height, speed: v.velocity.height, ui)
                } else if axis == .horizontal, prefs.playback.swipeArt {
                    // También cuenta un deslizamiento corto pero rápido.
                    let flick = abs(v.velocity.width) > 600 && abs(x) > 30
                    if x < -80 || (flick && x < 0) {
                        swipe(-1)
                    } else if x > 80 || (flick && x > 0) {
                        swipe(1)
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { x = 0 }
                    }
                }
            }
    }

    /// La portada vieja queda donde la soltó el dedo y la nueva arranca invisible
    /// en el centro; el cambio de canción (y todo lo que redibuja) ocurre en ese
    /// cuadro. Las animaciones empiezan en el cuadro siguiente, ya sin trabajo
    /// pendiente, así no se pierde ningún cuadro en el movimiento.
    private func swipe(_ dir: CGFloat) {
        guard let current = song else { return }
        let target: CGFloat = dir < 0 ? -420 : 420
        token += 1
        let mine = token

        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            outgoing = Outgoing(song: current, token: mine)
            outX = x
            outOpacity = max(0, 1 - Double(abs(x)) / 520)
            x = 0
            reveal = 0
        }
        if dir < 0 { player.next() } else { player.previousTrack() }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.3)) {
                outX = target
                outOpacity = 0
            }
            withAnimation(.easeOut(duration: 0.38).delay(0.04)) {
                reveal = 1
            } completion: {
                if outgoing?.token == mine { outgoing = nil }
            }
        }
    }
}

// MARK: - Título

/// Título, artista y corazón. Aparte porque es lo único que mira la biblioteca.
private struct TitleRow: View {
    let song: Song?
    let ui: AppUI

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        let isFav = song.map { library.isFavorite($0.id) } ?? false
        HStack(spacing: 12) {
            // El contenedor anima la salida/entrada del título al cambiar de canción.
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(song?.title ?? "")
                        .font(.montserrat(23, .bold))
                        .tracking(-0.23)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    Text(song?.artist ?? "")
                        .font(.montserrat(15))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                }
                .id(song?.id)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .contentShape(Rectangle())
            .contextMenu {
                if let s = song {
                    Button { ui.sheet = .editTags(songId: s.id) } label: {
                        Label("Editar información…", systemImage: "pencil")
                    }
                    Button { ui.sheet = .cover(songId: s.id) } label: {
                        Label("Buscar portada…", systemImage: "photo")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: song?.id)
            Spacer(minLength: 0)
            Button {
                if let s = song {
                    library.toggleFavorite(s.id)
                    Haptics.soft()
                }
            } label: {
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isFav ? prefs.accent.color : Color.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .glassSurface(prefs, Circle(), interactive: true)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel(isFav ? "Quitar de favoritos" : "Añadir a favoritos")
        }
    }
}

// MARK: - Barra de progreso

/// Barra (u onda) y los dos tiempos. Es la única pieza que mira el reloj, así el
/// tic de cada cuarto de segundo no redibuja toda la pantalla.
private struct SeekSection: View {
    let song: Song?
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var scrub: ScrubState
    /// Si la reproducción está abierta (la onda solo late a la vista).
    let open: Bool

    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var waveforms: WaveformStore

    var body: some View {
        VStack(spacing: 0) {
            seekBar
            timeLabels.padding(.top, 4)
        }
        .task(id: song?.id) {
            if let s = song { waveforms.request(s) }
        }
    }

    private var accent: Color { prefs.accent.color }

    private var seekBar: some View {
        let duration = max(1, song?.duration ?? 1)
        let shown = scrub.target ?? clock.position
        let frac = min(1, max(0, shown / duration))
        return GeometryReader { geo in
            Group {
                if prefs.playback.seekStyle == "onda", let s = song {
                    LiveWaveform(
                        bars: waveforms.bars(for: s),
                        progress: frac,
                        accent: accent,
                        analyzer: player.analyzer,
                        live: open && player.isPlaying && scrub.target == nil,
                        scrubbing: scrub.target != nil
                    )
                    .frame(height: 52)
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
                        if scrub.target == nil {
                            scrub.start = clock.position
                            Haptics.soft()
                        }
                        let x = min(max(0, v.location.x / max(1, geo.size.width)), 1)
                        scrub.target = x * (duration - 0.5)
                    }
                    .onEnded { _ in
                        if let t = scrub.target { player.seek(to: t) }
                        scrub.target = nil
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

    private var timeLabels: some View {
        let shown = scrub.target ?? clock.position
        let duration = song?.duration ?? 0
        return HStack {
            Text(Format.time(shown)).foregroundStyle(Color.white)
            Spacer()
            Text("-" + Format.time(max(0, duration - shown))).foregroundStyle(Color.white.opacity(0.6))
        }
        .font(.mono(12))
    }
}

// MARK: - Onda viva

/// Barra de progreso tipo onda: cada barra late con su franja de frecuencias
/// y un punto marca por dónde va la canción.
struct LiveWaveform: View {
    let bars: [Double]
    let progress: Double
    let accent: Color
    let analyzer: AudioAnalyzer
    let live: Bool
    let scrubbing: Bool

    @State private var follower = BandFollower()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { timeline in
            let levels = follower.update(analyzer.snapshot, live: live, now: timeline.date)
            Canvas { ctx, size in
                let n = bars.count
                guard n > 0 else { return }
                let gap: CGFloat = 2
                let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                for i in 0..<n {
                    let band = levels[min(levels.count - 1, i * levels.count / n)]
                    let h = size.height * min(1, CGFloat(bars[i]) * (0.72 + 0.55 * band))
                    let rect = CGRect(x: CGFloat(i) * (w + gap), y: (size.height - h) / 2, width: w, height: h)
                    let played = (Double(i) + 0.5) / Double(n) <= progress
                    ctx.fill(Path(roundedRect: rect, cornerRadius: min(2, w / 2)),
                             with: .color(played ? accent : Color.white.opacity(0.16)))
                }
                // Punto de posición con halo.
                let x = min(size.width - 6, max(6, size.width * progress))
                let y = size.height / 2
                let halo: CGFloat = scrubbing ? 16 : 11
                ctx.fill(Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
                         with: .radialGradient(Gradient(colors: [accent.opacity(0.55), accent.opacity(0)]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: halo))
                let r: CGFloat = scrubbing ? 8 : 6
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white))
            }
        }
        .animation(.easeOut(duration: 0.15), value: scrubbing)
    }
}

/// Suaviza las bandas del analizador (sube rápido, baja lento).
final class BandFollower {
    private var values = [CGFloat](repeating: 0, count: AudioAnalyzer.bandCount)

    func update(_ s: AudioAnalyzer.Snapshot, live: Bool, now: Date) -> [CGFloat] {
        let fresh = live && now.timeIntervalSinceReferenceDate - s.time < 0.6
        for i in values.indices {
            let target = fresh ? CGFloat(s.bands[i]) : 0
            values[i] += (target - values[i]) * (target > values[i] ? 0.55 : 0.12)
        }
        return values
    }
}
