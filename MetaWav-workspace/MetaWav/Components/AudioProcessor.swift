// AudioProcessor.swift - Unified processor preserving original functionality + AU support
import AudioKit
import AudioKitEX
import Combine
import Foundation
import AVFoundation

class AudioProcessor: NSObject, ObservableObject {
    static let shared = AudioProcessor()
    
    // Original AudioKit components for reliable playback
    private var avPlayer: AVAudioPlayer?
    private let unified = UnifiedAudioEngine.shared
    let engine = AudioEngine()
    var player: AudioPlayer?
    var mixer: Mixer?
    
    
    // AU functionality removed - coming soon
    
    // Virtual output that can be accessed by other systems
    var virtualOutput: Mixer?
    
    @Published var volumeValue: Float = 1
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var ampEnabled: Bool = false {
        didSet {
            unified.setAmpEnabled(ampEnabled)
        }
    }
    
    // Track which file is currently loaded
    @Published var loadedFileURL: URL?
    
    private var cancellables = Set<AnyCancellable>()
    private var timeUpdateTimer: Timer?
    private var seekPendingTime: TimeInterval?
    private var transitionFadeTimer: Timer?
    private var isTransitionFading: Bool = false
    
    // AU processing state removed - coming soon
    
    // Track completion tolerance (kept small to minimize end-of-track gap)
    private let completionTolerance: TimeInterval = 0.01 // 10ms tolerance
    private let transitionFadeDuration: TimeInterval = 0.015 // 15ms fade for manual skips to avoid pops
    
    var onTrackFinished: (() -> Void)?
    
    
    override init() {
        super.init()
        setupEngine()
        setupBindings()
    }
    
    private func setupEngine() {
        mixer = Mixer()
        
        // Create virtual output - NEVER connects to system
        virtualOutput = Mixer()
        virtualOutput?.addInput(mixer!)
        
        // AudioProcessor NEVER outputs to system when AUs are inactive
        engine.output = virtualOutput
        
        // Tap for C++ processing is now handled elsewhere; no tap installed here.
        
        startEngine()
        
        print("🔗 AudioProcessor: AudioKit engine setup with virtual output and C++ plugin processing")
    }
    
    
    
    // Method for other systems to get our virtual output
    func getVirtualOutput() -> Mixer? {
        return virtualOutput
    }
    
    private func startEngine() {
        do {
            try engine.start()
        } catch {
            print("AudioKit engine failed to start: \(error)")
        }
    }

    
    private func setupBindings() {
        $volumeValue
            .sink { [weak self] value in
                self?.updateVolume(value)
            }
            .store(in: &cancellables)

        // Unified engine listens directly for buffer size changes
    }

    // Legacy tap reconfiguration removed; unified engine handles buffer sizing
    
    
    func load(url: URL) {
        do {
            // COMPLETE CLEANUP FIRST
            stopTimeUpdates()
            player?.stop()
            avPlayer?.stop()
            avPlayer = nil
            
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "AudioProcessor", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Open file once and reuse for both duration and engine
            let audioFile = try AVAudioFile(forReading: url)
            
            // Prepare unified engine with existing AVAudioFile
            unified.load(file: audioFile)
            
            // Get duration directly from AVAudioFile
            duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            
            currentTime = 0
            isPlaying = false
            loadedFileURL = url
            
            // Apply any pending seek
            if let seekTime = seekPendingTime {
                seek(to: seekTime)
                seekPendingTime = nil
            }
            
            print("📀 Loaded track: \(url.lastPathComponent), duration: \(duration)s")
            
        } catch {
            print("Audio loading failed: \(error)")
            duration = 0
            currentTime = 0
            isPlaying = false
            loadedFileURL = nil
        }
    }

    /// Load from an already-open AVAudioFile (avoids extra I/O and decoding).
    func load(file: AVAudioFile) {
        // COMPLETE CLEANUP FIRST
        stopTimeUpdates()
        player?.stop()
        avPlayer?.stop()
        avPlayer = nil
        
        unified.load(file: file)
        
        duration = Double(file.length) / file.fileFormat.sampleRate
        currentTime = 0
        isPlaying = false
        loadedFileURL = file.url
        
        // Apply any pending seek
        if let seekTime = seekPendingTime {
            seek(to: seekTime)
            seekPendingTime = nil
        }
        
        print("📀 Loaded track (pre-opened file): \(file.url.lastPathComponent), duration: \(duration)s")
    }
    
    private func updateVolume(_ value: Float) {
        let curvedValue = pow(value, 0.7)
        avPlayer?.volume = curvedValue
        player?.volume = curvedValue
        unified.setVolume(curvedValue)
    }
    
