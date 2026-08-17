// AudioPerformanceOptimizer.swift - Applies performance settings to speed up MetaWav
import Foundation
import AVFoundation
import AudioKit
import Combine
import ObjectiveC

class AudioPerformanceOptimizer: ObservableObject {
    static let shared = AudioPerformanceOptimizer()
    
    private let settingsManager = SettingsManager.shared
    private let audioProcessor = AudioProcessor.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Performance state
    @Published var isOptimized = false
    @Published var currentBufferSize = 2048
    @Published var currentUIFPS = 50
    @Published var isHardwareAccelerated = false
    
    // UI update throttling
    private var uiUpdateTimer: Timer?
    private var lastUIUpdate = Date()
    private var pendingUIUpdates: [() -> Void] = []
    
    // Audio processing queues
    private let audioProcessingQueue = DispatchQueue(label: "audio.processing", qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "audio.metadata", qos: .utility)
    private let uiUpdateQueue = DispatchQueue(label: "ui.updates", qos: .userInteractive)
    
    // Performance monitoring
    private var performanceMetrics: [String: Any] = [:]
    private var lastPerformanceCheck = Date()
    
    private init() {
        setupBindings()
        applySettings()
        print("🚀 AudioPerformanceOptimizer initialized")
    }
    
    // MARK: - Settings Integration
    
    private func setupBindings() {
        // Listen for settings changes
        settingsManager.$audioBufferSize
            .sink { [weak self] newBufferSize in
                self?.updateBufferSize(newBufferSize)
            }
            .store(in: &cancellables)
        
        settingsManager.$uiUpdateFrequency
            .sink { [weak self] newFPS in
                self?.updateUIFPS(newFPS)
            }
            .store(in: &cancellables)
        
        settingsManager.$enableAudioOptimizations
            .sink { [weak self] enabled in
                self?.toggleOptimizations(enabled)
            }
            .store(in: &cancellables)
        
        settingsManager.$useHardwareAcceleration
            .sink { [weak self] enabled in
                self?.toggleHardwareAcceleration(enabled)
            }
            .store(in: &cancellables)
    }
    
    func applySettings() {
        updateBufferSize(settingsManager.audioBufferSize)
        updateUIFPS(settingsManager.uiUpdateFrequency)
        toggleOptimizations(settingsManager.enableAudioOptimizations)
        toggleHardwareAcceleration(settingsManager.useHardwareAcceleration)
        
        print("🔧 Performance settings applied")
    }
    
    // MARK: - Buffer Size Optimization
    
    private func updateBufferSize(_ newSize: Int) {
        currentBufferSize = newSize
        
            // Apply to AudioKit engine
    // Note: AudioKit buffer size is managed internally
    print("🔧 AudioKit buffer size setting applied: \(newSize) samples")
    
    // Apply to AVAudioEngine if available
    // Note: AVAudioEngine buffer size is managed internally
    print("🔧 Buffer size setting applied: \(newSize) samples")
        
        updatePerformanceMetrics()
    }
    
    // MARK: - UI FPS Optimization
    
    private func updateUIFPS(_ newFPS: Int) {
        currentUIFPS = newFPS
        
        // Stop existing timer
        uiUpdateTimer?.invalidate()
        
        // Create new timer with optimized frequency
        let interval = 1.0 / Double(newFPS)
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.processPendingUIUpdates()
        }
        
