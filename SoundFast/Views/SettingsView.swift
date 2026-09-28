import MediaPlayer
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var ui: AppUI
    @Environment(\.dismiss) private var dismiss

    private var accent: Color { prefs.accent.color }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Ink.text)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Cerrar")
                Spacer()
                Text("Ajustes").font(.sora(17, .bold)).foregroundStyle(Ink.text)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    profile
                    appearance
                    playbackSection
                    soundSection
                    gesturesSection
                    librarySection
                    aboutSection
                    Text("SoundFast · Hecho para iPhone")
                        .font(.sora(12))
                        .foregroundStyle(Ink.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .background(prefs.theme.bg.ignoresSafeArea())
    }

    // MARK: Encabezado

    private var profile: some View {
        HStack(spacing: 14) {
            Text("S")
                .font(.sora(30, .heavy))
                .tracking(-1.2)
                .foregroundStyle(Ink.onAccent)
                .frame(width: 58, height: 58)
                .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("SoundFast").font(.sora(19, .heavy)).foregroundStyle(Ink.text)
                Text(
                    Format.count(library.songs.count, "canción", "canciones") + " · "
                        + Format.count(library.playlists.count, "lista", "listas") + " · "
                        + Format.count(library.favorites.count, "favorito", "favoritos")
                )
                .font(.sora(12))
                .foregroundStyle(Ink.dim)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    // MARK: Apariencia

    private var appearance: some View {
        section("APARIENCIA") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Color de acento").font(.sora(15, .medium)).foregroundStyle(Ink.text)
                        Spacer()
                        Text(prefs.accent.name).font(.sora(13)).foregroundStyle(Ink.dim)
                    }
                    HStack {
                        ForEach(Accent.all) { a in
                            Button {
                                prefs.look.accent = a.id
                                Haptics.soft()
                            } label: {
                                Circle()
                                    .fill(a.color)
                                    .frame(width: 32, height: 32)
                                    .padding(3)
                                    .overlay(Circle().stroke(a.id == prefs.accent.id ? a.color : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(a.name)
                            if a.id != Accent.all.last?.id { Spacer(minLength: 0) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tema").font(.sora(15, .medium)).foregroundStyle(Ink.text)
                    HStack(spacing: 8) {
                        ForEach(AppTheme.all) { t in
                            Button {
                                prefs.look.theme = t.id
                                Haptics.soft()
                            } label: {
                                VStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(t.surf2).frame(height: 14)
                                    Spacer(minLength: 0)
                                    Text(t.name).font(.sora(11, .semibold)).foregroundStyle(Color(hex: 0xE6E5E9))
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 70)
                                .background(t.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(t.id == prefs.theme.id ? accent : Ink.chipBorder, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                optionRow("Fondo al reproducir", options: [("suave", "Portada suave"), ("intenso", "Intenso"), ("tema", "Tema")],
                          selected: prefs.look.npBg) { prefs.look.npBg = $0 }
                optionRow("Forma de la portada", options: [("redondeada", "Redonda"), ("cuadrada", "Recta"), ("circulo", "Disco")],
                          selected: prefs.look.artShape) { prefs.look.artShape = $0 }
                optionRow("Botón de reproducir", options: [("circulo", "Círculo"), ("cuadrado", "Cuadrado")],
                          selected: prefs.look.playShape) { prefs.look.playShape = $0 }

                Button {
                    prefs.resetLook()
                    Haptics.tap()
                } label: {
                    Text("Restablecer apariencia")
                        .font(.sora(13, .semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .card(prefs, radius: 18)
        }
    }

    private func optionRow(_ title: String, options: [(String, String)], selected: String,
                           set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.sora(15, .medium)).foregroundStyle(Ink.text)
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    Chip(label: option.1, selected: selected == option.0, fullWidth: true) { set(option.0) }
                }
            }
        }
    }

    // MARK: Secciones

    private var playbackSection: some View {
        section("REPRODUCCIÓN") {
            group {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Fundido entre canciones").font(.sora(15)).foregroundStyle(Ink.text)
                        Spacer()
                        Text(prefs.playback.crossfade > 0 ? "\(prefs.playback.crossfade) s" : "Apagado")
                            .font(.mono(13))
                            .foregroundStyle(Ink.dim)
                    }
                    CrossfadeSlider(value: prefs.playback.crossfade, accent: accent) { prefs.playback.crossfade = $0 }
                    Text(prefs.playback.crossfade > 0
                         ? "Una canción se desvanece mientras entra la siguiente."
                         : "Sin fundido, las canciones se encadenan sin silencios.")
                        .font(.sora(12))
                        .foregroundStyle(Ink.dim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                divider
                toggleRow("Reproducción sin pausas", "Para álbumes en vivo y mezclas continuas", isOn: prefs.playback.gapless) {
                    prefs.playback.gapless.toggle()
                }
                divider
                toggleRow("Reanudar al conectar auriculares", nil, isOn: prefs.playback.headphones) {
                    prefs.playback.headphones.toggle()
                }
            }
        }
    }

    private var soundSection: some View {
        section("SONIDO") {
            group {
                navRow("Ecualizador y graves", value: prefs.sound.eqOn ? prefs.sound.preset : "Apagado") {
                    dismiss()
                    Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        ui.soundOpen = true
                    }
                }
                divider
                HStack {
                    Text("Salida de audio").font(.sora(15)).foregroundStyle(Ink.text)
                    Spacer()
                    RoutePicker(tint: Ink.dim, activeTint: accent)
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
        }
    }

    private var gesturesSection: some View {
        section("GESTOS Y RESPUESTA") {
            group {
                toggleRow("Deslizar portada para cambiar", "Izquierda: siguiente · Derecha: anterior", isOn: prefs.playback.swipeArt) {
                    prefs.playback.swipeArt.toggle()
                }
                divider
                toggleRow("Vibración", nil, isOn: prefs.playback.haptics) {
                    prefs.playback.haptics.toggle()
                }
                divider
                HStack {
                    Text("Barra de progreso").font(.sora(15)).foregroundStyle(Ink.text)
                    Spacer()
                    HStack(spacing: 0) {
                        segment("Onda", on: prefs.playback.seekStyle == "onda") { prefs.playback.seekStyle = "onda" }
                        segment("Línea", on: prefs.playback.seekStyle != "onda") { prefs.playback.seekStyle = "linea" }
                    }
                    .padding(3)
                    .background(Color(hex: 0x1E1E23), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
        }
    }

    private var librarySection: some View {
        section("BIBLIOTECA") {
            group {
                HStack {
                    Text("Ordenar canciones por").font(.sora(15)).foregroundStyle(Ink.text)
                    Spacer()
                    Menu {
                        Picker("Ordenar", selection: $prefs.playback.sortBy) {
                            Text("Título").tag("titulo")
                            Text("Artista").tag("artista")
                            Text("Recientes").tag("recientes")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sortLabel).font(.sora(14)).foregroundStyle(Ink.dim)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.dim)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                divider
                toggleRow("Índice A–Z", "Solo al ordenar por título", isOn: prefs.playback.showAz) {
                    prefs.playback.showAz.toggle()
                }
                divider
                actionRow("Importar canciones", "MP3, M4A, FLAC o WAV desde Archivos o iCloud Drive") {
                    dismiss()
                    Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        ui.importing = true
                    }
                }
                divider
                actionRow("Actualizar biblioteca", refreshSubtitle) {
                    Task { await library.refresh() }
                    Haptics.tap()
                }
                divider
                musicAccessRow
            }
        }
    }

    private var aboutSection: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let date = info["SFBuildDate"] as? String ?? "—"
        return section("ACERCA DE") {
            group {
                navRow("Versión", value: "\(version) (\(build))", chevron: false) {}
                divider
                navRow("Compilada", value: date, chevron: false) {}
            }
        }
    }

    private var sortLabel: String {
        switch prefs.playback.sortBy {
        case "artista": return "Artista"
        case "recientes": return "Recientes"
        default: return "Título"
        }
    }

    private var refreshSubtitle: String {
        if library.isScanning { return "Buscando canciones…" }
        if library.lastScan != nil { return "Actualizada hace un momento" }
        return "Busca canciones nuevas en tu iPhone"
    }

    @ViewBuilder
    private var musicAccessRow: some View {
        switch library.musicAccess {
        case .authorized:
            navRow("Biblioteca de Música", value: "Conectada", chevron: false) {}
        case .denied, .restricted:
            actionRow("Biblioteca de Música", "Sin permiso. Toca para abrir Ajustes del iPhone.") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        default:
            actionRow("Usar la biblioteca de Música", "Canciones descargadas o pasadas con iTunes (sin DRM)") {
                Task { await library.requestMusicAccess() }
            }
        }
    }

    // MARK: Piezas

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow(color: Ink.dim).padding(.leading, 4)
            content()
        }
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(prefs.theme.surf, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Ink.cardBorder, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Ink.cardBorder).frame(height: 1).padding(.leading, 16)
    }

    private func toggleRow(_ label: String, _ sub: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.soft()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.sora(15)).foregroundStyle(Ink.text)
                    if let sub { Text(sub).font(.sora(12)).foregroundStyle(Ink.dim) }
                }
                Spacer(minLength: 0)
                SwitchView(isOn: isOn, accent: accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "Activado" : "Desactivado")
    }

    private func navRow(_ label: String, value: String?, chevron: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.sora(15)).foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                if let value { Text(value).font(.sora(14)).foregroundStyle(Ink.dim).lineLimit(1) }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x5A5A62))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(!chevron)
    }

    private func actionRow(_ label: String, _ sub: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.sora(15, .semibold)).foregroundStyle(accent)
                if let sub { Text(sub).font(.sora(12)).foregroundStyle(Ink.dim) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func segment(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.soft()
        } label: {
            Text(label)
                .font(.sora(12, .semibold))
                .foregroundStyle(on ? Ink.onAccent : Ink.chipText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(on ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Deslizador 0–12 s del fundido.
struct CrossfadeSlider: View {
    let value: Int
    let accent: Color
    let onChange: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let pct = CGFloat(value) / 12
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track).frame(height: 5)
                Capsule().fill(accent).frame(width: max(5, geo.size.width * pct), height: 5)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                    .frame(width: 20, height: 20)
                    .offset(x: (geo.size.width - 20) * pct)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = Int((min(max(0, g.location.x / max(1, geo.size.width)), 1) * 12).rounded())
                        if v != value {
                            Haptics.tick()
                            onChange(v)
                        }
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Fundido entre canciones")
        .accessibilityValue(value > 0 ? "\(value) segundos" : "Apagado")
        .accessibilityAdjustableAction { dir in
            onChange(min(12, max(0, value + (dir == .increment ? 1 : -1))))
        }
    }
}
