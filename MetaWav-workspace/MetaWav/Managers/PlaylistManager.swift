// PlaylistManager.swift - Complete implementation with all required methods
import Foundation
import SwiftUI
import AVFoundation

// MARK: - Playlist Manager
class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()
    
    @Published var playlists: [PlaylistMetadata] = []
    
    private let fileManager = FileManager.default
    
    // REQUIRED: playlistDirectory property
    var playlistDirectory: URL {
        let userHome = fileManager.homeDirectoryForCurrentUser
        let playlistDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Playlists")
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: playlistDir.path) {
            do {
                try fileManager.createDirectory(at: playlistDir, withIntermediateDirectories: true)
                print("📁 Created playlists directory: \(playlistDir.path)")
            } catch {
                print("❌ Failed to create playlists directory: \(error)")
            }
        }
        
        return playlistDir
    }
    
    private init() {
        loadAllPlaylists()
    }
    
    // MARK: - Core Playlist Operations
    
    /// Create a new playlist
    func createPlaylist(name: String, description: String? = nil) throws -> PlaylistMetadata {
        // Check if playlist already exists
        if playlists.contains(where: { $0.name == name }) {
            throw PlaylistError.playlistAlreadyExists(name)
        }
        
        let playlist = PlaylistMetadata(name: name, description: description)
        
        try savePlaylist(playlist)
        playlists.append(playlist)
        
        print("✅ Created playlist: \(name)")
        return playlist
    }
    
    /// Save playlist to disk
    func savePlaylist(_ playlist: PlaylistMetadata) throws {
        let sanitizedName = sanitizeFilename(playlist.name)
        let playlistURL = playlistDirectory.appendingPathComponent("\(sanitizedName).metaplaylist")
        
        print("💾 Saving playlist: \(playlist.name)")
        print("   To: \(playlistURL.path)")
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(playlist)
        
        try data.write(to: playlistURL, options: [.atomic])
        print("✅ Playlist saved successfully")
        
        // Update the playlist in memory if it exists
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        }
        
        // Notify UI of changes (targeted)
        DispatchQueue.main.async {
            NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
        }
    }
    
    /// Load all playlists from disk
    func loadAllPlaylists() {
        print("📚 Loading all playlists from: \(playlistDirectory.path)")
        
        do {
            let files = try fileManager.contentsOfDirectory(at: playlistDirectory, includingPropertiesForKeys: nil)
            let playlistFiles = files.filter { $0.pathExtension == "metaplaylist" }
            
            print("   Found \(playlistFiles.count) .metaplaylist files")
            
            var loadedPlaylists: [PlaylistMetadata] = []
            
            for playlistFile in playlistFiles {
                do {
                    let data = try Data(contentsOf: playlistFile)
                    let playlist = try PropertyListDecoder().decode(PlaylistMetadata.self, from: data)
                    loadedPlaylists.append(playlist)
                } catch {
                    print("❌ Failed to load playlist from \(playlistFile.lastPathComponent): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.playlists = loadedPlaylists
            }
            print("📚 Successfully loaded \(loadedPlaylists.count) playlists")
            
        } catch {
            print("❌ Error scanning playlists directory: \(error)")
            DispatchQueue.main.async {
                self.playlists = []
            }
        }
    }
    
    /// Delete a playlist
    func deletePlaylist(_ playlist: PlaylistMetadata) throws {
        print("🗑️ Deleting playlist: \(playlist.name)")
        
        let sanitizedName = sanitizeFilename(playlist.name)
        let playlistURL = playlistDirectory.appendingPathComponent("\(sanitizedName).metaplaylist")
        
        if fileManager.fileExists(atPath: playlistURL.path) {
            try fileManager.removeItem(at: playlistURL)
            print("✅ Deleted playlist file: \(playlistURL.path)")
        }
        
        // Remove from memory
        playlists.removeAll { $0.id == playlist.id }
        
        print("✅ Playlist '\(playlist.name)' deleted successfully")
        
        // Notify UI of deletion (targeted)
        DispatchQueue.main.async {
            NotificationManager.shared.postNotification(.playlistDeleted, object: nil)
        }
    }
    
    // MARK: - Track Operations
    
    /// Add a track to a playlist
    func addTrackToPlaylist(_ track: TrackMetadata, from album: AlbumMetadata, to playlistName: String) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == playlistName }) else {
            throw PlaylistError.playlistNotFound(playlistName)
        }
        
        var playlist = playlists[playlistIndex]
        
        // Check if track is already in playlist
        if playlist.tracks.contains(where: { $0.filePath == track.filePath }) {
            throw PlaylistError.trackAlreadyInPlaylist(track.name, playlistName)
        }
        
        // Create playlist track
        let playlistTrack = PlaylistTrack(
            filePath: track.filePath,
            trackName: track.name,
            artistName: track.artist,
            albumName: album.albumName,
            duration: track.duration
        )
        
        // Add to playlist
        playlist.tracks.append(playlistTrack)
        playlist.updateTrackCount()
        playlist.calculateDuration()
        playlist.modifiedDate = Date()
        
        // Save updated playlist
        try savePlaylist(playlist)
        
        print("✅ Added '\(track.name)' to playlist '\(playlistName)'")
    }
    
    /// Remove a track from a playlist
    func removeTrackFromPlaylist(_ track: TrackMetadata, from playlistName: String) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == playlistName }) else {
            throw PlaylistError.playlistNotFound(playlistName)
        }
        
        var playlist = playlists[playlistIndex]
        
        // Find and remove the track
        let originalCount = playlist.tracks.count
        playlist.tracks.removeAll { $0.filePath == track.filePath }
        
        if playlist.tracks.count == originalCount {
            throw PlaylistError.trackNotInPlaylist(track.name, playlistName)
        }
        
        // Reorder remaining tracks
        for (index, var playlistTrack) in playlist.tracks.enumerated() {
            playlistTrack.playlistPosition = index + 1
            playlist.tracks[index] = playlistTrack
        }
        
        playlist.updateTrackCount()
        playlist.calculateDuration()
        playlist.modifiedDate = Date()
        
        // Save updated playlist
        try savePlaylist(playlist)
        
        print("✅ Removed '\(track.name)' from playlist '\(playlistName)'")
    }
    
    /// Reorder tracks in a playlist
    func reorderPlaylistTracks(in playlistName: String, fromOffsets source: IndexSet, toOffset destination: Int) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == playlistName }) else {
            throw PlaylistError.playlistNotFound(playlistName)
        }
        
        var playlist = playlists[playlistIndex]
        
        // Perform the reorder
        playlist.tracks.move(fromOffsets: source, toOffset: destination)
        
        // Update positions
        for (index, var track) in playlist.tracks.enumerated() {
            track.playlistPosition = index + 1
            playlist.tracks[index] = track
        }
        
        playlist.modifiedDate = Date()
        
        // Save updated playlist
        try savePlaylist(playlist)
        
        print("✅ Reordered tracks in playlist '\(playlistName)'")
    }
    
    // MARK: - Validation and Utilities
    
    /// Validate that all tracks in a playlist still exist
    func validatePlaylistTracks(_ playlist: PlaylistMetadata) -> (valid: [PlaylistTrack], missing: [PlaylistTrack]) {
        let validTracks = playlist.tracks.filter { track in
            FileManager.default.fileExists(atPath: track.filePath)
        }
        
        let missingTracks = playlist.tracks.filter { track in
            !FileManager.default.fileExists(atPath: track.filePath)
        }
        
        return (valid: validTracks, missing: missingTracks)
    }
    
    /// Get all tracks from all playlists
    func getAllPlaylistTracks() -> [(playlist: PlaylistMetadata, track: PlaylistTrack)] {
        var allTracks: [(playlist: PlaylistMetadata, track: PlaylistTrack)] = []
        
        for playlist in playlists {
            for track in playlist.tracks.sorted(by: { $0.playlistPosition < $1.playlistPosition }) {
                allTracks.append((playlist: playlist, track: track))
            }
        }
        
        return allTracks
    }
    
    /// Find playlists containing a specific track
    func findPlaylistsContaining(trackPath: String) -> [PlaylistMetadata] {
        return playlists.filter { playlist in
            playlist.tracks.contains { $0.filePath == trackPath }
        }
    }
    
    /// Get playlist by name
    func getPlaylist(named name: String) -> PlaylistMetadata? {
        return playlists.first { $0.name == name }
    }
    
    /// Rename a playlist
    func renamePlaylist(from oldName: String, to newName: String) throws {
        // Check if new name already exists
        if playlists.contains(where: { $0.name == newName }) {
            throw PlaylistError.playlistAlreadyExists(newName)
        }
        
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == oldName }) else {
            throw PlaylistError.playlistNotFound(oldName)
        }
        
        var playlist = playlists[playlistIndex]
        
        // Delete old file
        let oldSanitized = sanitizeFilename(oldName)
        let oldURL = playlistDirectory.appendingPathComponent("\(oldSanitized).metaplaylist")
        if fileManager.fileExists(atPath: oldURL.path) {
            try fileManager.removeItem(at: oldURL)
        }
        
        // Update playlist name and save with new name
        playlist.name = newName
        playlist.modifiedDate = Date()
        
        try savePlaylist(playlist)
        
        print("✅ Renamed playlist from '\(oldName)' to '\(newName)'")
    }

    /// Update playlist metadata (name, description) and persist
    func updatePlaylistMetadata(id: String, newName: String, newDescription: String?) throws {
        guard let index = playlists.firstIndex(where: { $0.playlistId == id }) else {
            throw PlaylistError.playlistNotFound(id)
        }
        let original = playlists[index]
        var updated = original
        let nameChanged = updated.name != newName
        updated.name = newName
        updated.description = newDescription
        updated.modifiedDate = Date()

        if nameChanged {
            // Delete old file when name changes
            let oldSanitized = sanitizeFilename(original.name)
            let oldURL = playlistDirectory.appendingPathComponent("\(oldSanitized).metaplaylist")
            if fileManager.fileExists(atPath: oldURL.path) {
                try fileManager.removeItem(at: oldURL)
            }
        }

        try savePlaylist(updated)
        playlists[index] = updated
    }
    
    /// Clean up playlists by removing missing tracks
    func cleanupPlaylists() -> [String] {
        var cleanedPlaylistNames: [String] = []
        
        for (_, var playlist) in playlists.enumerated() {
            let validation = validatePlaylistTracks(playlist)
            
            if !validation.missing.isEmpty {
                print("🧹 Cleaning up playlist '\(playlist.name)': removing \(validation.missing.count) missing tracks")
                
                playlist.tracks = validation.valid
                
                // Reorder positions
                for (trackIndex, var track) in playlist.tracks.enumerated() {
                    track.playlistPosition = trackIndex + 1
                    playlist.tracks[trackIndex] = track
                }
                
                playlist.updateTrackCount()
                playlist.calculateDuration()
                playlist.modifiedDate = Date()
                
                do {
                    try savePlaylist(playlist)
                    cleanedPlaylistNames.append(playlist.name)
                } catch {
                    print("❌ Failed to save cleaned playlist '\(playlist.name)': \(error)")
                }
            }
        }
        
        return cleanedPlaylistNames
    }
    
    
    // MARK: - Playlist Playback Operations
    
    /// Play a playlist from a specific track (Spotify-like behavior)
    func playPlaylistFromTrack(_ playlist: PlaylistMetadata, startingAt trackIndex: Int) {
        print("🎵 Playing playlist '\(playlist.name)' from track \(trackIndex + 1)")
        
        // Clear current queue
        QueueManager.shared.clearQueue()
        
        // Add all tracks from the playlist to the queue
        for (idx, playlistTrack) in playlist.tracks.enumerated() {
            // Try to get the full track metadata
            if let (album, trackMetadata) = AlbumMetadataManager.shared.findTrack(filePath: playlistTrack.filePath, name: playlistTrack.trackName) {
                QueueManager.shared.addToQueue(trackMetadata, from: album, playlistId: playlist.playlistId, playlistPosition: idx + 1)
            } else {
                // Create a minimal album if we can't find the original
                let minimalAlbum = AlbumMetadata(
                    albumName: playlistTrack.albumName,
                    albumType: nil,
                    frontArtPath: nil,
                    backArtPath: nil,
                    duration: playlistTrack.duration ?? 0,
                    genre: nil,
                    year: nil,
                    trackCount: 1,
                    discCount: 1,
                    discNames: nil,
                    tracks: []
                )
                // Create a minimal track metadata
                let minimalTrack = TrackMetadata(
                    filePath: playlistTrack.filePath,
                    discNumber: 1,
                    trackNumber: 1,
                    name: playlistTrack.trackName,
                    artist: playlistTrack.artistName,
                    duration: playlistTrack.duration
                )
                var albumWithTrack = minimalAlbum
                albumWithTrack.tracks = [minimalTrack]
                QueueManager.shared.addToQueue(minimalTrack, from: albumWithTrack, playlistId: playlist.playlistId, playlistPosition: idx + 1)
            }
        }
        
        // Set the current track to the starting position
        if trackIndex < QueueManager.shared.queue.count {
            QueueManager.shared.currentIndex = trackIndex
            QueueManager.shared.playCurrentTrack()
            print("🎵 Started playing playlist from track: \(playlist.tracks[trackIndex].trackName)")
        } else {
            print("❌ Invalid track index: \(trackIndex)")
        }
    }
    
    /// Play entire playlist from the beginning
    func playPlaylist(_ playlist: PlaylistMetadata) {
        playPlaylistFromTrack(playlist, startingAt: 0)
    }
    
    /// Add playlist tracks to current queue
    func addPlaylistToQueue(_ playlist: PlaylistMetadata) {
        print("➕ Adding playlist '\(playlist.name)' to current queue")
        
        for (idx, playlistTrack) in playlist.tracks.enumerated() {
            if let (album, trackMetadata) = AlbumMetadataManager.shared.findTrack(filePath: playlistTrack.filePath, name: playlistTrack.trackName) {
                QueueManager.shared.addToQueue(trackMetadata, from: album, playlistId: playlist.playlistId, playlistPosition: idx + 1)
            } else {
                // Create a minimal album if we can't find the original
                let minimalAlbum = AlbumMetadata(
                    albumName: playlistTrack.albumName,
                    albumType: nil,
                    frontArtPath: nil,
                    backArtPath: nil,
                    duration: playlistTrack.duration ?? 0,
                    genre: nil,
                    year: nil,
                    trackCount: 1,
                    discCount: 1,
                    discNames: nil,
                    tracks: []
                )
                // Create a minimal track metadata
                let minimalTrack = TrackMetadata(
                    filePath: playlistTrack.filePath,
                    discNumber: 1,
                    trackNumber: 1,
                    name: playlistTrack.trackName,
                    artist: playlistTrack.artistName,
                    duration: playlistTrack.duration
                )
                var albumWithTrack = minimalAlbum
                albumWithTrack.tracks = [minimalTrack]
                QueueManager.shared.addToQueue(minimalTrack, from: albumWithTrack, playlistId: playlist.playlistId, playlistPosition: idx + 1)
            }
        }
        
        print("✅ Added \(playlist.trackCount) tracks from playlist to queue")
    }
    
    // MARK: - Enhanced Track Operations
    
    /// Add multiple tracks to a playlist
    func addTracksToPlaylist(_ tracks: [TrackMetadata], to playlistName: String, at position: Int? = nil) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == playlistName }) else {
            throw PlaylistError.playlistNotFound(playlistName)
        }
        
        var playlist = playlists[playlistIndex]
        
        for track in tracks {
            playlist.addTrack(track, at: position)
        }
        
        try savePlaylist(playlist)
        playlists[playlistIndex] = playlist
        
        print("✅ Added \(tracks.count) tracks to playlist '\(playlistName)'")
    }
    
    /// Add entire album to playlist
    func addAlbumToPlaylist(_ album: AlbumMetadata, to playlistName: String, at position: Int? = nil) throws {
        try addTracksToPlaylist(album.tracks, to: playlistName, at: position)
        print("✅ Added album '\(album.albumName)' to playlist '\(playlistName)'")
    }
    
    /// Remove multiple tracks from playlist
    func removeTracksFromPlaylist(_ tracks: [TrackMetadata], from playlistName: String) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == playlistName }) else {
            throw PlaylistError.playlistNotFound(playlistName)
        }
        
        var playlist = playlists[playlistIndex]
        let trackPaths = Set(tracks.map { $0.filePath })
        
        // Remove tracks in reverse order to maintain indices
        for index in stride(from: playlist.tracks.count - 1, through: 0, by: -1) {
            if trackPaths.contains(playlist.tracks[index].filePath) {
                playlist.removeTrack(at: index)
            }
        }
        
        try savePlaylist(playlist)
        playlists[playlistIndex] = playlist
        
        print("✅ Removed \(tracks.count) tracks from playlist '\(playlistName)'")
    }
    
    /// Reorder tracks in playlist
    func reorderPlaylistTracks(in playlistName: String, from sourceIndex: Int, to destinationIndex: Int) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == playlistName }) else {
            throw PlaylistError.playlistNotFound(playlistName)
        }
        
        var playlist = playlists[playlistIndex]
        playlist.moveTrack(from: sourceIndex, to: destinationIndex)
        
        try savePlaylist(playlist)
        playlists[playlistIndex] = playlist
        
        print("✅ Reordered tracks in playlist '\(playlistName)'")
    }
    
    // MARK: - Advanced Features
    
    /// Check for duplicate tracks in a playlist
    func findDuplicateTracks(in playlist: PlaylistMetadata) -> [String: [PlaylistTrack]] {
        var trackCounts: [String: [PlaylistTrack]] = [:]
        
        for track in playlist.tracks {
            if trackCounts[track.filePath] == nil {
                trackCounts[track.filePath] = []
            }
            trackCounts[track.filePath]?.append(track)
        }
        
        // Return only tracks that appear more than once
        return trackCounts.filter { $0.value.count > 1 }
    }
    
    /// Remove duplicate tracks from a playlist (keeps first occurrence)
    func removeDuplicateTracks(from playlistName: String) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.name == playlistName }) else {
            throw PlaylistError.playlistNotFound(playlistName)
        }
        
        var playlist = playlists[playlistIndex]
        var seenPaths: Set<String> = []
        var uniqueTracks: [PlaylistTrack] = []
        
        for track in playlist.tracks {
            if !seenPaths.contains(track.filePath) {
                seenPaths.insert(track.filePath)
                uniqueTracks.append(track)
            }
        }
        
        playlist.tracks = uniqueTracks
        playlist.updatePositions()
        playlist.updateTrackCount()
        playlist.calculateDuration()
        playlist.modifiedDate = Date()
        
        try savePlaylist(playlist)
        playlists[playlistIndex] = playlist
        
        print("✅ Removed duplicate tracks from playlist '\(playlistName)'")
    }
    
    /// Get playlist statistics
    func getPlaylistStats(for playlist: PlaylistMetadata) -> PlaylistStats {
        let duplicates = findDuplicateTracks(in: playlist)
        let uniqueArtists = Set(playlist.tracks.compactMap { $0.artistName })
        let uniqueAlbums = Set(playlist.tracks.map { $0.albumName })
        
        return PlaylistStats(
            totalTracks: playlist.trackCount,
            uniqueTracks: playlist.trackCount - duplicates.values.flatMap { $0 }.count + duplicates.count,
            duplicateTracks: duplicates.values.flatMap { $0 }.count - duplicates.count,
            uniqueArtists: uniqueArtists.count,
            uniqueAlbums: uniqueAlbums.count,
            totalDuration: playlist.duration ?? 0
        )
    }
    
    /// Create a smart playlist based on criteria
    func createSmartPlaylist(name: String, criteria: SmartPlaylistCriteria) throws -> PlaylistMetadata {
        print("🧠 Creating smart playlist: \(name)")
        
        // Get all albums and tracks
        let allAlbums = AlbumMetadataManager.shared.loadAllAlbums()
        var matchingTracks: [TrackMetadata] = []
        
        for album in allAlbums {
            for track in album.tracks {
                if matchesCriteria(track: track, album: album, criteria: criteria) {
                    matchingTracks.append(track)
                }
            }
        }
        
        // Sort tracks based on criteria
        matchingTracks = sortTracksForSmartPlaylist(matchingTracks, criteria: criteria)
        
        // Limit to maximum tracks if specified
        if let maxTracks = criteria.maxTracks, matchingTracks.count > maxTracks {
            matchingTracks = Array(matchingTracks.prefix(maxTracks))
        }
        
        // Create the playlist
        var playlist = PlaylistMetadata(name: name, description: criteria.description)
        
        // Add matching tracks
        for track in matchingTracks {
            playlist.addTrack(track)
        }
        
        try savePlaylist(playlist)
        playlists.append(playlist)
        
        print("✅ Created smart playlist '\(name)' with \(matchingTracks.count) tracks")
        return playlist
    }
    
    /// Check if a track matches smart playlist criteria
    private func matchesCriteria(track: TrackMetadata, album: AlbumMetadata, criteria: SmartPlaylistCriteria) -> Bool {
        // Artist criteria
        if let artist = criteria.artist, track.artist?.localizedCaseInsensitiveContains(artist) != true {
            return false
        }
        
        // Album criteria
        if let albumName = criteria.album, !album.albumName.localizedCaseInsensitiveContains(albumName) {
            return false
        }
        
        // Genre criteria
        if let genre = criteria.genre, album.genre?.localizedCaseInsensitiveContains(genre) != true {
            return false
        }
        
        // Year criteria
        if let year = criteria.year, album.year != year {
            return false
        }
        
        // Duration criteria
        if let minDuration = criteria.minDuration, (track.duration ?? 0) < minDuration {
            return false
        }
        if let maxDuration = criteria.maxDuration, (track.duration ?? 0) > maxDuration {
            return false
        }
        
        // Play count criteria
        let playCount = PlayCountManager.shared.getPlayCount(trackId: track.stableTrackId)
        if let minPlays = criteria.minPlayCount, playCount < minPlays {
            return false
        }
        if let maxPlays = criteria.maxPlayCount, playCount > maxPlays {
            return false
        }
        
        return true
    }
    
    /// Sort tracks for smart playlist
    private func sortTracksForSmartPlaylist(_ tracks: [TrackMetadata], criteria: SmartPlaylistCriteria) -> [TrackMetadata] {
        switch criteria.sortBy {
        case .name:
            return tracks.sorted { (track1: TrackMetadata, track2: TrackMetadata) in track1.name < track2.name }
        case .artist:
            return tracks.sorted { (track1: TrackMetadata, track2: TrackMetadata) in (track1.artist ?? "") < (track2.artist ?? "") }
        case .album:
            // For album sorting, we'll need to get the album name from the metadata manager
            // For now, sort by track name as a fallback
            return tracks.sorted { (track1: TrackMetadata, track2: TrackMetadata) in track1.name < track2.name }
        case .duration:
            return tracks.sorted { (track1: TrackMetadata, track2: TrackMetadata) in (track1.duration ?? 0) < (track2.duration ?? 0) }
        case .playCount:
            return tracks.sorted { (track1: TrackMetadata, track2: TrackMetadata) in 
                PlayCountManager.shared.getPlayCount(trackId: track1.stableTrackId) > 
                PlayCountManager.shared.getPlayCount(trackId: track2.stableTrackId)
            }
        case .random:
            return tracks.shuffled()
        }
    }
    
    // MARK: - Artwork Management
    
    /// Save artwork for a playlist
    func savePlaylistArtwork(_ imageURL: URL, for playlistId: String) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.playlistId == playlistId }) else {
            throw PlaylistError.playlistNotFound(playlistId)
        }
        
        // Create artwork directory if it doesn't exist
        let artworkDir = playlistDirectory.appendingPathComponent("artwork")
        try FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        
        // Generate artwork filename
        let artworkFilename = "\(playlistId).jpg"
        let artworkPath = artworkDir.appendingPathComponent(artworkFilename)
        
        // Copy the image file
        try FileManager.default.copyItem(at: imageURL, to: artworkPath)
        
        // Update playlist artwork path
        playlists[playlistIndex].artworkPath = artworkPath.path
        
        // Save the updated playlist
        try savePlaylist(playlists[playlistIndex])
        
        print("✅ Saved artwork for playlist: \(playlists[playlistIndex].name)")
    }
    
    /// Remove artwork for a playlist
    func removePlaylistArtwork(for playlistId: String) throws {
        guard let playlistIndex = playlists.firstIndex(where: { $0.playlistId == playlistId }) else {
            throw PlaylistError.playlistNotFound(playlistId)
        }
        
        // Remove artwork file if it exists
        if let artworkPath = playlists[playlistIndex].artworkPath,
           FileManager.default.fileExists(atPath: artworkPath) {
            try FileManager.default.removeItem(atPath: artworkPath)
        }
        
        // Clear artwork path
        playlists[playlistIndex].artworkPath = nil
        
        // Save the updated playlist
        try savePlaylist(playlists[playlistIndex])
        
        print("✅ Removed artwork for playlist: \(playlists[playlistIndex].name)")
    }
    
    /// Get artwork path for a playlist
    func getPlaylistArtworkPath(for playlistId: String) -> String? {
        return playlists.first(where: { $0.playlistId == playlistId })?.artworkPath
    }
    
    // MARK: - Utilities
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}

