import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Posición de reproducción, separada para que solo se redibujen las vistas que la muestran.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
}

/// Cola, aleatorio, repetir, pantalla de bloqueo, interrupciones y auriculares.
@MainActor
final class PlayerController: ObservableObject {
    enum RepeatMode: String, Codable { case off, all, one }

    @Published private(set) var currentId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var queue: [String] = []
    @Published private(set) var ctxIds: [String] = []
    @Published private(set) var ctxName = "Todas las canciones"
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published var errorMessage: String?

    let clock: PlaybackClock
    private let engine: AudioEngine
    private let library: LibraryStore
    private let prefs: Preferences
    private var ticker: Timer?
    private var tickCount = 0
    private var subscriptions = Set<AnyCancellable>()
    private var resumeAfterInterruption = false
    private var pausedByRouteChange = false

    var position: Double { clock.position }

    var analyzer: AudioAnalyzer { engine.analyzer }

    init(library: LibraryStore, prefs: Preferences) {
        self.library = library
        self.prefs = prefs
        self.clock = PlaybackClock()
        self.engine = AudioEngine()
        restoreState()

        engine.nextSong = { [weak self] in self?.automaticNext() }
        engine.onAdvance = { [weak self] id in self?.didAdvance(to: id) }
        engine.onTrackEnd = { [weak self] in self?.didReachEnd() }
        engine.onError = { [weak self] error in self?.didFail(error) }

        engine.apply(prefs.sound)
        prefs.$sound
            .sink { [weak self] s in MainActor.assumeIsolated { self?.engine.apply(s) } }
            .store(in: &subscriptions)
        prefs.$playback
            .sink { [weak self] p in MainActor.assumeIsolated { self?.applyPlayback(p) } }
            .store(in: &subscriptions)
        applyPlayback(prefs.playback)

        configureSession()
        configureRemoteCommands()
        startTicker()
        updateNowPlaying()
    }

    // MARK: Consultas

    var current: Song? { currentId.flatMap { library.song($0) } }

    /// La cola vigente; si la canción actual no está en ella, toda la biblioteca.
    var effectiveQueue: [String] {
        if let c = currentId, queue.contains(c) { return queue }
        return library.songs.map(\.id)
    }

    var upcoming: [String] {
        let q = effectiveQueue
        guard let c = currentId, let i = q.firstIndex(of: c) else { return [] }
        return Array(q[(i + 1)...])
    }

    // MARK: Acciones

    func playFrom(_ id: String, ids: [String], name: String, forceShuffle: Bool? = nil) {
        let sh = forceShuffle ?? shuffle
        queue = sh ? [id] + ids.filter { $0 != id }.shuffled() : ids
        ctxIds = ids
        ctxName = name
        shuffle = sh
        start(id, transition: true)
        Haptics.tap()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let song = current else { return }
        activateSession()
        isPlaying = true
        if engine.currentSongId == song.id {
            engine.play()
        } else {
            let t = clock.position
            Task { await engine.load(song, at: t, autoplay: true) }
        }
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        engine.pause()
        isPlaying = false
        clock.position = engine.currentTime
        updateNowPlaying()
        saveState()
    }

    func next() {
        guard currentId != nil, let n = nextId(manual: true) else { return }
        // Sin vibración: al pasar canciones se sentía como un corte.
        start(n, autoplay: isPlaying, transition: true)
    }

    func previous() {
        guard currentId != nil else { return }
        if clock.position > 3 {
            seek(to: 0)
        } else {
            previousTrack()
        }
    }

    /// Siempre va a la anterior (usado al deslizar la portada).
    func previousTrack() {
        let q = effectiveQueue
        guard let c = currentId, let i = q.firstIndex(of: c), !q.isEmpty else { return }
        start(q[(i - 1 + q.count) % q.count], autoplay: isPlaying, transition: true)
    }

