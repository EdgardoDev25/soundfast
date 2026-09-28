import SwiftUI
import UIKit

/// Un cuadro de animación: fase acumulada y niveles de la música ya suavizados.
struct EffectFrame {
    var phase: Double
    var level: CGFloat
    var bass: CGFloat
    var bands: [CGFloat]
    /// Giro del anillo (grados): acelera con los golpes de bajo.
    var spin: Double = 0
    /// Desplazamiento de color (grados de tono): salta en cada golpe.
    var hueShift: Double = 0
    /// Centro de la portada y su radio (para Ondas, Remolino y Anillo).
    var focus: CGPoint = .zero
    var artRadius: CGFloat = 150
}

/// Suaviza lo que llega del analizador (sube rápido, baja lento) y avanza la fase.
final class VisualMotion {
    private var last: TimeInterval?
    private var phase: Double = 0
    private var level: Float = 0
    private var bass: Float = 0
    private var bands = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
    private var spin: Double = 0
    private var hueShift: Double = 0
    private var hueTarget: Double = 0
    private var bassAverage: Float = 0
    private var lastBeat: TimeInterval = 0

    func advance(to date: Date, snapshot s: AudioAnalyzer.Snapshot, playing: Bool,
                 settings: VisualSettings, reduceMotion: Bool) -> EffectFrame {
        let now = date.timeIntervalSinceReferenceDate
        let dt = min(0.1, max(0, now - (last ?? now)))
        last = now

        let fresh = playing && settings.reactive && now - s.time < 0.6
        func follow(_ current: Float, _ target: Float, up: Float, down: Float) -> Float {
            current + (target - current) * (target > current ? up : down)
        }
        level = follow(level, fresh ? s.level : 0, up: 0.45, down: 0.07)
        bass = follow(bass, fresh ? s.bass : 0, up: 0.5, down: 0.09)
        for i in bands.indices {
            bands[i] = follow(bands[i], fresh ? s.bands[i] : 0, up: 0.5, down: 0.12)
        }

        var rate = 0.12 + settings.speed * 1.1
        if reduceMotion { rate *= 0.25 }
        phase += dt * rate * (1 + Double(level) * 0.7)

        // Anillo: gira lento y se dispara con cada golpe de bajo (como los parlantes JBL).
        let b = Double(bass)
        spin += dt * (25 + 520 * b * b + 90 * Double(level)) * (0.4 + settings.speed * 1.2) * (reduceMotion ? 0.25 : 1)
        bassAverage += (bass - bassAverage) * 0.05
        if fresh, bass > bassAverage * 1.35, bass > 0.25, now - lastBeat > 0.18 {
            lastBeat = now
            hueTarget += 38
        }
        hueTarget += dt * 12
        hueShift += (hueTarget - hueShift) * 0.12

        return EffectFrame(
            phase: phase,
            level: CGFloat(level),
            bass: CGFloat(bass),
            bands: bands.map { CGFloat($0) },
            spin: spin.truncatingRemainder(dividingBy: 360),
            hueShift: hueShift
        )
    }
}

// MARK: - Paletas

enum EffectPalette {
    static func colors(option: String, artwork: [Color], hue: Double, accent: Accent) -> [Color] {
        func set(_ hues: [Double], l: Double = 0.7, c: Double = 0.18) -> [Color] {
            hues.map { .oklch(l, c, $0) }
        }
        switch option {
        case "acento":
            let a = accent.c < 0.02 ? 250 : accent.h
            return set([a, a + 28, a - 28, a + 55], l: max(0.62, accent.l - 0.05), c: max(0.12, accent.c))
        case "arcoiris": return set([15, 75, 145, 210, 275, 330])
        case "fuego": return set([28, 45, 12, 60], l: 0.72, c: 0.2)
        case "oceano": return set([235, 200, 265, 185], l: 0.68, c: 0.15)
        case "neon": return set([340, 195, 135, 290], l: 0.75, c: 0.22)
        default:
            if artwork.count >= 2 { return artwork }
            return set([hue, hue + 45, hue - 50, hue + 110], l: 0.66, c: 0.16)
        }
    }

