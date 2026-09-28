import AVKit
import SwiftUI

/// Estado de navegación de la interfaz.
@MainActor
final class AppUI: ObservableObject {
    enum Tab { case songs, favs, lists }

    enum Sheet: Identifiable {
        case queue
        case addTo(songId: String)
        case picker(playlistId: String)

        var id: String {
            switch self {
            case .queue: return "queue"
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
    @Published var npDrag: CGFloat = 0
    @Published var soundOpen = false
    @Published var settingsOpen = false
    @Published var sheet: Sheet?
    @Published var modal: Modal?
    @Published var importing = false
    @Published var azLetter: String?

    /// Para `.alert(isPresented:)`.
    var modalShown: Bool {
        get { modal != nil }
        set { if !newValue { modal = nil } }
    }

    func openNowPlaying() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            npOpen = true
            npDrag = 0
        }
    }

    func closeNowPlaying() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            npOpen = false
            npDrag = 0
        }
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
                .background(prefs.theme.surf, in: Circle())
                .overlay(Circle().stroke(Ink.border, lineWidth: 1))
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
                .font(mono ? .mono(12, .bold) : .sora(13, .semibold))
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

    var body: some View {
        ZStack {
            (song.map { ArtColors.bg($0.hue) } ?? Color(hex: 0x2A2A30))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(song?.initial ?? "")
                    .font(.sora(letterSize, .heavy))
                    .tracking(-letterSize * 0.03)
                    .foregroundStyle(song.map { ArtColors.fg($0.hue) } ?? Ink.dim)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: song?.id) {
            guard let song else {
                image = nil
                return
            }
            image = artwork.cached(song)
            if image == nil { image = await artwork.load(song) }
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
            .font(.sora(13, .semibold))
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
            .background(prefs.theme.surf, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Ink.cardBorder, lineWidth: 1))
    }
}
