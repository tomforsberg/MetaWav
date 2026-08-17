import AVFoundation
import Foundation

/// Lightweight stereo DSP meter for per-channel RMS + peak with attack/release and peak hold.
/// Designed to run on the audio thread with no allocations in `process`.
final class StereoVuMeterDSP {
    // MARK: - Configuration
    let sampleRate: Double
    let rmsWindowMs: Double
    let attackMs: Double
    let releaseMs: Double
    let peakHoldMs: Double

    // MARK: - Audio-thread state
    private var msL: Double = 0.0
    private var msR: Double = 0.0
    private var displayDbL: Double = -120.0
    private var displayDbR: Double = -120.0
    private var peakDbHoldL: Double = -120.0
    private var peakDbHoldR: Double = -120.0
    private var peakHoldCounterSamplesL: Int = 0
    private var peakHoldCounterSamplesR: Int = 0

    // MARK: - Published values (audio → UI snapshot)
    private(set) var currentDbL: Double = -120.0
    private(set) var currentDbR: Double = -120.0
    private(set) var currentPeakDbL: Double = -120.0
    private(set) var currentPeakDbR: Double = -120.0
    private(set) var lastProcessTime: TimeInterval = 0

    // MARK: - Coefficients
    private let rmsA: Double
    private let attackAlpha: Double
    private let releaseAlpha: Double
    private let peakHoldSamples: Int

    init(sampleRate: Double,
         rmsWindowMs: Double = 300.0,
         attackMs: Double = 10.0,
         releaseMs: Double = 300.0,
         peakHoldMs: Double = 750.0) {
        self.sampleRate = sampleRate
        self.rmsWindowMs = rmsWindowMs
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.peakHoldMs = peakHoldMs

        let tauRms = rmsWindowMs / 1000.0
        self.rmsA = exp(-1.0 / (tauRms * sampleRate))

        let tauAttack = attackMs / 1000.0
        let tauRelease = releaseMs / 1000.0
        self.attackAlpha  = exp(-1.0 / (tauAttack  * sampleRate))
        self.releaseAlpha = exp(-1.0 / (tauRelease * sampleRate))

        self.peakHoldSamples = Int((peakHoldMs / 1000.0) * sampleRate)
    }

