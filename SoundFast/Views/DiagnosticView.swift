import SwiftUI
import UIKit

/// Pantalla temporal de la etapa 1: confirma que la cadena
/// compilar en la nube → firmar → instalar funciona en el iPhone real.
struct DiagnosticView: View {
    @StateObject private var tone = ToneTest()

    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    card
                    audioTest
                    hapticTest
                    Text("SoundFast · Hecho para iPhone")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOUNDFAST")
                .font(.system(size: 11, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)
            Text("Todo en orden")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Theme.text)
            Text("Etapa 1 · compilada en la nube, instalada desde Windows")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textDim)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            row("Versión", info["CFBundleShortVersionString"] as? String ?? "—")
            divider
            row("Build", info["CFBundleVersion"] as? String ?? "—")
            divider
            row("Compilada", info["SFBuildDate"] as? String ?? "—")
            divider
            row("iOS", UIDevice.current.systemVersion)
            divider
            row("Modelo", Self.modelIdentifier)
        }
        .background(Theme.surf, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var audioTest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRUEBA DE AUDIO")
                .font(.system(size: 11, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.textDim)

            Button(action: tone.toggle) {
                HStack(spacing: 14) {
                    Image(systemName: tone.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 52, height: 52)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tone.isPlaying ? "Sonando…" : "Reproducir tono")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Bloquea el iPhone: debe seguir sonando y verse en la pantalla de bloqueo y la Dynamic Island.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textDim)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Theme.surf, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            if let error = tone.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    private var hapticTest: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Text("Probar vibración")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 16)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    /// Ej. "iPhone17,2" para el iPhone 16 Pro Max.
    private static var modelIdentifier: String {
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
