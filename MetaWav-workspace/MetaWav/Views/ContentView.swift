// ContentView.swift - UPDATED: Added Album Type Support in LoadFiles
import SwiftUI
import AVFoundation
import AppKit
import Foundation
import Combine
import Darwin

// MARK: - Aspect Ratio Constants
struct PanelAspectRatios {
    // CD Panel (transport, timecode, power) - based on your fixed dimensions
    static let cdPanelRatio: CGFloat = 1024.0 / 286.39  // width / height = ~3.576
    static let cdPanelBaseWidth: CGFloat = 1024.0
    static let cdPanelBaseHeight: CGFloat = 286.39
    
    // Bottom Panel (tracklist, art, metadata) - based on your fixed dimensions
    static let bottomPanelRatio: CGFloat = 1024.0 / 440.0  // width / height = ~2.327
    static let bottomPanelBaseWidth: CGFloat = 1024.0
    static let bottomPanelBaseHeight: CGFloat = 440.0 // 400 content + 40 scrubber
    
    // Library Panel - no aspect ratio lock, can resize freely
    static let libraryPanelBaseWidth: CGFloat = 300.0
}

// MARK: - Main Deck Panel Modes
// Streaming and tape skins have been retired; CD is the only deck mode.
enum MainPanelMode: String {
    case cd
}

// MARK: - Aspect Ratio Locked CD Panel
struct AspectRatioLockedCDPanel: View {
    @Binding var isPoweredOn: Bool
    @Binding var activeView: BottomPanelViewType
    @Binding var isBottomPanelVisible: Bool
    @Binding var timecodePanelMode: TimecodePanelMode
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentFileIndex: Int?
    @Binding var currentTime: TimeInterval
    @Binding var currentAlbum: AlbumMetadata?
    @ObservedObject private var albumManager = AlbumMetadataManager.shared
    @Binding var menuTriggeredFileImport: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    @Binding var selectedTrack: TrackMetadata?
    @Binding var mainPanelMode: MainPanelMode
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let aspectRatio = PanelAspectRatios.cdPanelRatio
            
            // Calculate height based on width and aspect ratio
            let calculatedHeight = availableWidth / aspectRatio
            
            ZStack {
                // Background image - scales to fill the calculated dimensions
                Image("background")
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: .fill)
                    .frame(width: availableWidth, height: calculatedHeight)
                    .clipped()
                    .allowsHitTesting(false)
                
                // All CD panel content scaled proportionally
                Group {
                    // Top drag strip that acts as a title bar area for moving the window
                    TitlebarDragStrip()
                        .frame(height: 28)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .allowsHitTesting(true)
                        .offset(y: -(calculatedHeight/2) + 14)
                        .zIndex(2000)
                        
                    ExtraItems(mainPanelMode: $mainPanelMode)
                        .allowsHitTesting(false)
                    
                    Lights(
                        isPoweredOn: $isPoweredOn,
                        timecodePanelMode: $timecodePanelMode,
                        mainPanelMode: $mainPanelMode
                    )
                    .allowsHitTesting(false)
                    
                    // LoadFiles is a CD-deck affordance only
                    if mainPanelMode == .cd {
                        LoadFiles(
                            audioFiles: $audioFiles,
                            isPoweredOn: $isPoweredOn,
                            currentAlbum: $currentAlbum,
                            currentFileIndex: $currentFileIndex,
                            currentTime: $currentTime,
                            menuTriggeredImport: $menuTriggeredFileImport
                        )
                    }
                    
                    PowerButton(
                        isPoweredOn: $isPoweredOn,
                        audioFiles: $audioFiles,
                        currentFileIndex: $currentFileIndex,
                        currentTime: $currentTime,
                        audioPlayer: $audioPlayer,
                        selectedTrack: $selectedTrack,
                        mainPanelMode: $mainPanelMode
                    )
                    
                    // Timecode pane is part of the CD deck; hide for streaming face
                    if mainPanelMode == .cd {
                        TimecodePane(
                            currentFileIndex: $currentFileIndex,
                            audioFiles: $audioFiles,
                            isPoweredOn: $isPoweredOn,
                            currentAlbum: $currentAlbum,
                            timecodePanelMode: $timecodePanelMode
                        )
                        // Allow interaction only for ADVANCED mode so the in-panel scrubber can seek.
                        .allowsHitTesting(isPoweredOn && timecodePanelMode == .advanced && AudioProcessor.shared.duration > 0)
                    }
                    
                    // Classic CD transport only in CD mode; Streaming mode uses inline unicode controls
                    if mainPanelMode == .cd {
                        TransportControls(
                            audioFiles: $audioFiles,
                            currentFileIndex: $currentFileIndex,
                            currentTime: $currentTime,
                            isPoweredOn: $isPoweredOn,
                            audioPlayer: $audioPlayer,
                            selectedTrack: $selectedTrack
                        )
                        .disabled(!isPoweredOn)
                    }
                    
                    AdditionalControls(
                        activeView: $activeView,
                        isBottomPanelVisible: $isBottomPanelVisible,
                        mainPanelMode: $mainPanelMode,
                        isPoweredOn: $isPoweredOn,
                        timecodePanelMode: $timecodePanelMode
                    )
                    .zIndex(1000)
                }
                .scaleEffect(
                    // Scale all content proportionally based on size difference from base
                    min(availableWidth / PanelAspectRatios.cdPanelBaseWidth,
                        calculatedHeight / PanelAspectRatios.cdPanelBaseHeight)
                )
            }
            .frame(width: availableWidth, height: calculatedHeight)
        }
        .aspectRatio(PanelAspectRatios.cdPanelRatio, contentMode: .fit)
    }
}

// MARK: - Main Content View Broken Into Smaller Components
// MARK: - Updated ContentView with Simplified Layout
struct ContentView: View {
    @State private var isPoweredOn = false
    @State private var audioFiles: [AVAudioFile] = []
    @State private var currentFileIndex: Int?
    @State private var currentTime: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var activeView: BottomPanelViewType = .metadata
    @State private var mainPanelMode: MainPanelMode = .cd
    @State private var timecodePanelMode: TimecodePanelMode = .standard

    
    @State private var currentAlbum: AlbumMetadata? = nil
    @ObservedObject private var albumManager = AlbumMetadataManager.shared
    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    
    @State private var isEditing = false
    @State private var selectedTrack: TrackMetadata? = nil
    
    
    @State private var isDragging: Bool = false
    @State private var leftColumnWidth: CGFloat = 700 // Initial width for left column
    
    @State private var isBottomPanelVisible = true {
        didSet {
                            NotificationManager.shared.log("isBottomPanelVisible changed to: \(isBottomPanelVisible)")
            WindowManager.shared.togglePanels(visible: isBottomPanelVisible)
        }
    }
    
    @State private var menuTriggeredFileImport = false
    
    // Playlist system integration
    @StateObject private var playlistManager = PlaylistManager.shared
    @StateObject private var allTracksManager = AllTracksManager.shared
    @StateObject private var settingsManager = SettingsManager.shared

    var body: some View {
            GeometryReader { geometry in
                // Unified layout: keep panels in hierarchy and hide via sizing to preserve state
                HStack(spacing: 0) {
                    // Left Column (CD + Library)
                    VStack(spacing: 0) {
                        // CD Panel (top) - responsive to window width
                        AspectRatioLockedCDPanel(
                            isPoweredOn: $isPoweredOn,
                            activeView: $activeView,
                            isBottomPanelVisible: $isBottomPanelVisible,
                            timecodePanelMode: $timecodePanelMode,
                            audioFiles: $audioFiles,
                            currentFileIndex: $currentFileIndex,
                            currentTime: $currentTime,
                            currentAlbum: $currentAlbum,
                            // Album manager handles albums automatically
                            menuTriggeredFileImport: $menuTriggeredFileImport,
                            audioPlayer: $audioPlayer,
                            selectedTrack: $selectedTrack,
                            mainPanelMode: $mainPanelMode
                        )
                        // CD panel sizes itself by width/aspect ratio; keep it at the top

                        // Library Panel (bottom)
                        LibraryPanel(
                            currentAlbum: $currentAlbum,
                            audioFiles: $audioFiles,
                            currentFileIndex: $currentFileIndex,
                            currentTime: $currentTime,
                            selectedTrack: $selectedTrack,
                            isPoweredOn: $isPoweredOn,
                            audioPlayer: $audioPlayer,
                            onNavigateToArtist: { artistName in
                                                                     NotificationManager.shared.log("Artist navigation triggered: \(artistName)")
                            }
                        )
                        // Library fills remaining vertical space under the CD panel
                        .padding(.top, 0)
                        .frame(maxHeight: .infinity)
                        // Hide library when panels are not visible, but keep it alive
                        .frame(height: isBottomPanelVisible ? nil : 0)
                        .clipped()
                    }
                    // Left column is 70% when panels visible, otherwise expand to full width
                    .frame(width: geometry.size.width * (isBottomPanelVisible ? 0.7 : 1.0))
                    .frame(maxHeight: .infinity, alignment: .top)

                    // Right Column (Dynamic Panel)
                    AdditionalWindowView(
                        activeView: $activeView,
                        currentFileIndex: $currentFileIndex,
                        audioFiles: $audioFiles,
                        currentTime: $currentTime,
                        isEditing: $isEditing,
                        currentAlbum: $currentAlbum,
                        selectedTrack: $selectedTrack,
                        isPoweredOn: $isPoweredOn
                    )
                    // Width collapses to zero when hidden; view stays in hierarchy
                    .frame(width: geometry.size.width * (isBottomPanelVisible ? 0.3 : 0.0))
                    .frame(maxHeight: .infinity)
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .glassFill(.regularMaterial)
            .clipped()
            .onAppear {
                setupInitialState()
            }
            .onChange(of: isPoweredOn) { _, powered in
                // Always reset Timecode panel to STANDARD on power-on
                if powered {
                    timecodePanelMode = .standard
                }
            }
            .keyboardShortcut(".", modifiers: .command)
            .onChange(of: albumManager.lastUpdateTime) { _, _ in
                // Force UI refresh when metadata is updated
                NotificationManager.shared.log("Album manager updated, refreshing UI")
            }
            .onChange(of: audioProcessor.currentTime) { _, newTime in
                // Keep high-level currentTime in sync for all scrubbers (CD, NPS, Streaming)
                currentTime = newTime
            }

            .setupNotificationHandlers(
                currentAlbum: $currentAlbum,
                currentFileIndex: $currentFileIndex,
                selectedTrack: $selectedTrack,
                audioFiles: $audioFiles,
                menuTriggeredFileImport: $menuTriggeredFileImport,
                isBottomPanelVisible: $isBottomPanelVisible,
                playlistManager: playlistManager,
                allTracksManager: allTracksManager
            )

        }

        // Removed old createCDOnlyLayout helper; CD-only is inlined with precise height
        
        // KEEP ALL THESE METHODS (unchanged)
        private func setupInitialState() {
            // Album manager will load albums automatically
            playlistManager.loadAllPlaylists()
            allTracksManager.refreshAllTracks()
            
            // Test the new logging system
            NotificationManager.shared.log("MetaWav app initialized with new logging system")
            
            if settingsManager.powerOnByDefault && !isPoweredOn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isPoweredOn = true
                    NotificationManager.shared.log("Auto-powered on due to 'Power on by default' setting")
                }
            }
            
            // Always reset Timecode panel to STANDARD on app launch
            timecodePanelMode = .standard
        }
        
        private func updateCurrentTrackForMenu() {
            if let index = currentFileIndex,
               index < audioFiles.count,
               let album = currentAlbum {
                
                let audioFile = audioFiles[index]
                if let track = album.tracks.first(where: { $0.filePath == audioFile.url.path }) {
                    MenuBarManager.shared.updateCurrentTrack(track)
                    return
                }
            }
            MenuBarManager.shared.updateCurrentTrack(nil)
        }
        
        private func loadAllAlbums() {
            // The albumManager will automatically update the UI when it changes
                            NotificationManager.shared.log("Album manager updated, UI will refresh automatically")
        }

        
    }

    // Soft reopen reset (unused placeholder reserved for future use)
    private func performSoftReopenReset() {}

// MARK: - Streaming Deck Face (Streaming Panel Skin)
struct StreamingDeckFace: View {
    @Binding var isPoweredOn: Bool
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var currentTime: TimeInterval
    
    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    
    @State private var scrubValue: Double = 0
    @State private var scrubbing: Bool = false
    @State private var wasPlayingBeforeSeek: Bool = false
    
    private var artworkPath: String? {
        if let album = queueManager.currentItem?.album,
           let front = album.frontArtPath,
           FileManager.default.fileExists(atPath: front) {
            return front
        }
        if let album = currentAlbum,
           let front = album.frontArtPath,
           FileManager.default.fileExists(atPath: front) {
            return front
        }
        return nil
    }
    
    private var trackTitle: String {
        queueManager.currentItem?.displayName ?? "No Track"
    }
    
    private var artistName: String {
        queueManager.currentItem?.artistName ?? "Unknown Artist"
    }
    
