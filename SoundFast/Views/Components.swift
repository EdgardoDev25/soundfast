import AVKit
import SwiftUI
import UIKit

/// Desplazamiento de "Sonando ahora" mientras se arrastra. Va aparte de AppUI
/// para que, durante el gesto, solo se muevan las capas y no se redibuje la biblioteca.
@MainActor
final class SheetMotion: ObservableObject {
    @Published var drag: CGFloat = 0
}

/// Letra que se está tocando en el índice A–Z. Va aparte de AppUI para que
/// arrastrar el índice no vuelva a filtrar y redibujar la biblioteca entera
/// en cada letra.
@MainActor
final class AZState: ObservableObject {
    @Published var letter: String?
}

/// Estado de navegación de la interfaz.
@MainActor
final class AppUI: ObservableObject {
    enum Tab { case songs, favs, lists }

    enum Sheet: Identifiable {
        case queue
        case effects
        case addTo(songId: String)
        case cover(songId: String)
        case editTags(songId: String)
        case picker(playlistId: String)

        var id: String {
            switch self {
            case .queue: return "queue"
            case .effects: return "effects"
            case .cover(let s): return "cover-\(s)"
            case .editTags(let s): return "tags-\(s)"
            case .addTo(let s): return "addTo-\(s)"
            case .picker(let p): return "picker-\(p)"
            }
        }
    }

    enum Modal: Identifiable {
        case newList(songId: String?)
        case rename(playlistId: String)
        case deleteList(playlistId: String)
        case deleteSong(songId: String)

        var id: String {
            switch self {
            case .newList(let s): return "new-\(s ?? "")"
            case .rename(let p): return "rename-\(p)"
            case .deleteList(let p): return "deleteList-\(p)"
            case .deleteSong(let s): return "deleteSong-\(s)"
            }
        }
    }

    @Published var tab: Tab = .songs
    @Published var openList: String?
    @Published var query = ""
    @Published var npOpen = false
    let motion = SheetMotion()
    /// Sube al cerrar "Sonando ahora": la biblioteca centra la canción que suena.
    @Published private(set) var revealTick = 0
    @Published var soundOpen = false
    @Published var settingsOpen = false
    @Published var sheet: Sheet?
    @Published var modal: Modal?
    @Published var importing = false
    let az = AZState()

    /// Para `.alert(isPresented:)`.
    var modalShown: Bool {
        get { modal != nil }
        set { if !newValue { modal = nil } }
    }

    func openNowPlaying() {
        hideKeyboard()
        Haptics.warmUp()
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
            npOpen = true
            motion.drag = 0
        }
    }

    /// `velocity`: rapidez del dedo al soltar (pt/s), para que el cierre la continúe.
    func closeNowPlaying(velocity: CGFloat = 0) {
        let response = velocity > 1200 ? 0.34 : 0.42
        withAnimation(.spring(response: response, dampingFraction: 0.9)) {
            npOpen = false
            motion.drag = 0
        }
        revealTick += 1
    }

    private let panelSpring = Animation.spring(response: 0.42, dampingFraction: 0.9)

    /// Paneles Sonido y Ajustes (suben desde abajo; el minirreproductor queda encima).
    func openSound() {
        hideKeyboard()
        withAnimation(panelSpring) {
            settingsOpen = false
            soundOpen = true
        }
    }

    func openSettings() {
        hideKeyboard()
        withAnimation(panelSpring) {
            soundOpen = false
            settingsOpen = true
        }
    }

    func closePanels() {
        withAnimation(panelSpring) {
            soundOpen = false
            settingsOpen = false
        }
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Botones

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 42
    let action: () -> Void
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: size, height: size)
                .surface(prefs, Circle(), border: Ink.border, interactive: true)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Botón que se encoge un poco al tocarlo.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Fila que se ilumina al tocarla.
struct RowPressStyle: ButtonStyle {
    var baseColor: Color = .clear

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.06) : baseColor)
    }
}

struct SwitchView: View {
    let isOn: Bool
    let accent: Color

    var body: some View {
        Capsule()
            .fill(isOn ? accent : Ink.switchOff)
            .frame(width: 50, height: 30)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .offset(x: isOn ? 23 : 3)
            }
            .animation(.easeOut(duration: 0.2), value: isOn)
    }
}

struct Chip: View {
    let label: String
    let selected: Bool
    var mono = false
    var fullWidth = false
    let action: () -> Void
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Button {
            action()
            Haptics.soft()
        } label: {
            Text(label)
                .font(mono ? .mono(12, .bold) : .montserrat(13, .semibold))
                .foregroundStyle(selected ? prefs.accent.color : Ink.chipText)
                .padding(.horizontal, fullWidth ? 0 : 14)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: 36)
                .background(selected ? prefs.accent.alpha(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? prefs.accent.color : Ink.chipBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Marca de selección circular (hojas "Añadir a una lista").
struct CheckCircle: View {
    let checked: Bool
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(checked ? accent : Color(hex: 0x4A4A52), lineWidth: 2)
                .background(Circle().fill(checked ? accent : Color.clear))
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Ink.onAccent)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Portada

struct ArtworkView: View {
    let song: Song?
    let size: CGFloat
    var radius: CGFloat = 10
    var letterSize: CGFloat = 20

    @EnvironmentObject private var artwork: ArtworkStore
    @State private var image: UIImage?

    /// Cambia si cambia la canción o si se descargó una portada nueva.
    private var loadKey: String {
        guard let song else { return "" }
        return song.id + "#" + String(artwork.revision[song.id] ?? 0)
    }

    var body: some View {
        ZStack {
            (song.map { ArtColors.bg($0.hue) } ?? Color(hex: 0x2A2A30))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Text(song?.initial ?? "")
                    .font(.montserrat(letterSize, .heavy))
                    .tracking(-letterSize * 0.03)
                    .foregroundStyle(song.map { ArtColors.fg($0.hue) } ?? Ink.dim)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: image)
        .task(id: loadKey) {
            guard let song else {
                image = nil
                return
            }
            image = artwork.cached(song, size: size)
            if image == nil { image = await artwork.load(song, size: size) }
        }
    }
}

/// Barras animadas junto a la canción que suena.
struct PlayingBars: View {
    let color: Color
    let animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let speed = 0.5 + Double(i) * 0.17
                    let phase = (t / speed + Double(i) * 0.3).truncatingRemainder(dividingBy: 2)
                    let v = phase < 1 ? phase : 2 - phase
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 3, height: 14 * (animating ? 0.25 + 0.75 * v : 0.4))
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}

// MARK: - AirPlay / Bluetooth

struct RoutePicker: UIViewRepresentable {
    var tint: Color = .white
    var activeTint: Color

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(activeTint)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(activeTint)
    }
}

// MARK: - Aviso flotante

struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.montserrat(13, .semibold))
            .foregroundStyle(Ink.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0x1F1F24), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: 0x33333A), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 8)
            .padding(.horizontal, 24)
    }
}

extension View {
    /// Tarjeta del prototipo (fondo de superficie, borde fino).
    @MainActor
    func card(_ prefs: Preferences, radius: CGFloat = 24, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .surface(prefs, RoundedRectangle(cornerRadius: radius, style: .continuous), border: Ink.cardBorder)
    }
}
