import SwiftUI

/// Se abre desde "Sonando ahora": la parte de arriba sigue viéndose para probar en vivo.
struct EffectsSheet: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    private var accent: Color { prefs.accent.color }

    var body: some View {
        let on = prefs.visuals.enabled
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        prefs.visuals.enabled.toggle()
                        Haptics.tap()
                    } label: {
                        HStack {
                            Text("Efectos de fondo").font(.montserrat(15, .semibold)).foregroundStyle(Ink.text)
                            Spacer()
                            SwitchView(isOn: on, accent: accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(on ? "Activado" : "Desactivado")

                    VStack(alignment: .leading, spacing: 18) {
                        styleGrid
                        palettes
                        sliderRow("Intensidad", value: prefs.visuals.intensity) { prefs.visuals.intensity = $0 }
                        sliderRow("Velocidad", value: prefs.visuals.speed) { prefs.visuals.speed = $0 }
                        reactiveRow
                    }
                    .disabled(!on)
                    .opacity(on ? 1 : 0.35)
                    .animation(.easeOut(duration: 0.2), value: on)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.visible)
        .sheetBackground(prefs)
        .presentationCornerRadius(28)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Efectos").font(.montserrat(20, .heavy)).foregroundStyle(Ink.text)
                Text("Fondo animado mientras suena la música").font(.montserrat(13)).foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 12)
            Button("Listo") { dismiss() }
                .font(.montserrat(15, .semibold))
                .foregroundStyle(accent)
                .buttonStyle(.plain)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private var styleGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(VisualSettings.styles, id: \.id) { style in
                let selected = prefs.visuals.style == style.id
                Button {
                    withAnimation(.easeOut(duration: 0.3)) { prefs.visuals.style = style.id }
                    Haptics.soft()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: style.icon)
                            .font(.system(size: 22, weight: .semibold))
                        Text(style.name).font(.montserrat(12, .semibold))
                    }
                    .foregroundStyle(selected ? accent : Ink.chipText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .background(selected ? prefs.accent.alpha(0.14) : prefs.theme.surf,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(prefs.theme.glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? accent : Ink.chipBorder, lineWidth: 1.5)
                    )
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var palettes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colores").font(.montserrat(13, .semibold)).foregroundStyle(Ink.dim)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(VisualSettings.palettes, id: \.id) { p in
                        paletteChip(p.id, p.name)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }

    private var reactiveRow: some View {
        Button {
            prefs.visuals.reactive.toggle()
            Haptics.soft()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reaccionar a la música").font(.montserrat(15)).foregroundStyle(Ink.text)
                    Text("Se mueve con el bajo y el volumen de cada canción")
                        .font(.montserrat(12)).foregroundStyle(Ink.dim)
                }
                Spacer(minLength: 0)
                SwitchView(isOn: prefs.visuals.reactive, accent: accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(prefs.visuals.reactive ? "Activado" : "Desactivado")
    }

    private func paletteChip(_ id: String, _ name: String) -> some View {
        let selected = prefs.visuals.palette == id
        let swatch = EffectPalette.colors(option: id, artwork: [], hue: 20, accent: prefs.accent)
        return Button {
            prefs.visuals.palette = id
            Haptics.soft()
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -5) {
                    ForEach(0..<min(3, swatch.count), id: \.self) { i in
                        Circle()
                            .fill(swatch[i])
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(prefs.theme.surf2, lineWidth: 1.5))
                    }
                }
                Text(name).font(.montserrat(13, .semibold))
            }
            .foregroundStyle(selected ? accent : Ink.chipText)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(selected ? prefs.accent.alpha(0.16) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? accent : Ink.chipBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ label: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.montserrat(15)).foregroundStyle(Ink.text)
                Spacer()
                Text("\(Int((value * 100).rounded()))%").font(.mono(13)).foregroundStyle(Ink.dim)
            }
            UnitSlider(value: value, accent: accent, label: label, onChange: set)
        }
    }
}

/// Deslizador 0…1 en pasos de 5 %.
struct UnitSlider: View {
    let value: Double
    let accent: Color
    let label: String
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let pct = CGFloat(min(1, max(0, value)))
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
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = min(max(0, g.location.x / max(1, geo.size.width)), 1)
                        let stepped = (Double(v) * 20).rounded() / 20
                        if stepped != value {
                            Haptics.tick()
                            onChange(stepped)
                        }
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) por ciento")
        .accessibilityAdjustableAction { dir in
            onChange(min(1, max(0, value + (dir == .increment ? 0.1 : -0.1))))
        }
    }
}