// MARK: - Playlist Errors

enum PlaylistError: LocalizedError {
    case playlistAlreadyExists(String)
    case playlistNotFound(String)
    case trackAlreadyInPlaylist(String, String)
    case trackNotInPlaylist(String, String)
    case invalidPlaylistFile(String)
    
    var errorDescription: String? {
        switch self {
        case .playlistAlreadyExists(let name):
            return "Playlist '\(name)' already exists"
        case .playlistNotFound(let name):
            return "Playlist '\(name)' not found"
        case .trackAlreadyInPlaylist(let track, let playlist):
            return "Track '\(track)' is already in playlist '\(playlist)'"
        case .trackNotInPlaylist(let track, let playlist):
            return "Track '\(track)' is not in playlist '\(playlist)'"
        case .invalidPlaylistFile(let reason):
            return "Invalid playlist file: \(reason)"
        }
    }
}

// MARK: - Extensions for Array Operations

extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let movedItems = source.map { self[$0] }
        
        // Remove items in reverse order to maintain indices
        for index in source.sorted(by: >) {
            self.remove(at: index)
        }
        
        // Calculate adjusted destination
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        
        // Insert items at new location
        for (offset, item) in movedItems.enumerated() {
            self.insert(item, at: adjustedDestination + offset)
        }
    }
}

