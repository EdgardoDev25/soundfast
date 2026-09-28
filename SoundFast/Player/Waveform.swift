import AVFoundation
import UIKit

/// Onda real de cada canción (60 barras), calculada una vez y guardada en memoria.
@MainActor
final class WaveformStore: ObservableObject {
    nonisolated static var barCount: Int { 60 }

    @Published private var cache: [String: [Double]] = [:]
    private var pending = Set<String>()

    func bars(for song: Song) -> [Double] {
        cache[song.id] ?? Self.placeholder(hue: song.hue)
    }

    func request(_ song: Song) {
        guard cache[song.id] == nil, !pending.contains(song.id) else { return }
        pending.insert(song.id)
        Task {
            let url = try? await MediaFiles.playableURL(for: song)
            let bins = Self.barCount
            let bars = await Task.detached(priority: .utility) { () -> [Double]? in
                guard let url else { return nil }
                return WaveformStore.compute(url: url, bins: bins)
            }.value
            self.cache[song.id] = bars ?? Self.placeholder(hue: song.hue)
            self.pending.remove(song.id)
        }
    }

    /// Mide el volumen (RMS) en una ventana corta al centro de cada barra.
    private nonisolated static func compute(url: URL, bins: Int) -> [Double]? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let window: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: window) else { return nil }
        let total = file.length
        var values: [Double] = []
        values.reserveCapacity(bins)

        for i in 0..<bins {
            let center = AVAudioFramePosition(Double(total) * (Double(i) + 0.5) / Double(bins))
            file.framePosition = max(0, min(total - AVAudioFramePosition(window), center - AVAudioFramePosition(window / 2)))
            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: window)
            } catch {
                values.append(0)
                continue
            }
            guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
                values.append(0)
                continue
            }
            var sum: Float = 0
            for j in 0..<Int(buffer.frameLength) { sum += data[j] * data[j] }
            values.append(Double(sqrt(sum / Float(buffer.frameLength))))
        }

        guard let peak = values.max(), peak > 0 else { return nil }
        return values.map { 0.18 + 0.82 * pow($0 / peak, 0.8) }
    }

    /// La onda decorativa del prototipo, mientras se calcula la real.
    nonisolated static func placeholder(hue: Double) -> [Double] {
        let seed = hue / 30
        return (0..<barCount).map { i in
            let x = Double(i)
            let v = abs(sin(x * 0.61 + seed) * cos(x * 0.19 + seed * 1.7)) * (0.55 + 0.45 * abs(sin(x * 1.9 + seed)))
            return (18 + 82 * v) / 100
        }
    }
}

/// Portadas guardadas en la caché, cargadas fuera del hilo principal.
@MainActor
final class ArtworkStore: ObservableObject {
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 300
    }

    func cached(_ song: Song) -> UIImage? {
        guard song.hasArtwork else { return nil }
        return cache.object(forKey: song.id as NSString)
    }

    func load(_ song: Song) async -> UIImage? {
        guard song.hasArtwork else { return nil }
        if let image = cache.object(forKey: song.id as NSString) { return image }
        let path = MediaFiles.artworkURL(for: song.id).path
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            UIImage(contentsOfFile: path)?.preparingForDisplay()
        }.value
        if let image { cache.setObject(image, forKey: song.id as NSString) }
        return image
    }
}