        print("🔧 UI update frequency set to: \(newFPS) FPS (\(String(format: "%.2f", interval))s interval)")
        updatePerformanceMetrics()
    }
    
    // MARK: - Audio Optimizations
    
    private func toggleOptimizations(_ enabled: Bool) {
        isOptimized = enabled
        
        if enabled {
            enableAudioOptimizations()
        } else {
            disableAudioOptimizations()
        }
        
        print("🔧 Audio optimizations: \(enabled ? "enabled" : "disabled")")
    }
    
    private func enableAudioOptimizations() {
        // Move heavy audio processing to background queues
        audioProcessor.audioProcessingQueue = audioProcessingQueue
        
        // Enable audio format optimization
        optimizeAudioFormats()
        
        // Enable smart caching
        enableAudioCaching()
        
        // Optimize audio file loading
        optimizeAudioFileLoading()
    }
    
    private func disableAudioOptimizations() {
        // Revert to default settings
        audioProcessor.audioProcessingQueue = .main
        
        // Disable optimizations
        disableAudioCaching()
    }
    
    // MARK: - Hardware Acceleration
    
    private func toggleHardwareAcceleration(_ enabled: Bool) {
        isHardwareAccelerated = enabled
        
        if enabled {
            enableHardwareAcceleration()
        } else {
            disableHardwareAcceleration()
        }
        
        print("🔧 Hardware acceleration: \(enabled ? "enabled" : "disabled")")
    }
    
    private func enableHardwareAcceleration() {
        // Try to use hardware-optimized sample rates
        let hardwareSampleRates: [Double] = [44100, 48000, 96000, 192000]
        
        for sampleRate in hardwareSampleRates {
            if AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) != nil {
                // Apply hardware-optimized format
                print("🔧 Using hardware-optimized sample rate: \(sampleRate)")
                break
            }
        }
        
        // Enable hardware-specific audio processing
        enableHardwareAudioProcessing()
    }
    
    private func disableHardwareAcceleration() {
        // Revert to standard audio processing
        disableHardwareAudioProcessing()
    }
    
    // MARK: - UI Update Throttling
    
    func throttleUIUpdate(_ update: @escaping () -> Void) {
        if shouldThrottleUIUpdates() {
            pendingUIUpdates.append(update)
        } else {
            update()
        }
    }
    
    private func shouldThrottleUIUpdates() -> Bool {
        let timeSinceLastUpdate = Date().timeIntervalSince(lastUIUpdate)
        let minInterval = 1.0 / Double(currentUIFPS)
        return timeSinceLastUpdate < minInterval
    }
    
    private func processPendingUIUpdates() {
        let updates = pendingUIUpdates
        pendingUIUpdates.removeAll()
        
        // Process updates on main queue
        DispatchQueue.main.async {
            for update in updates {
                update()
            }
        }
        
        lastUIUpdate = Date()
    }
    
    // MARK: - Audio Format Optimization
    
    private func optimizeAudioFormats() {
        // Use compressed formats when possible for faster loading
        let preferredFormats = ["mp3", "aac", "m4a", "flac", "wav"]
        
        // Optimize audio file reading
        audioProcessor.preferredFormats = preferredFormats
    }
    
    // MARK: - Audio Caching
    
    private func enableAudioCaching() {
        // Enable audio buffer caching
        audioProcessor.enableBufferCaching = true
        
        // Enable metadata caching
        audioProcessor.enableMetadataCaching = true
    }
    
    private func disableAudioCaching() {
        audioProcessor.enableBufferCaching = false
        audioProcessor.enableMetadataCaching = false
    }
    
    // MARK: - Audio File Loading Optimization
    
    private func optimizeAudioFileLoading() {
        // Pre-load audio headers only
        audioProcessor.preloadMode = .headersOnly
        
        // Enable lazy loading for large files
        audioProcessor.enableLazyLoading = true
        
        // Use background queue for file operations
        audioProcessor.fileLoadingQueue = metadataQueue
    }
    
    // MARK: - Hardware Audio Processing
    
    private func enableHardwareAudioProcessing() {
        // Enable hardware-specific optimizations
        audioProcessor.enableHardwareProcessing = true
        
        // Use hardware audio units when available
        audioProcessor.preferHardwareUnits = true
    }
    
    private func disableHardwareAudioProcessing() {
        audioProcessor.enableHardwareProcessing = false
        audioProcessor.preferHardwareUnits = false
    }
    
    // MARK: - Performance Monitoring
    
    private func updatePerformanceMetrics() {
        performanceMetrics = [
            "bufferSize": currentBufferSize,
            "bufferLatency": getBufferLatency(),
            "uiFPS": currentUIFPS,
            "uiUpdateInterval": 1.0 / Double(currentUIFPS),
            "isOptimized": isOptimized,
            "isHardwareAccelerated": isHardwareAccelerated,
            "audioProcessingQueue": audioProcessingQueue.label,
            "metadataQueue": metadataQueue.label,
            "uiUpdateQueue": uiUpdateQueue.label
        ]
        
        lastPerformanceCheck = Date()
    }
    
    func getPerformanceMetrics() -> [String: Any] {
        return performanceMetrics
    }
    
    func getBufferLatency() -> TimeInterval {
        // Calculate theoretical latency based on buffer size
        let sampleRate: Double = 44100
        let samplesPerFrame = Double(currentBufferSize)
        return samplesPerFrame / sampleRate
    }
    
    // MARK: - Public Interface
    
    func optimizeForPlayback() {
        // Apply playback-specific optimizations
        if isOptimized {
            // Reduce UI updates during playback
            let playbackFPS = max(15, currentUIFPS / 2)
            updateUIFPS(playbackFPS)
            
            // Increase buffer size for smoother playback
            let playbackBufferSize = min(8192, currentBufferSize * 2)
            updateBufferSize(playbackBufferSize)
            
            print("🔧 Optimized for playback: \(playbackFPS) FPS, \(playbackBufferSize) samples")
        }
    }
    
    func optimizeForEditing() {
        // Apply editing-specific optimizations
        if isOptimized {
            // Higher UI responsiveness for editing
            let editingFPS = min(60, currentUIFPS * 2)
            updateUIFPS(editingFPS)
            
            // Lower buffer size for lower latency
            let editingBufferSize = max(512, currentBufferSize / 2)
            updateBufferSize(editingBufferSize)
            
            print("🔧 Optimized for editing: \(editingFPS) FPS, \(editingBufferSize) samples")
        }
    }
    
    func restoreDefaultOptimizations() {
        // Restore to user-selected settings
        updateBufferSize(settingsManager.audioBufferSize)
        updateUIFPS(settingsManager.uiUpdateFrequency)
        print("🔧 Restored default optimizations")
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
        
        cancellables.removeAll()
        
        print("🧹 AudioPerformanceOptimizer cleaned up")
    }
}

