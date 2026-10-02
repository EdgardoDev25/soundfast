import Foundation
import MediaPlayer
import UIKit

/// Lo que se guarda en disco. Fuera de la clase para poder codificarlo en otro hilo.
private struct LibrarySnapshot: Codable, Sendable {
    var songs: [Song]
    var favorites: [String]
    var playlists: [Playlist]
    var onboarded: Bool
    /// Opcional: las bibliotecas guardadas antes no lo traen.
    var cleaned: [String: CleanRecord]?
}

/// Lo que "Limpiar títulos" cambió en una canción, para poder verlo y deshacerlo.
struct CleanRecord: Codable, Sendable, Equatable {
    var oldTitle: String
    var oldArtist: String
    var newTitle: String
    var newArtist: String
    var date: Date
}

/// Canciones, favoritos y listas. Se guarda en Application Support/library.json.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published var favorites: [String] = [] {
        didSet {
            favoriteSet = Set(favorites)
            scheduleSave()
        }
    }
    @Published var playlists: [Playlist] = [] { didSet { scheduleSave() } }
    @Published var onboarded = false { didSet { scheduleSave() } }
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var musicAccess = MPMediaLibrary.authorizationStatus()
    /// Mensaje corto para mostrar tras importar o actualizar.
    @Published var notice: String?
    /// Títulos limpiados (id → antes y después).
    @Published private(set) var cleaned: [String: CleanRecord] = [:]

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

    /// Lo que la lista consulta a cada rato, calculado una sola vez al cambiar la
    /// biblioteca. Antes se recalculaba canción por canción en cada redibujado:
    /// buscar, arrastrar el índice A–Z o cambiar de canción repasaba la biblioteca
    /// entera pasando títulos a minúsculas y quitando tildes.
    private struct Keys {
        /// Título, artista y álbum tal cual, para saber si hay que recalcular.
        let raw: String
        /// Lo mismo en minúsculas, para el buscador.
        let search: String
        /// Letra del índice A–Z.
        let letter: String
    }
    private var keys: [String: Keys] = [:]
    private var favoriteSet: Set<String> = []
    /// Letras del índice A–Z que tienen al menos una canción.
    private(set) var presentLetters: Set<String> = []
    private(set) var totalDuration: Double = 0

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    init() {
        if let data = try? Data(contentsOf: LibraryStore.fileURL),
           let snap = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            favorites = snap.favorites
            playlists = snap.playlists
            onboarded = snap.onboarded
            cleaned = snap.cleaned ?? [:]
            setSongs(snap.songs)
        }
        // Dentro de init los observadores no corren, así que va aquí a mano.
        favoriteSet = Set(favorites)
    }

    // MARK: Consultas

    func song(_ id: String) -> Song? { byId[id] }

    func isFavorite(_ id: String) -> Bool { favoriteSet.contains(id) }

    func playlist(_ id: String) -> Playlist? { playlists.first { $0.id == id } }

    var hasMusicAccess: Bool { musicAccess == .authorized }

    /// Canciones que se ven en la lista, ya filtradas por el buscador.
    func visible(query: String, favoritesOnly: Bool) -> [Song] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty && !favoritesOnly { return songs }
        return songs.filter { song in
            if favoritesOnly, !favoriteSet.contains(song.id) { return false }
            guard !q.isEmpty else { return true }
            return keys[song.id]?.search.contains(q) ?? false
        }
    }

    /// Primera canción de esa letra del índice (o la siguiente que haya).
    func firstSong(fromLetter letter: String) -> String? {
        guard let i = Song.indexLetters.firstIndex(of: letter) else { return nil }
        let match = songs.first { song in
            let l = keys[song.id]?.letter ?? "#"
            return (Song.indexLetters.firstIndex(of: l) ?? 0) >= i
        }
        return (match ?? songs.last)?.id
    }

    // MARK: Favoritos y listas

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.append(id) }
    }

    @discardableResult
    func createPlaylist(named name: String, with songId: String? = nil) -> Playlist {
        createPlaylist(named: name, songIds: songId.map { [$0] } ?? [])
    }

    @discardableResult
    func createPlaylist(named name: String, songIds: [String]) -> Playlist {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = Playlist(
            id: "p" + UUID().uuidString.prefix(8),
            name: clean.isEmpty ? "Nueva lista" : clean,
            songIds: songIds
        )
        playlists.append(p)
        return p
    }

    /// Añade varias canciones a una lista (las que ya estaban no se repiten).
    func add(_ songIds: [String], to playlistId: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        let have = Set(playlists[i].songIds)
        playlists[i].songIds.append(contentsOf: songIds.filter { !have.contains($0) })
    }

    func remove(_ songIds: [String], from playlistId: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        let out = Set(songIds)
        playlists[i].songIds.removeAll { out.contains($0) }
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
        // Al volver a la app se reescanea siempre, y casi siempre sale lo mismo.
        // Reordenar la biblioteca entera (comparación por idioma, cara) y rehacer
        // los índices para nada se sentía como un frenazo al entrar.
        let sameAsBefore = found.count == byId.count && found.allSatisfy { byId[$0.id] == $0 }
        if !sameAsBefore {
            setSongs(found)
            prune()
            scheduleSave()
        }
        isScanning = false
        lastScan = Date()
        if announce {
            let added = found.filter { !before.contains($0.id) }.count
            let removed = before.subtracting(found.map(\.id)).count
            var parts: [String] = []
            if added > 0 { parts.append(Format.count(added, "canción nueva", "canciones nuevas")) }
            if removed > 0 { parts.append(Format.count(removed, "quitada", "quitadas")) }
            notice = parts.isEmpty ? "Biblioteca al día · no hay canciones nuevas" : "Biblioteca actualizada · " + parts.joined(separator: " · ")
        }
    }

    /// Guarda la información editada de una canción (solo en SoundFast; el archivo no se toca).
    func updateTags(_ id: String, _ tags: SongTags) {
        guard var s = byId[id] else { return }
        let clean = { (v: String) in v.trimmingCharacters(in: .whitespacesAndNewlines) }
        s.title = clean(tags.title).isEmpty ? s.title : clean(tags.title)
        s.artist = clean(tags.artist).isEmpty ? "Artista desconocido" : clean(tags.artist)
        s.album = clean(tags.album)
        s.genre = clean(tags.genre)
        s.year = Int(clean(tags.year))
        s.track = Int(clean(tags.track))
        byId[id] = s
        setSongs(songs.map { $0.id == id ? s : $0 })
        scheduleSave()
    }

    // MARK: Limpiar títulos

    /// Aplica las sugerencias elegidas. Guarda el antes para poder deshacerlo.
    func applyClean(_ suggestions: [TitleCleaner.Suggestion]) {
        guard !suggestions.isEmpty else { return }
        var log = cleaned
        var changed: [String: Song] = [:]
        for sug in suggestions {
            guard var s = byId[sug.id], !sug.newTitle.isEmpty else { continue }
            // Si ya se había limpiado, se conserva el original de verdad.
            let first = log[sug.id]
            s.title = sug.newTitle
            s.artist = sug.newArtist.isEmpty ? s.artist : sug.newArtist
            log[sug.id] = CleanRecord(
                oldTitle: first?.oldTitle ?? sug.oldTitle, oldArtist: first?.oldArtist ?? sug.oldArtist,
                newTitle: s.title, newArtist: s.artist, date: Date()
            )
            changed[s.id] = s
        }
        guard !changed.isEmpty else { return }
        cleaned = log
        setSongs(songs.map { changed[$0.id] ?? $0 })
        scheduleSave()
    }

    /// Vuelve al título y artista que tenía antes de limpiarlo.
    func revertClean(_ ids: [String]) {
        var log = cleaned
        var changed: [String: Song] = [:]
        for id in ids {
            guard let rec = log[id] else { continue }
            log[id] = nil
            guard var s = byId[id] else { continue }
            s.title = rec.oldTitle
            s.artist = rec.oldArtist
            changed[id] = s
        }
        cleaned = log
        if !changed.isEmpty { setSongs(songs.map { changed[$0.id] ?? $0 }) }
        scheduleSave()
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

    /// Borra varias de una vez (solo las importadas). Devuelve cuántas borró.
    @discardableResult
    func deleteFiles(_ list: [Song]) -> Int {
        var removed = Set<String>()
        for song in list {
            guard case .file(let path) = song.source else { continue }
            try? FileManager.default.removeItem(at: MediaFiles.url(forRelativePath: path))
            try? FileManager.default.removeItem(at: MediaFiles.artworkURL(for: song.id))
            removed.insert(song.id)
        }
        guard !removed.isEmpty else { return 0 }
        setSongs(songs.filter { !removed.contains($0.id) })
        prune()
        scheduleSave()
        return removed.count
    }

    // MARK: Interno

    private func setSongs(_ list: [Song]) {
        songs = sort(list)
        byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var newKeys: [String: Keys] = [:]
        newKeys.reserveCapacity(list.count)
        var letters = Set<String>()
        var total: Double = 0
        for song in list {
            total += song.duration
            let raw = song.title + "\u{1}" + song.artist + "\u{1}" + song.album
            // Si el texto no cambió, se reaprovecha lo ya calculado.
            if let old = keys[song.id], old.raw == raw {
                newKeys[song.id] = old
                letters.insert(old.letter)
                continue
            }
            let letter = Song.indexLetter(for: song.title)
            newKeys[song.id] = Keys(raw: raw, search: raw.lowercased(), letter: letter)
            letters.insert(letter)
        }
        keys = newKeys
        presentLetters = letters
        totalDuration = total
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
            self?.saveInBackground()
        }
    }

    /// Guarda ya mismo, en este hilo (al pasar la app a segundo plano: si se
    /// dejara para después podría no alcanzar a escribirse).
    func saveNow() {
        let snap = snapshot()
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: LibraryStore.fileURL, options: .atomic)
        }
    }

    /// Guardado de todos los días. Codificar la biblioteca entera a JSON toma su
    /// tiempo, así que se hace fuera del hilo principal para no frenar una
    /// animación en curso.
    private func saveInBackground() {
        let snap = snapshot()
        let url = LibraryStore.fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snap) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(songs: Array(byId.values), favorites: favorites, playlists: playlists,
                        onboarded: onboarded, cleaned: cleaned)
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
                    hasArtwork: hasArt,
                    genre: item.genre ?? "",
                    year: item.releaseDate.map { Calendar.current.component(.year, from: $0) },
                    track: item.albumTrackNumber > 0 ? item.albumTrackNumber : nil
                ))
            }
        }
        return result
    }
}
