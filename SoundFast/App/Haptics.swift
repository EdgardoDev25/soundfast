import UIKit

/// Vibraciones cortas. Respetan el ajuste "Vibración".
@MainActor
enum Haptics {
    static var enabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let selection = UISelectionFeedbackGenerator()

    /// Toque normal (reproducir, cambiar canción…).
    static func tap() {
        guard enabled else { return }
        medium.impactOccurred(intensity: 0.7)
        medium.prepare()
    }

    /// Toque suave (interruptores, chips).
    static func soft() {
        guard enabled else { return }
        light.impactOccurred()
        light.prepare()
    }

    /// Paso de un control (índice A–Z, perillas, arrastres).
    static func tick() {
        guard enabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    /// Despierta el motor de vibración antes de un gesto. Si está dormido, la
    /// primera vibración detiene el hilo principal unos milisegundos y se ve
    /// como un tirón en la animación.
    static func warmUp() {
        guard enabled else { return }
        light.prepare()
        selection.prepare()
    }
}
