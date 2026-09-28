import PhotosUI
import SwiftUI

/// Editar la información de una canción. Se guarda en SoundFast (el archivo no se modifica).
struct EditTagsSheet: View {
    let songId: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var artwork: ArtworkStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: AppUI
    @Environment(\.dismiss) private var dismiss

    @State private var tags = SongTags()
    @State private var loaded = false
    @State private var photo: PhotosPickerItem?
    @FocusState private var focused: Field?

    private enum Field: Hashable { case title, artist, album, genre, year, track }

    var body: some View {
        let song = library.song(songId)
        VStack(spacing: 0) {
            HStack {
                Button("Cancelar") { dismiss() }
                    .font(.montserrat(15))
                    .foregroundStyle(Ink.dim)
                    .buttonStyle(.plain)
                Spacer()
                Text("Editar información").font(.montserrat(17, .bold)).foregroundStyle(Ink.text)
                Spacer()
                Button("Guardar") { save() }
                    .font(.montserrat(15, .bold))
                    .foregroundStyle(prefs.accent.color)
                    .buttonStyle(.plain)
                    .disabled(!loaded || song.map { SongTags($0) } == tags)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 18) {
                    cover(song)
                    if loaded {
                        fields
                    }
                    Text("Los cambios se guardan en SoundFast; el archivo de audio no se modifica.")
                        .font(.montserrat(12))
                        .foregroundStyle(Ink.faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetBackground(prefs)
        .presentationCornerRadius(28)
        .onAppear {
            if !loaded, let song {
                tags = SongTags(song)
                loaded = true
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await usePhoto(item) }
        }
    }

    // MARK: Portada

    private func cover(_ song: Song?) -> some View {
        HStack(spacing: 16) {
            ArtworkView(song: song, size: 104, radius: 16, letterSize: 44)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Elegir de Fotos", systemImage: "photo.on.rectangle")
                        .font(.montserrat(14, .semibold))
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .glassSurface(prefs, Capsule(), interactive: true)
                }
                Button {
                    // Cambia esta hoja por la de buscar portada en internet.
                    ui.sheet = .cover(songId: songId)
                } label: {
                    Label("Buscar en internet", systemImage: "magnifyingglass")
                        .font(.montserrat(14, .semibold))
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .glassSurface(prefs, Capsule(), interactive: true)
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Campos

    private var fields: some View {
        VStack(spacing: 0) {
            field("Título", \.title, .title)
            divider
            field("Artista", \.artist, .artist)
            divider
            field("Álbum", \.album, .album)
            divider
            field("Género", \.genre, .genre)
            divider
            HStack(spacing: 0) {
                field("Año", \.year, .year, numeric: true)
                Rectangle().fill(Ink.cardBorder).frame(width: 1, height: 36)
                field("Nº de pista", \.track, .track, numeric: true)
            }
        }
        .surface(prefs, RoundedRectangle(cornerRadius: 18, style: .continuous), border: Ink.cardBorder)
    }

    private var divider: some View {
        Rectangle().fill(Ink.cardBorder).frame(height: 1).padding(.leading, 16)
    }

    private func field(_ label: String, _ key: WritableKeyPath<SongTags, String>, _ f: Field, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.montserrat(10, .semibold))
                .tracking(1)
                .foregroundStyle(focused == f ? prefs.accent.color : Ink.dim)
            TextField("", text: $tags[dynamicMember: key],
                      prompt: Text(numeric ? "—" : "Sin \(label.lowercased())").foregroundColor(Ink.faint))
            .font(.montserrat(16, .medium))
            .foregroundStyle(Ink.text)
            .tint(prefs.accent.color)
            .keyboardType(numeric ? .numberPad : .default)
            .textInputAutocapitalization(numeric ? .never : .words)
            .autocorrectionDisabled()
            .focused($focused, equals: f)
            .submitLabel(.next)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focused = f }
    }

    // MARK: Acciones

    private func save() {
        library.updateTags(songId, tags)
        player.updateNowPlaying()
        Haptics.tap()
        dismiss()
    }

    private func usePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              MediaFiles.saveArtwork(image, for: songId) else { return }
        library.markArtwork(songId)
        artwork.invalidate(songId)
        player.updateNowPlaying()
        Haptics.tap()
    }
}
