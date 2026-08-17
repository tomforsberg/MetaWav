import SwiftUI
import AVFoundation
import AppKit
import MediaPlayer

// MARK: - Media Key Handler (Fallback when app is active)
// Preferred: MPRemoteCommandCenter https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
// This NSEvent-based handler acts as a fallback when the app is active to mirror button animations/sounds
// immediately. Debounced to avoid double-handling when MPRemoteCommandCenter also fires.
class MediaKeyHandler: ObservableObject {
    static let shared = MediaKeyHandler()
    
    var onPreviousTrack: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var lastKeyCodeHandled: Int?
    private var lastHandleTime: CFAbsoluteTime = 0
    
    private init() {
        setupEventMonitors()
    }
    
    private func setupEventMonitors() {
        // Local monitor for when app is active (can consume events)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            return self?.handleMediaKeyEvent(event) ?? event
        }
        
        // Global monitor for background visibility (cannot consume). We only use it
        // to mirror animations when possible; MPRemoteCommandCenter remains the system path.
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            _ = self?.handleMediaKeyEvent(event)
        }
        
        print("📱 Media key handlers setup (fallback: local + global with debounce)")
    }
    
    private func handleMediaKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard event.subtype.rawValue == 8 else { return event }
        
        let keyCode = ((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = (event.data1 & 0x0000FFFF)
        let keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA // 0xA is KeyDown
        
        if keyState { // Only handle key down events
            // Simple debounce to avoid double-handling with MPRemoteCommandCenter
            let now = CFAbsoluteTimeGetCurrent()
            if let last = lastKeyCodeHandled, last == keyCode, (now - lastHandleTime) < 0.15 {
                return event
            }
            switch keyCode {
            case Int(NX_KEYTYPE_REWIND): // F7 - Previous
                print("🎯 F7 (Previous) media key pressed - MetaWav handling")
                self.onPreviousTrack?()
                lastKeyCodeHandled = keyCode
                lastHandleTime = now
                return nil // Consume when local to prevent other apps
            case Int(NX_KEYTYPE_PLAY): // F8 - Play/Pause
                print("🎯 F8 (Play/Pause) media key pressed - MetaWav handling")
                self.onPlayPause?()
                lastKeyCodeHandled = keyCode
                lastHandleTime = now
                return nil
            case Int(NX_KEYTYPE_FAST): // F9 - Next
                print("🎯 F9 (Next) media key pressed - MetaWav handling")
                self.onNextTrack?()
                lastKeyCodeHandled = keyCode
                lastHandleTime = now
                return nil
            default:
                break
            }
        }
        
        return event // Let other events pass through
    }
    
    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Now Playing Manager
class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()
    
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    
    // Callbacks for transport controls
    var onPlayCommand: (() -> Void)?
    var onPauseCommand: (() -> Void)?
    var onNextCommand: (() -> Void)?
    var onPreviousCommand: (() -> Void)?
    var onStopCommand: (() -> Void)?
    var onChangePlaybackPosition: ((TimeInterval) -> Void)?
    
    private init() {
        setupRemoteCommandCenter()
    }
    
    private func setupRemoteCommandCenter() {
        print("🎛️ Setting up Remote Command Center for media key control")
        // Standard implementation per Apple docs:
        // MPRemoteCommandCenter: https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
        // This is the supported way to handle F7/F8/F9 on macOS. Avoid NSEvent-based interception
        // to prevent conflicts with other media apps and ensure system routing via Control Center.
        
        // Enable the commands we want to handle
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.isEnabled = true
        // Also enable toggle as some keyboards emit a toggle play/pause event
        // Docs: https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter/1623261-toggleplaypausecommand
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.isEnabled = true
        remoteCommandCenter.previousTrackCommand.isEnabled = true
        remoteCommandCenter.stopCommand.isEnabled = true
        
        // Enable seeking from Control Center when supported
        if #available(macOS 10.12.2, *) {
            remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true
        }
        
        // Add targets for the commands
        remoteCommandCenter.playCommand.addTarget { [weak self] event in
            print("🎯 MPRemoteCommand: PLAY")
            self?.onPlayCommand?()
            return .success
        }
        
        remoteCommandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            print("🎯 MPRemoteCommand: TOGGLE_PLAY_PAUSE")
            // Route to play or pause based on current playback state
            if let self = self {
                // We don't hold playback state here; defer to the app's callbacks if available
                // If the app provided both play and pause handlers, choose based on MPNowPlaying state
                let isPlaying = (self.nowPlayingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.floatValue == 1.0
                if isPlaying {
                    self.onPauseCommand?()
                } else {
                    self.onPlayCommand?()
                }
            }
            return .success
        }
        
        if #available(macOS 10.12.2, *) {
            remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let self = self, let e = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                print("🎯 MPRemoteCommand: CHANGE_PLAYBACK_POSITION -> \(e.positionTime)")
                self.onChangePlaybackPosition?(e.positionTime)
                return .success
            }
        }

        remoteCommandCenter.pauseCommand.addTarget { [weak self] event in
            print("🎯 MPRemoteCommand: PAUSE")
            self?.onPauseCommand?()
            return .success
        }
        
        remoteCommandCenter.nextTrackCommand.addTarget { [weak self] event in
            print("🎯 MPRemoteCommand: NEXT")
            self?.onNextCommand?()
            return .success
        }
        
        remoteCommandCenter.previousTrackCommand.addTarget { [weak self] event in
            print("🎯 MPRemoteCommand: PREVIOUS")
            self?.onPreviousCommand?()
            return .success
        }
        
        remoteCommandCenter.stopCommand.addTarget { [weak self] event in
            print("🎯 MPRemoteCommand: STOP")
            self?.onStopCommand?()
            return .success
        }
        
        // Disable commands we don't use
        remoteCommandCenter.seekForwardCommand.isEnabled = false
        remoteCommandCenter.seekBackwardCommand.isEnabled = false
        remoteCommandCenter.skipForwardCommand.isEnabled = false
        remoteCommandCenter.skipBackwardCommand.isEnabled = false
    }
    
    func updateNowPlayingInfo(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval,
        currentTime: TimeInterval = 0,
        playbackRate: Float = 1.0,
        artwork: MPMediaItemArtwork? = nil
    ) {
        // Publish Now Playing per Apple docs:
        // MPNowPlayingInfoCenter: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
        // Populate title/artist/album/artwork and keep elapsed time + playback rate in sync so
        // Control Center can display progress and route remote commands correctly.
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        
        if let artist = artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        if let album = album {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        }
        
        if let artwork = artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        if #available(macOS 10.12.2, *) {
            nowPlayingInfoCenter.playbackState = playbackRate > 0 ? .playing : .paused
        }
        print("📻 Updated Now Playing: '\(title)' by '\(artist ?? "Unknown Artist")'")
        print("   This tells macOS that MetaWav is the active media player")
    }
    
    /// Update only the elapsed playback time to keep Control Center progress accurate
    /// Docs: MPNowPlayingInfoCenter: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
    func updateElapsedTime(_ time: TimeInterval) {
        guard var info = nowPlayingInfoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        nowPlayingInfoCenter.nowPlayingInfo = info
    }
    
    func setPlaybackState(isPlaying: Bool) {
        guard var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo else { return }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        if #available(macOS 10.12.2, *) {
            nowPlayingInfoCenter.playbackState = isPlaying ? .playing : .paused
        }
        
        print("📻 Playback state updated: \(isPlaying ? "Playing" : "Paused")")
    }
    
    func clearNowPlayingInfo() {
        nowPlayingInfoCenter.nowPlayingInfo = nil
        if #available(macOS 10.12.2, *) {
            nowPlayingInfoCenter.playbackState = .stopped
        }
        print("📻 Cleared Now Playing info - released media key control")
    }
    
    func createArtwork(from imagePath: String) -> MPMediaItemArtwork? {
        // Load image on background queue to avoid blocking main thread
        guard let image = DispatchQueue.global(qos: .utility).sync(execute: {
            NSImage(contentsOfFile: imagePath)
        }) else { return nil }
        
        return MPMediaItemArtwork(boundsSize: image.size) { size in
            // Process image resize on background queue
            return DispatchQueue.global(qos: .utility).sync(execute: {
                let resizedImage = NSImage(size: size)
                resizedImage.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: size))
                resizedImage.unlockFocus()
                return resizedImage
            })
        }
    }
    
    func cleanup() {
        onPlayCommand = nil
        onPauseCommand = nil
        onNextCommand = nil
        onPreviousCommand = nil
        onStopCommand = nil
        clearNowPlayingInfo()
    }
}

