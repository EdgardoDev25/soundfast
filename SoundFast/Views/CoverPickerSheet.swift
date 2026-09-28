import SwiftUI

/// Elegir la portada de una canción entre resultados de internet.
struct CoverPickerSheet: View {
    let songId: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var covers: CoverService
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [CoverCandidate] = []
    @State private var loading = false
    @State private var applying: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let song = library.song(songId)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Portada").font(.montserrat(20, .heavy)).foregroundStyle(Ink.text)
                    Text(song.map { "\($0.title) · \($0.artist)" } ?? "")
                        .font(.montserrat(13)).foregroundStyle(Ink.dim).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button("Listo") { dismiss() }
                    .font(.montserrat(15, .semibold))
                    .foregroundStyle(prefs.accent.color)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.dim)
                TextField("", text: $query, prompt: Text("Artista y canción o álbum").foregroundColor(Ink.muted))
                    .font(.montserrat(15))
                    .foregroundStyle(Ink.text)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .surface(prefs, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                if loading {
                    ProgressView().tint(prefs.accent.color).padding(.top, 40)
                } else if results.isEmpty {
                    Text("No se encontraron portadas. Prueba escribiendo el artista y el álbum.")
                        .font(.montserrat(14)).foregroundStyle(Ink.dim)
                        .multilineTextAlignment(.center)
                        .padding(40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(results) { c in
                            Button {
                                Task {
                                    applying = c.id
                                    let ok = await covers.apply(c, to: songId)
                                    applying = nil
                                    Haptics.tap()
                                    if ok { dismiss() }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    AsyncImage(url: c.url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Color.white.opacity(0.06)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        if applying == c.id {
                                            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.5))
                                            ProgressView().tint(.white)
                                        }
                                    }
                                    Text(c.title).font(.montserrat(11, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                                    Text(c.artist).font(.montserrat(10)).foregroundStyle(Ink.dim).lineLimit(1)
                                }
                            }
                            .buttonStyle(PressableStyle(scale: 0.96))
                            .disabled(applying != nil)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetBackground(prefs)
        .presentationCornerRadius(28)
        .task {
            if let song, query.isEmpty { query = CoverService.term(for: song) }
            await search()
        }
    }

    private func search() async {
        guard let song = library.song(songId) else { return }
        loading = true
        results = await covers.candidates(for: song, query: query)
        loading = false
    }
}
