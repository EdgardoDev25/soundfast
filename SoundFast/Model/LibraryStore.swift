import Foundation
import MediaPlayer
import UIKit

/// Canciones, favoritos y listas. Se guarda en Application Support/library.json.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published var favorites: [String] = [] { didSet { scheduleSave() } }
    @Published var playlists: [Playlist] = [] { didSet { scheduleSave() } }
    @Published var onboarded = false { didSet { scheduleSave() } }
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var musicAccess = MPMediaLibrary.authorizationStatus()
    /// Mensaje corto para mostrar tras importar o actualizar.
    @Published var notice: String?

    private var sortBy = "titulo"
    private var sortAscending = true

    func setSort(by key: String, ascending: Bool) {
        guard key != sortBy || ascending != sortAscending else { return }
        sortBy = key
        sortAscending = ascending
        songs = sort(songs)
    }

    private var byId: [String: Song] = [:]
    private var saveTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var songs: [Song]
        var favorites: [String]
        var playlists: [Playlist]
        var onboarded: Bool
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    init() {
        if let data = try? Data(contentsOf: LibraryStore.fileURL),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            favorites = snap.favorites
            playlists = snap.playlists
            onboarded = snap.onboarded
            setSongs(snap.songs)
        }
    }

    // MARK: Consultas

    func song(_ id: String) -> Song? { byId[id] }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func playlist(_ id: String) -> Playlist? { playlists.first { $0.id == id } }

    var totalDuration: Double { songs.reduce(0) { $0 + $1.duration } }

    var hasMusicAccess: Bool { musicAccess == .authorized }

    // MARK: Favoritos y listas

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.append(id) }
    }

    @discardableResult
    func createPlaylist(named name: String, with songId: String? = nil) -> Playlist {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = Playlist(
            id: "p" + UUID().uuidString.prefix(8),
            name: clean.isEmpty ? "Nueva lista" : clean,
            songIds: songId.map { [$0] } ?? []
        )
        playlists.append(p)
        return p
    }

    func rename(_ playlistId: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].name = clean
    }

    func deletePlaylist(_ playlistId: String) {
        playlists.removeAll { $0.id == playlistId }
    }

    func toggle(_ songId: String, in playlistId: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if let j = playlists[i].songIds.firstIndex(of: songId) {
            playlists[i].songIds.remove(at: j)
        } else {
            playlists[i].songIds.append(songId)
        }
    }

    func movePlaylistSongs(_ playlistId: String, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].songIds.move(fromOffsets: from, toOffset: to)
    }

    // MARK: Importar y actualizar

    func requestMusicAccess() async {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
            MPMediaLibrary.requestAuthorization { cont.resume(returning: $0) }
        }
        musicAccess = status
        if status == .authorized { await refresh() }
    }

    /// Copia los archivos elegidos a Documentos y actualiza la biblioteca.
    func importFiles(_ urls: [URL]) async {
        var copied = 0
        var failed = 0
        for url in urls where MediaFiles.isAudio(url) {
            do {
                _ = try MediaFiles.importCopy(of: url)
                copied += 1
            } catch {
                failed += 1
            }
        }
        await refresh()
        if copied > 0 {
            notice = Format.count(copied, "canción importada", "canciones importadas")
                + (failed > 0 ? " · \(failed) con error" : "")
        } else if failed > 0 {
            notice = "No se pudieron importar los archivos"
        }
    }

    /// Busca canciones nuevas en Documentos y en la biblioteca de Música.
    /// Con `announce` muestra un aviso con el resultado.
    func refresh(announce: Bool = false) async {
        guard !isScanning else { return }
        let before = Set(byId.keys)
        isScanning = true
        musicAccess = MPMediaLibrary.authorizationStatus()
        let existing = byId
        let includeLibrary = musicAccess == .authorized
        let found = await Task.detached(priority: .userInitiated) {
            await LibraryScanner.scan(existing: existing, includeLibrary: includeLibrary)
        }.value
        setSongs(found)
        prune()
        isScanning = false
        lastScan = Date()
        scheduleSave()
        if announce {
            let added = found.filter { !before.contains($0.id) }.count
            let removed = before.subtracting(found.map(\.id)).count
            var parts: [String] = []
            if added > 0 { parts.append(Format.count(added, "canción nueva", "canciones nuevas")) }
            if removed > 0 { parts.append(Format.count(removed, "quitada", "quitadas")) }
            notice = parts.isEmpty ? "Biblioteca al día · no hay canciones nuevas" : "Biblioteca actualizada · " + parts.joined(separator: " · ")
        }
    }

    /// Ya hay portada guardada para esta canción (descargada de internet).
    func markArtwork(_ id: String) {
        guard var s = byId[id] else { return }
        s.hasArtwork = true
        byId[id] = s
        if let i = songs.firstIndex(where: { $0.id == id }) { songs[i] = s }
        scheduleSave()
    }

    /// Borra del iPhone una canción importada (solo archivos, no la biblioteca de Música).
    func deleteFile(_ song: Song) {
        guard case .file(let path) = song.source else { return }
        try? FileManager.default.removeItem(at: MediaFiles.url(forRelativePath: path))
        try? FileManager.default.removeItem(at: MediaFiles.artworkURL(for: song.id))
        setSongs(songs.filter { $0.id != song.id })
        prune()
        scheduleSave()
    }

    // MARK: Interno

    private func setSongs(_ list: [Song]) {
        songs = sort(list)
        byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func prune() {
        let f = favorites.filter { byId[$0] != nil }
        if f != favorites { favorites = f }
        let p = playlists.map { pl -> Playlist in
            var pl = pl
            pl.songIds = pl.songIds.filter { byId[$0] != nil }
            return pl
        }
        if p != playlists { playlists = p }
    }

    private func sort(_ list: [Song]) -> [Song] {
        let es = Locale(identifier: "es")
        func less(_ a: String, _ b: String) -> Bool {
            a.compare(b, options: [.caseInsensitive, .numeric], range: nil, locale: es) == .orderedAscending
        }
        // Siempre desempata por título, para que el orden sea estable.
        let ascending: (Song, Song) -> Bool
        switch sortBy {
        case "artista":
            ascending = {
                $0.artist.caseInsensitiveCompare($1.artist) == .orderedSame
                    ? less($0.title, $1.title) : less($0.artist, $1.artist)
            }
        case "album":
            ascending = {
                $0.album.caseInsensitiveCompare($1.album) == .orderedSame
                    ? less($0.title, $1.title) : less($0.album, $1.album)
            }
        case "fecha":
            ascending = { $0.addedAt == $1.addedAt ? less($0.title, $1.title) : $0.addedAt < $1.addedAt }
        case "duracion":
            ascending = { $0.duration == $1.duration ? less($0.title, $1.title) : $0.duration < $1.duration }
        default:
            ascending = { less($0.title, $1.title) }
        }
        return sortAscending ? list.sorted(by: ascending) : list.sorted { ascending($1, $0) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snap = Snapshot(songs: Array(byId.values), favorites: favorites, playlists: playlists, onboarded: onboarded)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: LibraryStore.fileURL, options: .atomic)
        }
    }
}

