import SwiftUI

/// Ecualizador de 10 bandas + graves y agudos independientes.
struct SoundView: View {
    @EnvironmentObject private var prefs: Preferences
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
                Text("Sonido").font(.sora(17, .bold)).foregroundStyle(Ink.text)
                Spacer()
                Button("Restablecer") {
                    withAnimation(.easeOut(duration: 0.25)) { prefs.resetSound() }
                    Haptics.tap()
                }
                .font(.sora(13, .semibold))
                .foregroundStyle(accent)
                .buttonStyle(.plain)
                .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 16) {
                    toneCard
                    eqCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(prefs.theme.bg.ignoresSafeArea())
    }

    // MARK: Tono (graves / agudos)

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("TONO").eyebrow(color: accent)
                Spacer()
                Text("Independiente del ecualizador").font(.sora(12)).foregroundStyle(Ink.dim)
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
                            .font(.sora(30, .heavy))
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
                            .font(.sora(17, .heavy))
                            .foregroundStyle(Ink.text)
                    }
                    .accessibilityLabel("Agudos")
                    Text("AGUDOS").eyebrow(10, color: Ink.dim)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Punto de graves").font(.sora(12)).foregroundStyle(Ink.dim)
                HStack(spacing: 8) {
                    ForEach(SoundSettings.bassFrequencies, id: \.self) { f in
                        Chip(label: "\(Int(f)) Hz", selected: prefs.sound.bassFreq == f, mono: true, fullWidth: true) {
                            prefs.sound.bassFreq = f
                        }
                    }
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
                            if name != SoundSettings.custom {
                                withAnimation(.easeOut(duration: 0.25)) { prefs.applyPreset(name) }
                                Haptics.soft()
                            }
                        } label: {
                            Text(name)
                                .font(.sora(13, .semibold))
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
            .animation(.easeOut(duration: 0.2), value: prefs.sound.eqOn)
        }
        .card(prefs)
    }

    private var presetNames: [String] {
        SoundSettings.presetOrder + (prefs.sound.preset == SoundSettings.custom ? [SoundSettings.custom] : [])
    }
}

// MARK: - Perilla

/// Perilla circular: se gira arrastrando hacia arriba o a la derecha.
struct Knob<Center: View>: View {
    @Binding var value: Double
    let size: CGFloat
    let stroke: CGFloat
    let innerRatio: CGFloat
    let dotRadius: CGFloat
    let dotDistance: CGFloat
    let color: Color
    @ViewBuilder let center: () -> Center

    @State private var start: Double?

    var body: some View {
        let scale = size / 200
        let v = value / 100
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Ink.track, style: StrokeStyle(lineWidth: stroke * scale, lineCap: .round))
                .rotationEffect(.degrees(135))
                .frame(width: 168 * scale, height: 168 * scale)
            Circle()
                .trim(from: 0, to: 0.75 * v)
                .stroke(color, style: StrokeStyle(lineWidth: stroke * scale, lineCap: .round))
                .rotationEffect(.degrees(135))
                .frame(width: 168 * scale, height: 168 * scale)
            Circle()
                .fill(Color(hex: 0x1F1F25))
                .overlay(Circle().stroke(Color(hex: 0x2F2F36), lineWidth: 1.5))
                .frame(width: 168 * scale * innerRatio, height: 168 * scale * innerRatio)
            Circle()
                .fill(Color.white)
                .frame(width: dotRadius * 2 * scale, height: dotRadius * 2 * scale)
                .offset(y: -dotDistance * scale)
                .rotationEffect(.degrees(-135 + 270 * v))
            center()
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if start == nil { start = value }
                    let d = Double(g.translation.width - g.translation.height)
                    let new = min(100, max(0, ((start ?? 0) + d / 2.2).rounded()))
                    if Int(new / 10) != Int(value / 10) { Haptics.tick() }
                    if new != value { value = new }
                }
                .onEnded { _ in start = nil }
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(value)) por ciento")
        .accessibilityAdjustableAction { dir in
            value = min(100, max(0, value + (dir == .increment ? 10 : -10)))
        }
    }
}

// MARK: - Banda del ecualizador

struct BandSlider: View {
    let value: Double
    let label: String
    let accent: Color
    let onChange: (Double) -> Void

    private let height: CGFloat = 150

    var body: some View {
        let pos = (12 - value) / 24          // 0 arriba … 1 abajo
        VStack(spacing: 6) {
            Text(value == 0 ? "0" : (value > 0 ? "+" : "") + "\(Int(value))")
                .font(.mono(9.5))
                .foregroundStyle(value == 0 ? Ink.faint : accent)
                .frame(height: 12)
            ZStack(alignment: .top) {
                Capsule().fill(Ink.track).frame(width: 4, height: height)
                Rectangle().fill(Color(hex: 0x3A3A42)).frame(width: 12, height: 1).offset(y: height / 2)
                Capsule()
                    .fill(accent)
                    .frame(width: 4, height: abs(pos - 0.5) * height)
                    .offset(y: (value >= 0 ? pos : 0.5) * height)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .frame(width: 18, height: 18)
                    .offset(y: pos * height - 9)
            }
            .frame(width: 28, height: height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = min(12, max(-12, ((0.5 - g.location.y / height) * 24).rounded()))
                        if v != value {
                            Haptics.tick()
                            onChange(v)
                        }
                    }
            )
            Text(label)
                .font(.mono(9.5))
                .foregroundStyle(Ink.dim)
        }
        .frame(width: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) hercios")
        .accessibilityValue("\(Int(value)) decibelios")
        .accessibilityAdjustableAction { dir in
            onChange(min(12, max(-12, value + (dir == .increment ? 1 : -1))))
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