    func seek(to time: Double) {
        guard let song = current else { return }
        let t = min(max(0, time), max(0, song.duration - 0.5))
        clock.position = t
        if engine.currentSongId == song.id {
            engine.seek(to: t)
        }
        updateNowPlaying()
    }

    func toggleShuffle() {
        let ctx = ctxIds.isEmpty ? library.songs.map(\.id) : ctxIds
        if !shuffle {
            shuffle = true
            if let c = currentId {
                queue = [c] + ctx.filter { $0 != c }.shuffled()
            } else {
                queue = ctx.shuffled()
            }
        } else {
            shuffle = false
            queue = ctx
        }
        Haptics.tap()
        saveState()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        Haptics.tap()
        saveState()
    }

    func playFromQueue(_ id: String) {
        start(id, transition: true)
    }

    func removeFromQueue(_ id: String) {
        guard id != currentId else { return }
        queue = effectiveQueue.filter { $0 != id }
        saveState()
    }

    func moveUpcoming(from source: IndexSet, to destination: Int) {
        let q = effectiveQueue
        guard let c = currentId, let i = q.firstIndex(of: c) else { return }
        var up = Array(q[(i + 1)...])
        up.move(fromOffsets: source, toOffset: destination)
        queue = Array(q[...i]) + up
        Haptics.tick()
        saveState()
    }

    /// "Reproducir a continuación".
    func playNext(_ id: String) {
        guard currentId != nil else {
            playFrom(id, ids: [id], name: ctxName)
            return
        }
        var q = effectiveQueue.filter { $0 != id }
        let i = currentId.flatMap { q.firstIndex(of: $0) } ?? -1
        q.insert(id, at: i + 1)
        queue = q
        Haptics.soft()
        saveState()
    }

    /// "Añadir al final de la cola".
    func addToQueue(_ id: String) {
        guard currentId != nil else {
            playFrom(id, ids: [id], name: ctxName)
            return
        }
        var q = effectiveQueue.filter { $0 != id || $0 == currentId }
        q.append(id)
        queue = q
        Haptics.soft()
        saveState()
    }

    /// La biblioteca cambió (se borró una canción, por ejemplo).
    func libraryDidChange() {
        if let c = currentId, library.song(c) == nil {
            engine.unload()
            currentId = nil
            isPlaying = false
            clock.position = 0
            updateNowPlaying()
        }
        queue = queue.filter { library.song($0) != nil }
        ctxIds = ctxIds.filter { library.song($0) != nil }
        measureLibrary()
    }

    // MARK: Interno

    /// `transition`: la canción que sonaba se desvanece mientras entra la nueva.
    private func start(_ id: String, at time: Double = 0, autoplay: Bool = true, transition: Bool = false) {
        guard let song = library.song(id) else { return }
        currentId = id
        clock.position = time
        isPlaying = autoplay
        errorMessage = nil
        if autoplay { activateSession() }
        updateNowPlaying()
        saveState()
        Task { await engine.load(song, at: time, autoplay: autoplay, transition: transition) }
    }

    private func nextId(manual: Bool) -> String? {
        let q = effectiveQueue
        guard !q.isEmpty else { return nil }
        guard let c = currentId, let i = q.firstIndex(of: c) else { return q.first }
        if i < q.count - 1 { return q[i + 1] }
        return (manual || repeatMode == .all) ? q.first : nil
    }

    private func automaticNext() -> Song? {
        if repeatMode == .one { return current }
        return nextId(manual: false).flatMap { library.song($0) }
    }

    private func didAdvance(to id: String) {
        currentId = id
        clock.position = 0
        updateNowPlaying()
        saveState()
    }

    private func didReachEnd() {
        if let next = automaticNext() {
            start(next.id)
        } else {
            isPlaying = false
            clock.position = 0
            updateNowPlaying()
            saveState()
        }
    }

    private func didFail(_ error: Error) {
        isPlaying = false
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        updateNowPlaying()
    }

