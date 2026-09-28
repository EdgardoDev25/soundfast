import Foundation

struct Song: Identifiable, Codable, Hashable {
    enum Source: Codable, Hashable {
        /// Archivo dentro de Documentos de la app (ruta relativa).
        case file(String)
        /// Canción de la biblioteca de Música del iPhone (persistentID).
        case library(UInt64)
    }

    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var source: Source
    var addedAt: Date
    var hasArtwork: Bool

    /// Tono estable para la portada generada.
    var hue: Double {
        var hash: UInt32 = 5381
        for byte in id.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return Double(hash % 360)
    }

    /// Letra del índice A–Z ("#" para números y símbolos).
    var indexLetter: String { Song.indexLetter(for: title) }

    /// Inicial que se muestra en la portada generada.
    var initial: String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "·" }
        return String(first).uppercased()
    }

    var isImportedFile: Bool {
        if case .file = source { return true }
        return false
    }

    static let indexLetters: [String] = ["#"] + "ABCDEFGHIJKLMNÑOPQRSTUVWXYZ".map { String($0) }

    static func indexLetter(for title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "#" }
        let upper = String(first).uppercased()
        if upper == "Ñ" { return upper }
        let folded = upper.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        if let scalar = folded.unicodeScalars.first, scalar.value >= 65, scalar.value <= 90 {
            return String(Character(scalar))
        }
        return "#"
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var songIds: [String]
}

enum Format {
    /// 3:07
    static func time(_ seconds: Double) -> String {
        let t = max(0, Int(seconds.isFinite ? seconds : 0))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}
