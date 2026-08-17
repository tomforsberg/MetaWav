import AVFoundation
import Foundation

/// Lightweight DSP meter for RMS + peak with attack/release and peak hold.
/// Designed to run on the audio thread with no allocations in `process`.
final class VuMeterDSP {
    // MARK: - Configuration
    let sampleRate: Double
    let rmsWindowMs: Double
    let attackMs: Double
    let releaseMs: Double
    let peakHoldMs: Double
    
    // MARK: - Audio-thread state
    private var ms: Double = 0.0              // running mean-square
    private var displayDb: Double = -120.0    // smoothed meter dB
    private var peakDbHold: Double = -120.0   // held peak dB
    private var peakHoldCounterSamples: Int = 0
    
    // MARK: - Published values (audio → UI snapshot)
    // These are updated only from `process` and read from UI on a timer.
    private(set) var currentDb: Double = -120.0
    private(set) var currentPeakDb: Double = -120.0
    private(set) var isPeakLitFlag: Bool = false
    
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
        
        // Single-pole IIR RMS window:
        // ms[n] = a*ms[n-1] + (1-a)*x^2, a = exp(-1/(tau*fs))
        let tauRms = rmsWindowMs / 1000.0
        self.rmsA = exp(-1.0 / (tauRms * sampleRate))
        
        // Attack / release smoothing in dB domain.
        let tauAttack = attackMs / 1000.0
        let tauRelease = releaseMs / 1000.0
        self.attackAlpha  = exp(-1.0 / (tauAttack  * sampleRate))
        self.releaseAlpha = exp(-1.0 / (tauRelease * sampleRate))
        
        // Peak hold in samples
        self.peakHoldSamples = Int((peakHoldMs / 1000.0) * sampleRate)
    }
    
    // MARK: - Audio-thread entry point
    func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        if frames == 0 { return }
        
        let channels = Int(buffer.format.channelCount)
        let eps = 1e-12
        
        // Convert per-sample coefficients to per-block so the configured
        // attack/release times behave correctly at the tap's buffer size.
        let frameCount = Double(frames)
        let rmsBlockA = pow(rmsA, frameCount)
        let attackBlockAlpha = pow(attackAlpha, frameCount)
        let releaseBlockAlpha = pow(releaseAlpha, frameCount)
        
        // Compute block RMS and peak in linear domain.
        var sumSquares: Double = 0.0
        var peakLinear: Double = 0.0
        
        for frame in 0..<frames {
            var mixedSample: Double = 0.0
            for ch in 0..<channels {
                let s = Double(channelData[ch][frame])
                mixedSample += s
                let absS = abs(s)
                if absS > peakLinear {
                    peakLinear = absS
                }
            }
            mixedSample /= Double(channels)
            sumSquares += mixedSample * mixedSample
        }
        
        let blockMs = sumSquares / Double(frames)
        
        // One-pole RMS smoothing in mean-square domain, using block-sized step.
        let localMs = rmsBlockA * ms + (1.0 - rmsBlockA) * blockMs
        
        // RMS → dBFS
        let rms = sqrt(localMs + eps)
        var db = 20.0 * log10(rms + eps)
        
        // Instantaneous peak (per block) in dBFS
        var localPeakDb: Double = -120.0
        if peakLinear > 0.0 {
            localPeakDb = 20.0 * log10(peakLinear + eps)
        }
        
        // Attack / release smoothing in dB domain, using block-sized step.
        let prevDisplay = displayDb
        if db > prevDisplay {
            db = attackBlockAlpha * prevDisplay + (1.0 - attackBlockAlpha) * db
        } else {
            db = releaseBlockAlpha * prevDisplay + (1.0 - releaseBlockAlpha) * db
        }
        
        // Peak hold handling
        var holdDb = peakDbHold
        var holdCounter = peakHoldCounterSamples
        
        if localPeakDb > holdDb {
            holdDb = localPeakDb
            holdCounter = peakHoldSamples
        } else {
            if holdCounter > 0 {
                holdCounter -= frames
                if holdCounter < 0 { holdCounter = 0 }
            } else {
                // After hold, decay peak toward current level
                holdDb = releaseAlpha * holdDb + (1.0 - releaseAlpha) * db
            }
        }
        
        let minDb = -80.0
        db = max(minDb, db)
        localPeakDb = max(minDb, localPeakDb)
        holdDb = max(minDb, holdDb)
        
        // Commit to state
        ms = localMs
        displayDb = db
        peakDbHold = holdDb
        peakHoldCounterSamples = holdCounter
        
        currentDb = db
        currentPeakDb = holdDb
        isPeakLitFlag = holdDb > -1.0
    }
    
    // MARK: - UI helpers (poll from main/UI thread)
    
    /// Raw smoothed dBFS value for debugging/advanced mapping.
    var currentDbValue: Double { currentDb }
    
    func normalizedLevel(minDb: Double = -40.0, maxDb: Double = 0.0) -> Double {
        let db = currentDb
        if db <= minDb { return 0.0 }
        if db >= maxDb { return 1.0 }
        return (db - minDb) / (maxDb - minDb)
    }
    
    func normalizedPeak(minDb: Double = -40.0, maxDb: Double = 0.0) -> Double {
        let db = currentPeakDb
        if db <= minDb { return 0.0 }
        if db >= maxDb { return 1.0 }
        return (db - minDb) / (maxDb - minDb)
    }
    
    func isPeakLit() -> Bool {
        isPeakLitFlag
    }
}


