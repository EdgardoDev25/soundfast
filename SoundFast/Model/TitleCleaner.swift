import Foundation

/// Propone títulos más limpios quitando el "ruido" típico de las descargas
/// ("| Video Oficial", "(Lyrics)", "[NCS Release]", "(MP3_128K)", 🎵…).
///
/// Es conservador a propósito:
/// - Solo quita un paréntesis o un trozo tras "|" si TODO lo que dice es ruido
///   (así "(feat. X)", "(Remix)" o "(En Vivo)" se quedan).
/// - El artista solo cambia si era "Artista desconocido" y el título trae
///   "Artista - Canción".
/// - Si el resultado queda vacío o muy corto, no propone nada.
/// - Nunca toca el archivo: se guarda como una edición más y se puede deshacer.
enum TitleCleaner {
    struct Suggestion: Identifiable, Equatable, Sendable {
        let id: String
        let oldTitle: String
        let newTitle: String
        let oldArtist: String
        let newArtist: String

        var changesTitle: Bool { oldTitle != newTitle }
        var changesArtist: Bool { oldArtist != newArtist }
    }

    /// Palabras que por sí solas ya delatan ruido.
    private static let strong: Set<String> = [
        "video", "videoclip", "videolyric", "videolyrics", "audio", "lyrics", "lyric", "letra", "letras",
        "visualizer", "visualiser", "mp3", "128k", "128kbps", "192k", "256k", "320k", "320kbps", "kbps",
        "ncs", "hd", "hq", "4k", "1080p", "720p",
    ]
    /// Palabras que acompañan al ruido pero solas no bastan ("(Official)" se queda).
    private static let weak: Set<String> = [
        "oficial", "official", "con", "en", "de", "the", "music", "musical", "clip", "release",
        "free", "download", "copyright", "full", "new", "nuevo", "y", "and",
    ]
    /// Símbolos que se quitan sin preguntar.
    private static let symbols: Set<Character> = ["🎵", "🎶", "♪", "♫", "♬", "🎧", "🔥", "\u{FE0F}"]

    static func suggestion(for s: Song) -> Suggestion? {
        var title = String(s.title.filter { !symbols.contains($0) })
        var artist = s.artist

        title = removeJunkGroups(title)
        title = removeJunkSegments(title)
        title = tidy(title)

        if let (left, right) = splitDash(title) {
            if fold(left) == fold(artist) {
                // "Zaider - La Cometa" con artista Zaider → "La Cometa".
                title = right
            } else if isUnknown(artist) {
                artist = left
                title = right
            }
        }
        title = tidy(title)

        guard title.count >= 2, title != s.title || artist != s.artist else { return nil }
        return Suggestion(id: s.id, oldTitle: s.title, newTitle: title, oldArtist: s.artist, newArtist: artist)
    }

    /// Clave para comparar canciones (buscar duplicadas): título limpio, sin el
    /// "Artista - " del principio, en minúsculas, sin tildes ni símbolos.
    static func matchKey(for s: Song) -> String {
        var title = suggestion(for: s)?.newTitle ?? s.title
        if let (_, right) = splitDash(title) { title = right }
        return fold(title).filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Piezas

    /// ¿Todo el texto es ruido? Necesita al menos una palabra fuerte.
    static func isJunk(_ text: String) -> Bool {
        let words = fold(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !words.isEmpty else { return true }
        var sawStrong = false
        for w in words {
            if strong.contains(w) { sawStrong = true; continue }
            if weak.contains(w) { continue }
            return false
        }
        return sawStrong
    }

    /// Quita (…), […], {…} y 【…】 cuyo contenido sea solo ruido.
    private static func removeJunkGroups(_ text: String) -> String {
        let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "【": "】"]
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if let close = pairs[c], let end = text[text.index(after: i)...].firstIndex(of: close) {
                let inner = String(text[text.index(after: i)..<end])
                if isJunk(inner) {
                    i = text.index(after: end)
                    continue
                }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return out
    }

    /// Quita lo que va tras "|" (o tras el último " - ") si es solo ruido.
    private static func removeJunkSegments(_ text: String) -> String {
        var parts = text.split(whereSeparator: { $0 == "|" || $0 == "｜" }).map(String.init)
        while parts.count > 1, let last = parts.last, isJunk(last) { parts.removeLast() }
        var result = parts.joined(separator: "|")
        for dash in [" - ", " – ", " — "] {
            if let r = result.range(of: dash, options: .backwards) {
                let tail = String(result[r.upperBound...])
                let head = String(result[..<r.lowerBound])
                if !head.trimmingCharacters(in: .whitespaces).isEmpty, isJunk(tail) { result = head }
            }
        }
        return result
    }

    /// "Artista - Canción" → (Artista, Canción), solo si ambos lados tienen texto.
    private static func splitDash(_ text: String) -> (String, String)? {
        for dash in [" - ", " – ", " — "] {
            if let r = text.range(of: dash) {
                let left = text[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let right = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !left.isEmpty, right.count >= 2 { return (left, right) }
            }
        }
        return nil
    }

    private static func tidy(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "()", with: "").replacingOccurrences(of: "[]", with: "")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        let edge = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—|｜:·,_"))
        return t.trimmingCharacters(in: edge)
    }

    private static func isUnknown(_ artist: String) -> Bool {
        let a = fold(artist).trimmingCharacters(in: .whitespaces)
        return a.isEmpty || a == "artista desconocido" || a == "unknown artist" || a == "desconocido"
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
    }
}

/// Canciones que parecen la misma: mismo título limpio y casi la misma duración.
enum DuplicateFinder {
    struct Group: Identifiable, Sendable {
        let id: String
        let songs: [Song]
    }

    static func groups(in songs: [Song]) -> [Group] {
        var buckets: [String: [Song]] = [:]
        for s in songs {
            let key = TitleCleaner.matchKey(for: s)
            guard key.count >= 2 else { continue }
            buckets[key, default: []].append(s)
        }
        var result: [Group] = []
        for (key, list) in buckets where list.count > 1 {
            // Dentro del mismo título, juntas solo si duran casi lo mismo (±3 s):
            // dos versiones distintas de una canción no son duplicadas.
            let sorted = list.sorted { $0.duration < $1.duration }
            var cluster: [Song] = [sorted[0]]
            func flush() {
                if cluster.count > 1 { result.append(Group(id: key + "#" + cluster[0].id, songs: cluster)) }
            }
            for s in sorted.dropFirst() {
                if let last = cluster.last, abs(s.duration - last.duration) <= 3 {
                    cluster.append(s)
                } else {
                    flush()
                    cluster = [s]
                }
            }
            flush()
        }
        return result.sorted { $0.songs[0].title.localizedCaseInsensitiveCompare($1.songs[0].title) == .orderedAscending }
    }
}
