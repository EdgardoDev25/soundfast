import SwiftUI

/// Biblioteca: Canciones, Favoritos y Listas, con buscador e índice A–Z.
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI

    private var accent: Color { prefs.accent.color }

    private var playlist: Playlist? {
        guard ui.tab == .lists, let id = ui.openList else { return nil }
        return library.playlist(id)
    }

    private var trimmedQuery: String { ui.query.trimmingCharacters(in: .whitespaces).lowercased() }

    private func matches(_ s: Song) -> Bool {
        let q = trimmedQuery
        return q.isEmpty || s.title.lowercased().contains(q) || s.artist.lowercased().contains(q)
            || s.album.lowercased().contains(q)
    }

    private var visibleSongs: [Song] {
        switch ui.tab {
        case .songs:
            return library.songs.filter(matches)
        case .favs:
            let favs = Set(library.favorites)
            return library.songs.filter { favs.contains($0.id) && matches($0) }
        case .lists:
            guard let playlist else { return [] }
            return playlist.songIds.compactMap { library.song($0) }
        }
    }

    private var contextName: String {
        switch ui.tab {
        case .songs: return "Todas las canciones"
        case .favs: return "Favoritos"
        case .lists: return playlist?.name ?? "Listas"
        }
    }

    private var showAZ: Bool {
        ui.tab == .songs && trimmedQuery.isEmpty && prefs.playback.showAz
            && prefs.playback.sortBy == "titulo" && library.songs.count > 12
    }

    var body: some View {
        let songs = visibleSongs
        VStack(spacing: 0) {
            header
            if ui.tab != .lists {
                searchField
            }
            if !songs.isEmpty && (ui.tab != .lists || playlist != nil) {
                actions(songs)
            }
            ZStack(alignment: .trailing) {
                content(songs)
                if showAZ {
                    AZIndex(songs: library.songs)
                        .padding(.trailing, 2)
                        .padding(.top, 6)
                        .padding(.bottom, player.current != nil ? 96 : 12)
                }
                if let letter = ui.azLetter {
                    Text(letter)
                        .font(.sora(36, .heavy))
                        .foregroundStyle(accent)
                        .frame(width: 72, height: 72)
                        .background(Color(hex: 0x1F1F24), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(hex: 0x33333A), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
                        .padding(.trailing, 40)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .background(prefs.theme.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { TabBar() }
    }

    // MARK: Encabezado

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if playlist != nil {
                    Button {
                        ui.openList = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .heavy))
                            Text("LISTAS")
                                .font(.mono(11))
                                .tracking(1.5)
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Volver a listas")
                } else {
                    Text("BIBLIOTECA").eyebrow(color: accent)
                }

                Text(headTitle)
                    .font(.sora(34, .heavy))
                    .tracking(-0.7)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .onTapGesture {
                        if let playlist { ui.modal = .rename(playlistId: playlist.id) }
                    }

                HStack(spacing: 10) {
                    Text(headSub)
                        .font(.sora(13))
                        .foregroundStyle(Ink.dim)
                    if let playlist {
                        Button("Renombrar") { ui.modal = .rename(playlistId: playlist.id) }
                            .font(.sora(13, .semibold))
                            .foregroundStyle(accent)
                            .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if ui.tab == .songs {
                    CircleIconButton(systemName: "plus") { ui.importing = true }
                        .accessibilityLabel("Importar canciones")
                }
                CircleIconButton(systemName: "slider.horizontal.3") { ui.soundOpen = true }
                    .accessibilityLabel("Sonido")
                CircleIconButton(systemName: "gearshape") { ui.settingsOpen = true }
                    .accessibilityLabel("Ajustes")
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var headTitle: String {
        switch ui.tab {
        case .songs: return "Canciones"
        case .favs: return "Favoritos"
        case .lists: return playlist?.name ?? "Listas"
        }
    }

    private var headSub: String {
        switch ui.tab {
        case .songs:
            let minutes = Int((library.totalDuration / 60).rounded())
            return Format.count(library.songs.count, "canción", "canciones") + " · \(minutes) min"
        case .favs:
            return Format.count(library.favorites.count, "canción", "canciones")
        case .lists:
            if let playlist { return Format.count(playlist.songIds.count, "canción", "canciones") }
            return Format.count(library.playlists.count, "lista", "listas")
        }
    }

    // MARK: Buscador y acciones

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.dim)
            TextField("", text: $ui.query, prompt: Text("Buscar canción o artista").foregroundColor(Ink.muted))
                .font(.sora(15))
                .foregroundStyle(Ink.text)
                .tint(accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !ui.query.isEmpty {
                Button {
                    ui.query = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Ink.text)
                        .frame(width: 22, height: 22)
                        .background(Ink.switchOff, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(prefs.theme.surf, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func actions(_ songs: [Song]) -> some View {
        let ids = songs.map(\.id)
        return HStack(spacing: 10) {
            Button {
                if let first = ids.first { player.playFrom(first, ids: ids, name: contextName, forceShuffle: false) }
                ui.openNowPlaying()
            } label: {
                Label("Reproducir", systemImage: "play.fill")
                    .font(.sora(14, .bold))
                    .foregroundStyle(Ink.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableStyle(scale: 0.97))

            Button {
                if let pick = ids.randomElement() { player.playFrom(pick, ids: ids, name: contextName, forceShuffle: true) }
                ui.openNowPlaying()
            } label: {
                Label("Aleatorio", systemImage: "shuffle")
                    .font(.sora(14, .semibold))
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(prefs.theme.surf, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0x2C2C32), lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.97))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: Contenido

    @ViewBuilder
    private func content(_ songs: [Song]) -> some View {
        if ui.tab == .lists && playlist == nil {
            PlaylistsList()
        } else {
            ScrollViewReader { proxy in
                List {
                    if let playlist {
                        Button {
                            ui.sheet = .picker(playlistId: playlist.id)
                        } label: {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(hex: 0x3A3A42), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(accent))
                                Text("Añadir canciones")
                                    .font(.sora(15, .semibold))
                                    .foregroundStyle(accent)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .plainRow()
                    }

                    ForEach(songs) { song in
                        SongRow(
                            song: song,
                            trailingPadding: showAZ ? 30 : 20,
                            removeFromPlaylist: playlist.map { pl in { library.toggle(song.id, in: pl.id) } },
                            onTap: {
                                player.playFrom(song.id, ids: songs.map(\.id), name: contextName)
                                ui.openNowPlaying()
                            }
                        )
                        .id(song.id)
                        .plainRow()
                    }

                    emptyState(songs)
                        .plainRow()

                    if let playlist {
                        Button("Eliminar lista") { ui.modal = .deleteList(playlistId: playlist.id) }
                            .font(.sora(14, .semibold))
                            .foregroundStyle(Ink.danger)
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                            .plainRow()
                    }

                    Color.clear
                        .frame(height: player.current != nil ? 96 : 16)
                        .plainRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: ui.azLetter) { _, letter in
                    guard let letter, let target = firstSong(from: letter) else { return }
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    private func firstSong(from letter: String) -> String? {
        guard let i = Song.indexLetters.firstIndex(of: letter) else { return nil }
        let match = library.songs.first { (Song.indexLetters.firstIndex(of: $0.indexLetter) ?? 0) >= i }
        return (match ?? library.songs.last)?.id
    }

    @ViewBuilder
    private func emptyState(_ songs: [Song]) -> some View {
        if !songs.isEmpty {
            EmptyView()
        } else if ui.tab == .songs && library.songs.isEmpty {
            EmptyLibrary()
        } else if !trimmedQuery.isEmpty && ui.tab != .lists {
            VStack(spacing: 6) {
                Text("Sin resultados").font(.sora(16, .semibold)).foregroundStyle(Ink.text)
                Text("No hay canciones para “\(ui.query)”").font(.sora(13)).foregroundStyle(Ink.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 32)
        } else if ui.tab == .favs {
            VStack(spacing: 10) {
                Image(systemName: "heart")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color(hex: 0x5A5A62))
                Text("Aún no tienes favoritos").font(.sora(17, .bold)).foregroundStyle(Ink.text)
                Text("Toca el corazón mientras suena una canción para guardarla aquí.")
                    .font(.sora(14)).foregroundStyle(Ink.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 64)
            .padding(.horizontal, 40)
        } else if playlist != nil {
            VStack(spacing: 8) {
                Text("Esta lista está vacía").font(.sora(17, .bold)).foregroundStyle(Ink.text)
                Text("Añade canciones para escucharlas aparte.")
                    .font(.sora(14)).foregroundStyle(Ink.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 40)
        }
    }
}

extension View {
    /// Fila de List sin estilo del sistema.
    func plainRow() -> some View {
        self.listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Fila de canción

struct SongRow: View {
    let song: Song
    var trailingPadding: CGFloat = 20
    var removeFromPlaylist: (() -> Void)?
    let onTap: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let isCurrent = player.currentId == song.id
        let accent = prefs.accent.color
        Button(action: onTap) {
            HStack(spacing: 14) {
                ArtworkView(song: song, size: 48, radius: 10, letterSize: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.sora(15, .semibold))
                        .foregroundStyle(isCurrent ? accent : Ink.text)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.sora(13))
                        .foregroundStyle(Ink.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    PlayingBars(color: accent, animating: player.isPlaying)
                } else {
                    Text(Format.time(song.duration))
                        .font(.mono(12))
                        .foregroundStyle(Ink.muted)
                }
                if let removeFromPlaylist {
                    Button(action: removeFromPlaylist) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Ink.dim)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar de la lista")
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, removeFromPlaylist != nil ? 8 : trailingPadding)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(baseColor: isCurrent ? Color.white.opacity(0.04) : .clear))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                player.playNext(song.id)
            } label: {
                Label("A continuación", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                library.toggleFavorite(song.id)
                Haptics.soft()
            } label: {
                Label(library.isFavorite(song.id) ? "Quitar" : "Favorito",
                      systemImage: library.isFavorite(song.id) ? "heart.slash" : "heart")
            }
            .tint(Color(hex: 0xD9476B))
            Button {
                ui.sheet = .addTo(songId: song.id)
            } label: {
                Label("Lista", systemImage: "text.badge.plus")
            }
            .tint(Color(hex: 0x3A3A42))
        }
        .contextMenu {
            Button { player.playNext(song.id) } label: {
                Label("Reproducir a continuación", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button { player.addToQueue(song.id) } label: {
                Label("Añadir a la cola", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            Button { library.toggleFavorite(song.id) } label: {
                Label(library.isFavorite(song.id) ? "Quitar de favoritos" : "Añadir a favoritos",
                      systemImage: library.isFavorite(song.id) ? "heart.slash" : "heart")
            }
            Button { ui.sheet = .addTo(songId: song.id) } label: {
                Label("Añadir a una lista…", systemImage: "text.badge.plus")
            }
            if song.isImportedFile {
                Divider()
                Button(role: .destructive) { ui.modal = .deleteSong(songId: song.id) } label: {
                    Label("Eliminar del iPhone", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Listas

struct PlaylistsList: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let accent = prefs.accent.color
        ScrollView {
            LazyVStack(spacing: 0) {
                Button {
                    ui.modal = .newList(songId: nil)
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(hex: 0x3A3A42), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(accent))
                        Text("Nueva lista")
                            .font(.sora(16, .semibold))
                            .foregroundStyle(accent)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 72)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .padding(.top, 8)

                ForEach(library.playlists) { p in
                    Button {
                        ui.openList = p.id
                    } label: {
                        HStack(spacing: 14) {
                            PlaylistTile(playlist: p, size: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name)
                                    .font(.sora(16, .semibold))
                                    .foregroundStyle(Ink.text)
                                    .lineLimit(1)
                                Text(Format.count(p.songIds.count, "canción", "canciones"))
                                    .font(.sora(13))
                                    .foregroundStyle(Ink.dim)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: 0x5A5A62))
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 72)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                Color.clear.frame(height: player.current != nil ? 96 : 16)
            }
        }
    }
}

struct PlaylistTile: View {
    let playlist: Playlist
    let size: CGFloat
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        if let first = playlist.songIds.first.flatMap({ library.song($0) }), first.hasArtwork {
            ArtworkView(song: first, size: size, radius: 12, letterSize: 22)
        } else {
            let first = playlist.songIds.first.flatMap { library.song($0) }
            Text(playlist.name.first.map { String($0).uppercased() } ?? "·")
                .font(.sora(size * 0.4, .heavy))
                .foregroundStyle(first.map { ArtColors.fg($0.hue) } ?? Ink.dim)
                .frame(width: size, height: size)
                .background(first.map { ArtColors.bg($0.hue) } ?? Color(hex: 0x232329),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Biblioteca vacía

struct EmptyLibrary: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(hex: 0x5A5A62))
            Text("Aún no hay canciones")
                .font(.sora(17, .bold))
                .foregroundStyle(Ink.text)
            Text("Importa archivos de audio o cópialos a la carpeta SoundFast desde la app Archivos o desde “Dispositivos Apple” en Windows.")
                .font(.sora(14))
                .foregroundStyle(Ink.dim)
                .multilineTextAlignment(.center)
            Button {
                ui.importing = true
            } label: {
                Text("Importar archivos")
                    .font(.sora(14, .bold))
                    .foregroundStyle(Ink.onAccent)
                    .padding(.horizontal, 22)
                    .frame(height: 42)
                    .background(prefs.accent.color, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 6)
            if !library.hasMusicAccess {
                Button("Usar la biblioteca de Música") {
                    Task { await library.requestMusicAccess() }
                }
                .font(.sora(14, .semibold))
                .foregroundStyle(prefs.accent.color)
                .buttonStyle(.plain)
            }
            if library.isScanning {
                ProgressView().tint(prefs.accent.color).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 36)
    }
}

// MARK: - Barra inferior

struct TabBar: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        HStack(spacing: 0) {
            tab(.songs, "Canciones", "music.note")
            tab(.favs, "Favoritos", "heart")
            tab(.lists, "Listas", "music.note.list")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(prefs.theme.tab.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(hex: 0x1F1F24)).frame(height: 1)
        }
    }

    private func tab(_ t: AppUI.Tab, _ label: String, _ icon: String) -> some View {
        let on = ui.tab == t
        return Button {
            if t != .lists { ui.openList = nil }
            ui.tab = t
            Haptics.soft()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: on && t == .favs ? "heart.fill" : icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.sora(10.5, .semibold))
            }
            .foregroundStyle(on ? prefs.accent.color : Ink.tabOff)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
