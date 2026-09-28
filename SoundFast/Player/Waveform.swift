import AVFoundation
import ImageIO
import SwiftUI
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
///
/// Hay dos tamaños a propósito: las filas de la lista y el minirreproductor usan
/// una miniatura, porque tener en memoria cientos de portadas a tamaño completo
/// (y dejar que el sistema las encoja en cada cuadro) hacía pesado el scroll.
@MainActor
final class ArtworkStore: ObservableObject {
    /// Lado máximo de la miniatura, en píxeles: 64 pt a 3× de un iPhone Pro.
    static let thumbPixels: CGFloat = 192
    /// Hasta este tamaño en puntos se usa la miniatura.
    static let thumbLimit: CGFloat = 80

    private let full = NSCache<NSString, UIImage>()
    private let thumbs = NSCache<NSString, UIImage>()
    private var palettes: [String: [Color]] = [:]
    /// Sube cuando una portada cambia, para que las vistas la vuelvan a cargar.
    @Published private(set) var revision: [String: Int] = [:]

    init() {
        // Las grandes solo hacen falta en "Sonando ahora": con unas pocas basta.
        full.countLimit = 8
        thumbs.countLimit = 500
    }

    func invalidate(_ songId: String) {
        full.removeObject(forKey: songId as NSString)
        thumbs.removeObject(forKey: songId as NSString)
        palettes[songId] = nil
        revision[songId, default: 0] += 1
    }

    private func box(_ size: CGFloat) -> NSCache<NSString, UIImage> {
        size <= Self.thumbLimit ? thumbs : full
    }

    func cached(_ song: Song, size: CGFloat) -> UIImage? {
        guard song.hasArtwork else { return nil }
        return box(size).object(forKey: song.id as NSString)
    }

    func load(_ song: Song, size: CGFloat) async -> UIImage? {
        guard song.hasArtwork else { return nil }
        let cache = box(size)
        if let image = cache.object(forKey: song.id as NSString) { return image }
        let path = MediaFiles.artworkURL(for: song.id).path
        let small = size <= Self.thumbLimit
        let maxPixels = Self.thumbPixels
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            small ? ArtworkStore.thumbnail(path: path, maxPixels: maxPixels)
                  : UIImage(contentsOfFile: path)?.preparingForDisplay()
        }.value
        if let image { cache.setObject(image, forKey: song.id as NSString) }
        return image
    }

    /// Decodifica directamente al tamaño pedido (ImageIO), sin pasar por la
    /// imagen completa: mucho más rápido y con mucha menos memoria.
    private nonisolated static func thumbnail(path: String, maxPixels: CGFloat) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Colores dominantes de la portada, para los efectos de fondo.
    /// Le basta la miniatura: de todos modos se reduce a 24×24 para contarlos.
    func palette(_ song: Song) async -> [Color] {
        if let p = palettes[song.id] { return p }
        guard let image = await load(song, size: Self.thumbLimit) else { return [] }
        let colors = await Task.detached(priority: .utility) {
            EffectPalette.dominant(from: image)
        }.value
        palettes[song.id] = colors
        return colors
    }
}
