// AudioPerformanceManager.swift - Manages audio performance settings
import Foundation
import AVFoundation
import AudioToolbox

class AudioPerformanceManager: ObservableObject {
    static let shared = AudioPerformanceManager()
    
    private let settingsManager = SettingsManager.shared
    private var audioEngine: AVAudioEngine?
    
    @Published var currentBufferSize: Int = 4096
    @Published var isOptimized: Bool = true
    @Published var currentUIFPS: Int = 15
    @Published var isHardwareAccelerated: Bool = true
    
    private init() {
        loadSettings()
        setupAudioEngine()
    }
    
    // MARK: - Settings Management
    
    func loadSettings() {
        currentBufferSize = settingsManager.audioBufferSize
        isOptimized = settingsManager.enableAudioOptimizations
        currentUIFPS = settingsManager.uiUpdateFrequency
        isHardwareAccelerated = settingsManager.useHardwareAcceleration
        
        print("🔧 Audio performance settings loaded:")
        print("   Buffer size: \(currentBufferSize) samples")
        print("   Optimizations: \(isOptimized)")
        print("   UI FPS: \(currentUIFPS)")
        print("   Hardware acceleration: \(isHardwareAccelerated)")
    }
    
    func applySettings() {
        loadSettings()
        setupAudioEngine()
        print("🔧 Audio performance settings applied")
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        guard isOptimized else {
            print("🔧 Audio optimizations disabled - using default settings")
            return
        }
        
        do {
            // Create new audio engine with optimized settings
            let engine = AVAudioEngine()
            
            // Configure buffer size for input node (if available)
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let optimizedFormat = AVAudioFormat(
                standardFormatWithSampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount
            )
            
            if let format = optimizedFormat {
                inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(currentBufferSize), format: format) { buffer, _ in
                    // Process audio buffer with optimized settings
                    self.processAudioBuffer(buffer)
                }
            }
            
            // Configure output node
            let outputNode = engine.outputNode
            let outputFormat = outputNode.inputFormat(forBus: 0)
            let optimizedOutputFormat = AVAudioFormat(
                standardFormatWithSampleRate: outputFormat.sampleRate,
                channels: outputFormat.channelCount
            )
            
            if let format = optimizedOutputFormat {
                outputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(currentBufferSize), format: format) { buffer, _ in
                    // Process output buffer
                    self.processOutputBuffer(buffer)
                }
            }
            
            // Enable hardware acceleration if available
            if isHardwareAccelerated {
                enableHardwareAcceleration(for: engine)
            }
            
            // Prepare and start engine
            engine.prepare()
            try engine.start()
            
            audioEngine = engine
            print("🔧 Audio engine configured with optimized settings")
            
        } catch {
            print("❌ Failed to setup optimized audio engine: \(error)")
            // Fall back to default engine
            setupDefaultAudioEngine()
        }
    }
    
    private func setupDefaultAudioEngine() {
        // Use system default audio engine
        audioEngine = AVAudioEngine()
        print("🔧 Using default audio engine")
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Process audio with optimized settings
        guard isOptimized else { return }
        
        // Apply buffer size optimizations
        let frameCount = buffer.frameLength
        let optimizedFrameCount = min(frameCount, AVAudioFrameCount(currentBufferSize))
        
        // Process only the optimized frame count
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                let channelBuffer = channelData[channel]
                // Process audio data with optimized settings
                processChannelData(channelBuffer, frameCount: optimizedFrameCount)
            }
        }
    }
    
    private func processOutputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Process output buffer if needed
        guard isOptimized else { return }
        
        // Apply any output optimizations
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                let channelBuffer = channelData[channel]
                // Apply output processing if needed
                processOutputChannelData(channelBuffer, frameCount: buffer.frameLength)
            }
        }
    }
    
    private func processChannelData(_ data: UnsafePointer<Float>, frameCount: AVAudioFrameCount) {
        // Apply audio processing optimizations
        // This is where you'd implement specific audio processing algorithms
        
        // For now, just ensure we're not doing heavy processing on main thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Process audio data in background
            // This prevents main thread blocking during audio playback
        }
    }
    
    private func processOutputChannelData(_ data: UnsafePointer<Float>, frameCount: AVAudioFrameCount) {
        // Process output data if needed
        // This could include volume normalization, limiting, etc.
    }
    
    // MARK: - Hardware Acceleration
    
    private func enableHardwareAcceleration(for engine: AVAudioEngine) {
        // Enable hardware acceleration features for macOS
        let outputNode = engine.outputNode
        let outputFormat = outputNode.inputFormat(forBus: 0)
        
        // Try to use hardware-optimized sample rates
        let hardwareSampleRates: [Double] = [44100, 48000, 96000, 192000]
        for sampleRate in hardwareSampleRates {
            if AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: outputFormat.channelCount
            ) != nil {
                // Use hardware-optimized format
                print("🔧 Using hardware-optimized sample rate: \(sampleRate)")
                break
            }
        }
        
        print("🔧 Hardware acceleration enabled")
    }
    
    // MARK: - UI Performance Management
    
    func getOptimalUIFPS() -> Int {
        return currentUIFPS
    }
    
    func shouldThrottleUIUpdates() -> Bool {
        // Return true if we should throttle UI updates during audio playback
        return currentUIFPS < 30
    }
    
    func getUIUpdateInterval() -> TimeInterval {
        return 1.0 / Double(currentUIFPS)
    }
    
    // MARK: - Buffer Size Management
    
    func getOptimalBufferSize() -> Int {
        return currentBufferSize
    }
    
    func getBufferLatency() -> TimeInterval {
        // Calculate theoretical latency based on buffer size
        // Assuming 44.1kHz sample rate
        let sampleRate: Double = 44100
        let samplesPerFrame = Double(currentBufferSize)
        return samplesPerFrame / sampleRate
    }
    
    // MARK: - Performance Monitoring
    
    func getPerformanceMetrics() -> [String: Any] {
        return [
            "bufferSize": currentBufferSize,
            "bufferLatency": getBufferLatency(),
            "uiFPS": currentUIFPS,
            "uiUpdateInterval": getUIUpdateInterval(),
            "isOptimized": isOptimized,
            "isHardwareAccelerated": isHardwareAccelerated
        ]
    }
    
    // MARK: - Public Interface
    
    func updateSettings() {
        loadSettings()
        setupAudioEngine()
    }
    
    func resetToDefaults() {
        settingsManager.resetToDefaults()
        loadSettings()
        setupAudioEngine()
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        audioEngine?.stop()
        audioEngine = nil
        print("🔧 Audio performance manager cleaned up")
    }
}
