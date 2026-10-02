import AVFoundation
import SwiftUI

// MARK: - Piezas comunes

private struct ToolHeader: View {
    let title: String
    let subtitle: String
    let onDone: () -> Void
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.montserrat(20, .heavy)).foregroundStyle(Ink.text).lineLimit(1)
                Text(subtitle).font(.montserrat(13)).foregroundStyle(Ink.dim).lineLimit(2)
            }
            Spacer(minLength: 12)
            Button("Listo", action: onDone)
                .font(.montserrat(15, .semibold))
                .foregroundStyle(prefs.accent.color)
                .buttonStyle(.plain)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }
}

private extension View {
    @MainActor
    func toolSheetStyle(_ prefs: Preferences) -> some View {
        self.presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .sheetBackground(prefs)
            .presentationCornerRadius(28)
    }
}

/// Botón ancho de acción al pie de las hojas.
private struct WideButton: View {
    let label: String
    var destructive = false
    let action: () -> Void
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.montserrat(15, .bold))
                .foregroundStyle(destructive ? Color.white : Ink.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(destructive ? Ink.danger : prefs.accent.color,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

/// Tamaño, formato y calidad aproximada de una canción importada.
enum FileFacts {
    static func url(_ s: Song) -> URL? {
        guard case .file(let path) = s.source else { return nil }
        return MediaFiles.url(forRelativePath: path)
    }

    static func format(_ s: Song) -> String {
        guard case .file(let path) = s.source else { return "MÚSICA" }
        let ext = (path as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "?" : ext
    }

    static func size(_ s: Song) -> Int64? {
        guard let url = url(s),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return n.int64Value
    }

    /// kbps a partir del tamaño y la duración.
    static func kbps(_ s: Song) -> Int? {
        guard let bytes = size(s), s.duration > 1 else { return nil }
        return Int(Double(bytes) * 8 / s.duration / 1000)
    }

    static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// ¿El archivo se puede abrir y reproducir? Se prueba como lo hace el motor.
    static func playable(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0 && file.processingFormat.sampleRate > 0
    }
}

// MARK: - Limpiar títulos

struct CleanTitlesSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [TitleCleaner.Suggestion] = []
    @State private var skipped: Set<String> = []
    @State private var loading = true
    @State private var showApplied = false
    @State private var confirmRevertAll = false

    var body: some View {
        let accent = prefs.accent.color
        let chosen = suggestions.filter { !skipped.contains($0.id) }
        VStack(spacing: 0) {
            ToolHeader(
                title: "Limpiar títulos",
                subtitle: "Quita “Video Oficial”, “(Lyrics)”, “[NCS Release]”… Solo cambia lo que ves en SoundFast; el archivo no se toca."
            ) { dismiss() }

            HStack(spacing: 8) {
                Chip(label: "Sugerencias (\(suggestions.count))", selected: !showApplied, fullWidth: true) { showApplied = false }
                Chip(label: "Aplicados (\(library.cleaned.count))", selected: showApplied, fullWidth: true) { showApplied = true }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if showApplied {
                appliedList
            } else if loading {
                ProgressView().tint(accent).frame(maxHeight: .infinity)
            } else if suggestions.isEmpty {
                empty("Todo limpio", "No hay títulos con ruido para quitar.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(suggestions) { s in
                            suggestionRow(s, on: !skipped.contains(s.id))
                        }
                    }
                    .padding(.bottom, 100)
                }
                .overlay(alignment: .bottom) {
                    WideButton(label: chosen.isEmpty ? "Elige al menos una" : "Aplicar a \(Format.count(chosen.count, "canción", "canciones"))") {
                        guard !chosen.isEmpty else { return }
                        library.applyClean(chosen)
                        Haptics.tap()
                        library.notice = Format.count(chosen.count, "título limpiado", "títulos limpiados")
                        showApplied = true
                        Task { await load() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
        }
        .toolSheetStyle(prefs)
        .task { await load() }
        .confirmationDialog("¿Deshacer todos?", isPresented: $confirmRevertAll, titleVisibility: .visible) {
            Button("Deshacer \(library.cleaned.count)", role: .destructive) {
                library.revertClean(Array(library.cleaned.keys))
                Task { await load() }
            }
        } message: {
            Text("Todas las canciones vuelven a su título y artista anteriores.")
        }
    }

    private func load() async {
        let songs = library.songs
        let found = await Task.detached(priority: .userInitiated) {
            songs.compactMap(TitleCleaner.suggestion(for:))
        }.value
        suggestions = found.sorted { $0.oldTitle.localizedCaseInsensitiveCompare($1.oldTitle) == .orderedAscending }
        skipped = skipped.intersection(found.map(\.id))
        loading = false
    }

    private func suggestionRow(_ s: TitleCleaner.Suggestion, on: Bool) -> some View {
        Button {
            if on { skipped.insert(s.id) } else { skipped.remove(s.id) }
            Haptics.tick()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                CheckCircle(checked: on, accent: prefs.accent.color)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.oldTitle)
                        .font(.montserrat(13))
                        .strikethrough(true, color: Ink.faint)
                        .foregroundStyle(Ink.dim)
                    Text(s.newTitle)
                        .font(.montserrat(15, .semibold))
                        .foregroundStyle(Ink.text)
                    if s.changesArtist {
                        Text("Artista: \(s.oldArtist) → \(s.newArtist)")
                            .font(.montserrat(12, .semibold))
                            .foregroundStyle(prefs.accent.light)
                    } else {
                        Text(s.oldArtist).font(.montserrat(12)).foregroundStyle(Ink.faint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    @ViewBuilder
    private var appliedList: some View {
        let records = library.cleaned.sorted { $0.value.date > $1.value.date }
        if records.isEmpty {
            empty("Nada aplicado aún", "Aquí verás cada título que se limpió: cómo estaba y cómo quedó.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records, id: \.key) { id, rec in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Antes: " + rec.oldTitle)
                                    .font(.montserrat(12))
                                    .foregroundStyle(Ink.dim)
                                Text(rec.newTitle)
                                    .font(.montserrat(15, .semibold))
                                    .foregroundStyle(Ink.text)
                                if rec.oldArtist != rec.newArtist {
                                    Text("Artista: \(rec.oldArtist) → \(rec.newArtist)")
                                        .font(.montserrat(12))
                                        .foregroundStyle(prefs.accent.light)
                                }
                            }
                            Spacer(minLength: 0)
                            Button("Deshacer") {
                                library.revertClean([id])
                                Haptics.soft()
                                Task { await load() }
                            }
                            .font(.montserrat(13, .semibold))
                            .foregroundStyle(prefs.accent.color)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                }
                .padding(.bottom, 100)
            }
            .overlay(alignment: .bottom) {
                WideButton(label: "Deshacer todos", destructive: true) { confirmRevertAll = true }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Duplicadas

struct DuplicatesSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [DuplicateFinder.Group] = []
    @State private var loading = true
    @State private var confirmAll = false
    @State private var pendingDelete: Song?

    /// La que se queda en cada grupo: la de mejor calidad (más kbps).
    private func best(_ g: DuplicateFinder.Group) -> Song {
        g.songs.max { (FileFacts.kbps($0) ?? 0) < (FileFacts.kbps($1) ?? 0) } ?? g.songs[0]
    }

    private var extras: [Song] {
        groups.flatMap { g in
            let keep = best(g)
            return g.songs.filter { $0.id != keep.id && $0.isImportedFile }
        }
    }

    var body: some View {
        let accent = prefs.accent.color
        VStack(spacing: 0) {
            ToolHeader(
                title: "Canciones duplicadas",
                subtitle: loading ? "Buscando…"
                    : groups.isEmpty ? "No se encontraron repetidas"
                    : "\(Format.count(groups.count, "grupo", "grupos")) · mismo título y casi la misma duración"
            ) { dismiss() }

            if loading {
                ProgressView().tint(accent).frame(maxHeight: .infinity)
            } else if groups.isEmpty {
                empty("Sin duplicadas", "Cada canción aparece una sola vez.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(groups) { g in groupCard(g) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                .overlay(alignment: .bottom) {
                    if !extras.isEmpty {
                        WideButton(label: "Borrar \(Format.count(extras.count, "repetida", "repetidas"))", destructive: true) {
                            confirmAll = true
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .toolSheetStyle(prefs)
        .task { await load() }
        .confirmationDialog("¿Borrar las repetidas?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Borrar \(extras.count)", role: .destructive) {
                let n = library.deleteFiles(extras)
                library.notice = Format.count(n, "canción eliminada", "canciones eliminadas")
                Task { await load() }
            }
        } message: {
            Text("En cada grupo se queda la de mejor calidad (marcada). Las demás se borran del iPhone.")
        }
        .confirmationDialog("¿Borrar esta canción?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { song in
            Button("Borrar", role: .destructive) {
                library.deleteFile(song)
                Task { await load() }
            }
        } message: { song in
            Text("“\(song.title)” se borrará del iPhone.")
        }
    }

    private func load() async {
        let songs = library.songs
        groups = await Task.detached(priority: .userInitiated) { DuplicateFinder.groups(in: songs) }.value
        loading = false
    }

    private func groupCard(_ g: DuplicateFinder.Group) -> some View {
        let keep = best(g)
        return VStack(spacing: 0) {
            ForEach(g.songs) { s in
                HStack(spacing: 12) {
                    ArtworkView(song: s, size: 44, radius: 9, letterSize: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.montserrat(14, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                        Text(details(s)).font(.mono(11)).foregroundStyle(Ink.dim).lineLimit(1)
                        if s.id == keep.id {
                            Text("SE QUEDA · MEJOR CALIDAD").eyebrow(9, color: prefs.accent.color)
                        }
                    }
                    Spacer(minLength: 0)
                    if s.isImportedFile {
                        Button { pendingDelete = s } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Ink.danger)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Borrar")
                    } else {
                        Text("App Música").font(.montserrat(11)).foregroundStyle(Ink.faint)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 4)
        .surface(prefs, RoundedRectangle(cornerRadius: 16, style: .continuous), border: Ink.cardBorder)
    }

    private func details(_ s: Song) -> String {
        var parts = [s.artist, Format.time(s.duration), FileFacts.format(s)]
        if let k = FileFacts.kbps(s) { parts.append("\(k) kbps") }
        if let b = FileFacts.size(s) { parts.append(FileFacts.megabytes(b)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Formatos

struct FormatsSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    /// "Todos", un formato ("MP3"…) o "error".
    @State private var filter = "Todos"
    /// Resultado de la verificación: true funciona, false no.
    @State private var status: [String: Bool] = [:]
    @State private var checking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var confirmBroken = false
    @State private var pendingDelete: Song?
    /// Tamaños leídos una sola vez (leerlos en cada redibujado era lento).
    @State private var sizes: [String: Int64] = [:]

    private var formats: [(name: String, count: Int, bytes: Int64)] {
        var byFormat: [String: (Int, Int64)] = [:]
        for s in library.songs {
            let f = FileFacts.format(s)
            let cur = byFormat[f] ?? (0, 0)
            byFormat[f] = (cur.0 + 1, cur.1 + (sizes[s.id] ?? 0))
        }
        return byFormat.map { (name: $0.key, count: $0.value.0, bytes: $0.value.1) }
            .sorted { $0.count > $1.count }
    }

    private var shown: [Song] {
        switch filter {
        case "Todos": return library.songs
        case "error": return library.songs.filter { status[$0.id] == false }
        default: return library.songs.filter { FileFacts.format($0) == filter }
        }
    }

    private var broken: [Song] { library.songs.filter { status[$0.id] == false && $0.isImportedFile } }

    var body: some View {
        let accent = prefs.accent.color
        let list = shown
        let fmts = formats
        VStack(spacing: 0) {
            ToolHeader(
                title: "Formatos",
                subtitle: fmts.map { "\($0.name) \($0.count)" }.joined(separator: " · ")
            ) { dismiss() }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Chip(label: "Todos (\(library.songs.count))", selected: filter == "Todos") { filter = "Todos" }
                    ForEach(fmts, id: \.name) { f in
                        Chip(label: "\(f.name) (\(f.count))", selected: filter == f.name, mono: true) { filter = f.name }
                    }
                    if status.values.contains(false) {
                        Chip(label: "No funcionan (\(status.values.filter { !$0 }.count))", selected: filter == "error") { filter = "error" }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 8)

            if let f = fmts.first(where: { $0.name == filter }), f.bytes > 0 {
                Text("\(Format.count(f.count, "archivo", "archivos")) · \(FileFacts.megabytes(f.bytes))")
                    .font(.montserrat(12))
                    .foregroundStyle(Ink.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(list) { s in row(s, accent: accent) }
                }
                .padding(.bottom, 130)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if !broken.isEmpty && !checking {
                        WideButton(label: "Borrar \(Format.count(broken.count, "la que no funciona", "las que no funcionan"))", destructive: true) {
                            confirmBroken = true
                        }
                    }
                    WideButton(label: checking ? "Verificando… (toca para detener)" : "Verificar si funcionan (\(list.filter(\.isImportedFile).count))") {
                        if checking { stop() } else { verify(list) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .toolSheetStyle(prefs)
        .task {
            let songs = library.songs
            sizes = await Task.detached(priority: .userInitiated) {
                var out: [String: Int64] = [:]
                for s in songs { if let b = FileFacts.size(s) { out[s.id] = b } }
                return out
            }.value
        }
        .onDisappear { stop() }
        .confirmationDialog("¿Borrar las que no funcionan?", isPresented: $confirmBroken, titleVisibility: .visible) {
            Button("Borrar \(broken.count)", role: .destructive) {
                let n = library.deleteFiles(broken)
                library.notice = Format.count(n, "canción eliminada", "canciones eliminadas")
            }
        } message: {
            Text("Son archivos que no se pudieron abrir. Se borran del iPhone.")
        }
        .confirmationDialog("¿Borrar esta canción?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { song in
            Button("Borrar", role: .destructive) { library.deleteFile(song) }
        } message: { song in
            Text("“\(song.title)” se borrará del iPhone.")
        }
    }

    private func row(_ s: Song, accent: Color) -> some View {
        HStack(spacing: 12) {
            Text(FileFacts.format(s))
                .font(.mono(10, .bold))
                .foregroundStyle(accent)
                .frame(width: 48, height: 24)
                .background(prefs.accent.alpha(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.montserrat(14, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text(rowDetails(s)).font(.mono(11)).foregroundStyle(Ink.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            statusIcon(s)
            if s.isImportedFile {
                Button { pendingDelete = s } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    @ViewBuilder
    private func statusIcon(_ s: Song) -> some View {
        switch status[s.id] {
        case true?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.oklch(0.75, 0.15, 150))
                .accessibilityLabel("Funciona")
        case false?:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Ink.danger)
                .accessibilityLabel("No funciona")
        case nil:
            EmptyView()
        }
    }

    private func rowDetails(_ s: Song) -> String {
        var parts = [s.artist, Format.time(s.duration)]
        if let k = FileFacts.kbps(s) { parts.append("\(k) kbps") }
        if let b = FileFacts.size(s) { parts.append(FileFacts.megabytes(b)) }
        if !s.isImportedFile { parts.append("App Música") }
        return parts.joined(separator: " · ")
    }

    /// Abre cada archivo fuera del hilo principal, uno por uno.
    private func verify(_ list: [Song]) {
        let targets = list.compactMap { s in FileFacts.url(s).map { (s.id, $0) } }
        guard !targets.isEmpty else { return }
        checking = true
        checkTask = Task {
            for (id, url) in targets {
                if Task.isCancelled { break }
                let ok = await Task.detached(priority: .utility) { FileFacts.playable(url) }.value
                status[id] = ok
            }
            checking = false
            let bad = targets.filter { status[$0.0] == false }.count
            library.notice = bad == 0 ? "Todas funcionan" : Format.count(bad, "no funciona", "no funcionan")
        }
    }

    private func stop() {
        checkTask?.cancel()
        checkTask = nil
        checking = false
    }
}

// MARK: - Vacío

@MainActor
private func empty(_ title: String, _ detail: String) -> some View {
    VStack(spacing: 6) {
        Text(title).font(.montserrat(17, .bold)).foregroundStyle(Ink.text)
        Text(detail).font(.montserrat(13)).foregroundStyle(Ink.dim).multilineTextAlignment(.center)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
