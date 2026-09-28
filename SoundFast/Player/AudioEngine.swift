import AVFoundation
import AudioToolbox

/// Motor de audio: dos "platos" (para el fundido entre canciones) → mezclador →
/// ecualizador (10 bandas + graves + agudos) → limitador → salida.
///
/// Todo corre en el hilo principal; un temporizador revisa la posición para
/// detectar el cambio de canción, iniciar fundidos y precargar la siguiente
/// (reproducción sin pausas).
@MainActor
final class AudioEngine {
    // MARK: Callbacks hacia el controlador

    /// La canción cambió sola (sin pausas o por fundido).
    var onAdvance: (@MainActor (String) -> Void)?
    /// Terminó la canción y no había nada precargado.
    var onTrackEnd: (@MainActor () -> Void)?
    /// Qué canción sigue automáticamente (respeta repetir y cola).
    var nextSong: (@MainActor () -> Song?)?
    var onError: (@MainActor (Error) -> Void)?

    var crossfade: Double = 0
    var gapless = true

    private(set) var isPlaying = false
    private(set) var currentSongId: String?

    // MARK: Grafo

    private let engine = AVAudioEngine()
    private let mix = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 12)
    private let limiter: AVAudioUnitEffect
    private let decks = [Deck(bus: 0), Deck(bus: 1)]
    private var activeIndex = 0
    private var active: Deck { decks[activeIndex] }
    private var other: Deck { decks[1 - activeIndex] }

    // MARK: Estado

    private var currentFile: AVAudioFile?
    private var pausedTime: Double = 0
    private var lastTime: Double = 0
    private var generation = 0
    private var timer: Timer?

    private var fading: Deck?
    private var fadeStart = Date()
    private var fadeDuration: Double = 0

    /// Evita pedir la siguiente canción más de una vez por pista.
    private var lookaheadDoneFor: Int?
    private var itemSerial = 0
    private var lookaheadBusy = false

    private final class Deck {
        let node = AVAudioPlayerNode()
        let bus: AVAudioNodeBus
        var items: [Item] = []
        var format: AVAudioFormat?

        init(bus: AVAudioNodeBus) { self.bus = bus }
    }

    private struct Item {
        let serial: Int
        let songId: String
        let file: AVAudioFile
        let startFrame: AVAudioFramePosition
        let frames: AVAudioFrameCount
        let nodeStart: AVAudioFramePosition
        var nodeEnd: AVAudioFramePosition { nodeStart + AVAudioFramePosition(frames) }
        var rate: Double { file.processingFormat.sampleRate }
    }

    init() {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)

        engine.attach(mix)
        engine.attach(eq)
        engine.attach(limiter)
        for deck in decks { engine.attach(deck.node) }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(mix, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        for deck in decks {
            engine.connect(deck.node, to: mix, fromBus: 0, toBus: deck.bus, format: nil)
        }

        for (i, f) in SoundSettings.bandFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = Float(f)
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        eq.bands[10].filterType = .lowShelf
        eq.bands[11].filterType = .highShelf
        eq.bands[11].frequency = 5000

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    // MARK: Ecualizador

    func apply(_ s: SoundSettings) {
        for i in 0..<10 {
            eq.bands[i].gain = Float(s.bands[i])
            eq.bands[i].bypass = !s.eqOn
        }
        let bass = eq.bands[10]
        bass.frequency = Float(s.bassFreq)
        bass.gain = Float(s.bassDb)
        bass.bypass = s.bass <= 0

        let treble = eq.bands[11]
        treble.gain = Float(s.trebleDb)
        treble.bypass = s.treble <= 0

        // Margen para que el refuerzo no sature; el limitador atrapa el resto.
        eq.globalGain = -Float(max(0, s.peakGain) * 0.6)
    }

    // MARK: Control

    /// Tiempo actual de la canción en segundos.
    var currentTime: Double {
        guard isPlaying else { return pausedTime }
        if let loc = locate(active), loc.item.songId == currentSongId {
            return Double(loc.frame) / loc.item.rate
        }
        return lastTime
    }

    var hasLoadedSong: Bool { currentFile != nil }

    /// Abre una canción y (si `autoplay`) empieza a sonar desde `time`.
    func load(_ song: Song, at time: Double = 0, autoplay: Bool) async {
        generation += 1
        let gen = generation
        stopDecks()
        stopTimer()
        currentSongId = song.id
        currentFile = nil
        pausedTime = time
        lastTime = time
        isPlaying = autoplay

        do {
            let url = try await MediaFiles.playableURL(for: song)
            guard gen == generation else { return }
            let file = try AVAudioFile(forReading: url)
            guard gen == generation else { return }
            currentFile = file
            // Si se pausó mientras cargaba, isPlaying ya es false.
            if isPlaying { try start(from: pausedTime) }
        } catch {
            guard gen == generation else { return }
            isPlaying = false
            onError?(error)
        }
    }

    func play() {
        guard !isPlaying else { return }
        guard currentFile != nil else {
            // Aún cargando: arrancará al terminar de abrir el archivo.
            if currentSongId != nil { isPlaying = true }
            return
        }
        do {
            try start(from: pausedTime)
        } catch {
            onError?(error)
        }
    }

    func pause() {
        guard isPlaying else { return }
        pausedTime = currentTime
        isPlaying = false
        stopDecks()
        engine.pause()
        stopTimer()
    }

    func seek(to time: Double) {
        pausedTime = max(0, time)
        lastTime = pausedTime
        guard isPlaying else { return }
        do {
            try start(from: pausedTime)
        } catch {
            onError?(error)
        }
    }

    /// Libera la canción actual (por ejemplo, si se borró).
    func unload() {
        generation += 1
        stopDecks()
        engine.pause()
        stopTimer()
        currentFile = nil
        currentSongId = nil
        isPlaying = false
        pausedTime = 0
    }

    // MARK: Interno

    private func start(from time: Double) throws {
        guard let file = currentFile, let id = currentSongId else { return }
        stopDecks()
        let deck = active
        connect(deck, format: file.processingFormat)
        try startEngine()
        schedule(file, songId: id, from: time, on: deck)
        deck.node.volume = 1
        deck.node.play()
        isPlaying = true
        lastTime = time
        startTimer()
    }

    private func startEngine() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func connect(_ deck: Deck, format: AVAudioFormat) {
        if let current = deck.format,
           current.sampleRate == format.sampleRate,
           current.channelCount == format.channelCount {
            return
        }
        engine.disconnectNodeOutput(deck.node)
        engine.connect(deck.node, to: mix, fromBus: 0, toBus: deck.bus, format: format)
        deck.format = format
    }

    private func schedule(_ file: AVAudioFile, songId: String, from time: Double, on deck: Deck) {
        let rate = file.processingFormat.sampleRate
        let length = max(1, file.length)
        let start = min(max(0, AVAudioFramePosition(time * rate)), length - 1)
        let frames = AVAudioFrameCount(max(1, length - start))
        let nodeStart = deck.items.last?.nodeEnd ?? 0
        deck.node.scheduleSegment(file, startingFrame: start, frameCount: frames, at: nil, completionHandler: nil)
        itemSerial += 1
        deck.items.append(Item(serial: itemSerial, songId: songId, file: file, startFrame: start, frames: frames, nodeStart: nodeStart))
    }

    private func stopDecks() {
        for deck in decks {
            deck.node.stop()
            deck.items.removeAll()
            deck.node.volume = 1
        }
        fading = nil
        lookaheadDoneFor = nil
        lookaheadBusy = false
    }

    /// Qué pista suena en un plato y en qué cuadro del archivo va.
    private func locate(_ deck: Deck) -> (item: Item, frame: AVAudioFramePosition)? {
        guard let first = deck.items.first else { return nil }
        guard let nodeTime = deck.node.lastRenderTime,
              let playerTime = deck.node.playerTime(forNodeTime: nodeTime) else {
            return (first, first.startFrame)
        }
        let s = max(0, playerTime.sampleTime)
        for item in deck.items where s < item.nodeEnd {
            if s >= item.nodeStart {
                return (item, item.startFrame + (s - item.nodeStart))
            }
        }
        return nil
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isPlaying else { return }
        updateFade()

        let deck = active
        guard let loc = locate(deck) else {
            // Se acabó todo lo programado en el plato activo.
            guard fading == nil, !lookaheadBusy else { return }
            isPlaying = false
            pausedTime = 0
            stopDecks()
            stopTimer()
            onTrackEnd?()
            return
        }

        let item = loc.item
        let frame = loc.frame
        lastTime = Double(frame) / item.rate
        if item.songId != currentSongId {
            // Entró la canción precargada (sin pausas).
            currentSongId = item.songId
            currentFile = item.file
            onAdvance?(item.songId)
        }

        guard item.serial == deck.items.last?.serial else { return }
        let remaining = Double(Int64(item.frames) - (frame - item.startFrame)) / item.rate
        guard lookaheadDoneFor != item.serial, !lookaheadBusy else { return }

        if crossfade > 0, fading == nil, remaining <= crossfade {
            beginCrossfade(after: item)
        } else if crossfade == 0, gapless, remaining <= 8 {
            preloadGapless(after: item, on: deck)
        }
    }

    private func preloadGapless(after item: Item, on deck: Deck) {
        lookaheadBusy = true
        lookaheadDoneFor = item.serial
        let gen = generation
        guard let next = nextSong?() else {
            lookaheadBusy = false
            return
        }
        Task { [weak self] in
            guard let self else { return }
            defer { self.lookaheadBusy = false }
            guard let url = try? await MediaFiles.playableURL(for: next),
                  let file = try? AVAudioFile(forReading: url),
                  gen == self.generation, self.isPlaying, deck === self.active,
                  let format = deck.format,
                  format.sampleRate == file.processingFormat.sampleRate,
                  format.channelCount == file.processingFormat.channelCount
            else { return }
            // Mismo formato: se encadena en el mismo plato, sin corte.
            self.schedule(file, songId: next.id, from: 0, on: deck)
        }
    }

    private func beginCrossfade(after item: Item) {
        lookaheadBusy = true
        lookaheadDoneFor = item.serial
        let gen = generation
        guard let next = nextSong?() else {
            lookaheadBusy = false
            return
        }
        Task { [weak self] in
            guard let self else { return }
            defer { self.lookaheadBusy = false }
            guard let url = try? await MediaFiles.playableURL(for: next),
                  let file = try? AVAudioFile(forReading: url),
                  gen == self.generation, self.isPlaying, self.fading == nil
            else { return }

            let old = self.active
            var remaining = 0.5
            if let loc = self.locate(old) {
                remaining = max(0.5, Double(Int64(loc.item.frames) - (loc.frame - loc.item.startFrame)) / loc.item.rate)
            }

            let incoming = self.other
            incoming.node.stop()
            incoming.items.removeAll()
            self.connect(incoming, format: file.processingFormat)
            self.schedule(file, songId: next.id, from: 0, on: incoming)
            incoming.node.volume = 0
            incoming.node.play()

            self.activeIndex = 1 - self.activeIndex
            self.fading = old
            self.fadeStart = Date()
            self.fadeDuration = min(self.crossfade, remaining)
            self.currentSongId = next.id
            self.currentFile = file
            self.lastTime = 0
            self.onAdvance?(next.id)
        }
    }

    private func updateFade() {
        guard let old = fading else { return }
        let p = min(1, Date().timeIntervalSince(fadeStart) / max(0.1, fadeDuration))
        // Curva de igual potencia: el volumen total no "se hunde" a mitad del fundido.
        active.node.volume = Float(sin(p * .pi / 2))
        old.node.volume = Float(cos(p * .pi / 2))
        if p >= 1 {
            old.node.stop()
            old.items.removeAll()
            old.node.volume = 1
            fading = nil
        }
    }

    private func handleConfigurationChange() {
        // Cambió la salida (auriculares, Bluetooth, AirPlay): el motor se detuvo.
        guard isPlaying else { return }
        let t = lastTime
        for deck in decks { deck.format = nil }
        do {
            pausedTime = t
            try start(from: t)
        } catch {
            isPlaying = false
            onError?(error)
        }
    }
}
