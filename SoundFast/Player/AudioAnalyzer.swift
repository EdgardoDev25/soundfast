import Accelerate
import AVFoundation

/// Analiza lo que suena (volumen y 24 bandas de frecuencia) para los efectos visuales.
/// `process` corre en el hilo de audio; `snapshot` se lee desde la interfaz.
final class AudioAnalyzer: @unchecked Sendable {
    static let bandCount = 24

    struct Snapshot {
        var level: Float = 0
        var bass: Float = 0
        var bands = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
        var time: TimeInterval = 0
    }

    private let lock = NSLock()
    private var latest = Snapshot()
    private var active = false

    private let size = 1024
    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]
    private var runningPeak: Float = 1e-3
    /// Qué cajas de la FFT van a cada banda (escala logarítmica).
    private let bandRanges: [Range<Int>]

    init() {
        fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 1024, isHalfWindow: false)

        let bins = 512
        var ranges: [Range<Int>] = []
        let minBin = 1.0, maxBin = Double(bins - 1)
        for b in 0..<AudioAnalyzer.bandCount {
            let lo = Int(minBin * pow(maxBin / minBin, Double(b) / Double(AudioAnalyzer.bandCount)))
            let hi = Int(minBin * pow(maxBin / minBin, Double(b + 1) / Double(AudioAnalyzer.bandCount)))
            ranges.append(lo..<max(lo + 1, hi))
        }
        bandRanges = ranges
    }

    /// Solo se calcula mientras algún efecto lo necesita.
    var isActive: Bool {
        get { lock.withLock { active } }
        set { lock.withLock { active = newValue } }
    }

    var snapshot: Snapshot {
        lock.withLock { latest }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard isActive, let fft, let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // Últimas 1024 muestras (mezcla de ambos canales si hay dos).
        var samples = [Float](repeating: 0, count: size)
        let offset = max(0, frames - size)
        let count = min(size, frames)
        let right = buffer.format.channelCount > 1 ? buffer.floatChannelData?[1] : nil
        for i in 0..<count {
            let l = channel[offset + i]
            samples[i] = right.map { (l + $0[offset + i]) * 0.5 } ?? l
        }

        let rms = vDSP.rootMeanSquare(samples)
        var windowed = [Float](repeating: 0, count: size)
        vDSP.multiply(samples, window, result: &windowed)

        var real = [Float](repeating: 0, count: size / 2)
        var imag = [Float](repeating: 0, count: size / 2)
        var magnitudes = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { sp in
                    sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                let input = split
                fft.forward(input: input, output: &split)
                vDSP.squareMagnitudes(split, result: &magnitudes)
            }
        }

        var bands = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
        var peak: Float = 0
        for (b, range) in bandRanges.enumerated() {
            var sum: Float = 0
            for k in range where k < magnitudes.count { sum += magnitudes[k] }
            let v = sqrt(sum / Float(range.count))
            bands[b] = v
            peak = max(peak, v)
        }
        // Ganancia automática: la banda más fuerte reciente ≈ 1.
        runningPeak = max(peak, runningPeak * 0.985, 1e-3)
        for b in 0..<bands.count {
            bands[b] = min(1, pow(bands[b] / runningPeak, 0.7))
        }
        let bass = (bands[0] + bands[1] + bands[2] + bands[3]) / 4

        let snap = Snapshot(level: min(1, rms * 4), bass: bass, bands: bands, time: Date.timeIntervalSinceReferenceDate)
        lock.withLock { latest = snap }
    }
}
