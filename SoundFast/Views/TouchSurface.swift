import SwiftUI
import UIKit

/// Superficie táctil nativa para perillas y deslizadores.
///
/// Los gestos de SwiftUI dentro de un ScrollView pierden contra el desplazamiento
/// cuando se mantiene presionado y se arrastra. Aquí se usa un reconocedor de UIKit
/// que empieza al instante y hace que el ScrollView espere: mientras el dedo esté
/// sobre el control, la pantalla no se desplaza.
struct TouchSurface: UIViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = false
        view.addGestureRecognizer(press)
        view.press = press
        context.coordinator.surface = self
        return view
    }

    func updateUIView(_ view: TrackingView, context: Context) {
        context.coordinator.surface = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var surface: TouchSurface?

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            guard let view = g.view, let surface else { return }
            let p = g.location(in: view)
            switch g.state {
            case .began: surface.onBegan(p)
            case .changed: surface.onChanged(p)
            case .ended, .cancelled, .failed: surface.onEnded()
            default: break
            }
        }
    }

    final class TrackingView: UIView {
        weak var press: UIGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let press else { return }
            // Todo ScrollView que contenga este control espera a que el dedo se levante.
            var v = superview
            while let current = v {
                if let scroll = current as? UIScrollView {
                    scroll.panGestureRecognizer.require(toFail: press)
                }
                v = current.superview
            }
        }
    }
}