    /// Colores dominantes de una portada (hasta 4, vivos).
    static func dominant(from image: UIImage) -> [Color] {
        guard let cg = image.cgImage else { return [] }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        struct Bucket { var weight: CGFloat = 0; var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0 }
        var buckets = [Bucket](repeating: Bucket(), count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            guard s > 0.18, v > 0.15 else { continue }
            let w = s * v
            let k = min(11, Int(h * 12))
            buckets[k].weight += w
            buckets[k].r += r * w
            buckets[k].g += g * w
            buckets[k].b += b * w
        }
        let top = buckets.filter { $0.weight > 0.4 }.sorted { $0.weight > $1.weight }.prefix(4)
        return top.map { bucket in
            let color = UIColor(red: bucket.r / bucket.weight, green: bucket.g / bucket.weight, blue: bucket.b / bucket.weight, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            return Color(UIColor(hue: h, saturation: max(s, 0.55), brightness: max(v, 0.75), alpha: 1))
        }
    }
}

// MARK: - Vista

/// Fondo animado de "Sonando ahora".
struct NowPlayingEffects: View {
    let settings: VisualSettings
    let colors: [Color]
    let analyzer: AudioAnalyzer
    let playing: Bool
    let visible: Bool
    var focus: CGPoint = .zero
    var artRadius: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = VisualMotion()

    var body: some View {
        let animating = visible && playing
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !animating)) { timeline in
            let frame = motion.advance(
                to: timeline.date, snapshot: analyzer.snapshot, playing: playing,
                settings: settings, reduceMotion: reduceMotion
            ).placed(at: focus, artRadius: artRadius)
            if settings.style == "liquido" {
                if #available(iOS 18.0, *) {
                    LiquidMesh(frame: frame, colors: colors, intensity: settings.intensity)
                } else {
                    canvas(frame, style: "aurora")
                }
            } else {
                canvas(frame, style: settings.style)
            }
        }
        .opacity(playing ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.6), value: playing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func canvas(_ frame: EffectFrame, style: String) -> some View {
        Canvas { ctx, size in
            EffectPainter.draw(style: style, in: &ctx, size: size, frame: frame,
                               colors: colors, intensity: settings.intensity)
        }
    }
}

@available(iOS 18.0, *)
private struct LiquidMesh: View {
    let frame: EffectFrame
    let colors: [Color]
    let intensity: Double

    var body: some View {
        MeshGradient(width: 3, height: 3, points: points, colors: meshColors, smoothsColors: true)
            .opacity(0.3 + 0.6 * intensity)
    }

    private var points: [SIMD2<Float>] {
        let t = frame.phase * 1.4
        let b = Float(frame.bass) * 0.08
        func wobble(_ i: Double, _ amp: Float) -> Float { Float(sin(t * (0.8 + i * 0.13) + i * 1.9)) * amp }
        return [
            [0, 0], [0.5 + wobble(1, 0.2), 0], [1, 0],
            [0, 0.5 + wobble(2, 0.2)], [0.5 + wobble(3, 0.22 + b), 0.45 + wobble(4, 0.2 + b)], [1, 0.5 + wobble(5, 0.2)],
            [0, 1], [0.5 + wobble(6, 0.2), 1], [1, 1],
        ]
    }

    private var meshColors: [Color] {
        let c = colors.isEmpty ? [Color.purple, .blue, .pink] : colors
        func at(_ i: Int) -> Color { c[i % c.count] }
        return [
            at(0), at(1).opacity(0.35), at(2),
            at(2).opacity(0.4), at(0), at(1).opacity(0.45),
            at(1), at(0).opacity(0.35), at(2),
        ]
    }
}

// MARK: - Dibujo

enum EffectPainter {
    static func draw(style: String, in ctx: inout GraphicsContext, size: CGSize, frame: EffectFrame,
                     colors: [Color], intensity: Double) {
        guard !colors.isEmpty, size.width > 0, size.height > 0 else { return }
        ctx.opacity = 0.3 + 0.7 * intensity
        switch style {
        case "ondas": waves(&ctx, size, frame, colors)
        case "particulas": particles(&ctx, size, frame, colors)
        case "espectro": spectrum(&ctx, size, frame, colors)
        case "remolino": swirl(&ctx, size, frame, colors)
        case "anillo": ring(&ctx, size, frame)
        default: aurora(&ctx, size, frame, colors)
        }
    }

    private static func color(_ colors: [Color], _ i: Int) -> Color { colors[i % colors.count] }

