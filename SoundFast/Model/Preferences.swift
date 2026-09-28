import SwiftUI

struct Look: Codable, Equatable {
    var accent = "ambar"
    var theme = "grafito"
    /// suave · intenso · tema
    var npBg = "suave"
    /// redondeada · cuadrada · circulo
    var artShape = "redondeada"
    /// circulo · cuadrado
    var playShape = "circulo"
}

struct PlaybackSettings: Codable, Equatable {
    /// Segundos de fundido entre canciones (0 = apagado).
    var crossfade = 0
    var gapless = true
    var headphones = true
    var swipeArt = true
    var haptics = true
    var showAz = true
    /// onda · linea
    var seekStyle = "onda"
    /// titulo · artista · album · fecha · duracion
    var sortBy = "titulo"
    var sortAscending = true

    static let sortOptions: [(id: String, name: String, icon: String)] = [
        ("titulo", "Título", "textformat"),
        ("artista", "Artista", "person"),
        ("album", "Álbum", "square.stack"),
        ("fecha", "Fecha de incorporación", "calendar"),
        ("duracion", "Duración", "clock"),
    ]

    init() {}

    /// Tolerante: si falta una clave (versión anterior), usa el valor por defecto
    /// en vez de perder todos los ajustes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlaybackSettings()
        crossfade = try c.decodeIfPresent(Int.self, forKey: .crossfade) ?? d.crossfade
        gapless = try c.decodeIfPresent(Bool.self, forKey: .gapless) ?? d.gapless
        headphones = try c.decodeIfPresent(Bool.self, forKey: .headphones) ?? d.headphones
        swipeArt = try c.decodeIfPresent(Bool.self, forKey: .swipeArt) ?? d.swipeArt
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        showAz = try c.decodeIfPresent(Bool.self, forKey: .showAz) ?? d.showAz
        seekStyle = try c.decodeIfPresent(String.self, forKey: .seekStyle) ?? d.seekStyle
        sortBy = try c.decodeIfPresent(String.self, forKey: .sortBy) ?? d.sortBy
        sortAscending = try c.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? d.sortAscending
        if sortBy == "recientes" {
            sortBy = "fecha"
            sortAscending = false
        }
    }
}

/// Efectos de fondo en la pantalla de reproducción.
struct VisualSettings: Codable, Equatable {
    var enabled = true
    /// aurora · liquido · ondas · particulas · espectro · remolino
    var style = "aurora"
    /// portada · acento · arcoiris · fuego · oceano · neon
    var palette = "portada"
    /// 0…1
    var intensity = 0.7
    /// 0…1
    var speed = 0.5
    /// Se mueve con el ritmo de la canción.
    var reactive = true

    static let styles: [(id: String, name: String, icon: String)] = [
        ("aurora", "Aurora", "sparkles"),
        ("liquido", "Líquido", "drop.fill"),
        ("ondas", "Ondas", "dot.radiowaves.left.and.right"),
        ("particulas", "Partículas", "circle.hexagongrid.fill"),
        ("espectro", "Espectro", "waveform"),
        ("remolino", "Remolino", "tornado"),
    ]

    static let palettes: [(id: String, name: String)] = [
        ("portada", "Portada"),
        ("acento", "Acento"),
        ("arcoiris", "Arcoíris"),
        ("fuego", "Fuego"),
        ("oceano", "Océano"),
        ("neon", "Neón"),
    ]
}

