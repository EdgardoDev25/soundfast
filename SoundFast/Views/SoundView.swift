import SwiftUI

/// Ecualizador de 10 bandas + graves y agudos independientes.
struct SoundView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var player: PlayerController

    private var accent: Color { prefs.accent.color }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Sonido") {
                Button("Restablecer") {
                    withAnimation(.easeOut(duration: 0.25)) { prefs.resetSound() }
                    Haptics.tap()
                }
                .font(.montserrat(13, .semibold))
                .foregroundStyle(accent)
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 16) {
                    toneCard
                    eqCard
                }
                .padding(.horizontal, 20)
                // Espacio para el minirreproductor, que sigue visible abajo.
                .padding(.bottom, player.current != nil ? 100 : 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Tono (graves / agudos)

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("TONO").eyebrow(color: accent)
                Spacer()
                Text("Independiente del ecualizador").font(.montserrat(12)).foregroundStyle(Ink.dim)
            }
            HStack(spacing: 14) {
                Knob(
                    value: $prefs.sound.bass,
                    size: 180, stroke: 12, innerRatio: 64.0 / 84.0, dotRadius: 5, dotDistance: 54,
                    color: accent
                ) {
                    VStack(spacing: 1) {
                        Text("GRAVES").eyebrow(10, color: Ink.dim)
                        Text("\(Int(prefs.sound.bass))%")
                            .font(.montserrat(30, .heavy))
                            .tracking(-0.6)
                            .foregroundStyle(Ink.text)
                        Text(String(format: "+%.1f dB", prefs.sound.bassDb))
                            .font(.mono(11))
                            .foregroundStyle(prefs.accent.light)
                    }
                }
                .accessibilityLabel("Graves")

                VStack(spacing: 10) {
                    Knob(
                        value: $prefs.sound.treble,
                        size: 108, stroke: 14, innerRatio: 62.0 / 84.0, dotRadius: 8, dotDistance: 50,
                        color: Color(hex: 0xE9E7E2)
                    ) {
                        Text("\(Int(prefs.sound.treble))%")
                            .font(.montserrat(17, .heavy))
                            .foregroundStyle(Ink.text)
                    }
                    .accessibilityLabel("Agudos")
                    Text("AGUDOS").eyebrow(10, color: Ink.dim)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Punto de graves").font(.montserrat(12)).foregroundStyle(Ink.dim)
                HStack(spacing: 8) {
                    ForEach(SoundSettings.bassFrequencies, id: \.self) { f in
                        Chip(label: "\(Int(f)) Hz", selected: prefs.sound.bassFreq == f, mono: true, fullWidth: true) {
                            withAnimation(.easeOut(duration: 0.25)) { prefs.sound.bassFreq = f }
                        }
                    }
                }
                if let info = SoundSettings.bassFrequencyInfo[prefs.sound.bassFreq] {
                    (Text(info.name + " · ").font(.montserrat(12, .bold)).foregroundColor(prefs.accent.color)
                        + Text(info.detail).font(.montserrat(12)).foregroundColor(Ink.dim))
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(nil, value: prefs.sound.bassFreq)
                }
                if prefs.sound.bass == 0 {
                    Text("Sube la perilla de graves para escuchar la diferencia.")
                        .font(.montserrat(12))
                        .foregroundStyle(Ink.faint)
                } else if prefs.sound.bass > 70 {
                    Label("Graves extremos: el resto de la música puede sonar más bajo o distorsionar. Cuida el volumen.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.montserrat(12))
                        .foregroundStyle(Color.oklch(0.8, 0.14, 75))
                }
            }
        }
        .card(prefs)
    }

    // MARK: Ecualizador

    private var eqCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ECUALIZADOR").eyebrow(color: accent)
                Spacer()
                Button {
                    prefs.sound.eqOn.toggle()
                    Haptics.tap()
                } label: {
                    SwitchView(isOn: prefs.sound.eqOn, accent: accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ecualizador")
                .accessibilityValue(prefs.sound.eqOn ? "Activado" : "Desactivado")
            }

            EQCurve(sound: prefs.sound, accent: accent)
                .frame(height: 110)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(presetNames, id: \.self) { name in
                        let on = prefs.sound.preset == name
                        Button {
                            if prefs.sound.eqOn, name != SoundSettings.custom {
                                withAnimation(.easeOut(duration: 0.25)) { prefs.applyPreset(name) }
                                Haptics.soft()
                            }
                        } label: {
                            Text(name)
                                .font(.montserrat(13, .semibold))
                                .foregroundStyle(on ? Ink.onAccent : Color(hex: 0xD6D5DA))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(on ? accent : Color(hex: 0x1E1E23), in: Capsule())
                                .overlay(Capsule().stroke(on ? accent : Ink.chipBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
            .opacity(prefs.sound.eqOn ? 1 : 0.35)

            HStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { i in
                    BandSlider(
                        value: prefs.sound.bands[i],
                        label: SoundSettings.bandLabels[i],
                        accent: accent
                    ) { v in prefs.setBand(i, v) }
                    if i < 9 { Spacer(minLength: 0) }
                }
            }
            .opacity(prefs.sound.eqOn ? 1 : 0.35)
            // Apagado, tocar una banda no lo enciende: hay que usar el interruptor.
            .allowsHitTesting(prefs.sound.eqOn)
            .animation(.easeOut(duration: 0.2), value: prefs.sound.eqOn)

            if !prefs.sound.eqOn {
                Text("Ecualizador apagado. Enciéndelo con el interruptor para ajustar las bandas.")
                    .font(.montserrat(12))
                    .foregroundStyle(Ink.faint)
            }
        }
        .card(prefs)
    }

    private var presetNames: [String] {
        SoundSettings.presetOrder + (prefs.sound.preset == SoundSettings.custom ? [SoundSettings.custom] : [])
    }
}

// MARK: - Perilla

/// Perilla circular. Tocando el aro se gira siguiendo el dedo en círculo;
/// tocando el centro se arrastra hacia arriba (sube) o abajo (baja).
/// Mientras se opera se ilumina.
struct Knob<Center: View>: View {
    @Binding var value: Double
    let size: CGFloat
    let stroke: CGFloat
    let innerRatio: CGFloat
    let dotRadius: CGFloat
    let dotDistance: CGFloat
    let color: Color
    @ViewBuilder let center: () -> Center

    @State private var active = false
    @State private var startValue: Double = 0
    @State private var startPoint: CGPoint = .zero
    @State private var lastAngle: Double = 0
    @State private var rotation: Double = 0
    @State private var rotary = false

    var body: some View {
        let scale = size / 200
        let v = value / 100
        let lw = stroke * scale * (active ? 1.25 : 1)
        ZStack {
            // Halo mientras se opera. Solo existe al tocar: un desenfoque
            // invisible igual se calculaba en cada cuadro al deslizar el panel.
            if active {
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: lw * 2.2)
                    .blur(radius: 10)
                    .frame(width: 168 * scale, height: 168 * scale)
                    .transition(.opacity)
            }
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Ink.track, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(135))
                .frame(width: 168 * scale, height: 168 * scale)
            Circle()
                .trim(from: 0, to: 0.75 * v)
                .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(135))
                .frame(width: 168 * scale, height: 168 * scale)
                .shadow(color: color.opacity(active ? 0.8 : 0), radius: active ? 8 : 0)
            Circle()
                .fill(Color(hex: 0x1F1F25))
                .overlay(Circle().stroke(active ? color : Color(hex: 0x2F2F36), lineWidth: active ? 2 : 1.5))
                .frame(width: 168 * scale * innerRatio, height: 168 * scale * innerRatio)
            Circle()
                .fill(active ? color : Color.white)
                .frame(width: dotRadius * 2 * scale * (active ? 1.5 : 1), height: dotRadius * 2 * scale * (active ? 1.5 : 1))
                .shadow(color: color.opacity(active ? 0.9 : 0), radius: active ? 6 : 0)
                .offset(y: -dotDistance * scale)
                .rotationEffect(.degrees(-135 + 270 * v))
            center()
        }
        .frame(width: size, height: size)
        .scaleEffect(active ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
        .overlay {
            TouchSurface(
                onBegan: { p in begin(at: p) },
                onChanged: { p in move(to: p) },
                onEnded: { end() }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(value)) por ciento")
        .accessibilityAdjustableAction { dir in
            value = min(100, max(0, value + (dir == .increment ? 10 : -10)))
        }
    }

    private func angle(of p: CGPoint) -> Double {
        atan2(Double(p.y - size / 2), Double(p.x - size / 2)) * 180 / .pi
    }

    private func begin(at p: CGPoint) {
        active = true
        startValue = value
        startPoint = p
        rotation = 0
        lastAngle = angle(of: p)
        // Aro → giro circular; centro → arrastre vertical.
        let distance = hypot(p.x - size / 2, p.y - size / 2)
        rotary = distance > size * 0.3
        Haptics.soft()
    }

    private func move(to p: CGPoint) {
        let new: Double
        if rotary {
            let a = angle(of: p)
            var d = a - lastAngle
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            lastAngle = a
            // Muy cerca del centro el ángulo salta; se ignora.
            if hypot(p.x - size / 2, p.y - size / 2) > size * 0.12 { rotation += d }
            new = startValue + rotation / 270 * 100
        } else {
            new = startValue + Double(startPoint.y - p.y) / 1.6
        }
        let clamped = min(100, max(0, new.rounded()))
        if Int(clamped / 5) != Int(value / 5) { Haptics.tick() }
        if clamped != value { value = clamped }
    }

    private func end() {
        active = false
    }
}