    private var duration: TimeInterval {
        audioProcessor.duration
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, currentTime / duration))
    }
    
    private var currentTimeString: String {
        timeString(from: currentTime)
    }
    
    private var totalTimeString: String {
        timeString(from: duration)
    }
    
    var body: some View {
        ZStack {
            // Equal margin from deck edges to streaming card on all sides
            ZStack {
                // Subtle glass + embedded well, with the same soft inset as the album art
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.35)) // match original CD glass tint
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        // Thin inner bevel to give a gentle "pushed-in" edge
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.8),
                                        Color.white.opacity(0.10)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                
                // Streaming deck model badge – top-right of the black background card
                VStack {
                    HStack {
                        Spacer()
                        Text("MS-12064")
                            .font(Font.custom("Rubik Mono One", size: 9))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 8)
                            .padding(.trailing, 14)
                    }
                    Spacer()
                }
                
                // Streaming content band spans from the left edge of the CD Load Files button
                // to the right edge of the Timecode pane in base CD coordinates.
                HStack(spacing: 24) {
                    // Artwork block (left) – recessed/embedded look
                    ZStack {
                        // Dark cavity behind art
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                        
                        Group {
                            if let path = artworkPath {
                                AsyncImageLoader(
                                    imagePath: path,
                                    size: CGSize(width: 220, height: 220)
                                )
                                .frame(width: 220, height: 220)
                                .clipped()
                            } else {
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        VStack(spacing: 6) {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 32, weight: .regular))
                                                .foregroundColor(.white.opacity(0.7))
                                            Text("FORS AUDIO")
                                                .font(Font.custom("Rubik Mono One", size: 10))
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                    )
                                    .frame(width: 220, height: 220)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        // Inner bevel to suggest inset
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.9),
                                        Color.black.opacity(0.2),
                                        Color.white.opacity(0.12)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    }
                    .frame(width: 220, height: 220)
                    
                    // Info + scrubber + inline transport (right)
                    VStack(alignment: .leading, spacing: 10) {
                        // Clean text stack
                        Text(trackTitle)
                            .font(Font.custom("Roboto", size: 20).weight(.medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Text(artistName)
                            .font(Font.custom("Roboto", size: 14))
                            .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        // Scrubber + time – symmetric gaps, slider centered
                        HStack(alignment: .center, spacing: 10) {
                            Text(currentTimeString)
                                .font(Font.custom("Roboto", size: 11))
                                .foregroundColor(.white.opacity(0.8))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                            
                            Slider(
                                value: Binding(
                                    get: { scrubValue },
                                    set: { newValue in
                                        scrubValue = newValue
                                    }
                                ),
                                in: 0...1,
                                onEditingChanged: { editing in
                                    scrubbing = editing
                                    if editing {
                                        wasPlayingBeforeSeek = audioProcessor.isPlaying
                                        if wasPlayingBeforeSeek {
                                            audioProcessor.pause()
                                        }
                                    } else {
                                        let seekTime = scrubValue * duration
                                        seekToTime(seekTime)
                                        if wasPlayingBeforeSeek {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                audioProcessor.play()
                                            }
                                        }
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity)
                            
                            Text(totalTimeString)
                                .font(Font.custom("Roboto", size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .leading)
                        }
                        
                        // Inline unicode transport, centered under scrubber – always visually stable
                        HStack(spacing: 18) {
                            Button(action: {
                                guard isPoweredOn else { return }
                                NowPlayingManager.shared.onPreviousCommand?()
                            }) {
                                Text("⏮")
                                    .font(Font.custom("Roboto", size: 20))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                guard isPoweredOn else { return }
                                if audioProcessor.isPlaying {
                                    NowPlayingManager.shared.onPauseCommand?()
                                } else {
                                    NowPlayingManager.shared.onPlayCommand?()
                                }
                            }) {
                                Text(audioProcessor.isPlaying ? "⏸" : "⏵")
                                    .font(Font.custom("Roboto", size: 22).weight(.medium))
                                    .foregroundColor(.white.opacity(1.0))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                guard isPoweredOn else { return }
                                NowPlayingManager.shared.onNextCommand?()
                            }) {
                                Text("⏭")
                                    .font(Font.custom("Roboto", size: 20))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.trailing, 16)
                }
                // Exact horizontal band between LoadFiles left edge and Timecode right edge:
                // LoadFiles: center -242.13, width 308.12 → left -396.19
                // Timecode: center 110.16, width 313.50 → right 266.91
                // Band width = 663.10, band center = -64.64 in CD base coordinates.
                .frame(width: 663.10)
                .offset(x: -64.64)
                .padding(.vertical, 20)
            }
            .padding(20) // equal inset from deck edges on all sides
        }
        .onChange(of: currentTime) { _, newTime in
            updateScrubFromTime(newTime)
        }
        // Fixed base size matching CD panel; whole deck is scaled like CD skin.
        .frame(width: PanelAspectRatios.cdPanelBaseWidth,
               height: PanelAspectRatios.cdPanelBaseHeight)
    }
    
    // Keep scrubber in sync with playback when not actively scrubbing
    private func updateScrubFromTime(_ time: TimeInterval) {
        guard !scrubbing, duration > 0 else { return }
        scrubValue = max(0, min(1, time / duration))
    }
    
    private func timeString(from time: TimeInterval) -> String {
        guard time.isFinite && time > 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func seekToTime(_ time: TimeInterval) {
        audioProcessor.seek(to: time)
        currentTime = time
    }
}

// MARK: - Tape Deck Face (Tape Panel Skin)
struct TapeDeckFace: View {
    @Binding var isPoweredOn: Bool
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var currentTime: TimeInterval
    
    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    
    @State private var leftVuLevel: CGFloat = 0.0
    @State private var rightVuLevel: CGFloat = 0.0
    @State private var reelAngle: Double = 0.0
    @State private var cassetteBaseColor: Color = Color(red: 0.86, green: 0.87, blue: 0.90)
    @State private var reelTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    @State private var tapeCounterValue: Int = 0
    @State private var tapeCounterOffset: Double = 0.0
    
    // Shuttle / scrubbing state for tape-style fast forward / rewind
    @State private var isRewinding: Bool = false
    @State private var isFastForwarding: Bool = false
    @State private var wasPlayingBeforeShuttle: Bool = false
    
    private var trackTitle: String {
        queueManager.currentItem?.displayName ?? "No Track"
    }
    
    private var artistName: String {
        queueManager.currentItem?.artistName ?? "Unknown Artist"
    }
    
    /// Text that appears "scribbled" on the cassette shell – always album-focused.
    private var cassetteAlbumTitle: String {
        if let name = queueManager.currentItem?.album?.albumName, !name.isEmpty {
            return name
        }
        if let name = currentAlbum?.albumName, !name.isEmpty {
            return name
        }
        return "UNTITLED MIX"
    }
    
    /// Whether a cassette is currently "loaded" in the deck (used to swap to an empty-well look).
    private var hasCassetteLoaded: Bool {
        isPoweredOn && queueManager.currentItem != nil
    }
    
    /// Normalized tape position across the entire queue (0.0 - 1.0).
    private var normalizedTapePosition: Double {
        guard
            let currentIndex = queueManager.currentIndex,
            !queueManager.queue.isEmpty
        else { return 0.0 }
        
        // Total duration of the current "tape" (entire queue)
        let totalDuration = queueManager.queue.reduce(0.0) { partial, item in
            partial + item.duration
        }
        guard totalDuration > 0 else { return 0.0 }
        
        // Sum duration of all items before the current one
        let elapsedBeforeCurrent = queueManager.queue.prefix(currentIndex).reduce(0.0) { partial, item in
            partial + item.duration
        }
        
        // Use AudioProcessor current time within the current track
        let currentWithinTrack = min(max(audioProcessor.currentTime, 0), audioProcessor.duration)
        let tapeElapsed = elapsedBeforeCurrent + currentWithinTrack
        
        return min(max(tapeElapsed / totalDuration, 0.0), 1.0)
    }
    
    var body: some View {
        // Transport geometry: keep controls perfectly tiled under the cassette.
        let cassetteWidth: CGFloat = 308.12
        let transportButtonWidth: CGFloat = cassetteWidth / 6.0
        let transportButtonHeight: CGFloat = 41.48 * (2.0 / 3.0) // 2/3 of original square height
        
        // Align the right edge of the VU cluster to mirror the left margin of the power button,
        // so the visual distance from each edge of the deck to its nearest control is symmetric.
        let vuClusterCenterX: CGFloat = 310.0
        
        // Counter placement: left-aligned with TD-12064 model text (fine-tuned horizontally),
        // and top-aligned with the cassette window's top edge.
        let counterOffsetX: CGFloat = 10.0
        // Cassette window center Y is -5.53 with height 150 → top at -80.53.
        // Counter frame height is 20, so center it 10 pts below the top edge to align top borders.
        let counterOffsetY: CGFloat = -70.53
        
        return ZStack {
            // Cassette well, VUs, and controls laid out directly on the CD background
            ZStack {
                // Cassette well: metal bezel + glass window with animated reels
                // Vertically aligned so its top edge matches the power LED top edge on the front panel.
                cassetteWindow
                    .frame(width: 308.12, height: 150) // roughly 2x LoadFiles height
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .offset(x: -242.13, y: -5.53) // same horizontal center as LoadFiles, nudged up to align with power LED
                
                // Mechanical cassette counter (tape position index)
                CassetteCounterView(
                    value: tapeCounterValue,
                    isEnabled: hasCassetteLoaded,
                    onReset: {
                        guard hasCassetteLoaded else { return }
                        // Define current normalized position as new zero; do not persist across power cycles.
                        tapeCounterOffset = normalizedTapePosition
                        tapeCounterValue = 0
                    }
                )
                .offset(x: counterOffsetX, y: counterOffsetY)
                
                // Tape transport controls – 6 CD-style buttons tiled exactly across the cassette width
                HStack(spacing: 0) {
                    // Rewind
                    Button(action: {
                        // Primary rewind behavior is handled by press-and-hold gesture for tape-style scrubbing.
                    }) {
                        Text("⏮")
                            .font(Font.custom("Roboto", size: 15))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(Realistic3DSquareButtonStyle(width: transportButtonWidth,
                                                              height: transportButtonHeight))
                    .onLongPressGesture(minimumDuration: 0.01,
                                        maximumDistance: 50,
                                        pressing: { pressing in
                                            if pressing {
                                                beginShuttle(direction: -1)
                                            } else {
                                                endShuttle()
                                            }
                                        },
                                        perform: {})
                    
                    // Fast forward
                    Button(action: {
                        // Primary fast-forward behavior is handled by press-and-hold gesture for tape-style scrubbing.
                    }) {
                        Text("⏭")
                            .font(Font.custom("Roboto", size: 15))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(Realistic3DSquareButtonStyle(width: transportButtonWidth,
                                                              height: transportButtonHeight))
                    .onLongPressGesture(minimumDuration: 0.01,
                                        maximumDistance: 50,
                                        pressing: { pressing in
                                            if pressing {
                                                beginShuttle(direction: 1)
                                            } else {
                                                endShuttle()
                                            }
                                        },
                                        perform: {})
                    
                    // Stop
                    Button(action: {
                        guard isPoweredOn else { return }
                        NowPlayingManager.shared.onStopCommand?()
                    }) {
                        Text("⏹")
                            .font(Font.custom("Roboto", size: 15))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(Realistic3DSquareButtonStyle(width: transportButtonWidth,
                                                              height: transportButtonHeight))
                    
                    // Play
                    Button(action: {
                        guard isPoweredOn else { return }
                        NowPlayingManager.shared.onPlayCommand?()
                    }) {
                        Text("⏵")
                            .font(Font.custom("Roboto", size: 15))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(Realistic3DSquareButtonStyle(width: transportButtonWidth,
                                                              height: transportButtonHeight))
                    
                    // Pause
                    Button(action: {
                        guard isPoweredOn else { return }
                        NowPlayingManager.shared.onPauseCommand?()
                    }) {
                        Text("⏸")
                            .font(Font.custom("Roboto", size: 15))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(Realistic3DSquareButtonStyle(width: transportButtonWidth,
                                                              height: transportButtonHeight))
                    
                    // Record (visual only for now)
                    Button(action: {
                        // Reserved for future record functionality
                    }) {
                        Text("●")
                            .font(Font.custom("Roboto", size: 15))
                            .foregroundColor(Color(red: 0.78, green: 0, blue: 0))
                    }
                    .buttonStyle(Realistic3DSquareButtonStyle(width: transportButtonWidth,
                                                              height: transportButtonHeight))
                }
                .frame(width: cassetteWidth, height: transportButtonHeight, alignment: .center)
                // Tucked directly under cassette well, centered (shifted up with cassette to preserve spacing)
                .offset(x: -242.13, y: 89.47)
                
                // Dual VU meters where the timecode pane used to be
                // Right edge aligned so its margin from the deck edge matches the power button's left margin.
                HStack(spacing: 16) {
                    vuMeterView(label: "L", level: leftVuLevel)
                    vuMeterView(label: "R", level: rightVuLevel)
                }
                // Width ~316 (2×150 + 16 spacing).
                // Top of meters aligned with cassette top and power LED top edge
                // (cassette/VU top ≈ -80.53, VU height 80 → center ≈ -40.53).
                .offset(x: vuClusterCenterX, y: -40.53)
                
                // Three Distressor-style pots directly under the VUs, evenly spaced across the VU width
                HStack {
                    Spacer()
                    distressorPot(label: "INPUT")
                    Spacer()
                    distressorPot(label: "OUTPUT")
                    Spacer()
                    distressorPot(label: "MIX")
                    Spacer()
                }
                // Match the approximate combined width of the dual VU meters (2×150 + 16 spacing ≈ 316)
                .frame(width: 316)
                // Align horizontally with the VU center and tuck just beneath them (shifted up with VUs).
                // Dials moved 10 pts further down from original 49.47 → 59.47 to sit lower under the VUs.
                .offset(x: vuClusterCenterX, y: 59.47)
            }
            .padding(20)
        }
        .frame(width: PanelAspectRatios.cdPanelBaseWidth,
               height: PanelAspectRatios.cdPanelBaseHeight)
        .onAppear {
            refreshCassetteColor()
            // Reset counter when tape deck first appears
            tapeCounterOffset = 0.0
            tapeCounterValue = 0
        }
        .onChange(of: currentAlbum) { _, _ in
            refreshCassetteColor()
        }
        .onChange(of: queueManager.currentItem) { _, _ in
            // Always prefer the album art for the track that is actually playing.
            refreshCassetteColor()
            // Reset counter to start for new "tape" (album/queue)
            tapeCounterOffset = 0.0
            tapeCounterValue = 0
        }
        // Drive VU updates and transport motion from a stable UI-side timer so they
        // keep animating smoothly while audio is playing, independent of scrubber updates.
        .onReceive(reelTimer) { _ in
            updateVuLevels()
            
            // Drive reel rotation while powered on; spin faster when actually playing
            guard isPoweredOn else { return }
            let isMoving = audioProcessor.isPlaying
            let step = isMoving ? 4.0 : 0.75
            reelAngle = (reelAngle + step).truncatingRemainder(dividingBy: 360)
            
            // Tape-style shuttle when holding rewind; fast-forward uses varispeed for smooth audio
            if isRewinding, audioProcessor.duration > 0 {
                let shuttleSpeed: Double = 20.0 // seconds per second while shuttling (stronger audible effect)
                let frameDuration: Double = 1.0 / 30.0
                let delta = -shuttleSpeed * frameDuration
                let newTime = audioProcessor.currentTime + delta
                audioProcessor.seek(to: newTime)
            }
            
            // Update mechanical tape counter from normalized tape position.
            let rawPosition = normalizedTapePosition - tapeCounterOffset
            let clampedPosition = max(0.0, rawPosition)
            let newValue = Int(round(clampedPosition * 999.0))
            if newValue != tapeCounterValue {
                tapeCounterValue = newValue
            }
        }
    }
    
    /// Cassette window styled like a deck transport, with animated reels and label.
    private var cassetteWindow: some View {
        ZStack {
            // Outer metal bezel
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.22, green: 0.22, blue: 0.25),
                            Color.black.opacity(0.85)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.30),
                                    Color.black.opacity(0.95)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.6
                        )
                )
                .shadow(color: Color.black.opacity(0.85), radius: 8, x: 0, y: 4)
            
            // Inner deck cavity behind the cassette (slightly soft for depth-of-field)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .inset(by: 4)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.9),
                            Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.95)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .inset(by: 4)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.08)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: Color.black.opacity(0.7), radius: 6, x: 0, y: 2)
                .blur(radius: 0.8)
            
