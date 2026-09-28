import SwiftUI
import UIKit

// MARK: - Encabezado común

private struct SheetHeader: View {
    let title: String
    let subtitle: String
    let onDone: () -> Void
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.montserrat(20, .heavy)).foregroundStyle(Ink.text).lineLimit(1)
                Text(subtitle).font(.montserrat(13)).foregroundStyle(Ink.dim).lineLimit(1)
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
    func sheetStyle(_ prefs: Preferences) -> some View {
        self.presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .sheetBackground(prefs)
            .presentationCornerRadius(28)
    }
}

// MARK: - Cola

struct QueueSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let upcoming = player.upcoming
        VStack(spacing: 0) {
            SheetHeader(
                title: "A continuación",
                subtitle: "Desde \(player.ctxName) · \(upcoming.count) por sonar"
            ) { dismiss() }

            if let current = player.current {
                HStack(spacing: 12) {
                    ArtworkView(song: current, size: 44, radius: 9, letterSize: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.title).font(.montserrat(15, .semibold)).foregroundStyle(prefs.accent.color).lineLimit(1)
                        Text("SONANDO AHORA").eyebrow(10, color: Ink.dim)
                    }
                    Spacer(minLength: 0)
                    PlayingBars(color: prefs.accent.color, animating: player.isPlaying)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.04))
            }

            if upcoming.isEmpty {
                Text("No hay más canciones en la cola")
                    .font(.montserrat(14))
                    .foregroundStyle(Ink.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(upcoming, id: \.self) { id in
                        let song = library.song(id)
                        HStack(spacing: 12) {
                            ArtworkView(song: song, size: 44, radius: 9, letterSize: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song?.title ?? "—").font(.montserrat(15, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                                Text(song?.artist ?? "").font(.montserrat(13)).foregroundStyle(Ink.dim).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { player.playFromQueue(id) }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { player.moveUpcoming(from: $0, to: $1) }
                    .onDelete { offsets in
                        let ids = offsets.map { upcoming[$0] }
                        ids.forEach { player.removeFromQueue($0) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
                .tint(prefs.accent.color)
            }
        }
        .sheetStyle(prefs)
    }
}

// MARK: - Añadir una canción a listas

struct AddToPlaylistSheet: View {
    let songId: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        let song = library.song(songId)
        VStack(spacing: 0) {
            SheetHeader(
                title: "Añadir a una lista",
                subtitle: song.map { "\($0.title) · \($0.artist)" } ?? ""
            ) { dismiss() }

            ScrollView {
                LazyVStack(spacing: 0) {
                    Button {
                        newName = ""
                        creating = true
                    } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(hex: 0x3A3A42), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(width: 52, height: 52)
                                .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(prefs.accent.color))
                            Text("Nueva lista").font(.montserrat(16, .semibold)).foregroundStyle(prefs.accent.color)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 68)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())

                    ForEach(library.playlists) { p in
                        let checked = p.songIds.contains(songId)
                        Button {
                            library.toggle(songId, in: p.id)
                            Haptics.soft()
                        } label: {
                            HStack(spacing: 14) {
                                PlaylistTile(playlist: p, size: 52)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.name).font(.montserrat(16, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                                    Text(Format.count(p.songIds.count, "canción", "canciones")).font(.montserrat(13)).foregroundStyle(Ink.dim)
                                }
                                Spacer(minLength: 0)
                                CheckCircle(checked: checked, accent: prefs.accent.color)
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 68)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .sheetStyle(prefs)
        .alert("Nueva lista", isPresented: $creating) {
            TextField("Ej. Para entrenar", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") {
                library.createPlaylist(named: newName, with: songId)
                Haptics.tap()
            }
        } message: {
            Text("Ponle el nombre que quieras: un género, un ánimo, un momento.")
        }
    }
}

// MARK: - Elegir canciones para una lista

struct SongPickerSheet: View {
    let playlistId: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let playlist = library.playlist(playlistId)
        let selected = Set(playlist?.songIds ?? [])
        // Filtra la biblioteca, que tiene el texto ya preparado: hacerlo aquí
        // repasaba todos los títulos en cada letra que se escribía.
        let songs = library.visible(query: query, favoritesOnly: false)
        VStack(spacing: 0) {
            SheetHeader(
                title: "Añadir a “\(playlist?.name ?? "")”",
                subtitle: "\(selected.count) seleccionadas"
            ) { dismiss() }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.dim)
                TextField("", text: $query, prompt: Text("Buscar").foregroundColor(Ink.muted))
                    .font(.montserrat(15))
                    .foregroundStyle(Ink.text)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .surface(prefs, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(songs) { s in
                        Button {
                            library.toggle(s.id, in: playlistId)
                            Haptics.soft()
                        } label: {
                            HStack(spacing: 14) {
                                ArtworkView(song: s, size: 44, radius: 9, letterSize: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title).font(.montserrat(15, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                                    Text(s.artist).font(.montserrat(13)).foregroundStyle(Ink.dim).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                CheckCircle(checked: selected.contains(s.id), accent: prefs.accent.color)
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .sheetStyle(prefs)
    }
}

// MARK: - Primer inicio

struct OnboardingView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var ui: AppUI

    private var denied: Bool { library.musicAccess == .denied || library.musicAccess == .restricted }

    var body: some View {
        let accent = prefs.accent.color
        VStack(spacing: 0) {
            Spacer()
            Text("S")
                .font(.montserrat(48, .heavy))
                .tracking(-2)
                .foregroundStyle(Ink.onAccent)
                .frame(width: 96, height: 96)
                .background(accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: prefs.accent.alpha(0.35), radius: 24, y: 14)
            VStack(spacing: 12) {
                Text(denied ? "Sin acceso a tu música" : "Tu música, a tu manera")
                    .font(.montserrat(28, .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                Text(denied
                     ? "Para ver tus canciones, activa el acceso en Ajustes › SoundFast › Apple Music y biblioteca multimedia. También puedes importar archivos."
                     : "SoundFast lee tu biblioteca para mostrar tus canciones, favoritos y listas, con ecualizador y graves a tu medida. También puedes importar MP3, M4A o FLAC.")
                    .font(.montserrat(15))
                    .foregroundStyle(Ink.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    if denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } else {
                        Task {
                            await library.requestMusicAccess()
                            if library.hasMusicAccess { library.onboarded = true }
                        }
                    }
                } label: {
                    Text(denied ? "Abrir Ajustes" : "Permitir acceso a Música")
                        .font(.montserrat(16, .bold))
                        .foregroundStyle(Ink.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.97))

                Button {
                    ui.importing = true
                } label: {
                    Text("Importar archivos")
                        .font(.montserrat(16, .semibold))
                        .foregroundStyle(Ink.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .surface(prefs, RoundedRectangle(cornerRadius: 16, style: .continuous), border: Ink.border)
                }
                .buttonStyle(PressableStyle(scale: 0.97))

                Button("Ahora no") { library.onboarded = true }
                    .font(.montserrat(14, .semibold))
                    .foregroundStyle(Ink.dim)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
            if library.isScanning {
                ProgressView().tint(accent).padding(.top, 12)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeBackground())
    }
}
