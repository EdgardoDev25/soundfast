import AVFoundation
import MediaPlayer

/// Etapa 1: valida lo más delicado del proyecto antes de construir encima —
/// AVAudioEngine sonando con la pantalla bloqueada y los controles del sistema
/// (pantalla de bloqueo / Dynamic Island) respondiendo.
final class ToneTest: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var configured = false

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        do {
            if !configured { try configure() }
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            player.play()
            isPlaying = true
            lastError = nil
            updateNowPlaying()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    private func configure() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(makeArpeggio(), at: nil, options: .loops)

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle()
            return .success
        }
        configured = true
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Tono de prueba",
            MPMediaItemPropertyArtist: "SoundFast",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    /// Arpegio suave de La mayor (La–Do#–Mi–La), medio segundo por nota, en bucle.
    private func makeArpeggio() -> AVAudioPCMBuffer {
        let notes: [Double] = [220.0, 277.18, 329.63, 440.0]
        let sampleRate = format.sampleRate
        let perNote = Int(sampleRate * 0.5)
        let frames = AVAudioFrameCount(perNote * notes.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for (n, freq) in notes.enumerated() {
            for i in 0..<perNote {
                let t = Double(i) / sampleRate
                let envelope = min(1, t * 60) * exp(-3.5 * t)
                let sample = Float(sin(2 * Double.pi * freq * t) * envelope * 0.22)
                left[n * perNote + i] = sample
                right[n * perNote + i] = sample
            }
        }
        return buffer
    }
}