    private func applyPlayback(_ p: PlaybackSettings) {
        engine.crossfade = Double(p.crossfade)
        engine.gapless = p.gapless
        library.setSort(by: p.sortBy, ascending: p.sortAscending)
        let wasOn = engine.normalize
        engine.setNormalize(p.normalize)
        if p.normalize && !wasOn { measureLibrary() }
    }

    private var measureTask: Task<Void, Never>?

    /// Mide el volumen de toda la biblioteca en segundo plano (una sola vez por canción),
    /// para que al normalizar no haya que esperar al empezar cada una.
    func measureLibrary() {
        guard prefs.playback.normalize else { return }
        measureTask?.cancel()
        let songs = library.songs
        let store = engine.loudness
        measureTask = Task.detached(priority: .background) {
            for song in songs {
                if Task.isCancelled { return }
                if store.cached(song.id) != nil { continue }
                guard let url = try? await MediaFiles.playableURL(for: song) else { continue }
                _ = await store.gain(for: song.id, url: url)
            }
        }
    }

    private func startTicker() {
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard isPlaying else { return }
        if engine.currentSongId == currentId, engine.hasLoadedSong {
            clock.position = engine.currentTime
        }
        tickCount += 1
        if tickCount % 40 == 0 { saveState() }
    }

    // MARK: Sesión de audio

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(type: type, options: options) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { self?.handleRouteChange(reason: reason) }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaReset() }
        }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func handleInterruption(type: UInt?, options: UInt?) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch kind {
        case .began:
            // Llamada, alarma, Siri…
            resumeAfterInterruption = isPlaying
            if isPlaying {
                engine.pause()
                isPlaying = false
                clock.position = engine.currentTime
                updateNowPlaying()
            }
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: options ?? 0)
            if resumeAfterInterruption, opts.contains(.shouldResume) { play() }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reason: UInt?) {
        guard let reason, let kind = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }
        switch kind {
        case .oldDeviceUnavailable:
            // Se desconectaron los auriculares: pausar, como hace Música.
            if isPlaying {
                pause()
                pausedByRouteChange = true
            }
        case .newDeviceAvailable:
            if prefs.playback.headphones, !isPlaying, current != nil, pausedByRouteChange || Self.headphonesConnected {
                play()
            }
            pausedByRouteChange = false
        default:
            break
        }
    }

    private func handleMediaReset() {
        configureSession()
        if isPlaying, let song = current {
            let t = clock.position
            Task { await engine.load(song, at: t, autoplay: true) }
        }
    }

    private static var headphonesConnected: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
        return outputs.contains { [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0) }
    }

    // MARK: Pantalla de bloqueo / Centro de Control / Dynamic Island

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            MainActor.assumeIsolated { self?.seek(to: t) }
            return .success
        }
    }

    func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let song = current else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if song.hasArtwork, let image = UIImage(contentsOfFile: MediaFiles.artworkURL(for: song.id).path) {
            info[MPMediaItemPropertyArtwork] = Self.artwork(image)
        }
        center.nowPlayingInfo = info
    }

    /// Fuera del actor principal: el sistema pide la imagen desde otro hilo.
    private nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: Guardar / restaurar

    private struct SavedState: Codable {
        var currentId: String?
        var position: Double
        var queue: [String]
        var ctxIds: [String]
        var ctxName: String
        var shuffle: Bool
        var repeatMode: RepeatMode
    }

    private static let stateKey = "sf.player"

    func saveState() {
        let s = SavedState(
            currentId: currentId, position: clock.position, queue: queue, ctxIds: ctxIds,
            ctxName: ctxName, shuffle: shuffle, repeatMode: repeatMode
        )
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    private func restoreState() {
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let s = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        currentId = s.currentId.flatMap { library.song($0) != nil ? $0 : nil }
        clock.position = currentId == nil ? 0 : s.position
        queue = s.queue
        ctxIds = s.ctxIds
        ctxName = s.ctxName
        shuffle = s.shuffle
        repeatMode = s.repeatMode
    }
}
