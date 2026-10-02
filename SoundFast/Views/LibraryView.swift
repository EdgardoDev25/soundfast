import Combine
import SwiftUI

/// Biblioteca: Canciones, Favoritos y Listas, con buscador e índice A–Z.
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var ui: AppUI
    /// Sin observar a propósito: cada cambio de canción o de pausa volvía a armar
    /// la lista entera. Las filas sí lo observan (solo las que están a la vista).
    let player: PlayerController
    let hasCurrent: Bool

    /// Modo "Ordenar" dentro de una lista (arrastrar para reordenar).
    @State private var reordering = false
    /// Última canción centrada. En una clase para que anotarla no redibuje.
    @State private var centered = CenterMemo()

    final class CenterMemo {
        var id: String?
    }

    private var accent: Color { prefs.accent.color }

    private var playlist: Playlist? {
        guard ui.tab == .lists, let id = ui.openList else { return nil }
        return library.playlist(id)
    }

    private var trimmedQuery: String { ui.query.trimmingCharacters(in: .whitespaces) }

    /// El filtrado lo hace la biblioteca, que tiene el texto ya en minúsculas.
    private var visibleSongs: [Song] {
        switch ui.tab {
        case .songs:
            return library.visible(query: ui.query, favoritesOnly: false)
        case .favs:
            return library.visible(query: ui.query, favoritesOnly: true)
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
            && prefs.playback.sortBy == "titulo" && prefs.playback.sortAscending && library.songs.count > 12
    }

    var body: some View {
        let songs = visibleSongs
        ZStack(alignment: .trailing) {
                content(songs)
                if showAZ {
                    AZIndex(present: library.presentLetters, az: ui.az)
                        .padding(.trailing, 2)
                        .padding(.top, 6)
                        .padding(.bottom, hasCurrent ? 96 : 12)
                }
                AZBubble(az: ui.az)
        }
        // Título, botones y buscador sobre vidrio; la lista se desliza por debajo.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header
                if ui.tab != .lists {
                    searchField
                }
            }
            .padding(.bottom, 12)
            .topBarBackground(prefs)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { TabBar() }
        .onChange(of: ui.openList) { _, _ in reordering = false }
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
                    Text("SoundFast - Edgardo Rocha").eyebrow(color: accent)
                }

                Text(headTitle)
                    .font(.montserrat(34, .heavy))
                    .tracking(-0.7)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .onTapGesture {
                        if let playlist { ui.modal = .rename(playlistId: playlist.id) }
                    }

                HStack(spacing: 10) {
                    Text(headSub)
                        .font(.montserrat(13))
                        .foregroundStyle(Ink.dim)
                    if let playlist {
                        Button("Renombrar") { ui.modal = .rename(playlistId: playlist.id) }
                            .font(.montserrat(13, .semibold))
                            .foregroundStyle(accent)
                            .buttonStyle(.plain)
                        if playlist.songIds.count > 1 {
                            Button(reordering ? "Listo" : "Ordenar") {
                                withAnimation(.easeOut(duration: 0.2)) { reordering.toggle() }
                                Haptics.soft()
                            }
                            .font(.montserrat(13, .semibold))
                            .foregroundStyle(accent)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if ui.tab == .songs {
                    CircleIconButton(systemName: "plus") { ui.importing = true }
                        .accessibilityLabel("Importar canciones")
                }
                CircleIconButton(systemName: "slider.horizontal.3") { ui.openSound() }
                    .accessibilityLabel("Sonido")
                CircleIconButton(systemName: "gearshape") { ui.openSettings() }
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
            return Format.count(library.songs.count, "canción", "canciones") + " · " + Format.duration(library.totalDuration)
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
                .font(.montserrat(15))
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
        .surface(prefs, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func actions(_ songs: [Song]) -> some View {
        let ids = songs.map(\.id)
        // Va dentro de la lista: se oculta al hacer scroll.
        return HStack(spacing: 8) {
            Button {
                if let first = ids.first { player.playFrom(first, ids: ids, name: contextName, forceShuffle: false) }
                ui.openNowPlaying()
            } label: {
                Label("Reproducir", systemImage: "play.fill")
                    .font(.montserrat(14, .bold))
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
                HStack(spacing: 6) {
                    Image(systemName: "shuffle").font(.system(size: 13, weight: .bold))
                    Text("Aleatorio").font(.montserrat(13, .semibold))
                }
                .foregroundStyle(Ink.text)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .surface(prefs, RoundedRectangle(cornerRadius: 12, style: .continuous), border: Color(hex: 0x2C2C32), interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.97))

            if playlist == nil {
                SortMenu()
                if ui.tab == .songs {
                    RefreshButton()
                }
            }
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
                    if !songs.isEmpty {
                        actions(songs)
                            .plainRow()
                            .moveDisabled(true)
                    }

                    if let playlist, !reordering {
                        Button {
                            ui.sheet = .picker(playlistId: playlist.id)
                        } label: {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(hex: 0x3A3A42), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(accent))
                                Text("Añadir canciones")
                                    .font(.montserrat(15, .semibold))
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
                    .onMove(perform: reorderAction)

                    emptyState(songs)
                        .plainRow()

                    if let playlist, !reordering {
                        Button("Eliminar lista") { ui.modal = .deleteList(playlistId: playlist.id) }
                            .font(.montserrat(14, .semibold))
                            .foregroundStyle(Ink.danger)
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                            .plainRow()
                    }

                    Color.clear
                        .frame(height: hasCurrent ? 96 : 16)
                        .plainRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
                .scrollDismissesKeyboard(.immediately)
                .environment(\.editMode, .constant(reordering ? .active : .inactive))
                // Como Poweramp: al volver de la reproducción, la canción que suena ya
                // está centrada. Se centra mientras la reproducción tapa la lista
                // (al terminar de abrirse y después de cada cambio de canción), así
                // al cerrar no queda nada por hacer y la animación va limpia.
                .onReceive(ui.presence.$open.debounce(for: .seconds(0.6), scheduler: RunLoop.main)) { open in
                    if open { center(proxy, songs, force: true) }
                }
                .onReceive(player.$currentId.debounce(for: .seconds(0.9), scheduler: RunLoop.main)) { _ in
                    if ui.npOpen { center(proxy, songs, force: true) }
                }
                // Si se cierra antes de que alcance a centrarse.
                .onReceive(ui.reveal) { _ in center(proxy, songs, force: false) }
                // Con onReceive en vez de onChange: así esta vista no se suscribe
                // al índice y arrastrarlo no la vuelve a armar en cada letra.
                .onReceive(ui.az.$letter) { letter in
                    guard let letter, let target = library.firstSong(fromLetter: letter) else { return }
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    /// Centra la canción que suena, sin animación (ocurre detrás de la reproducción).
    private func center(_ proxy: ScrollViewProxy, _ songs: [Song], force: Bool) {
        guard let id = player.currentId, force || centered.id != id,
              songs.contains(where: { $0.id == id }) else { return }
        centered.id = id
        proxy.scrollTo(id, anchor: .center)
    }

    /// Solo dentro de una lista y con "Ordenar" activo.
    private var reorderAction: ((IndexSet, Int) -> Void)? {
        guard reordering, let playlist else { return nil }
        let id = playlist.id
        return { from, to in
            library.movePlaylistSongs(id, from: from, to: to)
            Haptics.tick()
        }
    }

    @ViewBuilder
    private func emptyState(_ songs: [Song]) -> some View {
        if !songs.isEmpty {
            EmptyView()
        } else if ui.tab == .songs && library.songs.isEmpty {
            EmptyLibrary()
        } else if !trimmedQuery.isEmpty && ui.tab != .lists {
            VStack(spacing: 6) {
                Text("Sin resultados").font(.montserrat(16, .semibold)).foregroundStyle(Ink.text)
                Text("No hay canciones para “\(ui.query)”").font(.montserrat(13)).foregroundStyle(Ink.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 32)
        } else if ui.tab == .favs {
            VStack(spacing: 10) {
                Image(systemName: "heart")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color(hex: 0x5A5A62))
                Text("Aún no tienes favoritos").font(.montserrat(17, .bold)).foregroundStyle(Ink.text)
                Text("Toca el corazón mientras suena una canción para guardarla aquí.")
                    .font(.montserrat(14)).foregroundStyle(Ink.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 64)
            .padding(.horizontal, 40)
        } else if playlist != nil {
            VStack(spacing: 8) {
                Text("Esta lista está vacía").font(.montserrat(17, .bold)).foregroundStyle(Ink.text)
                Text("Añade canciones para escucharlas aparte.")
                    .font(.montserrat(14)).foregroundStyle(Ink.dim)
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
                        .font(.montserrat(15, .semibold))
                        .foregroundStyle(isCurrent ? accent : Ink.text)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.montserrat(13))
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
            Button { ui.sheet = .editTags(songId: song.id) } label: {
                Label("Editar información…", systemImage: "pencil")
            }
            Button { ui.sheet = .cover(songId: song.id) } label: {
                Label(song.hasArtwork ? "Cambiar portada…" : "Buscar portada…", systemImage: "photo")
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
                            .font(.montserrat(16, .semibold))
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
                                    .font(.montserrat(16, .semibold))
                                    .foregroundStyle(Ink.text)
                                    .lineLimit(1)
                                Text(Format.count(p.songIds.count, "canción", "canciones"))
                                    .font(.montserrat(13))
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
                .font(.montserrat(size * 0.4, .heavy))
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
                .font(.montserrat(17, .bold))
                .foregroundStyle(Ink.text)
            Text("Importa archivos de audio o cópialos a la carpeta SoundFast desde la app Archivos o desde “Dispositivos Apple” en Windows.")
                .font(.montserrat(14))
                .foregroundStyle(Ink.dim)
                .multilineTextAlignment(.center)
            Button {
                ui.importing = true
            } label: {
                Text("Importar archivos")
                    .font(.montserrat(14, .bold))
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
                .font(.montserrat(14, .semibold))
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
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            tab(.songs, "Canciones", "music.note")
            tab(.favs, "Favoritos", "heart")
            tab(.lists, "Listas", "music.note.list")
        }
        .padding(5)
        .glassSurface(prefs, Capsule())
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
    }

    private func tab(_ t: AppUI.Tab, _ label: String, _ icon: String) -> some View {
        let on = ui.tab == t
        return Button {
            if t != .lists { ui.openList = nil }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { ui.tab = t }
            Haptics.soft()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: on && t == .favs ? "heart.fill" : icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.montserrat(10.5, .semibold))
            }
            .foregroundStyle(on ? prefs.accent.color : Ink.tabOff)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if on {
                    Capsule()
                        .fill(prefs.accent.alpha(0.16))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ordenar y actualizar

/// Menú de orden: criterio y dirección.
struct SortMenu: View {
    @EnvironmentObject private var prefs: Preferences

    private var directionLabels: (asc: String, desc: String) {
        switch prefs.playback.sortBy {
        case "fecha": return ("Más antiguas primero", "Más recientes primero")
        case "duracion": return ("Más cortas primero", "Más largas primero")
        default: return ("A → Z", "Z → A")
        }
    }

    var body: some View {
        Menu {
            Picker("Ordenar por", selection: $prefs.playback.sortBy) {
                ForEach(PlaybackSettings.sortOptions, id: \.id) { option in
                    Label(option.name, systemImage: option.icon).tag(option.id)
                }
            }
            Picker("Dirección", selection: $prefs.playback.sortAscending) {
                Label(directionLabels.asc, systemImage: "arrow.up").tag(true)
                Label(directionLabels.desc, systemImage: "arrow.down").tag(false)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Ink.text)
                .frame(width: 42, height: 42)
                .surface(prefs, RoundedRectangle(cornerRadius: 12, style: .continuous), border: Color(hex: 0x2C2C32), interactive: true)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Ordenar canciones")
        .onChange(of: prefs.playback.sortBy) { _, _ in Haptics.soft() }
        .onChange(of: prefs.playback.sortAscending) { _, _ in Haptics.soft() }
    }
}

/// Busca canciones nuevas (importadas, copiadas desde Archivos o desde Windows).
struct RefreshButton: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Button {
            Haptics.tap()
            Task { await library.refresh(announce: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(library.isScanning ? prefs.accent.color : Ink.text)
                .rotationEffect(.degrees(library.isScanning ? 360 : 0))
                .animation(
                    library.isScanning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                    value: library.isScanning
                )
                .frame(width: 42, height: 42)
                .surface(prefs, RoundedRectangle(cornerRadius: 12, style: .continuous), border: Color(hex: 0x2C2C32), interactive: true)
        }
        .buttonStyle(PressableStyle())
        .disabled(library.isScanning)
        .accessibilityLabel("Actualizar biblioteca")
    }
}
