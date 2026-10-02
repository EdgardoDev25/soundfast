import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var waveforms: WaveformStore
    @EnvironmentObject private var artwork: ArtworkStore
    @EnvironmentObject private var covers: CoverService

    @State private var modalText = ""
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    static let audioTypes: [UTType] = {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        return types
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                PlayerStage(
                    motion: ui.motion,
                    presence: ui.presence,
                    ui: ui,
                    player: player,
                    soundOpen: ui.soundOpen,
                    settingsOpen: ui.settingsOpen,
                    hasCurrent: player.currentId != nil,
                    clock: player.clock,
                    hiddenOffset: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom + 40
                )

                if !library.onboarded && library.songs.isEmpty {
                    OnboardingView()
                        .transition(.opacity)
                }

                if let toast {
                    Toast(text: toast)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
        .tint(prefs.accent.color)
        .sheet(item: $ui.sheet) { sheet in
            Group {
                switch sheet {
                case .queue: QueueSheet()
                case .effects: EffectsSheet()
                case .addTo(let id): AddToPlaylistSheet(songId: id)
                case .picker(let id): SongPickerSheet(playlistId: id)
                case .cover(let id): CoverPickerSheet(songId: id)
                case .editTags(let id): EditTagsSheet(songId: id)
                }
            }
            .withStores(library, prefs, player, ui, waveforms, artwork, covers)
        }
        .fileImporter(isPresented: $ui.importing, allowedContentTypes: Self.audioTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task {
                await library.importFiles(urls)
                library.onboarded = true
            }
        }
        .onOpenURL { url in
            // "Abrir en SoundFast" desde otra app (WhatsApp, Archivos, Safari…).
            guard MediaFiles.isAudio(url) else { return }
            Task {
                await library.importFiles([url])
                library.onboarded = true
            }
        }
        .alert(modalTitle, isPresented: $ui.modalShown, presenting: ui.modal) { modal in
            switch modal {
            case .newList, .rename:
                TextField("Ej. Para entrenar", text: $modalText)
                Button("Cancelar", role: .cancel) {}
                Button(modalOkLabel) { confirm(modal) }
            case .deleteList, .deleteSong:
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) { confirm(modal) }
            }
        } message: { modal in
            Text(modalMessage(modal))
        }
        .onChange(of: ui.modal?.id) { _, _ in
            if case .rename(let id) = ui.modal {
                modalText = library.playlist(id)?.name ?? ""
            } else {
                modalText = ""
            }
        }
        .onChange(of: library.songs) { _, _ in player.libraryDidChange() }
        .onChange(of: library.notice) { _, text in
            guard let text else { return }
            show(text)
            library.notice = nil
        }
        .onChange(of: player.errorMessage) { _, text in
            if let text { show(text) }
        }
        .animation(.easeOut(duration: 0.25), value: player.current != nil)
    }

    // MARK: Avisos

    private func show(_ text: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }

    // MARK: Diálogos

    private var modalTitle: String {
        switch ui.modal {
        case .newList?: return "Nueva lista"
        case .rename?: return "Renombrar lista"
        case .deleteList(let id)?: return "¿Eliminar “\(library.playlist(id)?.name ?? "")”?"
        case .deleteSong(let id)?: return "¿Eliminar “\(library.song(id)?.title ?? "")”?"
        case nil: return ""
        }
    }

    private var modalOkLabel: String {
        if case .rename? = ui.modal { return "Guardar" }
        return "Crear"
    }

    private func modalMessage(_ modal: AppUI.Modal) -> String {
        switch modal {
        case .newList: return "Ponle el nombre que quieras: un género, un ánimo, un momento."
        case .rename: return "Escribe el nuevo nombre."
        case .deleteList: return "Las canciones seguirán en tu biblioteca."
        case .deleteSong: return "Se borrará el archivo del iPhone y de tus listas."
        }
    }

    private func confirm(_ modal: AppUI.Modal) {
        switch modal {
        case .newList(let songId):
            library.createPlaylist(named: modalText, with: songId)
        case .rename(let id):
            library.rename(id, to: modalText)
        case .deleteList(let id):
            library.deletePlaylist(id)
            if ui.openList == id { ui.openList = nil }
        case .deleteSong(let id):
            if let song = library.song(id) { library.deleteFile(song) }
        }
        Haptics.tap()
    }
}

/// Biblioteca + minirreproductor + "Sonando ahora". Es la única vista que escucha el
/// arrastre, así la biblioteca (una lista larga) no se redibuja en cada cuadro.
///
/// Todo lo que recibe se puede comparar (sin closures): si nada cambió, SwiftUI
/// se salta su cuerpo cuando la raíz se redibuja por el reproductor.
private struct PlayerStage: View {
    @ObservedObject var motion: SheetMotion
    @ObservedObject var presence: NowPlayingPresence
    /// Referencias sin observar: solo se usan para acciones.
    let ui: AppUI
    let player: PlayerController
    let soundOpen: Bool
    let settingsOpen: Bool
    let hasCurrent: Bool
    let clock: PlaybackClock
    let hiddenOffset: CGFloat

    var body: some View {
        let npOpen = presence.open
        let t = min(1, max(0, motion.drag) / 500)
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // La biblioteca ya no se encoge al abrir la reproducción: al escalarla,
            // su barra de vidrio y el degradado del fondo se recalculaban en cada
            // cuadro y se veían recortados. Ahora queda quieta, solo se oscurece.
            LibraryView(player: player, hasCurrent: hasCurrent)
                .background(ThemeBackground())
                .allowsHitTesting(!npOpen)

            Color.black
                .opacity(npOpen ? 0.45 * Double(1 - t) : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if settingsOpen {
                SlidingPanel(onClose: { ui.closePanels() }) { SettingsView() }
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
            if soundOpen {
                SlidingPanel(onClose: { ui.closePanels() }) { SoundView() }
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }

            if hasCurrent {
                MiniPlayer(clock: clock)
                    .padding(.horizontal, 10)
                    // Sin barra de pestañas debajo (paneles abiertos) baja hasta el borde.
                    .padding(.bottom, soundOpen || settingsOpen ? 6 : 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityHidden(npOpen)
                    .zIndex(3)
            }

            NowPlayingView(clock: clock, presence: presence)
                .offset(y: npOpen ? motion.drag : hiddenOffset)
                .allowsHitTesting(npOpen)
                .accessibilityHidden(!npOpen)
                .zIndex(4)
        }
    }
}

extension View {
    /// Las hojas y pantallas completas reciben los mismos objetos compartidos.
    func withStores(
        _ library: LibraryStore, _ prefs: Preferences, _ player: PlayerController,
        _ ui: AppUI, _ waveforms: WaveformStore, _ artwork: ArtworkStore, _ covers: CoverService
    ) -> some View {
        self.environmentObject(library)
            .environmentObject(covers)
            .environmentObject(prefs)
            .environmentObject(player)
            .environmentObject(ui)
            .environmentObject(waveforms)
            .environmentObject(artwork)
            .preferredColorScheme(.dark)
    }
}
