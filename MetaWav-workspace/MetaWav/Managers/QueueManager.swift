// QueueManager.swift - Modern queue management system for MetaWav
import Foundation
import AVFoundation
import Combine
import SwiftUI
import MediaPlayer
import AppKit

// MARK: - Queue Item Model
struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    let audioFile: AVAudioFile
    let track: TrackMetadata?
    let album: AlbumMetadata?
    let addedAt: Date
    // Playlist provenance (if this item originated from a playlist)
    let playlistId: String?
    let playlistPosition: Int?
    let albumPosition: Int?
    
    init(
        audioFile: AVAudioFile,
        track: TrackMetadata? = nil,
        album: AlbumMetadata? = nil,
        playlistId: String? = nil,
        playlistPosition: Int? = nil,
        albumPosition: Int? = nil
    ) {
        self.audioFile = audioFile
        self.track = track
        self.album = album
        self.addedAt = Date()
        self.playlistId = playlistId
        self.playlistPosition = playlistPosition
        self.albumPosition = albumPosition
    }
    
    // Computed properties for easy access
    var displayName: String {
        return track?.name ?? audioFile.url.deletingPathExtension().lastPathComponent
    }
    
    var artistName: String {
        return track?.artist ?? album?.albumName ?? "Unknown Artist"
    }
    
    var duration: TimeInterval {
        return track?.duration ?? 0
    }
    
    var formattedDuration: String {
        guard duration > 0 else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Equatable conformance
    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool {
        // Compare by stable item identity so duplicate tracks (same URL) can be reordered independently
        return lhs.id == rhs.id
    }
}

// MARK: - Queue State
enum QueueState {
    case empty
    case playing
    case paused
    case stopped
}

// MARK: - Queue Manager
class QueueManager: ObservableObject {
    static let shared = QueueManager()
    
    // MARK: - Published Properties
    @Published var queue: [QueueItem] = []
    @Published var currentIndex: Int? = nil {
        didSet {
            // When the current index changes to a different item, ensure the next play counts once
            if oldValue != currentIndex {
                hasCountedCurrentTrack = false
                playEligibleAtTime = .infinity
            }
        }
    }
    @Published var currentItem: QueueItem? = nil
    @Published var state: QueueState = .empty
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .none
    
    // MARK: - Private Properties
    private var originalOrder: [QueueItem] = []
    private var cancellables = Set<AnyCancellable>()
    private let audioProcessor = AudioProcessor.shared
    
    // Track whether we've already counted the current track to avoid double-counting
    private var hasCountedCurrentTrack = false
    private var playEligibleAtTime: TimeInterval = .infinity
    
    // MARK: - Repeat Mode
    enum RepeatMode: CaseIterable {
        case none
        case one
        case all
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .one: return "One"
            case .all: return "All"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return "repeat"
            case .one: return "repeat.1"
            case .all: return "repeat"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var hasNext: Bool {
        guard let index = currentIndex else { return false }
        return index < queue.count - 1
    }
    
    // MARK: - Private Methods
    
    private func updateCurrentItem() {
        if let index = currentIndex, index < queue.count {
            currentItem = queue[index]
            // Also publish Now Playing when selection changes (even if paused)
            // so Control Center routes F7/F8/F9 to MetaWav reliably per docs.
            // MPNowPlayingInfoCenter: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
            // MPRemoteCommandCenter: https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
            let np = NowPlayingManager.shared
            let ap = audioProcessor
            var artwork: MPMediaItemArtwork?
            if let album = currentItem?.album, let artPath = album.frontArtPath {
                artwork = np.createArtwork(from: artPath)
            }
            let duration = currentItem?.duration ?? ap.duration
            np.updateNowPlayingInfo(
                title: currentItem?.displayName ?? "",
                artist: currentItem?.artistName ?? "",
                album: currentItem?.album?.albumName,
                duration: duration,
                currentTime: ap.currentTime,
                playbackRate: ap.isPlaying ? 1.0 : 0.0,
                artwork: artwork
            )
        } else {
            currentItem = nil
        }
    }
    