            // Cassette assembly: only visible when a tape is "loaded"
            if hasCassetteLoaded {
                // Actual cassette shell sitting behind the reels
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .inset(by: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                cassetteBaseColor.opacity(0.98),
                                cassetteBaseColor.opacity(0.80)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.black.opacity(0.25), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
                    .opacity(isPoweredOn ? 1.0 : 0.8)
                
                // Write-protect notches along the top edge of the cassette shell
                HStack(spacing: 160) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 18, height: 8)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 18, height: 8)
                }
                .offset(y: -32)
                
                // Cassette shell screws in the four corners
                Group {
                    cassetteScrew(offsetX: -118, offsetY: -30)
                    cassetteScrew(offsetX: 118, offsetY: -30)
                    cassetteScrew(offsetX: -118, offsetY: 30)
                    cassetteScrew(offsetX: 118, offsetY: 30)
                }
                
                // Colored cassette accent stripe (gives the shell a personality)
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                cassetteBaseColor.opacity(0.95),
                                cassetteBaseColor.opacity(0.75)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 20)
                    .cornerRadius(3)
                    .opacity(isPoweredOn ? 0.95 : 0.7)
                    .offset(y: -20)
                
                // Tape path across the reels (slightly translucent brown like real tape)
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.32, green: 0.20, blue: 0.08).opacity(0.98),
                                Color(red: 0.22, green: 0.14, blue: 0.06).opacity(0.9)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 10)
                    .opacity(0.9)
                    .offset(y: -10)
                    .blur(radius: 0.2)
                
                // Reels peeking through the cassette window
                HStack(spacing: 80) {
                    cassetteReel(isLeft: true)
                    cassetteReel(isLeft: false)
                }
                .offset(y: -6)
                // Slightly vignette the edges so reels feel recessed
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.55),
                            Color.clear,
                            Color.black.opacity(0.55)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blendMode(.multiply)
                    .opacity(0.45)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 2.5, x: 0, y: 1)
                
                // Hand‑scrawled album name directly on the cassette shell
                Text(cassetteAlbumTitle.uppercased())
                    .font(Font.custom("Marker Felt", size: 12))
                    .foregroundColor(Color.black.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: Color.white.opacity(0.45), radius: 1, x: 0, y: 0)
                    .rotationEffect(.degrees(-5))
                    .offset(y: 22)
            } else {
                // Empty deck look: subtle "NO CASSETTE LOADED" etched into the back wall
                Text("NO CASSETTE LOADED")
                    .font(Font.custom("Roboto", size: 9).weight(.medium))
                    .foregroundColor(Color.white.opacity(0.35))
                    .tracking(2)
                    .opacity(isPoweredOn ? 0.8 : 0.5)
                    .offset(y: -4)
            }
            
            // Head / capstan block inspired by classic TEAC / TASCAM decks
            HStack(spacing: 18) {
                // Left guide / roller (capstan) – wheel itself slowly turns with the tape
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.9),
                                    Color.black.opacity(0.4)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 6, height: 20)
                    // Rotating capstan wheel
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.95),
                                        Color.gray.opacity(0.7),
                                        Color.white.opacity(0.6)
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 6
                                )
                            )
                            .frame(width: 8, height: 8)
                        
                        // Very small seam / notch so rotation is visible but not cartoonish
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 1, height: 4)
                            .offset(y: -4)
                    }
                    // Use reelAngle directly so capstan motion tracks the reels (and
                    // gently drifts when powered but paused, like a real transport).
                    .rotationEffect(.degrees(reelAngle * 2.0))
                    .offset(x: 4)
                }
                
                // Three-head block
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.78, green: 0.79, blue: 0.82),
                                Color(red: 0.55, green: 0.56, blue: 0.60)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 52, height: 18)
                    .overlay(
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1, style: .continuous)
                                    .fill(Color.black.opacity(0.85))
                                    .frame(width: 10, height: 12)
                            }
                        }
                    )
                    .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1)
                
                // Right guide / roller (mirrored capstan)
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.9),
                                    Color.black.opacity(0.4)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 6, height: 20)
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.95),
                                        Color.gray.opacity(0.7),
                                        Color.white.opacity(0.6)
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 6
                                )
                            )
                            .frame(width: 8, height: 8)
                        
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 1, height: 4)
                            .offset(y: -4)
                    }
                    .rotationEffect(.degrees(reelAngle * 2.0))
                    .offset(x: -4)
                }
            }
            .offset(y: 16)
            
            // Global deck lighting to feel more naturally lit
            VStack(spacing: 0) {
                // Soft top light
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.04),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 46)
                
                Spacer(minLength: 0)
                
                // Subtle bottom shadow so the cassette sits into the well
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.45),
                        Color.black.opacity(0.18),
                        Color.clear
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 40)
            }
            .allowsHitTesting(false)
            
            // Front glass overlay & reflections (cassette sits clearly behind glass)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .inset(by: 3)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .inset(by: 3)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.14),
                                    Color.clear,
                                    Color.white.opacity(0.06)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                )
                .allowsHitTesting(false)
            
            // Diagonal glare band for extra "behind glass" feel
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: 150, height: 18)
                .offset(x: -40, y: -28)
                .blur(radius: 1.5)
                .blendMode(.screen)
                .opacity(isPoweredOn ? 0.9 : 0.4)
                .allowsHitTesting(false)
            
            // MWFA corner badge sitting on top of the glass
            Image("MWFA")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .shadow(color: Color.black.opacity(0.9), radius: 4, x: 0, y: 2)
                .opacity(isPoweredOn ? 0.95 : 0.6)
                .blendMode(.screen)
                .offset(x: -80, y: 44)
                .allowsHitTesting(false)
            
            // Existing capstan rollers are animated above; no extra motor wheel needed.
        }
    }
    
    /// Small recessed screw for cassette shell corners.
    private func cassetteScrew(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        Circle()
            .fill(Color.black.opacity(0.92))
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.6)
            )
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 4, height: 0.7)
            )
            .shadow(color: Color.black.opacity(0.9), radius: 1.5, x: 0, y: 0.8)
            .offset(x: offsetX, y: offsetY)
    }
    
    /// Single cassette reel with subtle metal + plastic styling.
    private func cassetteReel(isLeft: Bool) -> some View {
        let baseSize: CGFloat = 52
        
        return ZStack {
            // Outer ring
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.32),
                            Color.black.opacity(0.95)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: baseSize * 0.6
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.65),
                                    Color.black.opacity(0.9)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.1
                        )
                )
            
            // Inner plastic reel
            Circle()
                .inset(by: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.20, green: 0.20, blue: 0.24),
                            Color(red: 0.05, green: 0.05, blue: 0.06)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle()
                        .inset(by: 6)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                )
            
            // Spokes
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(Color.black.opacity(0.9))
                    .frame(width: 2.2, height: baseSize * 0.32)
                    .offset(y: -baseSize * 0.16)
                    .rotationEffect(.degrees(Double(i) * (360.0 / 5.0)))
            }
            
            // Center hub
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.9),
                            Color.gray.opacity(0.7),
                            Color.black.opacity(0.9)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: baseSize * 0.35
                    )
                )
                .frame(width: baseSize * 0.32, height: baseSize * 0.32)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.85), lineWidth: 0.6)
                )
        }
        .frame(width: baseSize, height: baseSize)
        .rotationEffect(.degrees(reelAngle * (isLeft ? 1.0 : -1.0)))
        .animation(.linear(duration: 0.02), value: reelAngle)
        .opacity(isPoweredOn ? 1.0 : 0.55)
    }
    
    // MARK: - Cassette Color from Album Art
    
    private func refreshCassetteColor() {
        // Prefer the album art for the item that is currently playing.
        if let playingAlbum = queueManager.currentItem?.album,
           let path = playingAlbum.frontArtPath,
           !path.isEmpty,
           let color = loadAverageCassetteColor(fromPath: path) {
            cassetteBaseColor = color
            return
        }
        
        // Fallback: use the bound currentAlbum if nothing is playing yet.
        if let album = currentAlbum,
           let path = album.frontArtPath,
           !path.isEmpty,
           let color = loadAverageCassetteColor(fromPath: path) {
            cassetteBaseColor = color
            return
        }
        
        // Safe default if we can't find artwork.
        cassetteBaseColor = Color(red: 0.86, green: 0.87, blue: 0.90)
    }
    
    private func loadAverageCassetteColor(fromPath path: String) -> Color? {
        guard let image = NSImage(contentsOfFile: path),
              let nsColor = averageColor(from: image) else {
            return nil
        }
        return Color(nsColor: nsColor)
    }
    
    /// Compute a quick approximate average color by downsampling to 1×1.
    private func averageColor(from image: NSImage) -> NSColor? {
        let size = NSSize(width: 1, height: 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        
        rep.size = size
        
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        
        return rep.colorAt(x: 0, y: 0)
    }
    
    // MARK: - Analog-style VU meter
    private func vuMeterView(label: String, level: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Font.custom("Roboto", size: 9).weight(.medium))
                .foregroundColor(.white.opacity(0.8))
            
            ZStack {
                let isPeaking = isPoweredOn && level > 0.9
                
                // Outer bezel for depth
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.95),
                                Color.black.opacity(0.7)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.18),
                                        Color.black.opacity(0.9)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                
                // Inner glass + backlight
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .inset(by: 3)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                // Warm backlit amber when powered, dull grey when off
                                isPoweredOn
                                ? Color(red: 0.95, green: 0.87, blue: 0.55).opacity(0.95)
                                : Color(red: 0.30, green: 0.30, blue: 0.30),
                                isPoweredOn
                                ? Color(red: 0.90, green: 0.80, blue: 0.45).opacity(0.90)
                                : Color(red: 0.18, green: 0.18, blue: 0.18)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        // Subtle inner bevel
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .inset(by: 3)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(isPoweredOn ? 0.35 : 0.15),
                                        Color.black.opacity(0.5)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: isPoweredOn
                        ? Color(red: 1.0, green: 0.9, blue: 0.6).opacity(0.20)
                        : Color.clear,
                        radius: 6,
                        x: 0,
                        y: 0
                    )
                
                GeometryReader { geo in
                    let size = geo.size
                    
                    // EXTREME: dial center pushed well below mid-height so we can dial it back later
                    let arcCenter = CGPoint(x: size.width * 0.5,
                                            y: size.height * 1.10)
                    // Needle pivot locked to bottom-center of the meter (unchanged)
                    let pivot = CGPoint(x: size.width * 0.5,
                                        y: size.height * 0.98)
                    // Very large radius so the dial is clearly "too big" inside the window
                    let radius = size.height * 0.95
                    
                    // Arc sweep from left (-20 dB) to right (+6 dB) around the arc center
                    let startAngle = -140.0   // far left
                    let endAngle   = -40.0    // far right
                    
                    // Scale range (dB) for mapping ticks and needle
                    let scaleMinDb = -20.0
                    let scaleMaxDb = 6.0      // a bit past +3 for overrun
                    let scaleSpan  = scaleMaxDb - scaleMinDb
                    
                    ZStack {
                        // Curved scale arc
                        Path { path in
                            path.addArc(
                                center: arcCenter,
                                radius: radius,
                                startAngle: Angle(degrees: startAngle),
                                endAngle: Angle(degrees: endAngle),
                                clockwise: false
                            )
                        }
                        .stroke(Color.black.opacity(0.6), lineWidth: 1)
                        
                        // Major tick marks & numeric labels (-20, -10, -5, 0, +3, +6)
                        let majorDbs: [Double] = [-20, -10, -5, 0, 3, 6]
                        ForEach(majorDbs, id: \.self) { db in
                            // Map dB value onto arc
                            let clampedDb = min(max(db, scaleMinDb), scaleMaxDb)
                            let t = (clampedDb - scaleMinDb) / scaleSpan
                            let angDeg = startAngle + t * (endAngle - startAngle)
                            let rad = CGFloat(angDeg * .pi / 180.0)
                            let outer = CGPoint(
                                x: arcCenter.x + cos(rad) * radius,
                                y: arcCenter.y + sin(rad) * radius
                            )
                            let inner = CGPoint(
                                x: arcCenter.x + cos(rad) * (radius - 8),
                                y: arcCenter.y + sin(rad) * (radius - 8)
                            )
                            
                            // Tick
                            Path { p in
                                p.move(to: inner)
                                p.addLine(to: outer)
                            }
                            .stroke(Color.black.opacity(0.8), lineWidth: db == 0 ? 1.3 : 1.0)
                            
                            // Label
                            let labelPoint = CGPoint(
                                x: arcCenter.x + cos(rad) * (radius - 16),
                                y: arcCenter.y + sin(rad) * (radius - 16)
                            )
                            let labelText: String = {
                                if db > 0 {
                                    return String(format: "+%g", db)
                                } else {
                                    return String(format: "%g", db)
                                }
                            }()
                            
                            Text(labelText)
                                .font(Font.custom("Roboto", size: 6))
                                .foregroundColor(
                                    db >= 0
                                    ? Color(red: 0.9, green: 0.2, blue: 0.15)
                                    : Color.black.opacity(0.75)
                                )
                                .position(labelPoint)
                        }
                        
                        // Minor ticks between -20 and +6
                        let minorCount = 26
                        ForEach(0...minorCount, id: \.self) { i in
                            let db = scaleMinDb + (scaleSpan / Double(minorCount)) * Double(i)
                            let clampedDb = min(max(db, scaleMinDb), scaleMaxDb)
                            let t = (clampedDb - scaleMinDb) / scaleSpan
                            let angDeg = startAngle + t * (endAngle - startAngle)
                            let rad = CGFloat(angDeg * .pi / 180.0)
                            let outer = CGPoint(
                                x: arcCenter.x + cos(rad) * radius,
                                y: arcCenter.y + sin(rad) * radius
                            )
                            let inner = CGPoint(
                                x: arcCenter.x + cos(rad) * (radius - 4),
                                y: arcCenter.y + sin(rad) * (radius - 4)
                            )
                            
                            Path { p in
                                p.move(to: inner)
                                p.addLine(to: outer)
                            }
                            .stroke(Color.black.opacity(0.55), lineWidth: 0.6)
                        }
                        
                        // "VU" legend
                        Text("VU")
                            .font(Font.custom("Roboto", size: 8).weight(.semibold))
                            .foregroundColor(Color.black.opacity(0.8))
                            // Fixed relative to meter height so it stays nicely visible above the pivot
                            .position(x: size.width * 0.5, y: size.height * 0.70)
                        
                        // Peak light (TEAC-style) at top right
                        Circle()
                            .fill(
                                isPeaking
                                ? Color(red: 0.9, green: 0.15, blue: 0.15)
                                : Color(red: 0.25, green: 0.10, blue: 0.10)
                            )
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.4),
                                                Color.black.opacity(0.7)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.7
                                    )
                            )
                            .shadow(
                                color: isPeaking
                                ? Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.6)
                                : Color.clear,
                                radius: 4,
                                x: 0,
                                y: 0
                            )
                            .position(
                                x: size.width * 0.88,
                                y: size.height * 0.20
                            )
                        
                        // Needle
                        let clamped = max(0.0, min(Double(level), 1.0))
                        // Map 0–1 into full dB range (-20…+6), then to angle
                        let dbFromLevel = scaleMinDb + clamped * scaleSpan
                        let t = (dbFromLevel - scaleMinDb) / scaleSpan
                        let needleAngle = startAngle + t * (endAngle - startAngle)
                        let needleRad = CGFloat(needleAngle * .pi / 180.0)
                        let needleLength = radius * 0.9
                        
                        // Needle drawn as a line from the bottom-center pivot up along the arc
                        Path { p in
                            p.move(to: pivot)
                            let tip = CGPoint(
                                x: pivot.x + cos(needleRad) * needleLength,
                                y: pivot.y + sin(needleRad) * needleLength
                            )
                            p.addLine(to: tip)
                        }
                        .stroke(Color(red: 0.9, green: 0.2, blue: 0.15), lineWidth: 1.4)
                        .animation(.easeOut(duration: 0.08), value: level)
                        
                        // Pivot cap drawn on top, fixed at the pivot point
                        Circle()
                            .fill(Color.black.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                            )
                            .position(pivot)
                    }
                }
                .allowsHitTesting(false)
            }
            // Bigger, analog proportion; height tuned so top aligns with cassette top via offset math above
            .frame(width: 150, height: 80)
        }
    }
    
    private func updateVuLevels() {
        guard isPoweredOn,
              let meter = UnifiedAudioEngine.shared.meter
        else {
            // When power is off or the meter is unavailable, let the needles
            // fall back toward rest like a real mechanical VU.
            let decay: CGFloat = 0.80
            leftVuLevel *= decay
            rightVuLevel *= decay
            return
        }
        
        // Map the DSP's smoothed RMS dB directly into 0–1, then let the
        // artwork's scale (‑20…+6) handle the visual calibration.
        // This keeps the math simple and guarantees motion whenever audio
        // is meaningfully above noise floor.
        var base = CGFloat(meter.normalizedLevel(minDb: -40.0, maxDb: 0.0))
        
        // Give very quiet-but-present material a little lift so the needle
        // still nudges off the peg when something is playing.
        if base > 0.02 {
            base = max(base, 0.15)
        }
        
        // Slightly de-correlate the two channels visually with small jitter.
        let jitterAmount: CGFloat = 0.06
        let jitterL = (CGFloat.random(in: -1.0...1.0)) * jitterAmount * base
        let jitterR = (CGFloat.random(in: -1.0...1.0)) * jitterAmount * base
        
        let targetL = max(0.0, min(1.0, base + jitterL))
        let targetR = max(0.0, min(1.0, base + jitterR))
        
        // UI-side smoothing that roughly mimics VU ballistics:
        // - Faster rise when signal increases (attack)
        // - Slower fall when signal drops (release)
        let attack: CGFloat = 0.30
        let release: CGFloat = 0.08
        
        func smooth(current: CGFloat, target: CGFloat) -> CGFloat {
            if target > current {
                return current + (target - current) * attack
            } else {
                return current + (target - current) * release
            }
        }
        
        leftVuLevel  = smooth(current: leftVuLevel,  target: targetL)
        rightVuLevel = smooth(current: rightVuLevel, target: targetR)
    }
    
    // MARK: - Tape-style shuttle helpers
    private func beginShuttle(direction: Int) {
        guard isPoweredOn, audioProcessor.duration > 0 else { return }
        
        // Start shuttling in the desired direction; remember original play state.
        wasPlayingBeforeShuttle = audioProcessor.isPlaying
        
        if direction < 0 {
            // Rewind: use seek-based shuttle (choppy but directionally accurate)
            isRewinding = true
            isFastForwarding = false
            // Ensure audio is audible while scrubbing
            if !audioProcessor.isPlaying {
                audioProcessor.play()
            }
        } else {
            // Fast-forward: use varispeed for smooth audible shuttle
            isRewinding = false
            isFastForwarding = true
            if !audioProcessor.isPlaying {
                audioProcessor.play()
            }
            // 4x speed feels "tape fast-forward" without going too extreme
            audioProcessor.rampPlaybackRate(to: 4.0, duration: 0.10)
        }
    }
    
    private func endShuttle() {
        guard isRewinding || isFastForwarding else { return }
        
        isRewinding = false
        isFastForwarding = false
        // Restore normal playback rate smoothly
        audioProcessor.rampPlaybackRate(to: 1.0, duration: 0.14)
        
        // Restore original play/pause state after shuttling
        if !wasPlayingBeforeShuttle {
            audioProcessor.pause()
        }
    }
    
    // Distressor-style pot / knob, styled to feel like a hardware compressor control
    private func distressorPot(label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // Outer bezel
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.95),
                                Color.black.opacity(0.75)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.18),
                                        Color.black.opacity(0.9)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.7), radius: 4, x: 0, y: 2)
                
                // Inner knob with slight metallic sheen
                Circle()
                    .inset(by: 4)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.24, green: 0.24, blue: 0.26),
                                Color.black
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 32
                        )
                    )
                    .overlay(
                        Circle()
                            .inset(by: 4)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.20),
                                        Color.black.opacity(0.8)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.white.opacity(0.05), radius: 1, x: 0, y: -1)
                
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let center = CGPoint(x: size / 2, y: size / 2)
                    let radius = size * 0.40
                    
                    ZStack {
                        // Tick marks around the knob, dense like a Distressor control
                        let tickCount = 21
                        // Arc for scale: from ~7 o'clock (bottom‑left) to ~5 o'clock (bottom‑right).
                        // Use explicit start/end angles and derive sweep so everything
                        // (ticks, labels, and pointer) shares the same mapping.
                        // 3 o'clock = 0°, 6 = 90°, 9 = 180°.
                        let startAngleDeg: Double = 120   // ≈ 7 o'clock on the left
                        let endAngleDeg: Double = 60      // ≈ 5 o'clock on the right
                        let sweepAngleDeg: Double = endAngleDeg - startAngleDeg  // -60°, clockwise across the bottom
                        ForEach(0..<tickCount, id: \.self) { index in
                            // Map t directly from 7 o'clock (min, left) to 5 o'clock (max, right)
                            let t = Double(index) / Double(tickCount - 1)
                            let angleDeg = startAngleDeg + t * sweepAngleDeg
                            let angleRad = CGFloat(angleDeg * .pi / 180.0) // degrees → radians
                            
                            let outer = CGPoint(
                                x: center.x + cos(angleRad) * (radius + 12),
                                y: center.y + sin(angleRad) * (radius + 12)
                            )
                            let inner = CGPoint(
                                x: center.x + cos(angleRad) * (radius + (index % 5 == 0 ? 6 : 9)),
                                y: center.y + sin(angleRad) * (radius + (index % 5 == 0 ? 6 : 9))
                            )
                            
                            Path { p in
                                p.move(to: inner)
                                p.addLine(to: outer)
                            }
                            .stroke(
                                Color.white.opacity(index % 5 == 0 ? 0.7 : 0.35),
                                lineWidth: index % 5 == 0 ? 0.9 : 0.5
                            )
                        }

                        // Numeric scale around the dial, mimicking a typical hardware pot:
                        //  - 0 at roughly 5 o'clock (full counter‑clockwise)
                        //  - 5 at 12 o'clock (straight up)
                        //  - 10 at roughly 7 o'clock (full clockwise)
                        let labelAngles: [(value: String, angleDeg: Double)] = [
                            ("0", 60),    // ≈ 5 o'clock
                            ("5", -90),   // ≈ 12 o'clock
                            ("10", 120)   // ≈ 7 o'clock
                        ]
                        ForEach(0..<labelAngles.count, id: \.self) { idx in
                            let spec = labelAngles[idx]
                            let angleRad = CGFloat(spec.angleDeg * .pi / 180.0) // degrees → radians
                            let labelRadius = radius + 16
                            let point = CGPoint(
                                x: center.x + cos(angleRad) * labelRadius,
                                y: center.y + sin(angleRad) * labelRadius
                            )

                            Text(spec.value)
                                .font(Font.custom("Roboto", size: 7))
                                .foregroundColor(Color.white.opacity(0.85))
                                .position(point)
                        }
                        
                        // Pointer line on the knob face – park it at the mid‑scale angle
                        // so it visually sits in the center of the 7→5 o'clock arc.
                        Path { p in
                            let midAngleDeg = (startAngleDeg + endAngleDeg) / 2.0  // center of arc (≈ 90° / 6 o'clock)
                            let angleRad = CGFloat(midAngleDeg * .pi / 180.0)
                            let start = CGPoint(
                                x: center.x + cos(angleRad) * (radius * 0.25),
                                y: center.y + sin(angleRad) * (radius * 0.25)
                            )
                            let end = CGPoint(
                                x: center.x + cos(angleRad) * radius,
                                y: center.y + sin(angleRad) * radius
                            )
                            p.move(to: start)
                            p.addLine(to: end)
                        }
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.95),
                                    Color(red: 0.95, green: 0.85, blue: 0.40)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        
                        // Center cap
                        Circle()
                            .fill(Color.black.opacity(0.95))
                            .frame(width: size * 0.18, height: size * 0.18)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                            )
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(6)
            }
            // Shrink knob size by 20% (original 56×56 → 44.8×44.8, rounded to 45)
            .frame(width: 45, height: 45)
            
            Text(label)
                .font(Font.custom("Roboto", size: 8).weight(.medium))
                .foregroundColor(.white.opacity(0.8))
                .textCase(.uppercase)
        }
    }
}