    private static func circle(_ center: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    private static func glow(_ c: Color, _ center: CGPoint, _ r: CGFloat, _ alpha: Double) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: [c.opacity(alpha), c.opacity(0)]), center: center, startRadius: 0, endRadius: r)
    }

    /// Manchas de luz grandes y difusas que flotan.
    private static func aurora(_ ctx: inout GraphicsContext, _ size: CGSize, _ f: EffectFrame, _ colors: [Color]) {
        var c = ctx
        c.addFilter(.blur(radius: min(size.width, size.height) * 0.1))
        c.blendMode = .plusLighter
        let t = f.phase
        for i in 0..<5 {
            let fi = Double(i)
            let x = size.width * (0.5 + 0.4 * sin(t * (0.7 + fi * 0.23) + fi * 1.7))
            let y = size.height * (0.42 + 0.34 * cos(t * (0.5 + fi * 0.19) + fi * 2.3))
            let r = size.width * (0.42 + 0.12 * sin(t * 0.9 + fi)) * (1 + 0.45 * f.bass)
            let center = CGPoint(x: x, y: y)
            c.fill(circle(center, r), with: glow(color(colors, i), center, r, 0.7))
        }
    }

    /// Anillos que nacen detrás de la portada y se expanden con el bajo.
    private static func waves(_ ctx: inout GraphicsContext, _ size: CGSize, _ f: EffectFrame, _ colors: [Color]) {
        let center = f.focus == .zero ? CGPoint(x: size.width / 2, y: size.height * 0.33) : f.focus
        let maxR = hypot(size.width, size.height) * 0.75
        var halo = ctx
        halo.addFilter(.blur(radius: 30))
        let hr = size.width * (0.5 + 0.5 * f.bass)
        halo.fill(circle(center, hr), with: glow(color(colors, 0), center, hr, 0.55))

        var rings = ctx
        rings.addFilter(.blur(radius: 2.5))
        rings.blendMode = .plusLighter
        let count = 8
        for i in 0..<count {
            let p = (f.phase * 0.45 + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let r = maxR * CGFloat(p)
            let alpha = (1 - p) * (0.3 + 0.7 * Double(f.level))
            rings.stroke(circle(center, r), with: .color(color(colors, i).opacity(alpha)),
                         lineWidth: 2 + 12 * f.bass * CGFloat(1 - p))
        }
    }

    /// Partículas de luz que suben; crecen con el volumen.
    private static func particles(_ ctx: inout GraphicsContext, _ size: CGSize, _ f: EffectFrame, _ colors: [Color]) {
        var c = ctx
        c.blendMode = .plusLighter
        let t = f.phase
        func rand(_ i: Int, _ n: Double) -> Double {
            let v = sin(Double(i) * 12.9898 + n * 78.233) * 43758.5453
            return v - floor(v)
        }
        for i in 0..<90 {
            let speed = 0.3 + rand(i, 1) * 0.9
            let p = (t * 0.25 * speed + rand(i, 2)).truncatingRemainder(dividingBy: 1)
            let y = size.height * CGFloat(1.05 - p * 1.15)
            let x = size.width * CGFloat(rand(i, 3)) + 22 * CGFloat(sin(t * speed * 2 + Double(i)))
            let s = CGFloat(2 + rand(i, 4) * 4.5) * (1 + f.level * 1.6)
            let alpha = sin(p * .pi) * (0.35 + 0.65 * rand(i, 5))
            let col = color(colors, i)
            let center = CGPoint(x: x, y: y)
            c.fill(circle(center, s * 4), with: glow(col, center, s * 4, alpha * 0.45))
            c.fill(circle(center, s), with: .color(col.opacity(alpha)))
        }
    }

    /// Barras de frecuencia abajo, con reflejo arriba.
    private static func spectrum(_ ctx: inout GraphicsContext, _ size: CGSize, _ f: EffectFrame, _ colors: [Color]) {
        let n = f.bands.count
        let bars = n * 2
        let w = size.width / CGFloat(bars)
        func value(_ j: Int) -> CGFloat {
            let k = j < n ? n - 1 - j : j - n        // graves al centro, agudos a los lados
            let idle = 0.07 + 0.05 * sin(f.phase * 3 + Double(j) * 0.45)
            return max(f.bands[k], CGFloat(idle))
        }
        for layer in 0..<2 {
            var c = ctx
            if layer == 0 { c.addFilter(.blur(radius: 18)) }
            c.blendMode = .plusLighter
            for j in 0..<bars {
                let v = value(j)
                let h = size.height * 0.45 * v
                let col = color(colors, j * colors.count / bars)
                let x = CGFloat(j) * w + w * 0.18
                let bottom = CGRect(x: x, y: size.height - h, width: w * 0.64, height: h)
                c.fill(Path(roundedRect: bottom, cornerRadius: w * 0.3),
                       with: .linearGradient(Gradient(colors: [col.opacity(0), col.opacity(0.95)]),
                                             startPoint: CGPoint(x: 0, y: size.height - h), endPoint: CGPoint(x: 0, y: size.height)))
                let top = CGRect(x: x, y: 0, width: w * 0.64, height: h * 0.45)
                c.fill(Path(roundedRect: top, cornerRadius: w * 0.3),
                       with: .linearGradient(Gradient(colors: [col.opacity(0.35), col.opacity(0)]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.45)))
            }
        }
    }

    /// Anillo de luces alrededor de la portada (estilo parlantes JBL): gira lento,
    /// se acelera con cada golpe de bajo y cambia de color al ritmo.
    private static func ring(_ ctx: inout GraphicsContext, _ size: CGSize, _ f: EffectFrame) {
        let center = f.focus == .zero ? CGPoint(x: size.width / 2, y: size.height * 0.33) : f.focus
        let segments = 48
        let step = 360.0 / Double(segments)
        let r = f.artRadius + 24 + 10 * f.bass
        let width = 7 + 12 * f.bass

        func segment(_ k: Int, radius: CGFloat, spin: Double, fill: Double) -> Path {
            var p = Path()
            let a = spin + Double(k) * step
            p.addArc(center: center, radius: radius,
                     startAngle: .degrees(a), endAngle: .degrees(a + step * fill), clockwise: false)
            return p
        }
        func color(_ k: Int, _ alpha: Double) -> Color {
            .oklch(0.74, 0.2, f.hueShift + Double(k) * 7.5, alpha)
        }
        func intensity(_ k: Int) -> Double {
            let n = f.bands.count
            let mirrored = k < segments / 2 ? k : segments - 1 - k
            let band = f.bands[min(n - 1, mirrored * n / (segments / 2))]
            return 0.3 + 0.7 * Double(band)
        }

        // Resplandor difuso detrás.
        var glow = ctx
        glow.addFilter(.blur(radius: 16))
        glow.blendMode = .plusLighter
        for k in 0..<segments {
            glow.stroke(segment(k, radius: r, spin: f.spin, fill: 0.9),
                        with: .color(color(k, intensity(k) * 0.9)), lineWidth: width * 2.2)
        }
        // Luces nítidas.
        var sharp = ctx
        sharp.blendMode = .plusLighter
        for k in 0..<segments {
            sharp.stroke(segment(k, radius: r, spin: f.spin, fill: 0.62),
                         with: .color(color(k, intensity(k))),
                         style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        // Segundo aro fino que gira al revés.
        for k in stride(from: 0, to: segments, by: 2) {
            sharp.stroke(segment(k, radius: r + width + 14, spin: -f.spin * 1.6, fill: 0.35),
                         with: .color(color(k + 12, 0.35 + 0.4 * Double(f.level))),
                         style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    /// Remolino de color que gira, más grande con el bajo.
    private static func swirl(_ ctx: inout GraphicsContext, _ size: CGSize, _ f: EffectFrame, _ colors: [Color]) {
        let center = f.focus == .zero ? CGPoint(x: size.width / 2, y: size.height * 0.38) : f.focus
        let gradient = Gradient(colors: colors + [colors[0]])
        var c = ctx
        c.addFilter(.blur(radius: size.width * 0.09))
        let r1 = max(size.width, size.height) * 0.7 * (1 + 0.18 * f.bass)
        c.opacity *= 0.9
        c.fill(circle(center, r1), with: .conicGradient(gradient, center: center, angle: .radians(f.phase * 1.3)))
        c.blendMode = .plusLighter
        c.opacity *= 0.6
        let r2 = r1 * 0.55
        c.fill(circle(center, r2), with: .conicGradient(Gradient(colors: colors.reversed() + [colors.last!]),
                                                         center: center, angle: .radians(-f.phase * 2.1)))
        // Oscurece los bordes para que el centro brille.
        var v = ctx
        v.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.55)]),
                                     center: center, startRadius: size.width * 0.25, endRadius: max(size.width, size.height) * 0.8))
    }
}

extension EffectFrame {
    func placed(at focus: CGPoint, artRadius: CGFloat) -> EffectFrame {
        var f = self
        f.focus = focus
        f.artRadius = artRadius
        return f
    }
}