struct TransportControls: View {
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentFileIndex: Int?
    @Binding var currentTime: TimeInterval
    @Binding var isPoweredOn: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    @Binding var selectedTrack: TrackMetadata?

    @ObservedObject private var audioProcessor = AudioProcessor.shared
    @ObservedObject private var nowPlayingManager = NowPlayingManager.shared
    @ObservedObject private var performanceOptimizer = AudioPerformanceOptimizer.shared
    @ObservedObject private var queueManager = QueueManager.shared
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var currentAlbum: AlbumMetadata?
    
    // States to trigger the existing 3D button press animations
    @State private var isPreviousPressed = false
    @State private var isPlayPressed = false
    @State private var isPausePressed = false
    @State private var isNextPressed = false
    
    // Custom button style that mimics your existing 3D styles but can be externally controlled
    private struct ProgrammaticPressButtonStyle: ButtonStyle {
        let isExternallyPressed: Bool
        let width: CGFloat
        let height: CGFloat
        let isSquare: Bool
        
        init(isExternallyPressed: Bool, size: CGFloat, isSquare: Bool) {
            self.isExternallyPressed = isExternallyPressed
            self.width = size
            self.height = size
            self.isSquare = isSquare
        }
        
        init(isExternallyPressed: Bool, width: CGFloat, height: CGFloat, isSquare: Bool) {
            self.isExternallyPressed = isExternallyPressed
            self.width = width
            self.height = height
            self.isSquare = isSquare
        }
        