// MARK: - View Extension for Notification Handlers (unchanged)
extension View {
    func setupNotificationHandlers(
        currentAlbum: Binding<AlbumMetadata?>,
        currentFileIndex: Binding<Int?>,
        selectedTrack: Binding<TrackMetadata?>,
        audioFiles: Binding<[AVAudioFile]>,
        menuTriggeredFileImport: Binding<Bool>,
        isBottomPanelVisible: Binding<Bool>,
        playlistManager: PlaylistManager,
        allTracksManager: AllTracksManager
    ) -> some View {
        // Break into smaller chains to speed up type-checking
        let v1 = self
            .onChange(of: currentAlbum.wrappedValue) { _, newAlbum in
                MenuBarManager.shared.updateCurrentAlbum(newAlbum)
                allTracksManager.refreshAllTracks()
            }
            .onChange(of: selectedTrack.wrappedValue) { _, newTrack in
                MenuBarManager.shared.updateSelectedTrack(newTrack)
            }
            .onChange(of: currentFileIndex.wrappedValue) { _, newIndex in
                updateCurrentTrackForMenu(
                    currentFileIndex: newIndex,
                    audioFiles: audioFiles.wrappedValue,
                    currentAlbum: currentAlbum.wrappedValue
                )
            }

        let v2 = v1
            .onChange(of: audioFiles.wrappedValue) { _, newFiles in
                updateCurrentTrackForMenu(
                    currentFileIndex: currentFileIndex.wrappedValue,
                    audioFiles: newFiles,
                    currentAlbum: currentAlbum.wrappedValue
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuLoadFiles)) { _ in
                print("📁 Menu-triggered file load received")
                menuTriggeredFileImport.wrappedValue = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePanels)) { _ in
                print("🔄 Toggle panels notification received")
                isBottomPanelVisible.wrappedValue.toggle()
            }