    func play() {
        // Transition to unified engine for audible playback
        unified.play()
        isPlaying = true
        startTimeUpdates()
    }
    
    private func playWithAudioKit() {
        guard let avPlayer = avPlayer else {
            print("⚠️ No AVAudioPlayer loaded")
            return
        }
        
        avPlayer.play()
        isPlaying = true
        startTimeUpdates()
        
        print("▶️ Started AudioKit playback, duration: \(duration)s")
    }
    
    
    func stop() {
        stopTimeUpdates()
        
        avPlayer?.stop()
        avPlayer?.currentTime = 0
        player?.stop()
        unified.stop()
        
        isPlaying = false
        currentTime = 0
        
        print("⏹ Stopped playback")
    }
    
    func pause() {
        avPlayer?.pause()
        player?.pause()
        unified.pause()
        
        isPlaying = false
        stopTimeUpdates()
        
        print("⏸ Paused playback at \(currentTime)s")
    }
    
    func fullCleanup() {
        stopTimeUpdates()
        transitionFadeTimer?.invalidate()
        transitionFadeTimer = nil
        isTransitionFading = false
        // Ensure the unified engine is fully stopped so no audio continues
        unified.stop()
        avPlayer?.stop()
        avPlayer = nil
        player?.stop()
        player = nil
        
        isPlaying = false
        currentTime = 0
        duration = 0
        loadedFileURL = nil
        
        print("🧹 AudioProcessor fully cleaned up")
    }
    
    
    func seek(to time: TimeInterval) {
        let clampedTime = min(max(time, 0), duration)
        unified.seek(to: clampedTime)
        currentTime = clampedTime
    }
    
    /// Adjust playback rate for tape-style fast forward (1.0 = normal).
    func setPlaybackRate(_ rate: Float) {
        unified.setTransportRate(rate)
    }
    
    /// Smoothly ramp playback rate back toward a target (used when exiting shuttle).
    func rampPlaybackRate(to rate: Float, duration: TimeInterval = 0.18) {
        unified.rampTransportRate(to: rate, duration: duration)
    }
    
    private func seekInAudioKit(to time: TimeInterval) {
        guard let avPlayer = avPlayer else {
            seekPendingTime = time
            return
        }
        
        let wasPlaying = isPlaying
        
        if isPlaying {
            pause()
        }
        
        avPlayer.currentTime = time
        currentTime = time
        
        if wasPlaying {
            play()
        }
        
        print("✅ AudioKit seek completed to: \(time)s")
    }
    
    func fadeOutThen(_ completion: @escaping () -> Void) {
        // If we're not currently playing, just run the completion immediately.
        guard isPlaying, !isTransitionFading else {
            completion()
            return
        }
        
        isTransitionFading = true
        transitionFadeTimer?.invalidate()
        
        let startSliderValue = volumeValue
        let steps = 6
        let stepDuration = transitionFadeDuration / Double(steps)
        var currentStep = 0
        
        transitionFadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            let t = min(Double(currentStep) / Double(steps), 1.0)
            let newSliderValue = startSliderValue * Float(max(0.0, 1.0 - t))
            self.updateVolume(newSliderValue)
            
            if currentStep >= steps {
                timer.invalidate()
                self.transitionFadeTimer = nil
                self.isTransitionFading = false
                // Restore the user-facing volume curve for the next track.
                self.updateVolume(startSliderValue)
                completion()
            }
        }
    }
    
    
    private func handlePlaybackFinished() {
        print("🏁 Track finished - calling completion handler")
        stopTimeUpdates()
        // For natural track ends, avoid extra fade/delay so transitions stay as tight as possible.
        isPlaying = false
        onTrackFinished?()
    }
    
    // FIXED: More reliable time updates with proper completion detection
    private func startTimeUpdates() {
        stopTimeUpdates()
        
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isPlaying {
                self.currentTime = self.unified.currentTime
                let timeRemaining = self.duration - self.currentTime
                if timeRemaining <= self.completionTolerance && self.currentTime > 0 {
                    print("🏁 Track completion detected - time remaining: \(timeRemaining)s")
                    self.handlePlaybackFinished()
                }
            }
        }
    }
    
    
    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
    
}

// MARK: - AVAudioPlayerDelegate

extension AudioProcessor: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🏁 AVAudioPlayerDelegate: Track finished successfully=\(flag)")
        DispatchQueue.main.async { [weak self] in
            self?.handlePlaybackFinished()
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ AVAudioPlayer decode error: \(error?.localizedDescription ?? "Unknown")")
        DispatchQueue.main.async { [weak self] in
            self?.handlePlaybackFinished()
        }
    }
}