    var hasPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }
    
    var queueCount: Int {
        return queue.count
    }
    
    var upcomingItems: [QueueItem] {
        // If nothing is selected yet, treat the entire queue as upcoming so users can reorder
        if currentIndex == nil {
            return queue
        }
        guard let index = currentIndex, index < queue.count - 1 else { return [] }
        return Array(queue[(index + 1)...])
    }
    
    var isQueueEmpty: Bool {
        return queue.isEmpty
    }
    
    // MARK: - Initialization
    private init() {
        setupAudioProcessorBinding()
        print("🎵 QueueManager initialized")
    }
    
    // MARK: - Audio Processor Integration
    private func setupAudioProcessorBinding() {
        // Listen for track completion
        audioProcessor.onTrackFinished = { [weak self] in
            self?.handleTrackFinished()
        }
        
        // Listen for playback state changes
        audioProcessor.$isPlaying
            .sink { [weak self] isPlaying in
                DispatchQueue.main.async {
                    self?.updateState(isPlaying: isPlaying)
                    // Keep Control Center playback state in sync
                    NowPlayingManager.shared.setPlaybackState(isPlaying: isPlaying)
                }
            }
            .store(in: &cancellables)

        // Listen for current time updates to apply play-count threshold
        audioProcessor.$currentTime
            .sink { [weak self] currentTime in
                guard let self = self,
                      let index = self.currentIndex,
                      index < self.queue.count,
                      self.audioProcessor.duration > 0 else { return }
                
                // Compute threshold: fixed 5 seconds regardless of track length
                let threshold = 5.0
                self.playEligibleAtTime = threshold
                
                if !self.hasCountedCurrentTrack && currentTime >= threshold {
                    let item = self.queue[index]
                    if let track = item.track {
                        let trackId = PlayCountManager.shared.generateTrackId(from: track)
                        print("📊 Threshold met. Incrementing play count for: \(track.name) (ID: \(trackId)) at t=\(currentTime)s")
                        PlayCountManager.shared.incrementPlayCount(trackId: trackId)
                    } else {
                        let trackId = PlayCountManager.shared.generateTrackId(from: item)
                        print("📊 Threshold met. Incrementing play count for: \(item.displayName) (ID: \(trackId)) at t=\(currentTime)s")
                        PlayCountManager.shared.incrementPlayCount(trackId: trackId)
                    }
                    self.hasCountedCurrentTrack = true
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateState(isPlaying: Bool) {
        if queue.isEmpty {
            state = .empty
        } else if isPlaying {
            state = .playing
        } else {
            state = .paused
        }
    }
    
    // MARK: - Core Queue Operations
    
    /// Add a single track to the queue
    func addToQueue(_ track: TrackMetadata, from album: AlbumMetadata, playlistId: String? = nil, playlistPosition: Int? = nil) {
        guard let audioFile = createAudioFile(from: track) else {
            print("❌ Failed to create audio file for track: \(track.name)")
            return
        }
        
        let item = QueueItem(
            audioFile: audioFile,
            track: track,
            album: album,
            playlistId: playlistId,
            playlistPosition: playlistPosition,
            albumPosition: track.trackNumber
        )
        queue.append(item)
        
        print("➕ Added to queue: \(item.displayName)")
    }
    
    /// Add multiple tracks to the queue
    func addToQueue(_ tracks: [TrackMetadata], from album: AlbumMetadata, playlistId: String? = nil) {
        for (idx, track) in tracks.enumerated() {
            addToQueue(track, from: album, playlistId: playlistId, playlistPosition: (playlistId != nil ? idx + 1 : nil))
        }
    }
    
    /// Add an entire album to the queue
    func addAlbumToQueue(_ album: AlbumMetadata) {
        let sortedTracks = album.tracks.sorted { track1, track2 in
            if track1.discNumber != track2.discNumber {
                return track1.discNumber < track2.discNumber
            }
            return track1.trackNumber < track2.trackNumber
        }
        
        addToQueue(sortedTracks, from: album)
        print("📀 Added album to queue: \(album.albumName) (\(sortedTracks.count) tracks)")
    }
    
    /// Insert track at specific position
    func insertAtQueue(_ track: TrackMetadata, from album: AlbumMetadata, at index: Int) {
        guard let audioFile = createAudioFile(from: track) else {
            print("❌ Failed to create audio file for track: \(track.name)")
            return
        }
        
        let item = QueueItem(audioFile: audioFile, track: track, album: album)
        let insertIndex = min(max(index, 0), queue.count)
        queue.insert(item, at: insertIndex)
        
        // Adjust current index if needed
        if let currentIdx = currentIndex, insertIndex <= currentIdx {
            currentIndex = currentIdx + 1
        }
        
        print("➕ Inserted at queue position \(insertIndex): \(item.displayName)")
    }
    
    /// Remove item from queue
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else {
            print("❌ Invalid queue index: \(index)")
            return
        }
        
        let removedItem = queue.remove(at: index)
        
        // Adjust current index if needed
        if let currentIdx = currentIndex {
            if index < currentIdx {
                currentIndex = currentIdx - 1
            } else if index == currentIdx {
                // Current track was removed
                if queue.isEmpty {
                    currentIndex = nil
                    stopPlayback()
                } else if currentIdx >= queue.count {
                    currentIndex = queue.count - 1
                }
            }
        }
        
        print("➖ Removed from queue: \(removedItem.displayName)")
    }
    
    /// Move item in queue
    func moveQueueItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < queue.count,
              destinationIndex >= 0 && destinationIndex < queue.count,
              sourceIndex != destinationIndex else {
            print("❌ Invalid move indices: \(sourceIndex) -> \(destinationIndex)")
            return
        }
        
        let item = queue.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        queue.insert(item, at: adjustedDestination)
        
        // Adjust current index if needed
        if let currentIdx = currentIndex {
            if sourceIndex == currentIdx {
                currentIndex = adjustedDestination
            } else if sourceIndex < currentIdx && adjustedDestination >= currentIdx {
                currentIndex = currentIdx - 1
            } else if sourceIndex > currentIdx && adjustedDestination <= currentIdx {
                currentIndex = currentIdx + 1
            }
        }
        
        print("🔄 Moved queue item: \(item.displayName) from \(sourceIndex) to \(adjustedDestination)")
    }
    
    /// Clear the entire queue
    func clearQueue() {
        queue.removeAll()
        currentIndex = nil
        updateCurrentItem()
        state = .empty
        originalOrder.removeAll()
        isShuffled = false
        
        print("🗑️ Queue cleared")
    }
    
    // MARK: - Playback Operations
    
    /// Play a specific track (adds to queue if not present)
    func playTrack(_ track: TrackMetadata, from album: AlbumMetadata) {
        // Check if track is already in queue
        if let existingIndex = queue.firstIndex(where: { $0.track?.filePath == track.filePath }) {
            currentIndex = existingIndex
            hasCountedCurrentTrack = false // Reset flag for new track
            playCurrentTrack()
            return
        }
        
        // Attempt to add to queue and play
        let previousCount = queue.count
        addToQueue(track, from: album)
        guard queue.count > previousCount else {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Can't Find Track"
                alert.informativeText = "MetaWav can't find the audio file for '\(track.name)'.\n\nTry reconnecting external drives, waking network shares, or use Edit → Repath Track… to relink the file."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        currentIndex = queue.count - 1
        hasCountedCurrentTrack = false // Reset flag for new track
        updateCurrentItem()
        playCurrentTrack()
    }
    
    /// Play album from a specific track (replaces current queue)
    func playAlbumFromTrack(_ track: TrackMetadata, from album: AlbumMetadata) {
        print("🎵 QueueManager.playAlbumFromTrack called for: \(track.name)")
        print("   Album: \(album.albumName)")
        print("   Track file path: \(track.filePath)")
        
        // Clear current queue
        clearQueue()
        
        // Add entire album to queue in proper order
        addAlbumToQueue(album)
        print("   Added \(queue.count) tracks to queue")
        
        // Find the index of the clicked track in the new queue
        if let trackIndex = queue.firstIndex(where: { $0.track?.filePath == track.filePath }) {
            currentIndex = trackIndex
            hasCountedCurrentTrack = false // Reset flag for new track
            updateCurrentItem()
            print("   Found track at index: \(trackIndex)")
            playCurrentTrack()
            print("🎵 Playing album from track: \(track.name) (position \(trackIndex + 1) of \(queue.count))")
        } else {
            print("❌ Failed to find track in album queue")
            print("   Queue tracks: \(queue.map { $0.track?.filePath ?? "nil" })")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Can't Find Track"
                alert.informativeText = "The requested track couldn't be prepared for playback.\n\nSome files may be missing. Try reconnecting external drives, waking network shares, or repath tracks from the Edit menu."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    
    /// Play current track in queue
    func playCurrentTrack() {
        guard let index = currentIndex, index < queue.count else {
            print("❌ No current track to play")
            return
        }
        
        let item = queue[index]
        updateCurrentItem()
        // Use the already-open AVAudioFile from the queue to avoid extra disk I/O
        audioProcessor.load(file: item.audioFile)
        
        // Do not increment at start; threshold-based increment handled by currentTime sink
        
        audioProcessor.play()
        
        print("▶️ Playing: \(item.displayName)")
        
        // Publish Now Playing metadata when playback starts so Control Center recognizes us
        // MPNowPlayingInfoCenter: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
        // MPRemoteCommandCenter: https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
        let np = NowPlayingManager.shared
        var artwork: MPMediaItemArtwork?
        if let album = item.album, let artPath = album.frontArtPath {
            artwork = np.createArtwork(from: artPath)
        }
        np.updateNowPlayingInfo(
            title: item.displayName,
            artist: item.artistName,
            album: item.album?.albumName,
            duration: audioProcessor.duration,
            currentTime: audioProcessor.currentTime,
            playbackRate: 1.0,
            artwork: artwork
        )
    }
    
    /// Play next track
    func nextTrack() {
        guard let index = currentIndex else {
            if !queue.isEmpty {
                currentIndex = 0
                hasCountedCurrentTrack = false // Reset flag for new track
                playCurrentTrack()
            }
            return
        }
        
        if index < queue.count - 1 {
            currentIndex = index + 1
            hasCountedCurrentTrack = false // Reset flag for new track
            updateCurrentItem()
            playCurrentTrack()
        } else if repeatMode == .all {
            currentIndex = 0
            hasCountedCurrentTrack = false // Reset flag for new track
            updateCurrentItem()
            playCurrentTrack()
        } else {
            stopPlayback()
        }
    }
    
    /// Play previous track
    func previousTrack() {
        guard let index = currentIndex else {
            if !queue.isEmpty {
                currentIndex = queue.count - 1
                hasCountedCurrentTrack = false // Reset flag for new track
                playCurrentTrack()
            }
            return
        }
        
        if index > 0 {
            currentIndex = index - 1
            hasCountedCurrentTrack = false // Reset flag for new track
            updateCurrentItem()
            playCurrentTrack()
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            hasCountedCurrentTrack = false // Reset flag for new track
            updateCurrentItem()
            playCurrentTrack()
        }
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        if audioProcessor.isPlaying {
            audioProcessor.pause()
        } else if audioProcessor.duration > 0 {
            // Resume; play counting will occur via threshold listener
            audioProcessor.play()
        } else if currentIndex != nil {
            playCurrentTrack()
        }
    }
    
    /// Stop playback
    func stopPlayback() {
        audioProcessor.stop()
        state = .stopped
        print("⏹️ Playback stopped")
    }
    
    // MARK: - Shuffle Operations
    
    /// Toggle shuffle mode
    func toggleShuffle() {
        if isShuffled {
            unshuffleQueue()
        } else {
            shuffleQueue()
        }
    }
    
    /// Shuffle the queue
    func shuffleQueue() {
        guard queue.count > 1 else {
            print("❌ Cannot shuffle - insufficient tracks")
            return
        }
        
        // Store original order
        originalOrder = queue
        
        // Keep current track in place, shuffle the rest
        if let currentIdx = currentIndex {
            let currentItem = queue[currentIdx]
            var beforeCurrent = Array(queue[0..<currentIdx])
            var afterCurrent = Array(queue[(currentIdx + 1)...])
            
            beforeCurrent.shuffle()
            afterCurrent.shuffle()
            
            queue = beforeCurrent + [currentItem] + afterCurrent
            
            // Update current index to maintain current track position
            currentIndex = beforeCurrent.count
        } else {
            queue.shuffle()
        }
        
        isShuffled = true
        print("🔀 Queue shuffled")
    }
    
    /// Unshuffle the queue
    func unshuffleQueue() {
        guard !originalOrder.isEmpty else {
            print("❌ No original order to restore")
            return
        }
        
        // Find current track in original order
        if let currentIdx = currentIndex, currentIdx < queue.count {
            let currentItem = queue[currentIdx]
            if let originalIndex = originalOrder.firstIndex(of: currentItem) {
                queue = originalOrder
                currentIndex = originalIndex
            } else {
                queue = originalOrder
                currentIndex = nil
            }
        } else {
            queue = originalOrder
        }
        
        isShuffled = false
        originalOrder.removeAll()
        print("🔄 Queue unshuffled")
    }
    
    // MARK: - Repeat Operations
    
    /// Cycle through repeat modes
    func cycleRepeatMode() {
        switch repeatMode {
        case .none:
            repeatMode = .one
        case .one:
            repeatMode = .all
        case .all:
            repeatMode = .none
        }
        print("🔄 Repeat mode: \(repeatMode.displayName)")
    }
    
    // MARK: - Private Helpers
    
    private func createAudioFile(from track: TrackMetadata) -> AVAudioFile? {
        let url = URL(fileURLWithPath: track.filePath)
        
        guard FileManager.default.fileExists(atPath: track.filePath) else {
            print("❌ File does not exist: \(track.filePath)")
            return nil
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            print("❌ Cannot access file: \(track.filePath)")
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            return try AVAudioFile(forReading: url)
        } catch {
            print("❌ Failed to create audio file: \(error)")
            return nil
        }
    }
    
    private func handleTrackFinished() {
        print("🎵 handleTrackFinished called - currentIndex: \(currentIndex ?? -1), queue.count: \(queue.count)")
        
        // Play count is now incremented when track starts playing, not when it finishes
        
        switch repeatMode {
        case .one:
            // Repeat current track
            playCurrentTrack()
        case .all:
            // Go to next track (or loop to beginning)
            nextTrack()
        case .none:
            // Go to next track or stop
            nextTrack()
        }
    }
    
    // MARK: - Queue Information
    
    /// Get queue position for a track
    func queuePosition(for track: TrackMetadata) -> Int? {
        return queue.firstIndex { $0.track?.filePath == track.filePath }
    }
    
    /// Check if track is in queue
    func isTrackInQueue(_ track: TrackMetadata) -> Bool {
        return queue.contains { $0.track?.filePath == track.filePath }
    }
    
    /// Get total queue duration
    var totalDuration: TimeInterval {
        return queue.reduce(0) { $0 + $1.duration }
    }
    
    /// Get remaining duration from current position
    var remainingDuration: TimeInterval {
        guard let index = currentIndex else { return totalDuration }
        return queue.suffix(from: index).reduce(0) { $0 + $1.duration }
    }
    
    // MARK: - Clean Action Methods
    
    /// Handle eject action - clear queue and stop playback
    func handleEject() {
        print("⏏️ QueueManager.handleEject called")
        clearQueue()
        stopPlayback()
        print("   Queue cleared and playback stopped")
    }

    /// Refresh any queue items that reference a given album with the updated album metadata
    /// Call this right after saving album metadata so transport uses the latest values immediately
    @MainActor
    func refreshAlbumInQueue(_ updatedAlbum: AlbumMetadata, oldName: String? = nil) {
        var changed = false
        let old = oldName?.lowercased()
        for index in queue.indices {
            if let album = queue[index].album {
                let name = album.albumName.lowercased()
                if name == updatedAlbum.albumName.lowercased() || (old != nil && name == old) {
                    let item = queue[index]
                    let newItem = QueueItem(
                        audioFile: item.audioFile,
                        track: item.track,
                        album: updatedAlbum,
                        playlistId: item.playlistId,
                        playlistPosition: item.playlistPosition,
                        albumPosition: item.albumPosition
                    )
                    queue[index] = newItem
                    changed = true
                }
            }
        }
        if changed {
            // Force Combine to publish the change and update Now Playing if needed
            queue = queue
            if currentIndex != nil { updateCurrentItem() }
        }
    }
}

// MARK: - Extensions

extension QueueManager {
    /// Load album into queue and start playing
    func loadAndPlayAlbum(_ album: AlbumMetadata, startAt track: TrackMetadata? = nil) {
        clearQueue()
        addAlbumToQueue(album)
        
        if let startTrack = track {
            if let index = queue.firstIndex(where: { $0.track?.filePath == startTrack.filePath }) {
                currentIndex = index
            } else {
                currentIndex = 0
            }
        } else {
            currentIndex = 0
        }
        
        playCurrentTrack()
        print("📀 Loaded and playing album: \(album.albumName)")
    }
    
    /// Replace current queue with new content
    func replaceQueue(with tracks: [TrackMetadata], from album: AlbumMetadata) {
        clearQueue()
        addToQueue(tracks, from: album)
        print("🔄 Queue replaced with \(tracks.count) tracks")
    }

    /// Build and play a virtual playlist (e.g., artist favorites) with stable positions
    /// - Parameters:
    ///   - tracks: Ordered tracks representing the virtual playlist
    ///   - playlistId: Stable identifier for this virtual playlist (used only for provenance)
    ///   - startIndex: Index in `tracks` to start playing from (defaults to 0)
    ///   - shuffle: If true, shuffles around the current item, but preserves displayed position via playlistPosition
    func playVirtualPlaylist(_ tracks: [TrackMetadata], playlistId: String, startIndex: Int = 0, shuffle: Bool = false) {
        clearQueue()

        for (idx, track) in tracks.enumerated() {
            if let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.name) {
                addToQueue(track, from: album, playlistId: playlistId, playlistPosition: idx + 1)
            } else {
                var minimalAlbum = AlbumMetadata(
                    albumName: track.artist ?? "Unknown",
                    albumType: nil,
                    frontArtPath: nil,
                    backArtPath: nil,
                    duration: track.duration ?? 0,
                    genre: nil,
                    year: nil,
                    trackCount: 1,
                    discCount: 1,
                    discNames: nil,
                    tracks: [track]
                )
                minimalAlbum.calculateDuration()
                addToQueue(track, from: minimalAlbum, playlistId: playlistId, playlistPosition: idx + 1)
            }
        }

        var resolvedIndex = 0
        if startIndex >= 0 && startIndex < tracks.count {
            let targetPath = tracks[startIndex].filePath
            if let qIndex = queue.firstIndex(where: { $0.track?.filePath == targetPath }) { resolvedIndex = qIndex }
        }

        currentIndex = resolvedIndex
        if shuffle { shuffleQueue() }
        playCurrentTrack()
    }
}