        let v3 = v2
            .onReceive(NotificationCenter.default.publisher(for: .trackRepathed)) { notification in
                handleTrackRepathed(
                    notification: notification,
                    selectedTrack: selectedTrack,
                    currentAlbum: currentAlbum.wrappedValue,
                    audioFiles: audioFiles
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .albumDeleted)) { notification in
                handleAlbumDeleted(
                    notification: notification,
                    currentAlbum: currentAlbum,
                    audioFiles: audioFiles,
                    currentFileIndex: currentFileIndex,
                    selectedTrack: selectedTrack
                )
            }

        let v4 = v3
            .onReceive(NotificationCenter.default.publisher(for: .playlistCreated)) { _ in
                print("📁 Playlist created notification received")
                playlistManager.loadAllPlaylists()
            }
            .onReceive(NotificationCenter.default.publisher(for: .playlistUpdated)) { _ in
                print("📁 Playlist updated notification received")
                playlistManager.loadAllPlaylists()
            }
            .onReceive(NotificationCenter.default.publisher(for: .playlistDeleted)) { _ in
                print("🗑️ Playlist deleted notification received")
                playlistManager.loadAllPlaylists()
            }

        let v5 = v4
            .onReceive(NotificationCenter.default.publisher(for: .albumUpdated)) { notification in
                print("🔄 Album updated notification received")
                if let album = notification.object as? AlbumMetadata {
                    if currentAlbum.wrappedValue?.albumName == album.albumName {
                        currentAlbum.wrappedValue = album
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .albumArtChanged)) { notification in
                print("🎨 Album art changed notification received")
                if let album = notification.object as? AlbumMetadata {
                    if currentAlbum.wrappedValue?.albumName == album.albumName {
                        currentAlbum.wrappedValue = album
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackMetadataChanged)) { notification in
                print("🎵 Track metadata changed notification received")
                if let (_, album) = notification.object as? (TrackMetadata, AlbumMetadata) {
                    if currentAlbum.wrappedValue?.albumName == album.albumName {
                        print("   Skipping disk reload for \(album.albumName) - using saved data")
                    }
                } else if let (_, albumName) = notification.object as? (TrackMetadata, String) {
                    // Backward compatibility
                    if currentAlbum.wrappedValue?.albumName == albumName {
                        print("   Skipping disk reload for \(albumName) - using saved data")
                    }
                }
            }

        return v5
    }
}

// MARK: - Helper Functions (unchanged)
@MainActor
private func updateCurrentTrackForMenu(
    currentFileIndex: Int?,
    audioFiles: [AVAudioFile],
    currentAlbum: AlbumMetadata?
) {
    if let index = currentFileIndex,
       index < audioFiles.count,
       let album = currentAlbum {
        
        let audioFile = audioFiles[index]
        if let track = album.tracks.first(where: { $0.filePath == audioFile.url.path }) {
            MenuBarManager.shared.updateCurrentTrack(track)
            return
        }
    }
    MenuBarManager.shared.updateCurrentTrack(nil)
}

private func loadAllAlbums(allAlbums: Binding<[AlbumMetadata]>) {
    allAlbums.wrappedValue = AlbumMetadataManager.shared.loadAllAlbums()
    print("📚 Loaded \(allAlbums.wrappedValue.count) albums")
}

private func handleTrackRepathed(
    notification: Notification,
    selectedTrack: Binding<TrackMetadata?>,
    currentAlbum: AlbumMetadata?,
    audioFiles: Binding<[AVAudioFile]>
) {
    print("🔗 Track repathed notification received")
    if let repathedTrack = notification.object as? TrackMetadata {
        // Update the current track if it matches the repathed track
        if selectedTrack.wrappedValue?.id == repathedTrack.id {
            selectedTrack.wrappedValue = repathedTrack
        }
        
        // Refresh the audio files if needed
        if let currentAlbum = currentAlbum,
           let trackIndex = currentAlbum.tracks.firstIndex(where: { $0.id == repathedTrack.id }),
           trackIndex < audioFiles.wrappedValue.count {
            
            // Reload the audio file from the new path
            do {
                let newAudioFile = try AVAudioFile(forReading: URL(fileURLWithPath: repathedTrack.filePath))
                audioFiles.wrappedValue[trackIndex] = newAudioFile
                print("✅ Updated audio file at index \(trackIndex)")
            } catch {
                print("❌ Failed to reload audio file: \(error)")
            }
        }
    }
}

@MainActor
private func handleAlbumDeleted(
    notification: Notification,
    currentAlbum: Binding<AlbumMetadata?>,
    audioFiles: Binding<[AVAudioFile]>,
    currentFileIndex: Binding<Int?>,
    selectedTrack: Binding<TrackMetadata?>
) {
    print("🗑️ Album deleted notification received")
    if let deletedAlbumName = notification.object as? String {
        // Clear current album if it was deleted
        if currentAlbum.wrappedValue?.albumName == deletedAlbumName {
            currentAlbum.wrappedValue = nil
            audioFiles.wrappedValue.removeAll()
            currentFileIndex.wrappedValue = nil
            selectedTrack.wrappedValue = nil
            MenuBarManager.shared.updateCurrentAlbum(nil)
            MenuBarManager.shared.updateSelectedTrack(nil)
        }
        
        // Album manager will handle the album list automatically via @StateObject
    }
}

// MARK: - Updated LoadFiles for Album System with Album Type Support
struct StaticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
            .brightness(0)
    }
}

// Updated LoadFiles View with Album Type support
struct LoadFiles: View {
    @Binding var audioFiles: [AVAudioFile]
    @Binding var isPoweredOn: Bool
    @Binding var currentAlbum: AlbumMetadata?
    @ObservedObject private var albumManager = AlbumMetadataManager.shared
    @Binding var currentFileIndex: Int?
    @Binding var currentTime: TimeInterval
    @Binding var menuTriggeredImport: Bool
    
    @State private var isImporting = false
    private let soundPlayer = SoundPlayer()
    
    // ADD THIS: Reference to settings manager to check sound effects setting
    @StateObject private var settingsManager = SettingsManager.shared
    
