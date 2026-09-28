import AVFoundation
import MediaPlayer
import UIKit
import UniformTypeIdentifiers

/// Rutas y lectura de archivos de audio.
enum MediaFiles {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac", "mp4"]

    /// Documentos de la app. Se ve en Archivos → En mi iPhone → SoundFast
    /// y en Windows desde "Dispositivos Apple" → Archivos.
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var artworkDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var exportDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func url(forRelativePath path: String) -> URL {
        documents.appendingPathComponent(path)
    }

    static func relativePath(of url: URL) -> String {
        let base = documents.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(base) {
            return String(full.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }

    /// Todos los archivos de audio dentro de Documentos (incluye subcarpetas).
    static func scanDocuments() -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in e where isAudio(url) {
            result.append(url)
        }
        return result
    }

    /// Copia un archivo elegido por el usuario dentro de Documentos, sin pisar otro con el mismo nombre.
    static func importCopy(of source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let name = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var dest = documents.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = documents.appendingPathComponent("\(name) \(n).\(ext)")
            n += 1
        }
        try fm.copyItem(at: source, to: dest)
        return dest
    }

    // MARK: Metadatos

    struct Metadata {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var artwork: Data?
    }

    static func readMetadata(_ url: URL) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var meta = fallbackMetadata(for: url)
        if let duration = try? await asset.load(.duration), duration.isNumeric {
            meta.duration = duration.seconds
        }
        var items: [AVMetadataItem] = (try? await asset.load(.commonMetadata)) ?? []
        if items.isEmpty, let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                items += (try? await asset.loadMetadata(for: format)) ?? []
            }
        }
        for item in items {
            guard let key = item.commonKey else { continue }
            if key == .commonKeyTitle {
                if let v = try? await item.load(.stringValue), !v.isEmpty { meta.title = v }
            } else if key == .commonKeyArtist {
                if let v = try? await item.load(.stringValue), !v.isEmpty { meta.artist = v }
            } else if key == .commonKeyAlbumName {
                if let v = try? await item.load(.stringValue), !v.isEmpty { meta.album = v }
            } else if key == .commonKeyArtwork, meta.artwork == nil {
                meta.artwork = try? await item.load(.dataValue)
            }
        }
        if meta.duration <= 0, let file = try? AVAudioFile(forReading: url) {
            meta.duration = Double(file.length) / file.processingFormat.sampleRate
        }
        return meta
    }

    /// "Artista - Título.mp3" → artista y título; si no, el nombre del archivo.
    private static func fallbackMetadata(for url: URL) -> Metadata {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.components(separatedBy: " - ")
        if parts.count >= 2 {
            return Metadata(
                title: parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces),
                artist: parts[0].trimmingCharacters(in: .whitespaces),
                album: "", duration: 0, artwork: nil
            )
        }
        return Metadata(title: name, artist: "Artista desconocido", album: "", duration: 0, artwork: nil)
    }

    // MARK: Portadas

    static func artworkURL(for songId: String) -> URL {
        let safe = songId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? songId
        return artworkDir.appendingPathComponent(safe + ".jpg")
    }

    /// Guarda la portada reducida a 600 px. Devuelve true si quedó guardada.
    @discardableResult
    static func saveArtwork(_ image: UIImage, for songId: String) -> Bool {
        let maxSide: CGFloat = 600
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return false }
        return (try? data.write(to: artworkURL(for: songId), options: .atomic)) != nil
    }

    // MARK: Biblioteca de Música del iPhone

    static func libraryItem(_ persistentID: UInt64) -> MPMediaItem? {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: NSNumber(value: persistentID),
            forProperty: MPMediaItemPropertyPersistentID
        ))
        return query.items?.first
    }

    /// URL que AVAudioFile puede abrir. Las canciones de la biblioteca a veces
    /// no se pueden leer directo; en ese caso se exportan una vez a la caché.
    static func playableURL(for song: Song) async throws -> URL {
        switch song.source {
        case .file(let path):
            return url(forRelativePath: path)
        case .library(let pid):
            let cached = exportDir.appendingPathComponent("\(pid).m4a")
            if FileManager.default.fileExists(atPath: cached.path) { return cached }
            guard let item = libraryItem(pid), let assetURL = item.assetURL else {
                throw PlaybackError.unavailable
            }
            if (try? AVAudioFile(forReading: assetURL)) != nil { return assetURL }
            return try await export(assetURL, to: cached)
        }
    }

    private static func export(_ assetURL: URL, to dest: URL) async throws -> URL {
        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw PlaybackError.unavailable
        }
        let tmp = dest.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".m4a")
        session.outputURL = tmp
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else { throw PlaybackError.unavailable }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}

enum PlaybackError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "No se pudo abrir la canción. Puede que ya no esté en el iPhone o que esté protegida (Apple Music)."
    }
}