// MARK: - Banda del ecualizador

struct BandSlider: View {
    let value: Double
    let label: String
    let accent: Color
    let onChange: (Double) -> Void

    @State private var active = false
    private let height: CGFloat = 150

    var body: some View {
        let pos = (12 - value) / 24          // 0 arriba … 1 abajo
        VStack(spacing: 6) {
            Text(value == 0 ? "0" : (value > 0 ? "+" : "") + "\(Int(value))")
                .font(.mono(9.5))
                .foregroundStyle(value == 0 && !active ? Ink.faint : accent)
                .frame(height: 12)
            ZStack(alignment: .top) {
                Capsule().fill(Ink.track).frame(width: active ? 6 : 4, height: height)
                Rectangle().fill(Color(hex: 0x3A3A42)).frame(width: 12, height: 1).offset(y: height / 2)
                Capsule()
                    .fill(accent)
                    .frame(width: active ? 6 : 4, height: abs(pos - 0.5) * height)
                    .offset(y: (value >= 0 ? pos : 0.5) * height)
                    .shadow(color: accent.opacity(active ? 0.8 : 0), radius: active ? 6 : 0)
                Circle()
                    .fill(active ? accent : Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .frame(width: active ? 22 : 18, height: active ? 22 : 18)
                    .offset(y: pos * height - (active ? 11 : 9))
            }
            .frame(width: 28, height: height, alignment: .top)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: active)
            .overlay {
                TouchSurface(
                    onBegan: { p in
                        active = true
                        set(p.y)
                    },
                    onChanged: { p in set(p.y) },
                    onEnded: { active = false }
                )
            }
            Text(label)
                .font(.mono(9.5))
                .foregroundStyle(active ? accent : Ink.dim)
        }
        .frame(width: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) hercios")
        .accessibilityValue("\(Int(value)) decibelios")
        .accessibilityAdjustableAction { dir in
            onChange(min(12, max(-12, value + (dir == .increment ? 1 : -1))))
        }
    }