    var body: some View {
        Button(action: {
            if isPoweredOn {
                // Only unload if nothing is playing and the queue is empty
                let ap = AudioProcessor.shared
                let qm = QueueManager.shared
                let safeToUnload = !ap.isPlaying && qm.isQueueEmpty
                if safeToUnload {
                    performCompleteUnload()
                }
                
                // FIXED: Only play sound if sound effects are enabled
                if settingsManager.enableSoundEffects {
                    soundPlayer.playSound(named: "OpenCDSound_1")
                }
                
                isImporting = true
            }
        }) {
            Text("LOAD FILES")
                .font(Font.custom("Roboto", size: 16))
                .lineSpacing(36)
                .opacity(0.80)
                .foregroundColor(Color(red: 0.96, green: 0.96, blue: 0.96))
        }
        .buttonStyle(Realistic3DLoadButtonStyle(width: 308.12, height: 71.10))
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audiovisualContent],
            allowsMultipleSelection: true
        ) { result in
            guard isPoweredOn else { return }
            
            switch result {
            case .success(let urls):
                Task {
                    await processSelectedFiles(urls)
                }
            case .failure(let error):
                print("Error selecting files: \(error.localizedDescription)")
            }
        }
        .onChange(of: menuTriggeredImport) { _, triggered in
            if triggered && isPoweredOn {
                // Only unload if nothing is playing and the queue is empty
                let ap = AudioProcessor.shared
                let qm = QueueManager.shared
                let safeToUnload = !ap.isPlaying && qm.isQueueEmpty
                if safeToUnload {
                    performCompleteUnload()
                }
                
                // FIXED: Only play sound if sound effects are enabled (for menu-triggered import too)
                if settingsManager.enableSoundEffects {
                    soundPlayer.playSound(named: "OpenCDSound_1")
                }
                
                isImporting = true
                menuTriggeredImport = false
            }
        }
        .offset(x: -242.13, y: -35.29)
    }

    private func performCompleteUnload() {
        print("🧹 COMPLETE UNLOAD before loading new files")
        AudioProcessor.shared.fullCleanup()
        currentAlbum = nil
        audioFiles.removeAll()
        currentFileIndex = nil
        currentTime = 0
        
        // CRITICAL: Clear menu state when unloading
        MenuBarManager.shared.updateCurrentAlbum(nil)
        MenuBarManager.shared.updateCurrentTrack(nil)
        MenuBarManager.shared.updateSelectedTrack(nil)
        
        print("✅ Complete unload finished - ready for new files")
    }

    // Bridge to reuse LoadFiles processing for external opens
    private func processIncomingExternalFiles(_ urls: [URL]) async {
        // If any .meta file is included, prefer treating it as a metadata album load
        let metaFiles = urls.filter { $0.pathExtension.lowercased() == "meta" }
        let audioFiles = urls.filter { ["wav","flac","mp3","aiff","aif","aac","alac","ogg","m4a","wma"].contains($0.pathExtension.lowercased()) }

        // Only unload if safe
        let ap = AudioProcessor.shared
        let qm = QueueManager.shared
        let safeToUnload = !ap.isPlaying && qm.isQueueEmpty
        if safeToUnload {
            performCompleteUnload()
        }

        if !metaFiles.isEmpty {
            // Load album metadata directly
            for metaURL in metaFiles {
                do {
                    let data = try Data(contentsOf: metaURL)
                    var album = try PropertyListDecoder().decode(AlbumMetadata.self, from: data)
                    // Ensure derived properties
                    album.updateTrackCount()
                    album.updateDiscCount()
                    try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(album)
                    DispatchQueue.main.async {
                        self.currentAlbum = album
                        // Map album tracks to audio files for immediate playback if reachable
                        var loaded: [AVAudioFile] = []
                        for track in album.tracks {
                            let url = URL(fileURLWithPath: track.filePath)
                            if let file = try? AVAudioFile(forReading: url) {
                                loaded.append(file)
                            }
                        }
                        self.audioFiles = loaded
                        self.currentFileIndex = loaded.isEmpty ? nil : 0
                        self.currentTime = 0
                        MenuBarManager.shared.updateCurrentAlbum(album)
                        MenuBarManager.shared.updateSelectedTrack(nil)
                        NotificationManager.shared.postNotification(.albumLoaded, object: album)
                    }
                } catch {
                    print("❌ Failed to load .meta: \(error)")
                }
            }
            return
        }

        if !audioFiles.isEmpty {
            await processSelectedFiles(audioFiles)
        }
    }
    private func processSelectedFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else {
            print("No files selected")
            return
        }

        var loadedAudioFiles: [AVAudioFile] = []
        var albumName: String?
        var genre: String?
        var year: String?
        var albumArtData: Data?
        var albumArtExtension: String?
        
        print("🎵 Processing \(urls.count) files...")
        
        // First pass: load audio files and extract album-level metadata
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Cannot access file: \(url.path)")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let audioFile = try AVAudioFile(forReading: url)
                loadedAudioFiles.append(audioFile)
                print("✅ Loaded audio file: \(url.lastPathComponent)")
                
                // Extract album metadata from first file only
                if albumName == nil {
                    let asset = AVURLAsset(url: url)
                    if #available(macOS 13.0, *) {
                        if let items = loadMetadataItemsSync(asset) {
                            for item in items {
                                guard let key = item.key as? String else { continue }
                                if (key.contains("Album") || key.contains("TALB")) && albumName == nil {
                                    albumName = loadStringValueSync(item) ?? nil
                                } else if (key.contains("Genre") || key.contains("TCON")) && genre == nil {
                                    genre = loadStringValueSync(item) ?? nil
                                } else if (key.contains("Date") || key.contains("TDRC")) && year == nil {
                                    year = extractYear(from: loadStringValueSync(item) ?? nil)
                                } else if key == "artwork" || key.contains("APIC") {
                                    if let data = loadDataValueSync(item) {
                                        albumArtData = data
                                        albumArtExtension = determineImageExtension(from: data)
                                        print("🎨 Found embedded album art")
                                    }
                                }
                            }
                        }
                    } else {
                        for item in asset.metadata {
                            guard let key = item.key as? String else { continue }
                            if (key.contains("Album") || key.contains("TALB")) && albumName == nil {
                                albumName = item.stringValue
                            } else if (key.contains("Genre") || key.contains("TCON")) && genre == nil {
                                genre = item.stringValue
                            } else if (key.contains("Date") || key.contains("TDRC")) && year == nil {
                                year = extractYear(from: item.stringValue)
                            } else if key == "artwork" || key.contains("APIC") {
                                if let data = item.dataValue {
                                    albumArtData = data
                                    albumArtExtension = determineImageExtension(from: data)
                                    print("🎨 Found embedded album art")
                                }
                            }
                        }
                    }
                }
            } catch {
                print("❌ Error loading file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        guard !loadedAudioFiles.isEmpty else {
            print("❌ No valid audio files loaded")
            return
        }
        
        // Second pass: Create track metadata with disc and track number extraction
        var tracks: [TrackMetadata] = []
        var tracksWithNumbers: [(audioFile: AVAudioFile, track: TrackMetadata)] = []
        var tracksWithoutNumbers: [(audioFile: AVAudioFile, track: TrackMetadata)] = []
        
        // Process tracks and extract track/disc numbers
        for audioFile in loadedAudioFiles {
            let url = audioFile.url
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let asset = AVURLAsset(url: url)
            var foundTrackNumber: Int?
            var foundDiscNumber: Int = 1 // Default to disc 1
            
            // Extract track and disc numbers from metadata
            if #available(macOS 13.0, *) {
                if let items = loadMetadataItemsSync(asset) {
                    for item in items {
                        guard let key = item.key as? String else { continue }
                        if key.contains("TRCK") || key.contains("Track") {
                            if let stringValue = loadStringValueSync(item) ?? nil {
                                let components = stringValue.components(separatedBy: "/")
                                if let number = Int(components[0]) { foundTrackNumber = number }
                            }
                        } else if key.contains("TPOS") || key.contains("Disc") {
                            if let stringValue = loadStringValueSync(item) ?? nil {
                                let components = stringValue.components(separatedBy: "/")
                                if let discNum = Int(components[0]), discNum > 0 { foundDiscNumber = discNum }
                            }
                        }
                    }
                }
            } else {
                for item in asset.metadata {
                    guard let key = item.key as? String else { continue }
                    if key.contains("TRCK") || key.contains("Track") {
                        if let stringValue = item.stringValue {
                            let components = stringValue.components(separatedBy: "/")
                            if let number = Int(components[0]) { foundTrackNumber = number }
                        }
                    } else if key.contains("TPOS") || key.contains("Disc") {
                        if let stringValue = item.stringValue {
                            let components = stringValue.components(separatedBy: "/")
                            if let discNum = Int(components[0]), discNum > 0 { foundDiscNumber = discNum }
                        }
                    }
                }
            }
            
            // Create track metadata using the updated method with disc number
            let track = AlbumMetadataManager.shared.createTrackMetadata(
                from: audioFile,
                trackNumber: foundTrackNumber ?? 1,
                discNumber: foundDiscNumber
            )
            
            if let trackNumber = foundTrackNumber {
                tracksWithNumbers.append((audioFile: audioFile, track: track))
                print("📁 Disc \(foundDiscNumber), Track \(trackNumber): \(track.name)")
            } else {
                tracksWithoutNumbers.append((audioFile: audioFile, track: track))
                print("❓ No track number found for: \(track.name) (assigned to disc \(foundDiscNumber))")
            }
        }
        
        // Sort tracks by disc first, then by track number within each disc
        tracksWithNumbers.sort { first, second in
            if first.track.discNumber != second.track.discNumber {
                return first.track.discNumber < second.track.discNumber
            }
            return first.track.trackNumber < second.track.trackNumber
        }
        
        // For tracks without numbers, assign them to continue the sequence within their disc
        // Group tracks without numbers by disc
        let tracksWithoutNumbersByDisc = Dictionary(grouping: tracksWithoutNumbers) { $0.track.discNumber }
        
        var allTrackTuples: [(audioFile: AVAudioFile, track: TrackMetadata)] = tracksWithNumbers
        
        for (discNumber, discTracksWithoutNumbers) in tracksWithoutNumbersByDisc {
            // Find the highest track number for this disc
            let maxTrackNumberInDisc = tracksWithNumbers
                .filter { $0.track.discNumber == discNumber }
                .map { $0.track.trackNumber }
                .max() ?? 0
            
            // Assign sequential track numbers to unnumbered tracks in this disc
            for (index, var trackTuple) in discTracksWithoutNumbers.enumerated() {
                trackTuple.track.trackNumber = maxTrackNumberInDisc + index + 1
                allTrackTuples.append(trackTuple)
                print("📁 Assigned Disc \(discNumber), Track \(trackTuple.track.trackNumber): \(trackTuple.track.name)")
            }
        }
        
        // Final sort of all tracks by disc then track number
        allTrackTuples.sort { first, second in
            if first.track.discNumber != second.track.discNumber {
                return first.track.discNumber < second.track.discNumber
            }
            return first.track.trackNumber < second.track.trackNumber
        }
        
        tracks = allTrackTuples.map { $0.track }
        let sortedAudioFiles = allTrackTuples.map { $0.audioFile }
        
        print("🎼 Final track order:")
        for (index, track) in tracks.enumerated() {
            print("  Disc \(track.discNumber), Track \(track.trackNumber). \(track.name) -> audioFiles[\(index)]")
        }
        
        // Create and save album with disc count and album type - UPDATED to include albumType
        let finalAlbumName = albumName ?? AlbumMetadataManager.shared.getNextUntitledAlbumName()
        
        var frontArtPath: String?
        if let artData = albumArtData, let ext = albumArtExtension {
            frontArtPath = saveEmbeddedAlbumArt(artData, fileExtension: ext, albumName: finalAlbumName)
        }
        
        // NEW: Determine album type based on track count (basic heuristic)
        let albumType = determineAlbumType(trackCount: tracks.count)
        
        // Set default values for genre and year if not found in metadata
        let defaultGenre = genre ?? "Other"
        let defaultYear = year ?? "2025"
        
        var newAlbum = AlbumMetadata(
            albumName: finalAlbumName,
            albumType: albumType, // NEW: Set detected album type
            frontArtPath: frontArtPath,
            backArtPath: nil,
            duration: nil,
            genre: defaultGenre,
            year: defaultYear,
            trackCount: tracks.count,
            discCount: 1, // Will be updated by updateDiscCount()
            discNames: nil,
            tracks: tracks
        )
        
        // Calculate derived properties including disc count
        newAlbum.calculateDuration()
        newAlbum.updateTrackCount()
        newAlbum.updateDiscCount() // NEW: Calculate actual disc count from tracks
        
        do {
            try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(newAlbum)
            // Emit targeted album art change for smart refresh
            NotificationManager.shared.postNotification(.albumArtChanged, object: newAlbum)
            
            // Update UI bindings with SORTED audio files
            DispatchQueue.main.async {
                // Only update UI bindings if nothing is playing and the queue is empty
                let ap = AudioProcessor.shared
                let qm = QueueManager.shared
                let safeToApplyBindings = !ap.isPlaying && qm.isQueueEmpty
                if safeToApplyBindings {
                    self.currentAlbum = newAlbum
                    self.audioFiles = sortedAudioFiles
                    self.currentFileIndex = 0 // Set to first track
                    self.currentTime = 0
                    
                    // CRITICAL: SYNC WITH MENU IMMEDIATELY AFTER LOADING
                    MenuBarManager.shared.updateCurrentAlbum(newAlbum)
                    MenuBarManager.shared.updateSelectedTrack(nil) // Clear selection when loading new album
                    
                    // Album manager will handle the album list automatically
                    
                    print("✅ NEW ALBUM LOADED (UI applied): \(sortedAudioFiles.count) files across \(newAlbum.discCount) disc(s)")
                    print("📋 Synced new album to menu system")
                } else {
                    // Preserve current playback and queue; album is already saved and will appear in library
                    print("✅ NEW ALBUM LOADED (library only, playback preserved): \(sortedAudioFiles.count) files across \(newAlbum.discCount) disc(s)")
                }

                // Notify library to navigate to the newly loaded album
                NotificationManager.shared.postNotification(.albumLoaded, object: newAlbum)
            }
            
            print("✅ Created album '\(finalAlbumName)' with \(tracks.count) tracks across \(newAlbum.discCount) disc(s)")
            print("🏷️ Detected album type: \(albumType ?? "Unknown")")
        } catch {
            print("❌ Failed to save album: \(error.localizedDescription)")
        }
    }
    
    // NEW: Function to determine album type based on track count and other heuristics
    private func determineAlbumType(trackCount: Int) -> String? {
        switch trackCount {
        case 1:
            return "Single"
        case 2...6:
            return "EP"
        case 7...:
            return "Album"
        default:
            return nil
        }
    }
    
    private func saveEmbeddedAlbumArt(_ data: Data, fileExtension: String, albumName: String) -> String? {
        let sanitizedName = sanitizeFilename(albumName)
        let artFilename = "\(sanitizedName)_cover.\(fileExtension)"
        
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let artDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Art")
        
        if !FileManager.default.fileExists(atPath: artDir.path) {
            do {
                try FileManager.default.createDirectory(at: artDir, withIntermediateDirectories: true)
                print("📁 Created MetaWav/Art directory")
            } catch {
                print("❌ Art directory creation failed: \(error)")
                return nil
            }
        }
        
        let artURL = artDir.appendingPathComponent(artFilename)
        
        do {
            try data.write(to: artURL)
            print("🎨 Saved embedded album art to: \(artURL.path)")
            return artURL.path
        } catch {
            print("❌ Failed to save embedded album art: \(error)")
            return nil
        }
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    private func determineImageExtension(from data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }

    private func extractYear(from dateString: String?) -> String? {
        guard let dateString = dateString else { return nil }
        if let yearRange = dateString.range(of: "\\d{4}", options: .regularExpression) {
            return String(dateString[yearRange])
        }
        return nil
    }
}

