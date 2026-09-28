import Foundation
import UIKit

/// Una portada encontrada en internet.
struct CoverCandidate: Identifiable, Hashable {
    let id: String
    let url: URL
    let title: String
    let artist: String
}

/// Busca y descarga portadas desde el buscador público de iTunes (gratis, sin cuenta).
/// Solo se envían el título y el artista de la canción.
@MainActor
final class CoverService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0

    private let library: LibraryStore
    private let artwork: ArtworkStore
    private var task: Task<Void, Never>?

    /// El buscador de Apple admite unas 20 consultas por minuto.
    private let delayBetweenRequests: UInt64 = 3_200_000_000

    init(library: LibraryStore, artwork: ArtworkStore) {
        self.library = library
        self.artwork = artwork
    }

    var missingCount: Int { library.songs.filter { !$0.hasArtwork }.count }

    // MARK: Una canción

    /// Opciones de portada para elegir a mano.
    func candidates(for song: Song, query: String? = nil) async -> [CoverCandidate] {
        let term = query?.trimmingCharacters(in: .whitespaces).isEmpty == false ? query! : Self.term(for: song)
        async let songs = (try? await Self.search(term, entity: "song")) ?? []
        async let albums = (try? await Self.search(term, entity: "album")) ?? []
        var seen = Set<URL>()
        return (await songs + albums).filter { seen.insert($0.url).inserted }
    }

    /// Descarga y guarda la portada elegida.
    @discardableResult
    func apply(_ candidate: CoverCandidate, to songId: String) async -> Bool {
        guard let image = await Self.download(candidate.url) else { return false }
        return save(image, for: [songId])
    }

    // MARK: Todas las que faltan

    func downloadMissing() {
        guard !isRunning else { return }
        let songs = library.songs.filter { !$0.hasArtwork }
        guard !songs.isEmpty else {
            library.notice = "Todas las canciones ya tienen portada"
            return
        }
        // Las canciones del mismo álbum comparten una sola búsqueda.
        var groups: [String: [Song]] = [:]
        var order: [String] = []
        for s in songs {
            let key = s.album.isEmpty ? "song:" + s.id : "album:" + s.artist.lowercased() + "|" + s.album.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }

        isRunning = true
        done = 0
        total = songs.count
        task = Task { [weak self] in
            guard let self else { return }
            var found = 0
            for (index, key) in order.enumerated() {
                if Task.isCancelled { break }
                guard let group = groups[key], let first = group.first else { continue }
                if index > 0 { try? await Task.sleep(nanoseconds: self.delayBetweenRequests) }
                let entity = first.album.isEmpty ? "song" : "album"
                let term = first.album.isEmpty ? Self.term(for: first) : Self.clean(first.artist) + " " + Self.clean(first.album)
                if let best = (try? await Self.search(term, entity: entity))?.first,
                   let image = await Self.download(best.url) {
                    if self.save(image, for: group.map(\.id)) { found += group.count }
                }
                self.done += group.count
            }
            self.isRunning = false
            self.library.notice = found > 0
                ? Format.count(found, "portada descargada", "portadas descargadas")
                : "No se encontraron portadas"
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    // MARK: Interno

    private func save(_ image: UIImage, for ids: [String]) -> Bool {
        var ok = false
        for id in ids where MediaFiles.saveArtwork(image, for: id) {
            library.markArtwork(id)
            artwork.invalidate(id)
            ok = true
        }
        return ok
    }

    /// "Artista título" sin paréntesis tipo (feat. …) o [Remastered].
    static func term(for song: Song) -> String {
        let artist = song.artist == "Artista desconocido" ? "" : clean(song.artist)
        return (artist + " " + clean(song.title)).trimmingCharacters(in: .whitespaces)
    }

    static func clean(_ s: String) -> String {
        var t = s
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]", "(?i)\\s-\\s.*remaster.*$", "(?i)\\bfeat\\..*$", "(?i)\\bft\\..*$"] {
            t = t.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let artworkUrl100: String?
            let collectionName: String?
            let trackName: String?
            let artistName: String?
        }
        let results: [Item]
    }

    nonisolated static func search(_ term: String, entity: String) async throws -> [CoverCandidate] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = comps.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results.compactMap { item in
            guard let small = item.artworkUrl100,
                  let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else { return nil }
            return CoverCandidate(
                id: big.absoluteString,
                url: big,
                title: item.trackName ?? item.collectionName ?? "",
                artist: item.artistName ?? ""
            )
        }
    }

    nonisolated static func download(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}