    private func set(_ y: CGFloat) {
        let v = min(12, max(-12, ((0.5 - y / height) * 24).rounded()))
        if v != value {
            Haptics.tick()
            onChange(v)
        }
    }
}

// MARK: - Curva

struct EQCurve: View {
    let sound: SoundSettings
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let points = curve(width: w, height: h) { sound.gain(at: $0) }
            let bass = curve(width: w, height: h) { sound.bassGain(at: $0) }
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Ink.border, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                Path { p in
                    p.addLines(points)
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.14))

                Path { p in p.addLines(bass) }
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                Path { p in p.addLines(points) }
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                Text("- - graves").font(.mono(9)).foregroundStyle(Color.white.opacity(0.45))
                    .padding(.leading, 8).padding(.top, 6)
                Text("20 Hz").font(.mono(9)).foregroundStyle(Ink.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 8).padding(.bottom, 6)
                Text("20 kHz").font(.mono(9)).foregroundStyle(Ink.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 8).padding(.bottom, 6)
            }
        }
        .background(Color(hex: 0x111114))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: sound)
        .accessibilityHidden(true)
    }

    private func curve(width w: CGFloat, height h: CGFloat, gain: (Double) -> Double) -> [CGPoint] {
        (0...80).map { k in
            let f = pow(10, log10(20.0) + (log10(20000.0) - log10(20.0)) * Double(k) / 80)
            let y = min(h - 3, max(3, h / 2 - CGFloat(gain(f) / 24) * (h / 2 - 6)))
            return CGPoint(x: CGFloat(k) / 80 * w, y: y)
        }
    }
}