    func process(buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        if frames == 0 { return }

        let channels = Int(buffer.format.channelCount)
        let eps = 1e-12

        let frameCount = Double(frames)
        let rmsBlockA = pow(rmsA, frameCount)
        let attackBlockAlpha = pow(attackAlpha, frameCount)
        let releaseBlockAlpha = pow(releaseAlpha, frameCount)

        var sumSquaresL: Double = 0.0
        var sumSquaresR: Double = 0.0
        var peakLinearL: Double = 0.0
        var peakLinearR: Double = 0.0

        if let channelData = buffer.floatChannelData {
            for frame in 0..<frames {
                let sL = Double(channelData[0][frame])
                sumSquaresL += sL * sL
                peakLinearL = max(peakLinearL, abs(sL))

                if channels > 1 {
                    let sR = Double(channelData[1][frame])
                    sumSquaresR += sR * sR
                    peakLinearR = max(peakLinearR, abs(sR))
                }
            }
        } else if let int16 = buffer.int16ChannelData {
            let scale = 1.0 / 32768.0
            for frame in 0..<frames {
                let sL = Double(int16[0][frame]) * scale
                sumSquaresL += sL * sL
                peakLinearL = max(peakLinearL, abs(sL))

                if channels > 1 {
                    let sR = Double(int16[1][frame]) * scale
                    sumSquaresR += sR * sR
                    peakLinearR = max(peakLinearR, abs(sR))
                }
            }
        } else if let int32 = buffer.int32ChannelData {
            let scale = 1.0 / 2147483648.0
            for frame in 0..<frames {
                let sL = Double(int32[0][frame]) * scale
                sumSquaresL += sL * sL
                peakLinearL = max(peakLinearL, abs(sL))

                if channels > 1 {
                    let sR = Double(int32[1][frame]) * scale
                    sumSquaresR += sR * sR
                    peakLinearR = max(peakLinearR, abs(sR))
                }
            }
        } else {
            // Unknown buffer format; avoid "stuck" by leaving previous values intact.
            return
        }

        if channels == 1 {
            sumSquaresR = sumSquaresL
            peakLinearR = peakLinearL
        }

        let blockMsL = sumSquaresL / Double(frames)
        let blockMsR = sumSquaresR / Double(frames)

        let localMsL = rmsBlockA * msL + (1.0 - rmsBlockA) * blockMsL
        let localMsR = rmsBlockA * msR + (1.0 - rmsBlockA) * blockMsR

        var dbL = 20.0 * log10(sqrt(localMsL + eps) + eps)
        var dbR = 20.0 * log10(sqrt(localMsR + eps) + eps)

        var localPeakDbL: Double = peakLinearL > 0.0 ? 20.0 * log10(peakLinearL + eps) : -120.0
        var localPeakDbR: Double = peakLinearR > 0.0 ? 20.0 * log10(peakLinearR + eps) : -120.0

        // Attack / release smoothing in dB domain.
        let prevL = displayDbL
        let prevR = displayDbR
        dbL = dbL > prevL ? (attackBlockAlpha * prevL + (1.0 - attackBlockAlpha) * dbL)
                          : (releaseBlockAlpha * prevL + (1.0 - releaseBlockAlpha) * dbL)
        dbR = dbR > prevR ? (attackBlockAlpha * prevR + (1.0 - attackBlockAlpha) * dbR)
                          : (releaseBlockAlpha * prevR + (1.0 - releaseBlockAlpha) * dbR)

        // Peak hold (use block-scaled release so decay behaves correctly at the tap buffer size)
        (peakDbHoldL, peakHoldCounterSamplesL) = updatePeakHold(
            localPeakDb: localPeakDbL,
            currentDb: dbL,
            holdDb: peakDbHoldL,
            holdCounter: peakHoldCounterSamplesL,
            frames: frames,
            releaseBlockAlpha: releaseBlockAlpha
        )
        (peakDbHoldR, peakHoldCounterSamplesR) = updatePeakHold(
            localPeakDb: localPeakDbR,
            currentDb: dbR,
            holdDb: peakDbHoldR,
            holdCounter: peakHoldCounterSamplesR,
            frames: frames,
            releaseBlockAlpha: releaseBlockAlpha
        )

        let minDb = -80.0
        dbL = max(minDb, dbL)
        dbR = max(minDb, dbR)
        localPeakDbL = max(minDb, localPeakDbL)
        localPeakDbR = max(minDb, localPeakDbR)
        peakDbHoldL = max(minDb, peakDbHoldL)
        peakDbHoldR = max(minDb, peakDbHoldR)

        // Commit
        msL = localMsL
        msR = localMsR
        displayDbL = dbL
        displayDbR = dbR

        currentDbL = dbL
        currentDbR = dbR
        currentPeakDbL = peakDbHoldL
        currentPeakDbR = peakDbHoldR
        lastProcessTime = Date().timeIntervalSince1970
    }

    private func updatePeakHold(
        localPeakDb: Double,
        currentDb: Double,
        holdDb: Double,
        holdCounter: Int,
        frames: Int,
        releaseBlockAlpha: Double
    ) -> (Double, Int) {
        var hd = holdDb
        var hc = holdCounter
        if localPeakDb > hd {
            hd = localPeakDb
            hc = peakHoldSamples
        } else {
            if hc > 0 {
                hc -= frames
                if hc < 0 { hc = 0 }
            } else {
                // After hold, decay peak toward current level
                hd = releaseBlockAlpha * hd + (1.0 - releaseBlockAlpha) * currentDb
            }
        }
        return (hd, hc)
    }

    func normalizedLevelL(minDb: Double = -40.0, maxDb: Double = 0.0) -> Double {
        normalize(db: currentDbL, minDb: minDb, maxDb: maxDb)
    }

    func normalizedLevelR(minDb: Double = -40.0, maxDb: Double = 0.0) -> Double {
        normalize(db: currentDbR, minDb: minDb, maxDb: maxDb)
    }

    func normalizedPeakL(minDb: Double = -40.0, maxDb: Double = 0.0) -> Double {
        normalize(db: currentPeakDbL, minDb: minDb, maxDb: maxDb)
    }

    func normalizedPeakR(minDb: Double = -40.0, maxDb: Double = 0.0) -> Double {
        normalize(db: currentPeakDbR, minDb: minDb, maxDb: maxDb)
    }

    private func normalize(db: Double, minDb: Double, maxDb: Double) -> Double {
        if db <= minDb { return 0.0 }
        if db >= maxDb { return 1.0 }
        return (db - minDb) / (maxDb - minDb)
    }
}