struct SoundSettings: Codable, Equatable {
    static let bandFrequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let bassFrequencies: [Double] = [40, 60, 80, 120]
    /// Nombre y efecto de cada punto de graves.
    static let bassFrequencyInfo: [Double: (name: String, detail: String)] = [
        40: ("Sub", "El retumbe profundo que se siente más de lo que se oye. Ideal para audífonos con buenos bajos."),
        60: ("Profundo", "Bajo grueso y redondo: bombo y línea de bajo con peso."),
        80: ("Golpe", "El golpe del bombo: bajos con más pegada y ritmo."),
        120: ("Cuerpo", "Calidez y cuerpo; se nota incluso en el altavoz del iPhone."),
    ]
    /// Forma del refuerzo de graves (debe coincidir con el motor de audio).
    static let bassBellWidth = 1.1          // octavas
    static let bassBellShare = 0.85         // parte del refuerzo en la campana
    static let bassShelfShare = 0.45        // parte en el estante por debajo
    static let bassShelfRatio = 0.6         // el estante empieza por debajo del punto
    static let presetOrder = ["Plano", "Rock", "Pop", "Electrónica", "Vocal", "Acústica", "Noche"]
    static let presets: [String: [Double]] = [
        "Plano": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Rock": [4, 3, 1, -1, -2, -1, 1, 3, 4, 4],
        "Pop": [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2],
        "Electrónica": [5, 4, 1, 0, -2, 1, 0, 1, 4, 5],
        "Vocal": [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
        "Acústica": [3, 2, 1, 1, 2, 2, 3, 2, 2, 1],
        "Noche": [2, 1, 0, -1, -1, 0, -1, -3, -4, -5],
    ]
    static let custom = "Personalizado"

    var eqOn = true
    var preset = "Plano"
    var bands: [Double] = Array(repeating: 0, count: 10)
    /// 0…100 → hasta +12 dB
    var bass: Double = 40
    var bassFreq: Double = 60
    /// 0…100 → hasta +8 dB
    var treble: Double = 10

    var bassDb: Double { bass * 0.12 }
    var trebleDb: Double { treble * 0.08 }

    var isModified: Bool { bass > 0 || treble > 0 || (eqOn && preset != "Plano") }

    /// Ganancia total aproximada (dB) a una frecuencia: la misma curva que dibuja el prototipo.
    func gain(at f: Double) -> Double { bandGain(at: f) + bassGain(at: f) + trebleGain(at: f) }

    func bassGain(at f: Double) -> Double {
        let octaves = log2(f / bassFreq)
        let sigma = SoundSettings.bassBellWidth / 2.355   // ancho → desviación de la campana
        let bell = exp(-(octaves * octaves) / (2 * sigma * sigma))
        let shelf = 1 / (1 + pow(f / (bassFreq * SoundSettings.bassShelfRatio), 4))
        return bassDb * (SoundSettings.bassBellShare * bell + SoundSettings.bassShelfShare * shelf)
    }

    func trebleGain(at f: Double) -> Double { trebleDb * (1 - 1 / (1 + pow(f / 5000, 2))) }

    func bandGain(at f: Double) -> Double {
        guard eqOn else { return 0 }
        let b = SoundSettings.bandFrequencies
        let x = log10(f)
        if x <= log10(b[0]) { return bands[0] }
        if x >= log10(b[9]) { return bands[9] }
        for i in 0..<9 {
            let a = log10(b[i]), c = log10(b[i + 1])
            if x <= c {
                let t = (x - a) / (c - a)
                let tt = (1 - cos(t * .pi)) / 2
                return bands[i] + (bands[i + 1] - bands[i]) * tt
            }
        }
        return 0
    }

    /// Pico de la curva, para bajar la ganancia general y no saturar.
    var peakGain: Double {
        var peak = 0.0
        for k in 0...60 {
            let f = pow(10, log10(20) + (log10(20000) - log10(20)) * Double(k) / 60)
            peak = max(peak, gain(at: f))
        }
        return peak
    }
}

/// Preferencias guardadas en el iPhone (apariencia, reproducción y sonido).
@MainActor
final class Preferences: ObservableObject {
    @Published var look: Look { didSet { save("look", look) } }
    @Published var playback: PlaybackSettings {
        didSet {
            save("playback", playback)
            Haptics.enabled = playback.haptics
        }
    }
    @Published var sound: SoundSettings { didSet { save("sound", sound) } }
    @Published var visuals: VisualSettings { didSet { save("visuals", visuals) } }

    init() {
        look = Preferences.load("look") ?? Look()
        playback = Preferences.load("playback") ?? PlaybackSettings()
        sound = Preferences.load("sound") ?? SoundSettings()
        visuals = Preferences.load("visuals") ?? VisualSettings()
        Haptics.enabled = playback.haptics
    }

    var accent: Accent { Accent.named(look.accent) }
    var theme: AppTheme { AppTheme.named(look.theme) }

    func resetLook() { look = Look() }

    func resetSound() {
        var s = sound
        s.bands = SoundSettings.presets["Plano"]!
        s.preset = "Plano"
        s.bass = 0
        s.treble = 0
        s.eqOn = true
        sound = s
    }

    func applyPreset(_ name: String) {
        guard let values = SoundSettings.presets[name] else { return }
        var s = sound
        s.preset = name
        s.bands = values
        s.eqOn = true
        sound = s
    }

    func setBand(_ index: Int, _ value: Double) {
        guard sound.bands[index] != value else { return }
        var s = sound
        s.bands[index] = value
        s.preset = SoundSettings.custom
        s.eqOn = true
        sound = s
    }

    private static let prefix = "sf.prefs."

    private func save<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Preferences.prefix + key)
        }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
