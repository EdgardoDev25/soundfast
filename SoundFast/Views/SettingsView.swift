import MediaPlayer
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var covers: CoverService
    @Environment(\.openURL) private var openURL

    private var accent: Color { prefs.accent.color }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Ajustes") { Color.clear.frame(width: 1, height: 1) }

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
                        .font(.montserrat(12))
                        .foregroundStyle(Ink.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                // Espacio para el minirreproductor, que sigue visible abajo.
                .padding(.bottom, player.current != nil ? 100 : 48)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Encabezado

    private var profile: some View {
        HStack(spacing: 14) {
            Image("AppIconImage")
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("SoundFast").font(.montserrat(19, .heavy)).foregroundStyle(Ink.text)
                Button {
                    if let url = URL(string: "https://edgfast.com") { openURL(url) }
                } label: {
                    HStack(spacing: 4) {
                        Text("Desarrollado por Edgardo Rocha")
                            .font(.montserrat(13, .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre edgfast.com")
                Text(
                    Format.count(library.songs.count, "canción", "canciones") + " · "
                        + Format.count(library.playlists.count, "lista", "listas") + " · "
                        + Format.count(library.favorites.count, "favorito", "favoritos")
                )
                .font(.montserrat(12))
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
                        Text("Color de acento").font(.montserrat(15, .medium)).foregroundStyle(Ink.text)
                        Spacer()
                        Text(prefs.accent.name).font(.montserrat(13)).foregroundStyle(Ink.dim)
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
                    Text("Tema").font(.montserrat(15, .medium)).foregroundStyle(Ink.text)
                    HStack(spacing: 8) {
                        ForEach(AppTheme.all) { t in
                            Button {
                                prefs.look.theme = t.id
                                Haptics.soft()
                            } label: {
                                VStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(t.surf2).frame(height: 14)
                                    Spacer(minLength: 0)
                                    Text(t.name).font(.montserrat(11, .semibold)).foregroundStyle(Color(hex: 0xE6E5E9))
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 70)
                                .background(
                                    t.glass
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [.oklch(0.5, 0.16, prefs.accent.h), .oklch(0.4, 0.15, prefs.accent.h + 70)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(t.bg),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(t.id == prefs.theme.id ? accent : Ink.chipBorder, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if prefs.theme.glass {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Desenfoque del vidrio").font(.montserrat(15, .medium)).foregroundStyle(Ink.text)
                            Spacer()
                            Text(glassLabel).font(.montserrat(13)).foregroundStyle(Ink.dim)
                        }
                        UnitSlider(value: prefs.look.glassBlur, accent: accent, label: "Desenfoque del vidrio") {
                            prefs.look.glassBlur = $0
                        }
                        Text("Menos: vidrio transparente, se ve el fondo. Más: vidrio esmerilado.")
                            .font(.montserrat(12)).foregroundStyle(Ink.dim)
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
                        .font(.montserrat(13, .semibold))
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
            Text(title).font(.montserrat(15, .medium)).foregroundStyle(Ink.text)
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
                        Text("Fundido entre canciones").font(.montserrat(15)).foregroundStyle(Ink.text)
                        Spacer()
                        Text(prefs.playback.crossfade > 0 ? "\(prefs.playback.crossfade) s" : "Apagado")
                            .font(.mono(13))
                            .foregroundStyle(Ink.dim)
                    }
                    CrossfadeSlider(value: prefs.playback.crossfade, accent: accent) { prefs.playback.crossfade = $0 }
                    Text(prefs.playback.crossfade > 0
                         ? "Una canción se desvanece mientras entra la siguiente."
                         : "Sin fundido, las canciones se encadenan sin silencios.")
                        .font(.montserrat(12))
                        .foregroundStyle(Ink.dim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                divider
                toggleRow("Reproducción sin pausas", "Para álbumes en vivo y mezclas continuas", isOn: prefs.playback.gapless) {
                    prefs.playback.gapless.toggle()
                }
                divider
                toggleRow("Normalizar volumen", "Iguala el volumen entre canciones grabadas más bajas o más fuertes", isOn: prefs.playback.normalize) {
                    prefs.playback.normalize.toggle()
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
                    ui.openSound()
                }
                divider
                // Un ajuste por salida: los graves potenciados para los audífonos
                // y otro para el parlante. Se elige solo al conectar.
                SoundProfileMenu()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                divider
                HStack {
                    Text("Salida de audio").font(.montserrat(15)).foregroundStyle(Ink.text)
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
                    Text("Barra de progreso").font(.montserrat(15)).foregroundStyle(Ink.text)
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
                    Text("Ordenar canciones por").font(.montserrat(15)).foregroundStyle(Ink.text)
                    Spacer()
                    Menu {
                        Picker("Ordenar", selection: $prefs.playback.sortBy) {
                            ForEach(PlaybackSettings.sortOptions, id: \.id) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        Picker("Dirección", selection: $prefs.playback.sortAscending) {
                            Text("Ascendente").tag(true)
                            Text("Descendente").tag(false)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sortLabel).font(.montserrat(14)).foregroundStyle(Ink.dim)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.dim)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                divider
                toggleRow("Índice A–Z", "Solo al ordenar por título (A → Z)", isOn: prefs.playback.showAz) {
                    prefs.playback.showAz.toggle()
                }
                divider
                actionRow("Importar canciones", "MP3, M4A, FLAC o WAV desde Archivos o iCloud Drive") {
                    ui.importing = true
                }
                divider
                actionRow("Actualizar biblioteca", refreshSubtitle) {
                    Task { await library.refresh(announce: true) }
                    Haptics.tap()
                }
                divider
                coversRow
                divider
                navRow("Limpiar títulos", value: library.cleaned.isEmpty ? nil : "\(library.cleaned.count) limpios") {
                    ui.sheet = .cleanTitles
                }
                divider
                navRow("Canciones duplicadas", value: nil) {
                    ui.sheet = .duplicates
                }
                divider
                navRow("Formatos y archivos", value: nil) {
                    ui.sheet = .formats
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
                divider
                navRow("Fuente", value: FontRegistry.status, chevron: false) {}
            }
        }
    }

    private var glassLabel: String {
        switch prefs.look.glassBlur {
        case ..<0.34: return "Transparente"
        case ..<0.67: return "Medio"
        default: return "Esmerilado"
        }
    }

    @ViewBuilder
    private var coversRow: some View {
        if covers.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Descargando portadas…").font(.montserrat(15, .semibold)).foregroundStyle(Ink.text)
                    Spacer()
                    Button("Detener") { covers.cancel() }
                        .font(.montserrat(13, .semibold))
                        .foregroundStyle(Ink.danger)
                        .buttonStyle(.plain)
                }
                ProgressView(value: Double(covers.done), total: Double(max(1, covers.total)))
                    .tint(accent)
                Text("\(covers.done) de \(covers.total) · puedes seguir usando la app")
                    .font(.montserrat(12)).foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } else {
            let missing = covers.missingCount
            actionRow(
                "Descargar portadas",
                missing > 0
                    ? Format.count(missing, "canción sin portada", "canciones sin portada") + " · se buscan en internet"
                    : "Todas tus canciones tienen portada. Para cambiar una: mantén presionada la canción."
            ) {
                covers.downloadMissing()
                Haptics.tap()
            }
            .disabled(missing == 0)
        }
    }

    private var sortLabel: String {
        let name = PlaybackSettings.sortOptions.first { $0.id == prefs.playback.sortBy }?.name ?? "Título"
        let short = name == "Fecha de incorporación" ? "Fecha" : name
        return short + (prefs.playback.sortAscending ? " ↑" : " ↓")
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
            .surface(prefs, RoundedRectangle(cornerRadius: 18, style: .continuous), border: Ink.cardBorder)
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
                    Text(label).font(.montserrat(15)).foregroundStyle(Ink.text)
                    if let sub { Text(sub).font(.montserrat(12)).foregroundStyle(Ink.dim) }
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
                Text(label).font(.montserrat(15)).foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                if let value { Text(value).font(.montserrat(14)).foregroundStyle(Ink.dim).lineLimit(1) }
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
                Text(label).font(.montserrat(15, .semibold)).foregroundStyle(accent)
                if let sub { Text(sub).font(.montserrat(12)).foregroundStyle(Ink.dim) }
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
                .font(.montserrat(12, .semibold))
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
