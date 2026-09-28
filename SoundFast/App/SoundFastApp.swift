import SwiftUI

@main
struct SoundFastApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var prefs: Preferences
    @StateObject private var player: PlayerController
    @StateObject private var ui: AppUI
    @StateObject private var waveforms: WaveformStore
    @StateObject private var artwork: ArtworkStore
    @StateObject private var covers: CoverService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerAll()
        let library = LibraryStore()
        let prefs = Preferences()
        _library = StateObject(wrappedValue: library)
        _prefs = StateObject(wrappedValue: prefs)
        _player = StateObject(wrappedValue: PlayerController(library: library, prefs: prefs))
        _ui = StateObject(wrappedValue: AppUI())
        _waveforms = StateObject(wrappedValue: WaveformStore())
        let artwork = ArtworkStore()
        _artwork = StateObject(wrappedValue: artwork)
        _covers = StateObject(wrappedValue: CoverService(library: library, artwork: artwork))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .withStores(library, prefs, player, ui, waveforms, artwork, covers)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                player.saveStateNow()
                library.saveNow()
                prefs.saveNow()
            case .active:
                // Recoge canciones copiadas desde Archivos o desde Windows.
                if library.onboarded || !library.songs.isEmpty {
                    Task { await library.refresh() }
                }
            default:
                break
            }
        }
    }
}