// MARK: - Updated TimecodePane
struct TimecodePane: View {
    @Binding var currentFileIndex: Int?
    @Binding var audioFiles: [AVAudioFile]
    @Binding var isPoweredOn: Bool
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var timecodePanelMode: TimecodePanelMode
    
    // Change this line:
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    @ObservedObject private var audioManager = AudioDeviceManager.shared
    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var audioEngine = UnifiedAudioEngine.shared
    
    private let activeGreen = Color(red: 0, green: 0.75, blue: 0.39)
    private let remainderGreen = Color(red: 0, green: 0.45, blue: 0.26)
    private let scrubberHeight: CGFloat = 3
    private let platePadding: CGFloat = 8
    
    @State private var hoverProgress: Double?
    @State private var lastCPUSampleWallTime: TimeInterval?
    @State private var lastCPUSampleTotalTime: TimeInterval?
    @State private var cpuPercentText: String = "--"
    @State private var memoryText: String = "--"
    @State private var diskUsageText: String = "--"
    @State private var lastDiskIOSampleWallTime: TimeInterval?
    @State private var lastDiskIOBytesRead: UInt64?
    @State private var lastDiskIOBytesWritten: UInt64?
    
    @State private var meterL: CGFloat = 0.0
    @State private var meterR: CGFloat = 0.0
    
    // Update the computed property to use QueueManager's currentItem:
    private var playingTrackInfo: (trackNumber: String, formatInfo: String)? {
        guard isPoweredOn,
              audioProcessor.duration > 0,
              let currentItem = QueueManager.shared.currentItem,
              let playingTrack = currentItem.track else { return nil }
        
        // Get effective sample rate from the current item's audio file
        let url = currentItem.audioFile.url
        let effectiveFormat = getEffectivePlaybackFormat(trackFormat: currentItem.audioFile.fileFormat, fileURL: url)
        // For lossy formats (e.g., MP3), show bitrate; for lossless/uncompressed show bit depth
        let tail: String = {
            if isLossyFromURL(url) {
                let kbps = estimatedBitrateKbps(fileURL: url, track: playingTrack)
                return kbps > 0 ? "\(kbps) kbps" : "-"
            } else {
                return effectiveFormat.bitDepth
            }
        }()
        let formatInfo = "\(effectiveFormat.sampleRate) | \(tail)"
        let trackNumber = String(format: "%02d", playingTrack.trackNumber)
        
        return (trackNumber: trackNumber, formatInfo: formatInfo)
    }
    
    private var formatInfoText: String {
        guard isPoweredOn else { return "SAMPLE RATE | BIT DEPTH" }
        return playingTrackInfo?.formatInfo ?? "Unknown | Unknown"
    }
    
    private var displayTrackNumber: String {
        guard isPoweredOn else { return "--" }
        // Prefer playlist position (from .metaplaylist) or album position (from .meta)
        if let pos = queueManager.currentItem?.playlistPosition { return String(format: "%02d", pos) }
        if let albumPos = queueManager.currentItem?.albumPosition { return String(format: "%02d", albumPos) }
        // Fallback: show current queue position
        if let idx = queueManager.currentIndex { return String(format: "%02d", idx + 1) }
        return "--"
    }

    private var selectedOutputDeviceName: String {
        guard audioManager.selectedDeviceID != 0 else { return "System Default" }
        return audioManager.outputDevices.first(where: { $0.deviceID == audioManager.selectedDeviceID })?.name ?? "Unknown Device"
    }
    
    private var currentFileType: String {
        guard let url = queueManager.currentItem?.audioFile.url else { return "--" }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "--" : ext
    }

    private var appVersionText: String {
        let short = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
        return "\(short) (\(build))"
    }

    private var appVersionShortText: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    
    private var audioChannelCountText: String {
        guard let channels = queueManager.currentItem?.audioFile.fileFormat.channelCount else { return "--" }
        return "\(channels)"
    }

    private var pluginCountText: String {
        "\(audioEngine.effectChain.count)"
    }
    
    private var nowPlayingTitle: String {
        if let name = queueManager.currentItem?.track?.name, !name.isEmpty { return name }
        if let url = queueManager.currentItem?.audioFile.url {
            return url.deletingPathExtension().lastPathComponent
        }
        return "--"
    }

    private var nowPlayingArtist: String {
        let a = queueManager.currentItem?.track?.artist
        return (a?.isEmpty == false) ? a! : "--"
    }
    
    private var nowPlayingArtistAlbum: String {
        let artist = queueManager.currentItem?.track?.artist
        let album = currentAlbum?.albumName
        switch (artist?.isEmpty == false ? artist : nil, album?.isEmpty == false ? album : nil) {
        case let (a?, b?): return "\(a) • \(b)"
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return "--"
        }
    }
    
    private var playbackProgress: Double {
        guard audioProcessor.duration > 0 else { return 0 }
        let ratio = audioProcessor.currentTime / audioProcessor.duration
        return min(max(ratio, 0), 1)
    }
    
    private func getBitDepth(from format: AVAudioFormat, fileURL: URL? = nil) -> String? {
        // Check if this is an MP3 file by examining the file URL
        // MP3 files should always be treated as 16-bit internally
        if let fileURL = fileURL,
           fileURL.pathExtension.lowercased() == "mp3" {
            return "16-bit"
        }
        
        switch format.commonFormat {
        case .pcmFormatFloat32: return "32-bit float"
        case .pcmFormatInt16: return "16-bit"
        case .pcmFormatInt32: return "32-bit"
        case .pcmFormatFloat64: return "64-bit float"
        default:
            guard let descPtr = Optional(format.streamDescription) else { return nil }
            let streamDesc = descPtr.pointee
            
            switch streamDesc.mBitsPerChannel {
            case 8: return "8-bit"
            case 16: return "16-bit"
            case 24: return "24-bit"
            case 32 where (streamDesc.mFormatFlags & kAudioFormatFlagIsFloat) != 0:
                return "32-bit float"
            case 32: return "32-bit int"
            case 64: return "64-bit"
            default: return nil
            }
        }
    }
    
    // MARK: - Effective Playback Format Logic
    
    private func getEffectivePlaybackFormat(trackFormat: AVAudioFormat, fileURL: URL? = nil) -> (sampleRate: String, bitDepth: String) {
        // Get track values
        let trackSampleRate = trackFormat.sampleRate
        let trackBitDepth = getBitDepth(from: trackFormat, fileURL: fileURL) ?? "Unknown"
        
        // Get device values (fail-safe: if no device selected, use track values)
        guard audioManager.selectedDeviceID != 0 else {
            return (sampleRate: "\(Int(trackSampleRate)) Hz", bitDepth: trackBitDepth)
        }
        
        // Parse device sample rate
        let deviceSampleRate = parseDeviceSampleRate(audioManager.currentSampleRate)
        let deviceBitDepth = audioManager.currentBitDepth
        
        // Choose the lowest values
        let effectiveSampleRate = min(trackSampleRate, deviceSampleRate)
        let effectiveBitDepth = chooseLowerBitDepth(track: trackBitDepth, device: deviceBitDepth)
        
        return (sampleRate: "\(Int(effectiveSampleRate)) Hz", bitDepth: effectiveBitDepth)
    }