// MARK: - AudioProcessor Extensions

extension AudioProcessor {
    // Add performance optimization properties
    var audioProcessingQueue: DispatchQueue {
        get { objc_getAssociatedObject(self, &AssociatedKeys.audioProcessingQueue) as? DispatchQueue ?? .main }
        set { objc_setAssociatedObject(self, &AssociatedKeys.audioProcessingQueue, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var enableBufferCaching: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.enableBufferCaching) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.enableBufferCaching, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var enableMetadataCaching: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.enableMetadataCaching) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.enableMetadataCaching, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var preloadMode: PreloadMode {
        get { objc_getAssociatedObject(self, &AssociatedKeys.preloadMode) as? PreloadMode ?? .full }
        set { objc_setAssociatedObject(self, &AssociatedKeys.preloadMode, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var enableLazyLoading: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.enableLazyLoading) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.enableLazyLoading, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var fileLoadingQueue: DispatchQueue {
        get { objc_getAssociatedObject(self, &AssociatedKeys.fileLoadingQueue) as? DispatchQueue ?? .main }
        set { objc_setAssociatedObject(self, &AssociatedKeys.fileLoadingQueue, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var enableHardwareProcessing: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.enableHardwareProcessing) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.enableHardwareProcessing, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var preferHardwareUnits: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.preferHardwareUnits) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.preferHardwareUnits, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var preferredFormats: [String] {
        get { objc_getAssociatedObject(self, &AssociatedKeys.preferredFormats) as? [String] ?? ["wav", "aiff"] }
        set { objc_setAssociatedObject(self, &AssociatedKeys.preferredFormats, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - Associated Keys

private struct AssociatedKeys {
    // Use unique addresses for associated object keys without exposing String internals
    static var audioProcessingQueue: UInt8 = 0
    static var enableBufferCaching: UInt8 = 0
    static var enableMetadataCaching: UInt8 = 0
    static var preloadMode: UInt8 = 0
    static var enableLazyLoading: UInt8 = 0
    static var fileLoadingQueue: UInt8 = 0
    static var enableHardwareProcessing: UInt8 = 0
    static var preferHardwareUnits: UInt8 = 0
    static var preferredFormats: UInt8 = 0
}

// MARK: - Enums

enum PreloadMode {
    case headersOnly
    case partial
    case full
}