        func makeBody(configuration: Configuration) -> some View {
            let isPressed = configuration.isPressed || isExternallyPressed
            let cornerRadius: CGFloat = isSquare ? 2 : 2
            
            configuration.label
                .frame(width: width, height: height)
                .background(
                    ZStack {
                        // Base button background with gradient
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: isPressed ?
                                              Color(red: 0.25, green: 0.25, blue: 0.25) :
                                              Color(red: 0.40, green: 0.40, blue: 0.40), location: 0.0),
                                        .init(color: Color(red: 0.33, green: 0.33, blue: 0.33), location: 0.5),
                                        .init(color: isPressed ?
                                              Color(red: 0.30, green: 0.30, blue: 0.30) :
                                              Color(red: 0.25, green: 0.25, blue: 0.25), location: 1.0)
                                    ]),
                                    startPoint: isPressed ? .bottomLeading : .topLeading,
                                    endPoint: isPressed ? .topTrailing : .bottomTrailing
                                )
                            )
                        
                        // Top highlight (specular reflection)
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(isPressed ? 0.05 : 0.15), location: 0.0),
                                        .init(color: Color.clear, location: isPressed ? 0.3 : 0.5)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Bottom shadow/depth
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.clear, location: isPressed ? 0.4 : 0.6),
                                        .init(color: Color.black.opacity(isPressed ? 0.25 : 0.15), location: 1.0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                )
                // Main border
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .inset(by: 0.5)
                        .stroke(
                            Color.black.opacity(isPressed ? 0.8 : 0.6),
                            lineWidth: isPressed ? 1.5 : 1.0
                        )
                )
                // Outer shadow for depth
                .shadow(
                    color: Color.black.opacity(isPressed ? 0.15 : 0.35),
                    radius: isPressed ? 1 : 3,
                    x: isPressed ? 0.5 : 2,
                    y: isPressed ? 0.5 : 3
                )
                // Inner shadow for pressed effect
                .overlay(
                    isPressed ?
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .inset(by: 1)
                        .stroke(
                            Color.black.opacity(0.3),
                            lineWidth: 1
                        )
                    : nil
                )
                // Position shift for depth
                .offset(
                    x: isPressed ? 1 : 0,
                    y: isPressed ? 1.5 : 0
                )
                // Scale for subtle size change
                .scaleEffect(isPressed ? 0.98 : 1.0)
                // Smooth spring animations
                .animation(
                    isPressed ?
                        .easeOut(duration: 0.12) :  // Press down: 120ms
                        .spring(response: 0.08, dampingFraction: 0.8, blendDuration: 0), // Release: 80ms spring
                    value: isPressed
                )
        }
    }
    
    private class SoundPlayer {
        private var sounds: [String: NSSound] = [:]
        private let settingsManager = SettingsManager.shared
        
        func play(named name: String) {
            guard settingsManager.enableSoundEffects else {
                print("🔇 Sound effects disabled - skipping \(name)")
                return
            }
            
            sounds[name]?.stop()
            
            if sounds[name] == nil {
                guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                    print("Sound file not found: \(name).wav")
                    return
                }
                sounds[name] = NSSound(contentsOf: url, byReference: false)
                sounds[name]?.volume = 1.0
            }
            
            sounds[name]?.currentTime = 0
            sounds[name]?.play()
            print("🔊 Playing transport sound: \(name)")
        }
    }
    
    private let soundPlayer = SoundPlayer()
    
    var body: some View {
        ZStack {
            // Symbol Labels - positioned ABOVE buttons
            Group {
                Text("⏏")
                    .font(Font.custom("Roboto", size: 17))
                    .lineSpacing(20)
                    .opacity(0.75)
                    .foregroundColor(.white)
                    .offset(x: -25.85, y: 18.24) // Above button
                    .allowsHitTesting(false)
                
                Text("⏵")
                    .font(Font.custom("Roboto", size: 17))
                    .lineSpacing(20)
                    .opacity(0.75)
                    .foregroundColor(.white)
                    .offset(x: 31.78, y: 18.24) // Above button
                    .allowsHitTesting(false)
                
                Text("⏹")
                    .font(Font.custom("Roboto", size: 17))
                    .lineSpacing(20)
                    .opacity(0.75)
                    .foregroundColor(.white)
                    .offset(x: 89.42, y: 18.24) // Above button
                    .allowsHitTesting(false)
                
                Text("⏸")
                    .font(Font.custom("Roboto", size: 17))
                    .lineSpacing(20)
                    .opacity(0.75)
                    .foregroundColor(.white)
                    .offset(x: 147.06, y: 18.24) // Above button
                    .allowsHitTesting(false)
                
                Text("⏮")
                    .font(Font.custom("Roboto", size: 17))
                    .lineSpacing(20)
                    .opacity(0.75)
                    .foregroundColor(.white)
                    .offset(x: 204.69, y: 18.24) // Above button
                    .allowsHitTesting(false)
                
                Text("⏭")
                    .font(Font.custom("Roboto", size: 17))
                    .lineSpacing(20)
                    .opacity(0.75)
                    .foregroundColor(.white)
                    .offset(x: 246.17, y: 18.24) // Above button
                    .allowsHitTesting(false)
            }
            
            // EJECT Button - Empty, no symbols
            Button(action: {
                soundPlayer.play(named: "EjectSound_1")
                if isPoweredOn { ejectAction() }
            }) {
                Color.clear
            }
            .realistic3DSquareButton(size: 41.48)
            .offset(x: -25.85, y: 50.63)
            
            // PLAY Button - with programmatic press state
            Button(action: {
                soundPlayer.play(named: "PlaySound_1")
                if isPoweredOn { playAction() }
            }) {
                Color.clear
            }
            .buttonStyle(ProgrammaticPressButtonStyle(
                isExternallyPressed: isPlayPressed,
                width: 73.80,
                height: 41.48,
                isSquare: false
            ))
            .offset(x: 31.78, y: 50.63)
            
            // STOP Button - Empty, no symbols
            Button(action: {
                soundPlayer.play(named: "StopSound_1")
                if isPoweredOn { stopAction() }
            }) {
                Color.clear
            }
            .realistic3DSquareButton(size: 41.48)
            .offset(x: 89.42, y: 50.63)
            
            // PAUSE Button - with programmatic press state
            Button(action: {
                soundPlayer.play(named: "PauseSound_1")
                if isPoweredOn { pauseAction() }
            }) {
                Color.clear
            }
            .buttonStyle(ProgrammaticPressButtonStyle(
                isExternallyPressed: isPausePressed,
                width: 73.80,
                height: 41.48,
                isSquare: false
            ))
            .offset(x: 147.06, y: 50.63)
            
            // PREVIOUS Button - with programmatic press state
            Button(action: {
                soundPlayer.play(named: "PrevSound_1")
                if isPoweredOn { previousAction() }
            }) {
                Color.clear
            }
            .buttonStyle(ProgrammaticPressButtonStyle(
                isExternallyPressed: isPreviousPressed,
                size: 41.48,
                isSquare: true
            ))
            .offset(x: 204.69, y: 50.63)
            
            // NEXT Button - with programmatic press state
            Button(action: {
                soundPlayer.play(named: "NextSound_1")
                if isPoweredOn { nextAction() }
            }) {
                Color.clear
            }
            .buttonStyle(ProgrammaticPressButtonStyle(
                isExternallyPressed: isNextPressed,
                size: 41.48,
                isSquare: true
            ))
            .offset(x: 246.17, y: 50.63)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MetaWav.Transport.PlayPressedAnimation"))) { _ in
            isPlayPressed = true
            soundPlayer.play(named: "PlaySound_1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isPlayPressed = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MetaWav.Transport.PausePressedAnimation"))) { _ in
            isPausePressed = true
            soundPlayer.play(named: "PauseSound_1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isPausePressed = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MetaWav.Transport.NextPressedAnimation"))) { _ in
            isNextPressed = true
            soundPlayer.play(named: "NextSound_1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isNextPressed = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MetaWav.Transport.PreviousPressedAnimation"))) { _ in
            isPreviousPressed = true
            soundPlayer.play(named: "PrevSound_1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isPreviousPressed = false
            }
        }
        .onChange(of: audioProcessor.currentTime) { _, newTime in
            currentTime = newTime
            // Keep Now Playing elapsed time in sync for Control Center
            nowPlayingManager.updateElapsedTime(newTime)
        }
        .onAppear {
            // AppDelegate wires MPRemoteCommandCenter globally; avoid re-registering here
        }
        .onDisappear {
            // Do not clear global Now Playing handlers to keep media keys working in background
        }
    }
    
    // Note: Global Now Playing handlers are established in AppDelegate for reliability.
    
    // MARK: - Transport Actions
    
    private func playAction() {
        print("🎯 PLAY button pressed - Diagnostics:")
        print("   isPoweredOn: \(isPoweredOn)")
        print("   queueManager.queueCount: \(queueManager.queueCount)")
        print("   queueManager.currentIndex: \(queueManager.currentIndex?.description ?? "nil")")
        print("   audioProcessor.duration: \(audioProcessor.duration)")
        print("   audioProcessor.isPlaying: \(audioProcessor.isPlaying)")
        
        guard !queueManager.isQueueEmpty else {
            showError(message: "No tracks in queue")
            return
        }
        
        if audioProcessor.isPlaying {
            print("   Already playing - no action needed")
            return
        }
        
        if audioProcessor.duration > 0 && queueManager.currentIndex != nil {
            print("   Resuming existing track")
            audioProcessor.play()
            
            // Optimize for playback
            performanceOptimizer.optimizeForPlayback()
            
            // Update Now Playing state for resume
            nowPlayingManager.setPlaybackState(isPlaying: true)
            return
        }
        
        // Use queue manager to play current track
        queueManager.playCurrentTrack()
        
        // Optimize for playback
        performanceOptimizer.optimizeForPlayback()
        
        // Update Now Playing info
        updateNowPlayingInfoFromQueue()
    }
    
    // NEW: Smart play/pause toggle for F8
    private func playPauseToggleAction() {
        print("⏯️ F8 PLAY/PAUSE TOGGLE pressed")
        print("   audioProcessor.isPlaying: \(audioProcessor.isPlaying)")
        print("   audioProcessor.duration: \(audioProcessor.duration)")
        
        // Play the appropriate sound effect
        if audioProcessor.isPlaying {
            soundPlayer.play(named: "PauseSound")
        } else {
            soundPlayer.play(named: "PlaySound")
        }
        
        // Use queue manager's toggle functionality
        queueManager.togglePlayPause()
        
        // Update Now Playing info
        updateNowPlayingInfoFromQueue()
    }
    
    private func playFile(at index: Int) {
        print("🎵 playFile called with index: \(index)")
        print("   audioFiles.count: \(audioFiles.count)")
        
        guard index >= 0 && index < audioFiles.count else {
            showError(message: "Track index \(index) out of range (0-\(audioFiles.count-1))")
            return
        }
        
        let file = audioFiles[index]
        print("   File: \(file.url.lastPathComponent)")
        print("   Full path: \(file.url.path)")
        
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            showError(message: "Audio file no longer exists: \(file.url.lastPathComponent)")
            return
        }
        
        guard file.url.startAccessingSecurityScopedResource() else {
            showError(message: "Cannot access audio file: permission denied")
            return
        }
        defer { file.url.stopAccessingSecurityScopedResource() }
        
        print("   Loading file into AudioProcessor (pre-opened AVAudioFile)...")
        audioProcessor.load(file: file)
        
        print("   AudioProcessor loaded - duration: \(audioProcessor.duration)")
        
        guard audioProcessor.duration > 0 else {
            showError(message: "Failed to load track: \(file.url.lastPathComponent)")
            return
        }
        
        audioProcessor.play()
        currentFileIndex = index
        
        // Optimize for playback
        performanceOptimizer.optimizeForPlayback()
        
        // Update Now Playing info to claim media key control
        updateNowPlayingInfo(for: file, at: index)
        
        print("✅ Successfully started playback:")
        print("   Track: \(file.url.lastPathComponent)")
        print("   Index: \(index)")
        print("   Duration: \(audioProcessor.duration)s")
    }
    
    private func pauseAction() {
        print("⏸ PAUSE button pressed")
        audioProcessor.pause()
        
        // Optimize for editing when paused
        performanceOptimizer.optimizeForEditing()
        
        // Update Now Playing state
        nowPlayingManager.setPlaybackState(isPlaying: false)
    }
    
    private func stopAction() {
        print("⏹ STOP button pressed")
        audioProcessor.stop()
        currentTime = 0
        
        // Restore default optimizations when stopped
        performanceOptimizer.restoreDefaultOptimizations()
        
        // Clear Now Playing info when stopped
        nowPlayingManager.clearNowPlayingInfo()
    }
    
    private func ejectAction() {
        print("⏏️ EJECT button pressed - initiating save and cleanup")
        // Flush any pending edits before eject
        NotificationManager.shared.postNotification(.saveRequested, object: nil)
        // Give UI tasks a moment to persist before teardown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        
            // Use the clean eject method from QueueManager
            queueManager.handleEject()
        
            // Perform additional cleanup for UI state
            audioProcessor.fullCleanup()
            audioFiles.removeAll()
            currentFileIndex = nil
            currentTime = 0
            currentAlbum = nil
            selectedTrack = nil
            audioPlayer = nil
        
            // Clear Now Playing info when ejected
            nowPlayingManager.clearNowPlayingInfo()
        
            MenuBarManager.shared.updateSelectedTrack(nil)
            MenuBarManager.shared.updateCurrentAlbum(nil)
            MenuBarManager.shared.updateCurrentTrack(nil)
        
            print("⏏️ FULL EJECT COMPLETED:")
            print("   Queue cleared: \(queueManager.queueCount) tracks")
            print("   audioFiles cleared: \(audioFiles.count) files")
            print("   currentFileIndex: \(currentFileIndex?.description ?? "nil")")
            print("   selectedTrack: \(selectedTrack?.name ?? "nil")")
            print("   audioProcessor cleaned up")
        }
    }

    private func nextAction() {
        print("⏭️ NEXT button pressed")
        // Flush any pending edits before changing track
        NotificationManager.shared.postNotification(.saveRequested, object: nil)
        print("   Current queue.count: \(queueManager.queueCount)")
        print("   Current currentIndex: \(queueManager.currentIndex?.description ?? "nil")")
        
        guard !queueManager.isQueueEmpty else {
            print("   No tracks in queue")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            // Apply a very short fade-out before advancing to the next track
            self.audioProcessor.fadeOutThen {
                self.queueManager.nextTrack()
                self.updateNowPlayingInfoFromQueue()
            }
        }
    }
    
    private func previousAction() {
        print("⏮️ PREVIOUS button pressed")
        // Flush any pending edits before changing track
        NotificationManager.shared.postNotification(.saveRequested, object: nil)
        print("   Current queue.count: \(queueManager.queueCount)")
        print("   Current currentIndex: \(queueManager.currentIndex?.description ?? "nil")")
        
        guard !queueManager.isQueueEmpty else {
            print("   No tracks in queue")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            // Apply a very short fade-out before going to the previous track
            self.audioProcessor.fadeOutThen {
                self.queueManager.previousTrack()
                self.updateNowPlayingInfoFromQueue()
            }
        }
    }
    
    private func playNextTrackIfAvailable() {
        print("🔄 Auto-advancing to next track")
        // This is now handled by QueueManager's handleTrackFinished method
        // No need to implement here as the queue manager handles track completion
    }
    
    // MARK: - Now Playing Info Updates
    
    private func updateNowPlayingInfoFromQueue() {
        guard let currentItem = queueManager.currentItem else {
            nowPlayingManager.clearNowPlayingInfo()
            return
        }
        
        // Create artwork if available
        var artwork: MPMediaItemArtwork?
        if let album = currentItem.album, let frontArtPath = album.frontArtPath {
            artwork = nowPlayingManager.createArtwork(from: frontArtPath)
        }
        
        // Update Now Playing with full metadata
        nowPlayingManager.updateNowPlayingInfo(
            title: currentItem.displayName,
            artist: currentItem.artistName,
            album: currentItem.album?.albumName,
            duration: audioProcessor.duration,
            currentTime: audioProcessor.currentTime,
            playbackRate: audioProcessor.isPlaying ? 1.0 : 0.0,
            artwork: artwork
        )
        
        print("📻 Now Playing: \(currentItem.displayName) - \(currentItem.artistName)")
    }
    
    private func updateNowPlayingInfo(for file: AVAudioFile, at index: Int) {
        // Legacy method - now redirects to queue-based method
        updateNowPlayingInfoFromQueue()
    }
    
    private func showError(message: String) {
        errorMessage = message
        showErrorAlert = true
        print("❌ Transport Error: \(message)")
    }
}