    // MARK: - Lossy detection and bitrate helpers for TimecodePane
    private func isLossyFromURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["mp3", "aac", "m4a", "ogg", "opus", "wma", "amr", "mp2"].contains(ext) { return true }
        return false
    }

    private func estimatedBitrateKbps(fileURL: URL, track: TrackMetadata) -> Int {
        // Prefer stored value if present and positive
        if let kbps = track.bitrateKbps, kbps > 0 { return kbps }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        // Use AVAudioFile-derived duration to avoid deprecated AVAsset duration API
        if let audioFile = try? AVAudioFile(forReading: fileURL) {
            let seconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            if seconds > 0 {
                if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 {
                    let rawKbps = Int(round((Double(size) * 8.0) / (seconds * 1000.0)))
                    if fileURL.pathExtension.lowercased() == "mp3" {
                        return snapToStandardMP3Bitrate(rawKbps)
                    }
                    return rawKbps
                }
            }
        }
        return 0
    }

    private func snapToStandardMP3Bitrate(_ kbps: Int) -> Int {
        let standards = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        var best = standards.first ?? kbps
        var bestDiff = Int.max
        for s in standards {
            let d = abs(s - kbps)
            if d < bestDiff { bestDiff = d; best = s }
        }
        return best
    }
    
    private func parseDeviceSampleRate(_ sampleRateString: String) -> Double {
        // Parse strings like "44.1 kHz", "48.0 kHz", "96.0 kHz"
        let cleanString = sampleRateString.replacingOccurrences(of: " kHz", with: "")
        if let value = Double(cleanString) {
            return value * 1000.0 // Convert kHz to Hz
        }
        return 44100.0 // Default fallback
    }
    
    private func chooseLowerBitDepth(track: String, device: String) -> String {
        let trackBits = extractBitDepthValue(track)
        let deviceBits = extractBitDepthValue(device)
        
        // If either is unknown, return the known one, or track as fallback
        if trackBits == nil && deviceBits == nil {
            return track
        } else if trackBits == nil {
            return device
        } else if deviceBits == nil {
            return track
        }
        
        // Choose the lower bit depth
        if trackBits! <= deviceBits! {
            return track
        } else {
            return device
        }
    }
    
    private func extractBitDepthValue(_ bitDepthString: String) -> Int? {
        // Extract numeric value from strings like "16-bit", "24-bit", "32-bit float"
        let pattern = #"(\d+)-bit"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: bitDepthString, range: NSRange(bitDepthString.startIndex..., in: bitDepthString)),
           let range = Range(match.range(at: 1), in: bitDepthString) {
            return Int(String(bitDepthString[range]))
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            switch timecodePanelMode {
            case .standard:
                standardView
            case .advanced:
                advancedView
            case .audio:
                audioView
            case .device:
                deviceView
            }
        }
        .frame(width: 313.50, height: 88.88)
        .background(
            ZStack {
                // Original dark plate, now with square edges
                Rectangle()
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.12))
                // Subtle vertical bevel to keep edges visually straight (no curved illusion)
                Rectangle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.10),
                                Color.black.opacity(0.6)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
        )
        .clipped() // ensure nothing can render outside the plate border
        .offset(x: 110.16, y: -44.17)
        .onChange(of: timecodePanelMode) { _, mode in
            // Make DEVICE stats feel "live" immediately when switching into the view.
            if isPoweredOn && mode == .device {
                sampleDeviceStats()
            }
        }
    }
    
    private var standardView: some View {
        // Classic STANDARD layout (matches the old build), without the sample-rate/bit-depth line.
        ZStack {
            Text("TRACK")
                .font(Font.custom("Roboto", size: 12).weight(.bold))
                .tracking(0.50)
                .lineSpacing(20)
                .foregroundColor(isPoweredOn ? .white : Color(white: 0.7, opacity: 0.3))
                .offset(x: -103.16, y: -14.03)
            
            Text(displayTrackNumber)
                .font(Font.custom("Roboto", size: 48).weight(.medium))
                .tracking(0.50)
                .lineSpacing(20)
                .foregroundColor(isPoweredOn ? activeGreen : .clear)
                .offset(x: -42.66, y: -0.53)
            
            // Only show time if something is actually loaded and playing/paused
            Text(isPoweredOn && audioProcessor.duration > 0 ? timeString(from: audioProcessor.currentTime) : "--:--")
                .font(Font.custom("Roboto", size: 36).weight(.light))
                .tracking(0.50)
                .lineSpacing(20)
                .foregroundColor(isPoweredOn ? activeGreen : .clear)
                .offset(x: 80.84, y: -0.53)
            
            Text("TIME")
                .font(Font.custom("Roboto", size: 12).weight(.bold))
                .tracking(0.50)
                .lineSpacing(20)
                .foregroundColor(isPoweredOn ? .white : Color(white: 0.7, opacity: 0.3))
                .offset(x: 111.84, y: 29.97)
        }
    }
    
    private var advancedView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 6) // push title block down a bit (less cramped)
            
            Text(nowPlayingTitle)
                .font(Font.custom("Roboto", size: 13).weight(.bold))
                .tracking(0.2)
                .foregroundColor(isPoweredOn ? .white : Color(white: 0.7, opacity: 0.3))
                .lineLimit(1)
                .truncationMode(.tail)
            
            Text(nowPlayingArtist)
                .font(Font.custom("Roboto", size: 12).weight(.light))
                .tracking(0.2)
                .foregroundColor(isPoweredOn ? Color.white.opacity(0.88) : Color(white: 0.7, opacity: 0.3))
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer(minLength: 0)
            
            // Time labels (optional) + in-panel scrubber
            HStack {
                Text(isPoweredOn && audioProcessor.duration > 0 ? timeString(from: audioProcessor.currentTime) : "--:--")
                    .font(Font.custom("Roboto", size: 10).weight(.light))
                    .tracking(0.2)
                    .foregroundColor(isPoweredOn ? activeGreen.opacity(0.9) : Color(white: 0.7, opacity: 0.3))
                    .monospacedDigit()
                
                Spacer(minLength: 0)
                
                Text(isPoweredOn && audioProcessor.duration > 0 ? "-\(timeString(from: max(0, audioProcessor.duration - audioProcessor.currentTime)))" : "--:--")
                    .font(Font.custom("Roboto", size: 10).weight(.light))
                    .tracking(0.2)
                    .foregroundColor(isPoweredOn ? activeGreen.opacity(0.9) : Color(white: 0.7, opacity: 0.3))
                    .monospacedDigit()
            }
            
            if isPoweredOn && audioProcessor.duration > 0 {
                scrubber
                    .frame(height: 14)
            } else {
                // placeholder bar to keep layout stable when nothing is loaded
                Rectangle()
                    .fill(remainderGreen.opacity(0.35))
                    .frame(height: 3)
                    .padding(.vertical, 5.5)
            }
        }
        .padding(.horizontal, platePadding)
        .padding(.vertical, platePadding - 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var audioView: some View {
        TimelineView(.periodic(from: .now, by: 1.0/30.0)) { context in
            HStack(alignment: .top, spacing: 10) {
                // Left column: audio facts (one per line)
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatInfoText)
                        .font(Font.custom("Roboto", size: 14).weight(.light))
                        .tracking(0.35)
                        .foregroundColor(isPoweredOn ? activeGreen : Color(white: 0.7, opacity: 0.3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    Text("TYPE: \(currentFileType)")
                        .font(Font.custom("Roboto", size: 10).weight(.light))
                        .tracking(0.2)
                        .foregroundColor(isPoweredOn ? Color.white.opacity(0.85) : Color(white: 0.7, opacity: 0.3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    Text("CH: \(audioChannelCountText)")
                        .font(Font.custom("Roboto", size: 10).weight(.light))
                        .tracking(0.2)
                        .foregroundColor(isPoweredOn ? Color.white.opacity(0.85) : Color(white: 0.7, opacity: 0.3))
                        .lineLimit(1)
                    
                    Text("PLUGINS: \(pluginCountText)")
                        .font(Font.custom("Roboto", size: 10).weight(.light))
                        .tracking(0.2)
                        .foregroundColor(isPoweredOn ? Color.white.opacity(0.85) : Color(white: 0.7, opacity: 0.3))
                        .lineLimit(1)
                    
                    Text("OUT: \(selectedOutputDeviceName)")
                        .font(Font.custom("Roboto", size: 10).weight(.light))
                        .tracking(0.2)
                        .foregroundColor(isPoweredOn ? Color.white.opacity(0.85) : Color(white: 0.7, opacity: 0.3))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.7)
                }
                
                Spacer(minLength: 0)
                
                // Right column: meters
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .top, spacing: 6) {
                        digitalMeterColumn(label: "L", level: meterL)
                        digitalMeterColumn(label: "R", level: meterR)
                    }
                }
            }
            .padding(.horizontal, platePadding)
            .padding(.vertical, platePadding - 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: context.date) { _, _ in
                guard isPoweredOn, timecodePanelMode == .audio else { return }
                updateDigitalMeters()
            }
        }
    }

    private func digitalMeterColumn(label: String, level: CGFloat) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(Font.custom("Roboto", size: 10).weight(.bold))
                .tracking(0.2)
                .foregroundColor(isPoweredOn ? .white : Color(white: 0.7, opacity: 0.3))
                .frame(width: 14)
            
            digitalMeterBar(level: level)
                .frame(width: 14, height: 54)
        }
    }

    private func digitalMeterBar(level: CGFloat) -> some View {
        GeometryReader { geo in
            let segments = 12
            let h = geo.size.height
            let segH = (h - CGFloat(segments - 1) * 2.0) / CGFloat(segments)
            let lit = Int(round(min(max(level, 0), 1) * CGFloat(segments)))
            
            VStack(spacing: 2) {
                ForEach((0..<segments).reversed(), id: \.self) { idx in
                    let isLit = idx < lit
                    Rectangle()
                        .fill(meterSegmentColor(index: idx, segments: segments, isLit: isLit))
                        .frame(height: max(segH, 1))
                }
            }
        }
    }

    private func meterSegmentColor(index: Int, segments: Int, isLit: Bool) -> Color {
        // Classic meter palette: green bottom, yellow mid, red top
        let redBand = 2       // top 2 segments
        let yellowBand = 3    // next 3 segments below red
        let base: Color = {
            if index >= segments - redBand { return Color(red: 0.95, green: 0.20, blue: 0.20) }       // red
            if index >= segments - redBand - yellowBand { return Color(red: 0.95, green: 0.80, blue: 0.20) } // yellow
            return activeGreen // green
        }()

        if isPoweredOn {
            return isLit ? base : base.opacity(0.14)
        } else {
            return Color.white.opacity(0.05)
        }
    }
    
    private var deviceView: some View {
        TimelineView(.periodic(from: .now, by: 5.0)) { context in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                
                HStack(alignment: .top, spacing: 12) {
                    // Left column: live process stats
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CPU: \(cpuPercentText)")
                        Text("MEM: \(memoryText)")
                        Text("DISK: \(diskUsageText)")
                        Text("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.7)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Right column: identity / copyright
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MetaWav \(appVersionShortText)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.7)
                        Text("by Fors Audio")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Professional Audio Library")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("© 2025. All rights reserved.")
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
                .font(Font.custom("Roboto", size: 10).weight(.light))
                .tracking(0.2)
                .foregroundColor(isPoweredOn ? Color.white.opacity(0.85) : Color(white: 0.7, opacity: 0.3))
                
                Spacer(minLength: 0)
            }
            // Keep horizontal inset, but center vertically so top/bottom margins match visually.
            .padding(.horizontal, platePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onChange(of: context.date) { _, _ in
                guard isPoweredOn, timecodePanelMode == .device else { return }
                sampleDeviceStats()
            }
        }
    }
    
    private func sampleDeviceStats() {
        guard let info = currentProcessRusage() else {
            cpuPercentText = "--"
            memoryText = "--"
            diskUsageText = "--"
            return
        }

        updateCPUUsage(info: info)
        updateMemory(info: info)
        updateDiskIO(info: info)
    }

    private func currentProcessRusage() -> rusage_info_current? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, reboundPtr)
            }
        }
        return result == 0 ? info : nil
    }

    private func updateCPUUsage(info: rusage_info_current) {
        cpuPercentText = "--"

        let userSeconds = Double(info.ri_user_time) / 1_000_000_000.0
        let systemSeconds = Double(info.ri_system_time) / 1_000_000_000.0
        let totalCPUSeconds = userSeconds + systemSeconds
        let now = Date().timeIntervalSince1970

        if let lastWall = lastCPUSampleWallTime,
           let lastTotal = lastCPUSampleTotalTime {
            let dt = now - lastWall
            let dCPU = totalCPUSeconds - lastTotal
            if dt > 0, dCPU >= 0 {
                let pct = (dCPU / dt) * 100.0
                cpuPercentText = String(format: "%.0f%%", pct)
            }
        }

        lastCPUSampleWallTime = now
        lastCPUSampleTotalTime = totalCPUSeconds
    }

    private func updateMemory(info: rusage_info_current) {
        let footprint = UInt64(info.ri_phys_footprint)
        let resident = UInt64(info.ri_resident_size)
        let phys = max(ProcessInfo.processInfo.physicalMemory, 1)
        let pct = Double(footprint) / Double(phys) * 100.0
        memoryText = "\(formatBytes(footprint)) (\(Int(round(pct)))%) • RES \(formatBytes(resident))"
    }

    private func updateDiskIO(info: rusage_info_current) {
        let bytesRead = UInt64(info.ri_diskio_bytesread)
        let bytesWritten = UInt64(info.ri_diskio_byteswritten)
        let now = Date().timeIntervalSince1970

        guard
            let lastT = lastDiskIOSampleWallTime,
            let lastR = lastDiskIOBytesRead,
            let lastW = lastDiskIOBytesWritten
        else {
            lastDiskIOSampleWallTime = now
            lastDiskIOBytesRead = bytesRead
            lastDiskIOBytesWritten = bytesWritten
            diskUsageText = "R --  W --"
            return
        }

        let dt = max(now - lastT, 0.001)
        let dR = bytesRead >= lastR ? (bytesRead - lastR) : 0
        let dW = bytesWritten >= lastW ? (bytesWritten - lastW) : 0

        lastDiskIOSampleWallTime = now
        lastDiskIOBytesRead = bytesRead
        lastDiskIOBytesWritten = bytesWritten

        let rps = Double(dR) / dt
        let wps = Double(dW) / dt
        diskUsageText = "R \(formatBytesPerSecond(rps))  W \(formatBytesPerSecond(wps))"
    }

    private func updateDigitalMeters() {
        guard let meter = audioEngine.stereoMeter else {
            meterL *= 0.92
            meterR *= 0.92
            return
        }
        // CD-player LED meters: use level/RMS for stable fill (no peak marker).
        let targetL = CGFloat(meter.normalizedLevelL(minDb: -55.0, maxDb: 0.0))
        let targetR = CGFloat(meter.normalizedLevelR(minDb: -55.0, maxDb: 0.0))

        // If DSP isn't being fed, decay quickly to avoid "stuck" visuals.
        let now = Date().timeIntervalSince1970
        if now - meter.lastProcessTime > 0.5 {
            meterL *= 0.85
            meterR *= 0.85
            return
        }

        // UI-side ballistics: fast rise, slower fall (feels "responsive" without jitter)
        func smooth(current: CGFloat, target: CGFloat) -> CGFloat {
            let up: CGFloat = 0.30
            let down: CGFloat = 0.88
            let a = target > current ? up : down
            return a * current + (1 - a) * target
        }

        meterL = smooth(current: meterL, target: targetL)
        meterR = smooth(current: meterR, target: targetR)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b >= 1_073_741_824.0 { return String(format: "%.2f GB", b / 1_073_741_824.0) }
        if b >= 1_048_576.0 { return String(format: "%.0f MB", b / 1_048_576.0) }
        if b >= 1024.0 { return String(format: "%.0f KB", b / 1024.0) }
        return "\(Int(bytes)) B"
    }

    private func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond.isNaN || bytesPerSecond.isInfinite { return "--" }
        if bytesPerSecond >= 1_073_741_824.0 { return String(format: "%.2f GB/s", bytesPerSecond / 1_073_741_824.0) }
        if bytesPerSecond >= 1_048_576.0 { return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0) }
        if bytesPerSecond >= 1024.0 { return String(format: "%.0f KB/s", bytesPerSecond / 1024.0) }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    
    private func timeString(from time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var scrubber: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let playedWidth = width * CGFloat(playbackProgress)
            let hoverWidth = hoverProgress.map { width * CGFloat(min(max($0, 0), 1)) }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(remainderGreen)
                        .frame(height: scrubberHeight)
                        .opacity(isPoweredOn ? 1 : 0.25)
                    
                    Rectangle()
                        .fill(activeGreen)
                        .frame(width: playedWidth, height: scrubberHeight)
                        .opacity(isPoweredOn ? 1 : 0)
                    
                    if let hoverWidth {
                        Rectangle()
                            .fill(activeGreen.opacity(0.25))
                            .frame(width: hoverWidth, height: scrubberHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: scrubberHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && audioProcessor.duration > 0 {
                    hoverProgress = playbackProgress
                } else {
                    hoverProgress = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedX = min(max(value.location.x, 0), width)
                        hoverProgress = Double(clampedX / width)
                    }
                    .onEnded { value in
                        defer { hoverProgress = nil }
                        guard isPoweredOn, audioProcessor.duration > 0 else { return }
                        
                        let clampedX = min(max(value.location.x, 0), width)
                        let progress = Double(clampedX / width)
                        let newTime = progress * audioProcessor.duration
                        audioProcessor.seek(to: newTime)
                    }
            )
        }
        .frame(height: scrubberHeight + 8, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 1)
    }
}

class SoundPlayer {
    private var audioPlayer: AVAudioPlayer?

    func playSound(named soundName: String) {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "wav") else {
            print("Sound file not found: \(soundName)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("Playing sound: \(soundName)")
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
        }
    }
}

// MARK: - AVFoundation modern metadata sync wrappers (macOS 13+)
@available(macOS 13.0, *)
private func loadMetadataItemsSync(_ asset: AVURLAsset) -> [AVMetadataItem]? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: [AVMetadataItem]?
    Task {
        result = try? await asset.load(.metadata)
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

@available(macOS 13.0, *)
private func loadStringValueSync(_ item: AVMetadataItem) -> String? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: String?
    Task {
        result = try? await item.load(.stringValue)
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

@available(macOS 13.0, *)
private func loadDataValueSync(_ item: AVMetadataItem) -> Data? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Data?
    Task {
        result = try? await item.load(.dataValue)
        semaphore.signal()
    }
    semaphore.wait()
    return result
}