/// Recorre Documentos y la biblioteca de Música fuera del hilo principal.
enum LibraryScanner {
    static func scan(existing: [String: Song], includeLibrary: Bool) async -> [Song] {
        var result: [Song] = []

        for url in MediaFiles.scanDocuments() {
            let rel = MediaFiles.relativePath(of: url)
            let id = "f:" + rel
            if let known = existing[id] {
                result.append(known)
                continue
            }
            let meta = await MediaFiles.readMetadata(url)
            var hasArt = false
            if let data = meta.artwork, let image = UIImage(data: data) {
                hasArt = MediaFiles.saveArtwork(image, for: id)
            }
            result.append(Song(
                id: id, title: meta.title, artist: meta.artist, album: meta.album,
                duration: meta.duration, source: .file(rel), addedAt: Date(), hasArtwork: hasArt
            ))
        }

        if includeLibrary {
            for item in MPMediaQuery.songs().items ?? [] {
                // Solo canciones descargadas y sin DRM: las de Apple Music por
                // suscripción no se pueden pasar por el ecualizador.
                guard !item.hasProtectedAsset, !item.isCloudItem, item.assetURL != nil else { continue }
                let id = "m:\(item.persistentID)"
                if let known = existing[id] {
                    result.append(known)
                    continue
                }
                var hasArt = false
                if let image = item.artwork?.image(at: CGSize(width: 600, height: 600)) {
                    hasArt = MediaFiles.saveArtwork(image, for: id)
                }
                result.append(Song(
                    id: id,
                    title: item.title ?? "Sin título",
                    artist: item.artist ?? "Artista desconocido",
                    album: item.albumTitle ?? "",
                    duration: item.playbackDuration,
                    source: .library(item.persistentID),
                    addedAt: item.dateAdded,
                    hasArtwork: hasArt
                ))
            }
        }
        return result
    }
}
