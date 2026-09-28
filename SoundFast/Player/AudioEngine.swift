import AVFoundation
import AudioToolbox

/// Motor de audio: dos "platos" (para los fundidos) → ganancia por plato
/// (normalizar volumen) → mezclador → ecualizador (10 bandas + graves + agudos)
/// → limitador → salida.
///
/// Todo corre en el hilo principal; un temporizador revisa la posición para
/// detectar el cambio de canción, llevar los fundidos y precargar la siguiente
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
    private(set) var normalize = false

    private(set) var isPlaying = false
    private(set) var currentSongId: String?

    /// Volumen y frecuencias de lo que suena, para los efectos visuales.
    let analyzer = AudioAnalyzer()
    /// Volumen medido de cada canción, para normalizar.
    let loudness = LoudnessStore()

    /// Fundido al cambiar de canción a mano: la que sale se apaga despacio
    /// mientras la nueva entra. Más largo si el usuario usa fundido entre canciones.
    private var skipFadeOut: Double { crossfade > 0 ? min(2.0, max(1.0, crossfade * 0.4)) : 1.0 }
    private var skipFadeIn: Double { skipFadeOut * 0.55 }
    /// Plato que sigue sonando completo mientras se abre la canción nueva;
    /// empieza a apagarse justo cuando la nueva arranca (sin hueco en medio).
    private var pendingOut: Deck?

    // MARK: Grafo

    private let engine = AVAudioEngine()
    private let mix = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 13)
    private let limiter: AVAudioUnitEffect
    private let decks = [Deck(bus: 0), Deck(bus: 1)]
    private var activeIndex = 0
    private var active: Deck { decks[activeIndex] }
    private var other: Deck { decks[1 - activeIndex] }

    // MARK: Estado

    private var currentFile: AVAudioFile?
    private var currentGain: Float = 0
    private var pausedTime: Double = 0
    private var lastTime: Double = 0
    private var generation = 0
    private var timer: Timer?
    /// Abriendo un archivo: no confundir el silencio con "se acabó la canción".
    private var isLoading = false

    private struct FadeOut {
        let deck: Deck
        let start: Date
        let duration: Double
        let from: Float
    }
    private var fadeOut: FadeOut?
    private var fadeIn: (start: Date, duration: Double)?

    /// Evita pedir la siguiente canción más de una vez por pista.
    private var lookaheadDoneFor: Int?
    private var itemSerial = 0
    private var lookaheadBusy = false

    private final class Deck {
        let node = AVAudioPlayerNode()
        /// Solo para la ganancia de normalización (globalGain admite subir, no solo bajar).
        let gain = AVAudioUnitEQ(numberOfBands: 1)
        let bus: AVAudioNodeBus
        var items: [Item] = []
        var format: AVAudioFormat?

        init(bus: AVAudioNodeBus) {
            self.bus = bus
            gain.bands[0].bypass = true
        }
    }

    private struct Item {
        let serial: Int
        let songId: String
        let file: AVAudioFile
        let gainDb: Float
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
        for deck in decks {
            engine.attach(deck.node)
            engine.attach(deck.gain)
        }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(mix, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        for deck in decks {
            engine.connect(deck.node, to: deck.gain, format: nil)
            engine.connect(deck.gain, to: mix, fromBus: 0, toBus: deck.bus, format: nil)
        }

        for (i, f) in SoundSettings.bandFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = Float(f)
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        // Graves: campana centrada en el punto elegido + estante por debajo.
        eq.bands[10].filterType = .parametric
        eq.bands[10].bandwidth = Float(SoundSettings.bassBellWidth)
        eq.bands[12].filterType = .lowShelf
        eq.bands[11].filterType = .highShelf
        eq.bands[11].frequency = 5000

        Self.installTap(on: engine.mainMixerNode, analyzer: analyzer)

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    /// Fuera del actor principal: el bloque corre en el hilo de audio.
    private nonisolated static func installTap(on node: AVAudioNode, analyzer: AudioAnalyzer) {
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            analyzer.process(buffer)
        }
    }

    // MARK: Ecualizador

    func apply(_ s: SoundSettings) {
        for i in 0..<10 {
            eq.bands[i].gain = Float(s.bands[i])
            eq.bands[i].bypass = !s.eqOn
        }
        let bell = eq.bands[10]
        bell.frequency = Float(s.bassFreq)
        bell.gain = Float(min(24, s.bassDb * SoundSettings.bassBellShare))
        bell.bypass = s.bass <= 0

        let shelf = eq.bands[12]
        shelf.frequency = Float(s.bassFreq * SoundSettings.bassShelfRatio)
        shelf.gain = Float(min(24, s.bassDb * SoundSettings.bassShelfShare))
        shelf.bypass = s.bass <= 0

        let treble = eq.bands[11]
        treble.gain = Float(s.trebleDb)
        treble.bypass = s.treble <= 0

        // Poco margen: el limitador atrapa los picos y así el refuerzo se siente completo.
        eq.globalGain = -Float(max(0, s.peakGain) * 0.15)
    }

    // MARK: Normalizar volumen

    func setNormalize(_ on: Bool) {
        guard on != normalize else { return }
        normalize = on
        guard let id = currentSongId else { return }
        if on {
            if let g = loudness.cached(id) {
                currentGain = g
                active.gain.globalGain = g
            }
        } else {
            currentGain = 0
            for deck in decks { deck.gain.globalGain = 0 }
        }
    }

    private func gain(for song: Song, url: URL) async -> Float {
        guard normalize else { return 0 }
        return await loudness.gain(for: song.id, url: url)
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
    /// Con `transition`, si ya sonaba algo, la canción anterior se desvanece
    /// mientras entra la nueva (cambio manual suave).
    func load(_ song: Song, at time: Double = 0, autoplay: Bool, transition: Bool = false) async {
        generation += 1
        let gen = generation
        let smooth = transition && autoplay && isPlaying && (!active.items.isEmpty || pendingOut != nil)

        if smooth {
            if !active.items.isEmpty {
                // Lo que suena ahora queda sonando hasta que la nueva esté lista.
                if let previous = pendingOut, previous !== active {
                    previous.node.stop()
                    previous.items.removeAll()
                    previous.node.volume = 1
                }
                pendingOut = active
                activeIndex = 1 - activeIndex
                if let f = fadeOut, f.deck === active { fadeOut = nil }
                active.node.stop()
                active.items.removeAll()
                active.node.volume = 1
            }
            // (Si ya había una esperando por un cambio rápido anterior, se mantiene.)
            fadeIn = nil
            lookaheadDoneFor = nil
            lookaheadBusy = false
        } else {
            stopDecks()
            stopTimer()
        }
        isLoading = true
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
            // Normalizar sin demorar el arranque: si aún no se midió, se mide
            // en segundo plano y se aplica al terminar.
            let cachedGain = normalize ? loudness.cached(song.id) : 0
            currentFile = file
            currentGain = cachedGain ?? 0
            isLoading = false
            // Si se pausó mientras cargaba, isPlaying ya es false.
            if isPlaying { try start(from: pausedTime, fadeIn: smooth ? skipFadeIn : 0) }
            if cachedGain == nil { measureLater(song, url: url, generation: gen) }
        } catch {
            guard gen == generation else { return }
            isLoading = false
            isPlaying = false
            stopDecks()
            onError?(error)
        }
    }

    private func measureLater(_ song: Song, url: URL, generation gen: Int) {
        Task { [weak self] in
            guard let self else { return }
            let g = await self.loudness.gain(for: song.id, url: url)
            guard gen == self.generation, self.normalize, self.currentSongId == song.id else { return }
            self.currentGain = g
            self.active.gain.globalGain = g
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
        guard isPlaying, !isLoading else { return }
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
        isLoading = false
        currentFile = nil
        currentSongId = nil
        isPlaying = false
        pausedTime = 0
    }

    // MARK: Interno

    private func start(from time: Double, fadeIn inDuration: Double = 0) throws {
        guard let file = currentFile, let id = currentSongId else { return }
        let deck = active
        deck.node.stop()
        deck.items.removeAll()
        if let out = pendingOut {
            pendingOut = nil
            if inDuration > 0 {
                // Ahora sí: la anterior se apaga mientras esta entra.
                beginFadeOut(out, duration: skipFadeOut)
            } else {
                out.node.stop()
                out.items.removeAll()
                out.node.volume = 1
            }
        }
        if inDuration == 0 { stopFadeOut() }
        connect(deck, format: file.processingFormat)
        deck.gain.globalGain = currentGain
        try startEngine()
        schedule(file, songId: id, gainDb: currentGain, from: time, on: deck)
        deck.node.volume = inDuration > 0 ? 0 : 1
        fadeIn = inDuration > 0 ? (Date(), inDuration) : nil
        deck.node.play()
        isPlaying = true
        lastTime = time
        lookaheadDoneFor = nil
        lookaheadBusy = false
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
        engine.disconnectNodeOutput(deck.gain)
        engine.connect(deck.node, to: deck.gain, format: format)
        engine.connect(deck.gain, to: mix, fromBus: 0, toBus: deck.bus, format: format)
        deck.format = format
    }

    private func schedule(_ file: AVAudioFile, songId: String, gainDb: Float, from time: Double, on deck: Deck) {
        let rate = file.processingFormat.sampleRate
        let length = max(1, file.length)
        let start = min(max(0, AVAudioFramePosition(time * rate)), length - 1)
        let frames = AVAudioFrameCount(max(1, length - start))
        let nodeStart = deck.items.last?.nodeEnd ?? 0
        deck.node.scheduleSegment(file, startingFrame: start, frameCount: frames, at: nil, completionHandler: nil)
        itemSerial += 1
        deck.items.append(Item(
            serial: itemSerial, songId: songId, file: file, gainDb: gainDb,
            startFrame: start, frames: frames, nodeStart: nodeStart
        ))
    }

    private func stopDecks() {
        for deck in decks {
            deck.node.stop()
            deck.items.removeAll()
            deck.node.volume = 1
        }
        pendingOut = nil
        fadeOut = nil
        fadeIn = nil
        lookaheadDoneFor = nil
        lookaheadBusy = false
    }

    private func beginFadeOut(_ deck: Deck, duration: Double) {
        if let current = fadeOut, current.deck !== deck {
            current.deck.node.stop()
            current.deck.items.removeAll()
            current.deck.node.volume = 1
        }
        fadeOut = FadeOut(deck: deck, start: Date(), duration: duration, from: deck.node.volume)
    }

    private func stopFadeOut() {
        guard let f = fadeOut else { return }
        f.deck.node.stop()
        f.deck.items.removeAll()
        f.deck.node.volume = 1
        fadeOut = nil
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
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
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
        updateFades()
        guard isPlaying, !isLoading else { return }

        let deck = active
        guard let loc = locate(deck) else {
            // Se acabó todo lo programado en el plato activo.
            guard fadeOut == nil, !lookaheadBusy else { return }
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
            currentGain = item.gainDb
            deck.gain.globalGain = item.gainDb
            onAdvance?(item.songId)
        }

        guard item.serial == deck.items.last?.serial else { return }
        let remaining = Double(Int64(item.frames) - (frame - item.startFrame)) / item.rate
        guard lookaheadDoneFor != item.serial, !lookaheadBusy else { return }

        if crossfade > 0, fadeOut == nil, remaining <= crossfade {
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
                  let file = try? AVAudioFile(forReading: url) else { return }
            let g = await self.gain(for: next, url: url)
            guard gen == self.generation, self.isPlaying, deck === self.active,
                  let format = deck.format,
                  format.sampleRate == file.processingFormat.sampleRate,
                  format.channelCount == file.processingFormat.channelCount
            else { return }
            // Mismo formato: se encadena en el mismo plato, sin corte.
            self.schedule(file, songId: next.id, gainDb: g, from: 0, on: deck)
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
                  let file = try? AVAudioFile(forReading: url) else { return }
            let g = await self.gain(for: next, url: url)
            guard gen == self.generation, self.isPlaying, self.fadeOut == nil else { return }

            let old = self.active
            var remaining = 0.5
            if let loc = self.locate(old) {
                remaining = max(0.5, Double(Int64(loc.item.frames) - (loc.frame - loc.item.startFrame)) / loc.item.rate)
            }
            let duration = min(self.crossfade, remaining)

            let incoming = self.other
            incoming.node.stop()
            incoming.items.removeAll()
            self.connect(incoming, format: file.processingFormat)
            incoming.gain.globalGain = g
            self.schedule(file, songId: next.id, gainDb: g, from: 0, on: incoming)
            incoming.node.volume = 0
            incoming.node.play()

            self.beginFadeOut(old, duration: duration)
            self.activeIndex = 1 - self.activeIndex
            self.fadeIn = (Date(), duration)
            self.currentSongId = next.id
            self.currentFile = file
            self.currentGain = g
            self.lastTime = 0
            self.onAdvance?(next.id)
        }
    }

    /// Curvas de igual potencia: el volumen total no "se hunde" a mitad del fundido.
    private func updateFades() {
        let now = Date()
        if let f = fadeOut {
            let p = min(1, now.timeIntervalSince(f.start) / max(0.05, f.duration))
            f.deck.node.volume = f.from * Float(cos(p * .pi / 2))
            if p >= 1 {
                f.deck.node.stop()
                f.deck.items.removeAll()
                f.deck.node.volume = 1
                fadeOut = nil
            }
        }
        if let f = fadeIn {
            let p = min(1, now.timeIntervalSince(f.start) / max(0.05, f.duration))
            active.node.volume = Float(sin(p * .pi / 2))
            if p >= 1 {
                active.node.volume = 1
                fadeIn = nil
            }
        }
    }

    private func handleConfigurationChange() {
        // Cambió la salida (auriculares, Bluetooth, AirPlay): el motor se detuvo.
        guard isPlaying, !isLoading else { return }
        let t = lastTime
        for deck in decks { deck.format = nil }
        stopFadeOut()
        do {
            pausedTime = t
            try start(from: t)
        } catch {
            isPlaying = false
            onError?(error)
        }
    }
}

// MARK: - Volumen de cada canción

/// Mide qué tan fuerte suena cada canción (una sola vez) y calcula cuánto
/// subirla o bajarla para que todas suenen parejo.
final class LoudnessStore: @unchecked Sendable {
    /// Nivel objetivo (RMS con compuerta, dBFS).
    static let target: Float = -13
    static let maxBoost: Float = 8
    static let maxCut: Float = -9

    private let lock = NSLock()
    private var cache: [String: Float] = [:]
    private var saveScheduled = false

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("loudness.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([String: Float].self, from: data) {
            cache = saved
        }
    }

    func cached(_ songId: String) -> Float? {
        lock.withLock { cache[songId] }
    }

    var measuredCount: Int { lock.withLock { cache.count } }

    /// Ganancia en dB para esta canción (la mide si hace falta).
    func gain(for songId: String, url: URL) async -> Float {
        if let g = cached(songId) { return g }
        let g = await Task.detached(priority: .userInitiated) { LoudnessStore.analyze(url) }.value
        guard let g else { return 0 }
        lock.withLock { cache[songId] = g }
        save()
        return g
    }

    private func save() {
        let snapshot = lock.withLock { cache }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    /// RMS de ~90 ventanas repartidas por la canción, ignorando silencios
    /// y pasajes muy bajos (parecido a como se mide la sonoridad en streaming).
    static func analyze(_ url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let rate = file.processingFormat.sampleRate
        let window = AVAudioFrameCount(min(32768, max(4096, rate * 0.4)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: window) else { return nil }
        let total = file.length
        let count = 90
        var levels: [Float] = []

        for i in 0..<count {
            let center = AVAudioFramePosition(Double(total) * (Double(i) + 0.5) / Double(count))
            file.framePosition = max(0, min(total - AVAudioFramePosition(window), center - AVAudioFramePosition(window / 2)))
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: window)) != nil,
                  let data = buffer.floatChannelData, buffer.frameLength > 0 else { continue }
            let channels = Int(buffer.format.channelCount)
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for c in 0..<min(2, channels) {
                let ch = data[c]
                for j in 0..<n { sum += ch[j] * ch[j] }
            }
            let ms = sum / Float(n * min(2, channels))
            if ms > 0 { levels.append(10 * log10(ms)) }
        }

        // Compuerta absoluta (silencios) y relativa (pasajes 10 dB por debajo del promedio).
        let loud = levels.filter { $0 > -50 }
        guard !loud.isEmpty else { return nil }
        let mean = 10 * log10(loud.map { pow(10, $0 / 10) }.reduce(0, +) / Float(loud.count))
        let gated = loud.filter { $0 > mean - 10 }
        let level = 10 * log10(gated.map { pow(10, $0 / 10) }.reduce(0, +) / Float(max(1, gated.count)))
        return min(maxBoost, max(maxCut, target - level))
    }
}
