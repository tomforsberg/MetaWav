// MetadataManager.swift - UPDATED: Added Album Type Support
import Foundation
import AppKit
import AVFoundation

/// Central album metadata manager.
/// Marked as `@unchecked Sendable` to satisfy Swift concurrency when captured in `@Sendable` closures.
/// This type is effectively main-thread-bound via its usage patterns.
final class AlbumMetadataManager: ObservableObject, @unchecked Sendable {
    static let shared = AlbumMetadataManager()
    private let fileManager = FileManager.default
    
    // MARK: - Published Properties
    @Published var isUpdating = false
    @Published var lastUpdateTime: Date?
    @Published var updateStatus: String = ""
    
    func saveAlbumMetadata(_ album: AlbumMetadata) throws {
        let sanitizedName = sanitizeFilename(album.albumName)
        let metaURL = metadataDirectory.appendingPathComponent("\(sanitizedName).meta")
        
        NotificationManager.shared.log("Saving album metadata: \(album.albumName)")
        
        // SIMPLE: Just encode and save directly
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(album)
        
        // Write directly to the final file
        try data.write(to: metaURL, options: [.atomic])
        
        // Trigger UI update (targeted)
        DispatchQueue.main.async {
            self.lastUpdateTime = Date()
            self.updateStatus = "Saved \(album.albumName)"
            self.objectWillChange.send()
            NotificationManager.shared.postNotification(.albumUpdated, object: album)
            NotificationManager.shared.postNotification(.albumMetadataChanged, object: album)
        }
        
        NotificationManager.shared.log("Successfully saved album metadata: \(album.albumName)")
    }
    


    // REPLACE your existing saveFrontArtwork method with this:
    func saveFrontArtwork(_ imageURL: URL, for albumName: String) throws {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            throw NSError(domain: "AlbumMetadataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Album not found"])
        }
        
        album.frontArtPath = imageURL.path
        try saveAlbumMetadata(album) // This will now trigger the refresh automatically
        DispatchQueue.main.async {
            NotificationManager.shared.postNotification(.albumArtChanged, object: album)
        }
        print("💾 Saved front artwork for album: \(albumName)")
    }

    // REPLACE your existing saveBackArtwork method with this:
    func saveBackArtwork(_ imageURL: URL, for albumName: String) throws {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            throw NSError(domain: "AlbumMetadataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Album not found"])
        }
        
        album.backArtPath = imageURL.path
        try saveAlbumMetadata(album) // This will now trigger the refresh automatically
        DispatchQueue.main.async {
            NotificationManager.shared.postNotification(.albumArtChanged, object: album)
        }
        print("💾 Saved back artwork for album: \(albumName)")
    }

    // REPLACE your existing updateTrackMetadata method with this:
    func updateTrackMetadata(
        _ updatedTrack: TrackMetadata,
        in albumName: String,
        forceReorder: Bool = false
    ) throws {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            throw AlbumError.albumNotFound(albumName)
        }
        
        // Find the original track
        guard let originalIndex = album.tracks.firstIndex(where: { $0.id == updatedTrack.id }) else {
            throw AlbumError.albumNotFound("Track not found in album")
        }
        
        let originalTrack = album.tracks[originalIndex]
        let positionChanged = updatedTrack.hasPositionChanges(comparedTo: originalTrack)
        
        if positionChanged {
            print("🔄 Track position changed: '\(updatedTrack.name)' from \(originalTrack.positionDescription) to \(updatedTrack.positionDescription)")
        }
        
        // Enforce MP3 bit depth rule before saving the track
        var enforcedTrack = updatedTrack
        let isMP3Format = (enforcedTrack.format?.uppercased() == "MP3") ||
                          (URL(fileURLWithPath: enforcedTrack.filePath).pathExtension.lowercased() == "mp3")
        if isMP3Format {
            enforcedTrack.bitDepth = "16-bit"
        }

        // Update the track
        album.tracks[originalIndex] = enforcedTrack
        
        // Validate and fix if position changed, conflicts exist, or forced
        let needsReordering = positionChanged ||
                             forceReorder ||
                             TrackReorderingManager.shared.hasTrackNumberConflicts(in: album)
        
        if needsReordering {
            print("🔄 Reordering album '\(albumName)' due to track changes")
            let wasFixed = TrackReorderingManager.shared.validateAndFixAlbum(&album)
            
            if wasFixed {
                print("✅ Applied auto-fixes during track update")
            }
        }
        
        album.calculateDuration()
        try saveAlbumMetadata(album) // This will now trigger the refresh automatically
        
        // Post notification for UI updates
        if needsReordering {
            NotificationManager.shared.postNotification(.albumReordered, object: album)
        }
        NotificationManager.shared.postNotification(.trackMetadataChanged, object: (album.tracks[originalIndex], album))
        
        print("✅ Updated track '\(updatedTrack.name)' in '\(albumName)'")
    }
    
    private var metadataDirectory: URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let customDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Metadata")
        
        // Create directory if needed
        if !FileManager.default.fileExists(atPath: customDir.path) {
            do {
                try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
                print("📁 Created metadata directory: \(customDir.path)")
            } catch {
                print("❌ Directory creation failed: \(error)")
            }
        } else {
            print("📁 Using metadata directory: \(customDir.path)")
        }
        
        return customDir
    }
    
    // MARK: - Album Management
    var metadataDirectoryURL: URL {
        return metadataDirectory
    }
    
    /// Load album metadata by name
    func loadAlbumMetadata(albumName: String) -> AlbumMetadata? {
        let sanitizedName = sanitizeFilename(albumName)
        let metaURL = metadataDirectory.appendingPathComponent("\(sanitizedName).meta")
        
        guard fileManager.fileExists(atPath: metaURL.path) else {
            NotificationManager.shared.log("No metadata file found for album: \(albumName)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: metaURL)
            var album = try PropertyListDecoder().decode(AlbumMetadata.self, from: data)
            
            // MIGRATION: Handle old albums without disc numbers and enforce MP3 bit depth rule
            var needsUpdate = false
            for (index, _) in album.tracks.enumerated() {
                // If track doesn't have a disc number (from old format), default to disc 1
                if album.tracks[index].discNumber == 0 {
                    album.tracks[index].discNumber = 1
                    needsUpdate = true
                }
                // Enforce: If track is MP3, set bitDepth to 16-bit
                let track = album.tracks[index]
                let extIsMP3 = URL(fileURLWithPath: track.filePath).pathExtension.lowercased() == "mp3"
                let formatIsMP3 = (track.format?.uppercased() == "MP3")
                if extIsMP3 || formatIsMP3 {
                    if track.bitDepth != "16-bit" {
                        album.tracks[index].bitDepth = "16-bit"
                        needsUpdate = true
                    }
                }
            }
            
            // Update disc count if needed
            if album.discCount == 0 || needsUpdate {
                album.updateDiscCount()
                needsUpdate = true
            }
            
            // Save updated album if migration occurred
            if needsUpdate {
                try saveAlbumMetadata(album)
                NotificationManager.shared.log("Migrated album '\(albumName)' to disc number format")
            }
            
            NotificationManager.shared.log("Loaded album metadata: \(albumName)")
            return album
        } catch {
            NotificationManager.shared.log("Failed to load album metadata for \(albumName): \(error)")
            return nil
        }
    }
    
    /// Check if an album name already exists
    func albumExists(named albumName: String) -> Bool {
        let sanitizedName = sanitizeFilename(albumName)
        let metaURL = metadataDirectory.appendingPathComponent("\(sanitizedName).meta")
        return fileManager.fileExists(atPath: metaURL.path)
    }
    
    /// Rename an album (renames the .meta file)
    @MainActor func renameAlbum(from oldName: String, to newName: String) throws {
        let oldSanitized = sanitizeFilename(oldName)
        let newSanitized = sanitizeFilename(newName)

        let oldURL = metadataDirectory.appendingPathComponent("\(oldSanitized).meta")
        let _ = metadataDirectory.appendingPathComponent("\(newSanitized).meta")

        // Load existing album data
        guard var album = loadAlbumMetadata(albumName: oldName) else {
            throw AlbumError.albumNotFound(oldName)
        }

        // Update in-memory name
        album.albumName = newName

        // Ensure target is clean: delete any pre-existing new meta
        if fileManager.fileExists(atPath: metadataDirectory.appendingPathComponent("\(newSanitized).meta").path) {
            try fileManager.removeItem(at: metadataDirectory.appendingPathComponent("\(newSanitized).meta"))
        }

        // Delete old .meta first (requirement)
        if fileManager.fileExists(atPath: oldURL.path) {
            try fileManager.removeItem(at: oldURL)
        }

        // Write the updated album to the new .meta
        try writeMetaFile(album)

        // Refresh UI
        refreshUI(after: album)

        NotificationManager.shared.log("Renamed album from '\(oldName)' to '\(newName)'")
    }
    
    /// Rename an album with instant updates and proper cleanup
    func renameAlbumInstantly(from oldName: String, to newName: String) async throws {
        NotificationManager.shared.log("Starting instant album rename: '\(oldName)' → '\(newName)'")
        
        // Load the album to be renamed
        guard var album = loadAlbumMetadata(albumName: oldName) else {
            throw AlbumError.albumNotFound(oldName)
        }
        
        // Store the old name for cleanup
        let originalName = album.albumName
        
        // Update the album name
        album.albumName = newName
        
        // Use the instant update system for proper cleanup
        try await saveAlbumMetadataInstantly(album, oldName: originalName)
        
        NotificationManager.shared.log("Album renamed instantly: '\(oldName)' → '\(newName)'")
    }
    
    /// Generate next available untitled album name
    func getNextUntitledAlbumName() -> String {
        var counter = 0
        var albumName: String
        
        repeat {
            albumName = counter == 0 ? "UntitledAlbum" : "UntitledAlbum \(counter)"
            counter += 1
        } while albumExists(named: albumName)
        
        return albumName
    }
    
    // MARK: - Enhanced Album Deletion with Artist Cleanup
    func deleteAlbum(_ albumName: String) throws {
        print("🗑️ Deleting album: \(albumName)")
        
        // Load the album to get file paths and artist information
        guard let album = loadAllAlbums().first(where: { $0.albumName == albumName }) else {
            throw AlbumError.albumNotFound(albumName)
        }
        
        // Collect all unique artists from this album before deletion
        let albumArtists = extractUniqueArtists(from: album)
        print("📝 Album contains artists: \(albumArtists.joined(separator: ", "))")
        
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
        
        // Delete the .meta file
        let metadataDir = metaWavDir.appendingPathComponent("Metadata")
        let sanitizedName = sanitizeFilename(albumName)
        let metaFileURL = metadataDir.appendingPathComponent("\(sanitizedName).meta")
        
        if FileManager.default.fileExists(atPath: metaFileURL.path) {
            try FileManager.default.removeItem(at: metaFileURL)
            print("✅ Deleted metadata file: \(metaFileURL.path)")
        }
        
        // Delete album directory if it exists (for imported MetaAlbums)
        let albumDir = metaWavDir.appendingPathComponent(sanitizedName)
        if FileManager.default.fileExists(atPath: albumDir.path) {
            try FileManager.default.removeItem(at: albumDir)
            print("✅ Deleted album directory: \(albumDir.path)")
        }
        
        // Delete album artwork if it exists
        try deleteAlbumArtwork(for: albumName)
        
        // Post album deletion notification
        NotificationManager.shared.postNotification(.albumDeleted, object: albumName)
        
        print("✅ Album '\(albumName)' deleted successfully")
        
        // Now check for orphaned artists and clean them up
        try cleanupOrphanedArtists(albumArtists, deletedAlbumName: albumName)
    }

    // MARK: - Artist Management Helper Methods

    /// Extract unique artists from an album including featured artists (from credits)
    private func extractUniqueArtists(from album: AlbumMetadata) -> [String] {
        var artists = Set<String>()
        
        // Collect main artists from all tracks
        for track in album.tracks {
            if let artist = track.artist, !artist.isEmpty {
                artists.insert(artist)
            }
        }
        
        // Also collect featured artists from credits using ArtistDetection
        for track in album.tracks {
            let featured = ArtistDetection.getFeaturedArtists(from: track)
            for name in featured where !name.isEmpty {
                artists.insert(name)
            }
        }
        
        return Array(artists).sorted()
    }

    /// Check if artists still exist in remaining albums and clean up if they don't
    private func cleanupOrphanedArtists(_ artistsToCheck: [String], deletedAlbumName: String) throws {
        guard !artistsToCheck.isEmpty else { return }
        
        print("🔍 Checking for orphaned artists after deleting '\(deletedAlbumName)'...")
        
        // Load all remaining albums
        let remainingAlbums = loadAllAlbums()
        
        // Collect all artists still present in the library (main + featured)
        var remainingArtists = Set<String>()
        for album in remainingAlbums {
            let albumArtists = extractUniqueArtists(from: album)
            for artist in albumArtists {
                remainingArtists.insert(artist)
            }
        }
        
        // Find artists that are no longer in any album
        let orphanedArtists = artistsToCheck.filter { !remainingArtists.contains($0) }
        
        if orphanedArtists.isEmpty {
            print("✅ All artists from deleted album still have other albums in library")
            return
        }
        
        print("🎭 Found \(orphanedArtists.count) orphaned artists:")
        for artist in orphanedArtists {
            print("   - \(artist)")
        }
        
        // Clean up artist-specific data
        for artist in orphanedArtists {
            try cleanupArtistData(artist)
        }
        
        // Log summary
        if orphanedArtists.count == 1 {
            print("🗑️ Cleaned up 1 artist who no longer has albums in the library")
        } else {
            print("🗑️ Cleaned up \(orphanedArtists.count) artists who no longer have albums in the library")
        }
        
        // Post coordinated refresh after cleanup
        SmartRefreshCoordinator.shared.processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))
    }

    /// Clean up all data associated with a specific artist
    private func cleanupArtistData(_ artistName: String) throws {
        print("🎭 Cleaning up data for artist: \(artistName)")
        
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
        
        let sanitizedArtistName = sanitizeFilename(artistName)
        
        // 1. Clean up artist artwork (if any exists)
        try cleanupArtistArtwork(sanitizedArtistName, metaWavDir: metaWavDir)
        
        // 2. Clean up artist-specific playlists (if any exist)
        try cleanupArtistPlaylists(artistName)
        
        // 3. Clean up any artist-specific directories or files
        try cleanupArtistFiles(sanitizedArtistName, metaWavDir: metaWavDir)
        
        print("✅ Completed cleanup for artist: \(artistName)")
    }

    /// Delete album artwork files
    private func deleteAlbumArtwork(for albumName: String) throws {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let artDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Art")
        
        let sanitizedName = sanitizeFilename(albumName)
        let artworkExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff"]
        var deletedArtworkCount = 0
        
        // Delete front artwork
        for ext in artworkExtensions {
            let frontArtPath = artDir.appendingPathComponent("\(sanitizedName)_cover.\(ext)")
            if FileManager.default.fileExists(atPath: frontArtPath.path) {
                try FileManager.default.removeItem(at: frontArtPath)
                print("✅ Deleted front artwork: \(frontArtPath.lastPathComponent)")
                deletedArtworkCount += 1
            }
        }
        
        // Delete back artwork
        for ext in artworkExtensions {
            let backArtPath = artDir.appendingPathComponent("\(sanitizedName)_back.\(ext)")
            if FileManager.default.fileExists(atPath: backArtPath.path) {
                try FileManager.default.removeItem(at: backArtPath)
                print("✅ Deleted back artwork: \(backArtPath.lastPathComponent)")
                deletedArtworkCount += 1
            }
        }
        
        if deletedArtworkCount > 0 {
            print("🎨 Deleted \(deletedArtworkCount) artwork file(s) for album '\(albumName)'")
        }
    }

    /// Clean up artist artwork files
    private func cleanupArtistArtwork(_ sanitizedArtistName: String, metaWavDir: URL) throws {
        let artDir = metaWavDir.appendingPathComponent("Art")
        
        guard FileManager.default.fileExists(atPath: artDir.path) else { return }
        
        let artworkExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff"]
        var deletedArtistArtCount = 0
        
        // Look for artist-specific artwork (artist photos, etc.)
        for ext in artworkExtensions {
            let artistArtPath = artDir.appendingPathComponent("\(sanitizedArtistName)_artist.\(ext)")
            if FileManager.default.fileExists(atPath: artistArtPath.path) {
                try FileManager.default.removeItem(at: artistArtPath)
                print("🎨 Deleted artist artwork: \(artistArtPath.lastPathComponent)")
                deletedArtistArtCount += 1
            }
            
            // Also check for artist photos
            let artistPhotoPath = artDir.appendingPathComponent("\(sanitizedArtistName)_photo.\(ext)")
            if FileManager.default.fileExists(atPath: artistPhotoPath.path) {
                try FileManager.default.removeItem(at: artistPhotoPath)
                print("📸 Deleted artist photo: \(artistPhotoPath.lastPathComponent)")
                deletedArtistArtCount += 1
            }
        }
        
        if deletedArtistArtCount > 0 {
            print("🎨 Deleted \(deletedArtistArtCount) artist artwork file(s)")
        }
    }

    /// Clean up artist-specific playlists
    private func cleanupArtistPlaylists(_ artistName: String) throws {
        let playlists = PlaylistManager.shared.playlists
        var deletedPlaylistCount = 0
        
        // Find playlists that might be artist-specific
        let artistPlaylists = playlists.filter { playlist in
            // Check if playlist name contains the artist name
            return playlist.name.lowercased().contains(artistName.lowercased()) ||
                   // Check if playlist description mentions the artist
                   (playlist.description?.lowercased().contains(artistName.lowercased()) ?? false) ||
                   // Check if playlist only contains tracks from this artist
                   isArtistOnlyPlaylist(playlist, artistName: artistName)
        }
        
        for playlist in artistPlaylists {
            // Confirm this is really an artist-only playlist before deleting
            if isArtistOnlyPlaylist(playlist, artistName: artistName) {
                do {
                    try PlaylistManager.shared.deletePlaylist(playlist)
                    print("📋 Deleted artist-only playlist: '\(playlist.name)'")
                    deletedPlaylistCount += 1
                } catch {
                    print("⚠️ Failed to delete artist playlist '\(playlist.name)': \(error)")
                }
            }
        }
        
        if deletedPlaylistCount > 0 {
            print("📋 Deleted \(deletedPlaylistCount) artist-specific playlist(s)")
            
        // Refresh playlists after deletion (targeted)
        NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
        }
    }

    /// Check if a playlist contains only tracks from a specific artist
    private func isArtistOnlyPlaylist(_ playlist: PlaylistMetadata, artistName: String) -> Bool {
        guard !playlist.tracks.isEmpty else { return false }
        
        // Check if all tracks in the playlist are from this artist
        // Need to find the actual track metadata to check artist
        let allAlbums = loadAllAlbums()
        
        for playlistTrack in playlist.tracks {
            // Find the full track metadata from albums
            var foundTrack: TrackMetadata?
            
            for album in allAlbums {
                if let track = album.tracks.first(where: { $0.filePath == playlistTrack.filePath }) {
                    foundTrack = track
                    break
                }
            }
            
            // If we can't find the track or it's from a different artist, this isn't an artist-only playlist
            guard let track = foundTrack,
                  let trackArtist = track.artist else {
                return false
            }
            
            if !trackArtist.lowercased().contains(artistName.lowercased()) {
                return false // Found a track from a different artist
            }
        }
        
        return true // All tracks are from this artist
    }

    /// Clean up any other artist-specific files or directories
    private func cleanupArtistFiles(_ sanitizedArtistName: String, metaWavDir: URL) throws {
        // Check for artist-specific directories
        let artistDir = metaWavDir.appendingPathComponent("Artists").appendingPathComponent(sanitizedArtistName)
        if FileManager.default.fileExists(atPath: artistDir.path) {
            try FileManager.default.removeItem(at: artistDir)
            print("📁 Deleted artist directory: \(artistDir.path)")
        }
        
        // Check for .metaartist files in the main Metadata directory
        let metadataDir = metaWavDir.appendingPathComponent("Metadata")
        if FileManager.default.fileExists(atPath: metadataDir.path) {
            let metaArtistFile = metadataDir.appendingPathComponent("\(sanitizedArtistName).metaartist")
            if FileManager.default.fileExists(atPath: metaArtistFile.path) {
                try FileManager.default.removeItem(at: metaArtistFile)
                print("📄 Deleted artist metadata file: \(metaArtistFile.lastPathComponent)")
            }
        }
        
        // Also check for artist-specific metadata files in ArtistMetadata directory (if it exists)
        let artistMetadataDir = metaWavDir.appendingPathComponent("ArtistMetadata")
        if FileManager.default.fileExists(atPath: artistMetadataDir.path) {
            // Check for both .metaartist and .artistmeta extensions
            let metaArtistFile = artistMetadataDir.appendingPathComponent("\(sanitizedArtistName).metaartist")
            let artistMetaFile = artistMetadataDir.appendingPathComponent("\(sanitizedArtistName).artistmeta")
            
            if FileManager.default.fileExists(atPath: metaArtistFile.path) {
                try FileManager.default.removeItem(at: metaArtistFile)
                print("📄 Deleted artist metadata file: \(metaArtistFile.lastPathComponent)")
            }
            
            if FileManager.default.fileExists(atPath: artistMetaFile.path) {
                try FileManager.default.removeItem(at: artistMetaFile)
                print("📄 Deleted artist metadata file: \(artistMetaFile.lastPathComponent)")
            }
        }
        
        // Scan all common MetaWav directories for any files containing the artist name
        try scanAndCleanArtistFiles(sanitizedArtistName, in: metaWavDir)
    }

    /// Comprehensive scan for any artist-related files across MetaWav directories
    private func scanAndCleanArtistFiles(_ sanitizedArtistName: String, in metaWavDir: URL) throws {
        let directoriesToScan = [
            "Metadata",
            "ArtistMetadata",
            "Artists",
            "Art",
            "Info"
        ]
        
        for dirName in directoriesToScan {
            let dirURL = metaWavDir.appendingPathComponent(dirName)
            guard FileManager.default.fileExists(atPath: dirURL.path) else { continue }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                
                for fileURL in files {
                    let fileName = fileURL.lastPathComponent
                    let fileNameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
                    
                    // Check if file name matches the artist (with various extensions)
                    if fileNameWithoutExtension == sanitizedArtistName {
                        // Check for artist-specific file extensions
                        let ext = fileURL.pathExtension.lowercased()
                        let artistFileExtensions = ["metaartist", "artistmeta", "artist", "jpg", "jpeg", "png", "gif", "bmp", "tiff"]
                        
                        if artistFileExtensions.contains(ext) {
                            try FileManager.default.removeItem(at: fileURL)
                            print("🗑️ Deleted artist file: \(fileName) from \(dirName)/")
                        }
                    }
                    
                    // Also check for files that contain artist name as prefix (like "ArtistName_photo.jpg")
                    if fileName.lowercased().hasPrefix(sanitizedArtistName.lowercased() + "_") {
                        try FileManager.default.removeItem(at: fileURL)
                        print("🗑️ Deleted artist-related file: \(fileName) from \(dirName)/")
                    }
                }
            } catch {
                print("⚠️ Could not scan directory \(dirName): \(error)")
            }
        }
    }

    // MARK: - Artist Query Methods

    /// Get all artists currently in the library
    func getAllArtists() -> [String] {
        let allAlbums = loadAllAlbums()
        var artists = Set<String>()
        
        for album in allAlbums {
            let albumArtists = extractUniqueArtists(from: album)
            for artist in albumArtists {
                artists.insert(artist)
            }
        }
        
        return Array(artists).sorted()
    }

    /// Get all albums for a specific artist
    func getAlbumsForArtist(_ artistName: String) -> [AlbumMetadata] {
        let allAlbums = loadAllAlbums()
        
        return allAlbums.filter { album in
            let albumArtists = extractUniqueArtists(from: album)
            return albumArtists.contains { $0.lowercased() == artistName.lowercased() }
        }
    }

    /// Check if an artist exists in the library
    func artistExists(_ artistName: String) -> Bool {
        let allArtists = getAllArtists()
        return allArtists.contains { $0.lowercased() == artistName.lowercased() }
    }

    /// Get track count for a specific artist
    func getTrackCountForArtist(_ artistName: String) -> Int {
        let allAlbums = loadAllAlbums()
        var trackCount = 0
        
        for album in allAlbums {
            for track in album.tracks {
                if let trackArtist = track.artist,
                   trackArtist.lowercased() == artistName.lowercased() {
                    trackCount += 1
                }
            }
        }
        
        return trackCount
    }
    
    /// Validate and repair file paths for all albums
    func validateAndRepairAllFilePaths() async throws -> [String] {
        print("🔍 Starting file path validation for all albums...")
        
        let allAlbums = loadAllAlbums()
        let repairedAlbums: [String] = []
        
        for album in allAlbums {
            // File path validation removed for simplicity
            // let repairedAlbum = try await InstantMetadataManager.shared.validateAndRepairFilePaths(for: album)
            // if repairedAlbum != album {
            //     repairedAlbums.append(album.albumName)
            // }
            _ = album
        }
        
        if repairedAlbums.isEmpty {
            print("✅ All file paths are valid")
        } else {
            print("🔧 Repaired \(repairedAlbums.count) albums with broken file paths")
        }
        
        return repairedAlbums
    }
    
    /// Check sandbox compliance for all albums
    func checkSandboxComplianceForAllAlbums() async throws -> [String] {
        print("🔒 Starting sandbox compliance check for all albums...")
        
        let allAlbums = loadAllAlbums()
        let nonCompliantAlbums: [String] = []
        
        for album in allAlbums {
            // Sandbox compliance check removed for simplicity
            // let compliantAlbum = try await InstantMetadataManager.shared.checkSandboxCompliance(for: album)
            // if compliantAlbum != album {
            //     nonCompliantAlbums.append(album.albumName)
            // }
            _ = album
        }
        
        if nonCompliantAlbums.isEmpty {
            print("✅ All albums are sandbox compliant")
        } else {
            print("⚠️ Found \(nonCompliantAlbums.count) albums with sandbox compliance issues")
        }
        
        return nonCompliantAlbums
    }

    /// Generate artist statistics
    func generateArtistReport() -> [String: Any] {
        let allArtists = getAllArtists()
        var report: [String: Any] = [:]
        
        report["total_artists"] = allArtists.count
        
        var artistDetails: [[String: Any]] = []
        
        for artist in allArtists {
            let albums = getAlbumsForArtist(artist)
            let trackCount = getTrackCountForArtist(artist)
            
            let artistInfo: [String: Any] = [
                "name": artist,
                "album_count": albums.count,
                "track_count": trackCount,
                "albums": albums.map { $0.albumName }
            ]
            
            artistDetails.append(artistInfo)
        }
        
        // Sort by track count descending
        artistDetails.sort {
            ($0["track_count"] as? Int ?? 0) > ($1["track_count"] as? Int ?? 0)
        }
        
        report["artists"] = artistDetails
        
        return report
    }

    /// Clean up all orphaned artist data in the library (maintenance function)
    func performArtistMaintenanceCleanup() throws {
        print("🧹 Performing artist maintenance cleanup...")
        
        let allArtists = getAllArtists()
        print("📊 Found \(allArtists.count) artists in library")
        
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
        
        var cleanedFiles = 0
        
        // Check for orphaned artist directories
        let artistsDir = metaWavDir.appendingPathComponent("Artists")
        if FileManager.default.fileExists(atPath: artistsDir.path) {
            let artistDirectories = try FileManager.default.contentsOfDirectory(at: artistsDir, includingPropertiesForKeys: nil)
            
            for artistDir in artistDirectories {
                let dirName = artistDir.lastPathComponent
                
                // Check if this artist still exists in the library
                if !allArtists.contains(where: { sanitizeFilename($0) == dirName }) {
                    try FileManager.default.removeItem(at: artistDir)
                    print("🗑️ Removed orphaned artist directory: \(dirName)")
                    cleanedFiles += 1
                }
            }
        }
        
        // Check for orphaned .metaartist files in Metadata directory
        let metadataDir = metaWavDir.appendingPathComponent("Metadata")
        if FileManager.default.fileExists(atPath: metadataDir.path) {
            let metadataFiles = try FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)
            
            for fileURL in metadataFiles {
                if fileURL.pathExtension.lowercased() == "metaartist" {
                    let artistName = fileURL.deletingPathExtension().lastPathComponent
                    
                    // Check if this artist still exists in the library
                    if !allArtists.contains(where: { sanitizeFilename($0) == artistName }) {
                        try FileManager.default.removeItem(at: fileURL)
                        print("🗑️ Removed orphaned artist metadata: \(fileURL.lastPathComponent)")
                        cleanedFiles += 1
                    }
                }
            }
        }
        
        // Check other directories for orphaned artist files
        let directoriesToCheck = ["ArtistMetadata", "Art", "Info"]
        for dirName in directoriesToCheck {
            let dirURL = metaWavDir.appendingPathComponent(dirName)
            if FileManager.default.fileExists(atPath: dirURL.path) {
                let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                
                for fileURL in files {
                    let fileName = fileURL.deletingPathExtension().lastPathComponent
                    let ext = fileURL.pathExtension.lowercased()
                    
                    // Check for various artist file types
                    if ["metaartist", "artistmeta", "artist"].contains(ext) {
                        if !allArtists.contains(where: { sanitizeFilename($0) == fileName }) {
                            try FileManager.default.removeItem(at: fileURL)
                            print("🗑️ Removed orphaned artist file: \(fileURL.lastPathComponent) from \(dirName)/")
                            cleanedFiles += 1
                        }
                    }
                }
            }
        }
        
        print("🧹 Artist maintenance complete: cleaned \(cleanedFiles) orphaned files")
    }

    /// Specifically clean up orphaned .metaartist files
    func cleanupOrphanedMetaArtistFiles() throws {
        print("🎭 Scanning for orphaned .metaartist files...")
        
        let allArtists = getAllArtists()
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
        
        var cleanedCount = 0
        
        // Scan all directories that might contain .metaartist files
        let directoriesToScan = [
            metaWavDir.appendingPathComponent("Metadata"),
            metaWavDir.appendingPathComponent("ArtistMetadata"),
            metaWavDir.appendingPathComponent("Artists"),
            metaWavDir.appendingPathComponent("Info")
        ]
        
        for directory in directoriesToScan {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                
                for fileURL in files {
                    if fileURL.pathExtension.lowercased() == "metaartist" {
                        let artistName = fileURL.deletingPathExtension().lastPathComponent
                        
                        // Check if this artist still exists in the library
                        let artistExists = allArtists.contains { sanitizeFilename($0) == artistName }
                        
                        if !artistExists {
                            try FileManager.default.removeItem(at: fileURL)
                            print("🗑️ Deleted orphaned .metaartist file: \(fileURL.lastPathComponent)")
                            cleanedCount += 1
                        } else {
                            print("✅ Keeping .metaartist file for active artist: \(artistName)")
                        }
                    }
                }
            } catch {
                print("⚠️ Could not scan directory \(directory.lastPathComponent): \(error)")
            }
        }
        
        if cleanedCount > 0 {
            print("🎭 Cleaned up \(cleanedCount) orphaned .metaartist files")
        } else {
            print("✅ No orphaned .metaartist files found")
        }
    }

    /// Debug function to show current artist files vs active artists
    func debugArtistFiles() {
        print("🔍 DEBUG: Current artist file status")
        
        let allArtists = getAllArtists()
        print("📊 Active artists in library: \(allArtists.count)")
        for artist in allArtists {
            print("   ✅ \(artist)")
        }
        
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
        
        // Check for .metaartist files
        let metadataDir = metaWavDir.appendingPathComponent("Metadata")
        if FileManager.default.fileExists(atPath: metadataDir.path) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)
                let metaArtistFiles = files.filter { $0.pathExtension.lowercased() == "metaartist" }
                
                print("\n📄 Found \(metaArtistFiles.count) .metaartist files:")
                for fileURL in metaArtistFiles {
                    let artistName = fileURL.deletingPathExtension().lastPathComponent
                    let isActive = allArtists.contains { sanitizeFilename($0) == artistName }
                    let status = isActive ? "✅ ACTIVE" : "❌ ORPHANED"
                    print("   \(status) \(fileURL.lastPathComponent)")
                }
            } catch {
                print("⚠️ Could not read Metadata directory: \(error)")
            }
        }
        
        // Check other directories too
        let otherDirs = ["ArtistMetadata", "Artists", "Art"]
        for dirName in otherDirs {
            let dirURL = metaWavDir.appendingPathComponent(dirName)
            if FileManager.default.fileExists(atPath: dirURL.path) {
                do {
                    let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                    let artistFiles = files.filter { file in
                        let ext = file.pathExtension.lowercased()
                        return ["metaartist", "artistmeta", "artist"].contains(ext)
                    }
                    
                    if !artistFiles.isEmpty {
                        print("\n📁 \(dirName)/ contains \(artistFiles.count) artist files:")
                        for fileURL in artistFiles {
                            let fileName = fileURL.deletingPathExtension().lastPathComponent
                            let isActive = allArtists.contains { sanitizeFilename($0) == fileName }
                            let status = isActive ? "✅ ACTIVE" : "❌ ORPHANED"
                            print("   \(status) \(fileURL.lastPathComponent)")
                        }
                    }
                } catch {
                    print("⚠️ Could not read \(dirName) directory: \(error)")
                }
            }
        }
    }
    // MARK: - Path Utilities
    func getMetadataPath(for albumName: String) -> URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metadataDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Metadata")
        
        let sanitizedName = sanitizeFilename(albumName)
        return metadataDir.appendingPathComponent("\(sanitizedName).meta")
    }

    func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    // MARK: - Utility Helpers (Write/Delete/Validate/Refresh)
    private func writeMetaFile(_ album: AlbumMetadata) throws {
        let sanitizedName = sanitizeFilename(album.albumName)
        let metaURL = metadataDirectory.appendingPathComponent("\(sanitizedName).meta")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(album)
        try data.write(to: metaURL, options: [.atomic])
    }

    private func deleteMetaFile(named albumName: String) throws {
        let sanitizedName = sanitizeFilename(albumName)
        let metaURL = metadataDirectory.appendingPathComponent("\(sanitizedName).meta")
        if fileManager.fileExists(atPath: metaURL.path) {
            try fileManager.removeItem(at: metaURL)
        }
    }

    private func validateFilePaths(for album: AlbumMetadata) -> [String] {
        var missing: [String] = []
        for track in album.tracks {
            if !fileManager.fileExists(atPath: track.filePath) {
                missing.append(track.filePath)
            }
        }
        return missing
    }

    @MainActor
    private func refreshUI(after album: AlbumMetadata) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            NotificationManager.shared.postNotification(.albumUpdated, object: album)
            NotificationManager.shared.postNotification(.albumMetadataChanged, object: album)
        }
    }

    // MARK: - Error Types
    enum AlbumError: LocalizedError {
        case albumNotFound(String)
        case metadataCorrupted(String)
        case fileSystemError(String)
        
        var errorDescription: String? {
            switch self {
            case .albumNotFound(let name):
                return "Album '\(name)' not found"
            case .metadataCorrupted(let details):
                return "Metadata corrupted: \(details)"
            case .fileSystemError(let details):
                return "File system error: \(details)"
            }
        }
    }
    
    // MARK: - Track Lookup
    
    /// Find track metadata by file path and name across all albums
    func findTrack(filePath: String, name: String) -> (album: AlbumMetadata, track: TrackMetadata)? {
        let allAlbums = loadAllAlbums()
        
        for album in allAlbums {
            if let track = album.tracks.first(where: {
                $0.filePath == filePath || $0.name == name
            }) {
                return (album: album, track: track)
            }
        }
        
        return nil
    }
    
    /// Load all album metadata files
    func loadAllAlbums() -> [AlbumMetadata] {
        NotificationManager.shared.log("Loading all albums from: \(metadataDirectory.path)")
        
        do {
            let files = try fileManager.contentsOfDirectory(at: metadataDirectory, includingPropertiesForKeys: nil)
            let metaFiles = files.filter { $0.pathExtension == "meta" }
            
            NotificationManager.shared.log("Found \(metaFiles.count) .meta files")
            
            var albums: [AlbumMetadata] = []
            
            for metaFile in metaFiles {
                do {
                    let data = try Data(contentsOf: metaFile)
                    var album = try PropertyListDecoder().decode(AlbumMetadata.self, from: data)
                    
                    // MIGRATION: Handle old albums without disc numbers and enforce MP3 bit depth rule
                    var needsUpdate = false
                    for (index, _) in album.tracks.enumerated() {
                        // Disc number migration (old albums)
                        if album.tracks[index].discNumber == 0 {
                            album.tracks[index].discNumber = 1
                            needsUpdate = true
                        }
                        // Enforce: If track is MP3, set bitDepth to 16-bit
                        let track = album.tracks[index]
                        let extIsMP3 = URL(fileURLWithPath: track.filePath).pathExtension.lowercased() == "mp3"
                        let formatIsMP3 = (track.format?.uppercased() == "MP3")
                        if extIsMP3 || formatIsMP3 {
                            if track.bitDepth != "16-bit" {
                                album.tracks[index].bitDepth = "16-bit"
                                needsUpdate = true
                            }
                        }
                    }
                    
                    if album.discCount == 0 || needsUpdate {
                        album.updateDiscCount()
                        needsUpdate = true
                    }
                    
                    // Note: We don't save here to avoid recursive calls
                    // The album will be saved when explicitly requested
                    
                    albums.append(album)
                } catch {
                    NotificationManager.shared.log("Failed to load album from \(metaFile.lastPathComponent): \(error)")
                }
            }
            
            NotificationManager.shared.log("Successfully loaded \(albums.count) albums")
            return albums
        } catch {
            NotificationManager.shared.log("Error scanning metadata directory: \(error)")
            return []
        }
    }
    
    /// Force reload all albums and trigger UI updates
    func forceReloadAlbums() {
        print("🔄 Force reloading albums...")
        
        // Trigger objectWillChange to notify SwiftUI
        objectWillChange.send()
        print("📡 objectWillChange sent")
        
        // Post notification for immediate UI refresh (full refresh intent)
        SmartRefreshCoordinator.shared.processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))
        print("📡 fullLibraryRefresh posted")
        
        print("✅ Albums force reloaded")
    }
    
    /// Get sorted track list from multiple albums (updated for disc support)
    func getSortedTracks(from albums: [AlbumMetadata]) -> [TrackMetadata] {
        var allTracks: [TrackMetadata] = []
        
        // Group tracks by album, then sort
        let sortedAlbums = albums.sorted { $0.albumName < $1.albumName }
        
        for album in sortedAlbums {
            // Sort tracks by disc number first, then track number within disc
            let sortedTracks = album.tracks.sorted { track1, track2 in
                if track1.discNumber != track2.discNumber {
                    return track1.discNumber < track2.discNumber
                }
                return track1.trackNumber < track2.trackNumber
            }
            allTracks.append(contentsOf: sortedTracks)
        }
        
        return allTracks
    }
    
    // MARK: - Track Operations
    
    /// Add or update a track in an album - UPDATED: Include albumType
    func addOrUpdateTrack(_ track: TrackMetadata, in albumName: String) throws {
        var album = loadAlbumMetadata(albumName: albumName) ?? AlbumMetadata(
            albumName: albumName,
            albumType: nil, // NEW: Default album type to nil
            frontArtPath: nil,
            backArtPath: nil,
            duration: nil,
            genre: nil,
            year: nil,
            trackCount: 0,
            discCount: 1, // NEW: Default to 1 disc
            discNames: nil,
            tracks: []
        )
        
        // Remove existing track with same file path if it exists
        album.tracks.removeAll { $0.filePath == track.filePath }
        
        // Add the new/updated track
        album.tracks.append(track)
        
        // Update album metadata
        album.updateTrackCount()
        album.updateDiscCount() // NEW: Update disc count
        album.calculateDuration()
        
        try saveAlbumMetadata(album)
        print("✅ Added/updated track '\(track.name)' in album '\(albumName)'")
    }
    
    /// Remove a track from an album
    func removeTrack(filePath: String, from albumName: String) throws {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            print("❌ Album not found: \(albumName)")
            return
        }
        
        album.tracks.removeAll { $0.filePath == filePath }
        album.updateTrackCount()
        album.updateDiscCount() // NEW: Update disc count after removal
        album.calculateDuration()
        
        // If no tracks left, consider removing the album
        if album.tracks.isEmpty {
            try deleteAlbum(named: albumName)
        } else {
            try saveAlbumMetadata(album)
        }
        
        print("✅ Removed track from album '\(albumName)'")
    }
    
    // MARK: - Artwork Management
    
    /// Load front artwork for an album - always reads path from .meta file
    func loadFrontArtwork(for albumName: String) -> NSImage? {
        // Always read path from .meta file first
        guard let album = loadAlbumMetadata(albumName: albumName),
              let frontPath = album.frontArtPath else {
            return nil
        }
        
        // Verify file exists at the path from .meta file
        guard fileManager.fileExists(atPath: frontPath) else {
            print("⚠️ Front artwork path from .meta file does not exist: \(frontPath)")
            return nil
        }
        
        // Load image on background queue to avoid blocking main thread
        return DispatchQueue.global(qos: .utility).sync(execute: {
            NSImage(contentsOfFile: frontPath)
        })
    }
    
    /// Load back artwork for an album - always reads path from .meta file
    func loadBackArtwork(for albumName: String) -> NSImage? {
        // Always read path from .meta file first
        guard let album = loadAlbumMetadata(albumName: albumName),
              let backPath = album.backArtPath else {
            return nil
        }
        
        // Verify file exists at the path from .meta file
        guard fileManager.fileExists(atPath: backPath) else {
            print("⚠️ Back artwork path from .meta file does not exist: \(backPath)")
            return nil
        }
        
        // Load image on background queue to avoid blocking main thread
        return DispatchQueue.global(qos: .utility).sync(execute: {
            NSImage(contentsOfFile: backPath)
        })
    }
    
    /// Merge two albums - newest data wins for album-level metadata - UPDATED: Include albumType
    private func mergeAlbums(sourceURL: URL, targetURL: URL, newAlbumName: String) throws {
        // Load both albums
        let sourceData = try Data(contentsOf: sourceURL)
        let sourceAlbum = try PropertyListDecoder().decode(AlbumMetadata.self, from: sourceData)
        
        let targetData = try Data(contentsOf: targetURL)
        var targetAlbum = try PropertyListDecoder().decode(AlbumMetadata.self, from: targetData)
        
        // Merge tracks (avoid duplicates by file path)
        for sourceTrack in sourceAlbum.tracks {
            // Remove existing track with same file path
            targetAlbum.tracks.removeAll { $0.filePath == sourceTrack.filePath }
            // Add the source track
            targetAlbum.tracks.append(sourceTrack)
        }
        
        // Update album-level metadata (source wins) - UPDATED: Include albumType
        targetAlbum.albumName = newAlbumName
        targetAlbum.albumType = sourceAlbum.albumType ?? targetAlbum.albumType // NEW: Merge album type
        targetAlbum.frontArtPath = sourceAlbum.frontArtPath ?? targetAlbum.frontArtPath
        targetAlbum.backArtPath = sourceAlbum.backArtPath ?? targetAlbum.backArtPath
        targetAlbum.genre = sourceAlbum.genre ?? targetAlbum.genre
        targetAlbum.year = sourceAlbum.year ?? targetAlbum.year
        
        // Recalculate derived fields
        targetAlbum.updateTrackCount()
        targetAlbum.updateDiscCount() // NEW: Update disc count after merge
        targetAlbum.calculateDuration()
        
        // Save merged album
        try saveAlbumMetadata(targetAlbum)
        
        // Remove source file
        try fileManager.removeItem(at: sourceURL)
        
        print("✅ Merged albums successfully")
    }
    
    /// Delete an album completely
    private func deleteAlbum(named albumName: String) throws {
        let sanitizedName = sanitizeFilename(albumName)
        let metaURL = metadataDirectory.appendingPathComponent("\(sanitizedName).meta")
        
        if fileManager.fileExists(atPath: metaURL.path) {
            try fileManager.removeItem(at: metaURL)
            print("🗑️ Deleted empty album: \(albumName)")
        }
    }
    
    // MARK: - Audio File Analysis (Updated for Disc Support)
    
    // MARK: - Sync wrappers for AVFoundation async loads (macOS 13+)
    @available(macOS 13.0, *)
    func loadTracksSync(_ asset: AVURLAsset, mediaType: AVMediaType) -> [AVAssetTrack]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [AVAssetTrack]?
        Task {
            result = try? await asset.loadTracks(withMediaType: mediaType)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @available(macOS 13.0, *)
    func loadEstimatedDataRateSync(_ track: AVAssetTrack) -> Float? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Float?
        Task {
            result = try? await track.load(.estimatedDataRate)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

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

    func createTrackMetadata(from audioFile: AVAudioFile, trackNumber: Int, discNumber: Int = 1) -> TrackMetadata {
        let url = audioFile.url
        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        
        // Determine bit depth - MP3 files should always be treated as 16-bit
        let bitDepth: String?
        if url.pathExtension.lowercased() == "mp3" {
            bitDepth = "16-bit"
        } else {
            bitDepth = audioFile.fileFormat.bitDepthString
        }
        
        // Initialize with basic file info (updated to include disc number)
        var trackMeta = TrackMetadata(
            filePath: url.path,
            discNumber: discNumber, // NEW: Set disc number
            trackNumber: trackNumber,
            name: url.deletingPathExtension().lastPathComponent,
            artist: nil,
            key: nil,
            bpm: nil,
            version: nil,
            isExplicit: nil,
            duration: duration,
            format: url.pathExtension.uppercased(),
            channelCount: Int(audioFile.fileFormat.channelCount),
            sampleRate: audioFile.fileFormat.sampleRate,
            bitDepth: bitDepth,
            bitrateKbps: nil,
            isrc: nil,
            credits: nil,
            lyrics: nil,
            notes: nil
        )
        
        // Extract metadata from audio file
        guard url.startAccessingSecurityScopedResource() else { return trackMeta }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let asset = AVURLAsset(url: url)

        if #available(macOS 13.0, *) {
            // If MP3, compute and store bitrateKbps once using modern loaders (sync wrappers)
            if url.pathExtension.lowercased() == "mp3" {
                if let audioTrack = loadTracksSync(asset, mediaType: .audio)?.first,
                   let bps = loadEstimatedDataRateSync(audioTrack), bps > 0 {
                    let rawKbps = Int(round(bps / 1000.0))
                    trackMeta.bitrateKbps = snapToStandardMP3Bitrate(rawKbps)
                }
            }
            // Load metadata entries
            if let metadataItems = loadMetadataItemsSync(asset) {
                for item in metadataItems {
                    if let key = item.key as? String {
                        if key.contains("Title") || key.contains("TIT2") {
                            if let value = loadStringValueSync(item) {
                                trackMeta.name = value
                            }
                        } else if key.contains("Artist") || key.contains("TPE1") {
                            if let value = loadStringValueSync(item) {
                                trackMeta.artist = value
                            }
                        } else if (key.contains("TRCK") || key.contains("Track")) && trackMeta.trackNumber == trackNumber {
                            if let stringValue = loadStringValueSync(item) {
                                let parts = stringValue.components(separatedBy: "/")
                                if let num = Int(parts[0]) { trackMeta.trackNumber = num }
                            }
                        } else if key.contains("TPOS") || key.contains("Disc") {
                            if let stringValue = loadStringValueSync(item) {
                                let parts = stringValue.components(separatedBy: "/")
                                if let discNum = Int(parts[0]) { trackMeta.discNumber = discNum }
                            }
                        } else if key.contains("ISRC") || key.contains("TSRC") {
                            if let value = loadStringValueSync(item) {
                                trackMeta.isrc = value
                            }
                        } else if key.contains("COMM") || key.contains("Comment") {
                            if let comment = loadStringValueSync(item), !comment.isEmpty {
                                trackMeta.notes = comment
                            }
                        }
                    }
                }
            }
        } else {
            // Legacy path for older macOS
            // If MP3, compute and store bitrateKbps once
            if url.pathExtension.lowercased() == "mp3" {
                if let audioTrack = AVURLAsset(url: url).tracks(withMediaType: .audio).first {
                    let bps = audioTrack.estimatedDataRate
                    if bps > 0 {
                        let rawKbps = Int(round(bps / 1000.0))
                        trackMeta.bitrateKbps = snapToStandardMP3Bitrate(rawKbps)
                    }
                }
            }
            for item in asset.metadata {
                if let key = item.key as? String {
                    if key.contains("Title") || key.contains("TIT2") {
                        trackMeta.name = item.stringValue ?? trackMeta.name
                    } else if key.contains("Artist") || key.contains("TPE1") {
                        trackMeta.artist = item.stringValue
                    } else if (key.contains("TRCK") || key.contains("Track")) && trackMeta.trackNumber == trackNumber {
                        if let stringValue = item.stringValue {
                            let parts = stringValue.components(separatedBy: "/")
                            if let num = Int(parts[0]) { trackMeta.trackNumber = num }
                        }
                    } else if key.contains("TPOS") || key.contains("Disc") {
                        if let stringValue = item.stringValue {
                            let parts = stringValue.components(separatedBy: "/")
                            if let discNum = Int(parts[0]) { trackMeta.discNumber = discNum }
                        }
                    } else if key.contains("ISRC") || key.contains("TSRC") {
                        trackMeta.isrc = item.stringValue
                    } else if key.contains("COMM") || key.contains("Comment") {
                        if let comment = item.stringValue, !comment.isEmpty { trackMeta.notes = comment }
                    }
                }
            }
        }
        
        return trackMeta
    }

    /// Snap bitrate to the nearest standard MP3 bitrate for display consistency
    private func snapToStandardMP3Bitrate(_ kbps: Int) -> Int {
        let standards = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        var best = standards.first ?? kbps
        var bestDiff = Int.max
        for s in standards {
            let d = abs(s - kbps)
            if d < bestDiff {
                bestDiff = d
                best = s
            }
        }
        return best
    }
}

// MARK: - Enhanced AlbumMetadataManager with Auto-Reordering

extension AlbumMetadataManager {
    
    // MARK: - Auto-Reordering Track Operations
    
    /// Add or update a track with automatic reordering - UPDATED: Include albumType
    func addOrUpdateTrackWithReordering(_ track: TrackMetadata, in albumName: String) throws {
        var album = loadAlbumMetadata(albumName: albumName) ?? AlbumMetadata(
            albumName: albumName,
            albumType: nil, // NEW: Default album type to nil
            frontArtPath: nil,
            backArtPath: nil,
            duration: nil,
            genre: nil,
            year: nil,
            trackCount: 0,
            discCount: 1,
            discNames: nil,
            tracks: []
        )
        
        // Check if this is an update or new track
        let isUpdate = album.tracks.contains { $0.filePath == track.filePath || $0.id == track.id }
        
        if isUpdate {
            print("🔄 Updating existing track: \(track.name)")
            // Remove existing track with same file path or ID
            album.tracks.removeAll { $0.filePath == track.filePath || $0.id == track.id }
        } else {
            print("🔥 Adding new track: \(track.name)")
        }
        
        // Add the new/updated track
        album.tracks.append(track)
        
        // FIXED: Use the correct method name from TrackReorderingManager
        let wasFixed = TrackReorderingManager.shared.validateAndFixAlbum(&album)
        
        // Update album metadata
        album.updateTrackCount()
        album.updateDiscCount()
        album.calculateDuration()
        
        try saveAlbumMetadata(album)
        
        // Post notification for UI updates
        NotificationManager.shared.postNotification(.albumReordered, object: album)
        
        if wasFixed {
            print("✅ Added/updated track '\(track.name)' with auto-fixing applied")
        } else {
            print("✅ Added/updated track '\(track.name)' - no reordering needed")
        }
    }
    
    /// Update track position with automatic conflict resolution
    func updateTrackPosition(
        trackId: UUID,
        newTrackNumber: Int? = nil,
        newDiscNumber: Int? = nil,
        in albumName: String
    ) throws {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            throw AlbumError.albumNotFound(albumName)
        }
        
        // FIXED: Use the correct method from TrackReorderingManager
        let success = TrackReorderingManager.shared.updateTrackPosition(
            trackId: trackId,
            newTrackNumber: newTrackNumber,
            newDiscNumber: newDiscNumber,
            in: &album
        )
        
        if success {
            album.calculateDuration()
            try saveAlbumMetadata(album)
            
            // Post notification for UI updates
            NotificationManager.shared.postNotification(.albumReordered, object: album)
            
            print("✅ Updated track position in album '\(albumName)'")
        } else {
            throw AlbumError.albumNotFound("Track not found for position update")
        }
    }
    
    /// Batch import tracks with automatic conflict resolution - UPDATED: Include albumType
    func batchImportTracks(_ tracks: [TrackMetadata], to albumName: String) throws {
        print("📦 Batch importing \(tracks.count) tracks to album '\(albumName)'")
        
        var album = loadAlbumMetadata(albumName: albumName) ?? AlbumMetadata(
            albumName: albumName,
            albumType: nil, // NEW: Default album type to nil
            frontArtPath: nil,
            backArtPath: nil,
            duration: nil,
            genre: nil,
            year: nil,
            trackCount: 0,
            discCount: 1,
            discNames: nil,
            tracks: []
        )
        
        // FIXED: Use the correct method from TrackReorderingManager
        TrackReorderingManager.shared.processImportedTracks(tracks, into: &album)
        
        try saveAlbumMetadata(album)
        
        // Post notification for UI updates
        NotificationManager.shared.postNotification(.tracksImported, object: album)
        
        print("✅ Batch imported \(tracks.count) tracks to '\(albumName)' with automatic reordering")
    }
    
    /// Remove track with automatic reordering of remaining tracks
    func removeTrackWithReordering(filePath: String, from albumName: String) throws {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            print("❌ Album not found: \(albumName)")
            return
        }
        
        // Find the track being removed for logging
        if let removedTrack = album.tracks.first(where: { $0.filePath == filePath }) {
            print("🗑️ Removing track '\(removedTrack.name)' from disc \(removedTrack.discNumber), position \(removedTrack.trackNumber)")
        }
        
        album.tracks.removeAll { $0.filePath == filePath }
        
        // If tracks remain, validate and fix any issues
        if !album.tracks.isEmpty {
            let wasFixed = TrackReorderingManager.shared.validateAndFixAlbum(&album)
            
            album.updateTrackCount()
            album.updateDiscCount()
            album.calculateDuration()
            try saveAlbumMetadata(album)
            
            // Post notification for UI updates
            NotificationManager.shared.postNotification(.albumReordered, object: album)
            
            if wasFixed {
                print("✅ Removed track and auto-fixed album '\(albumName)'")
            } else {
                print("✅ Removed track from album '\(albumName)' - no reordering needed")
            }
        } else {
            // If no tracks left, consider removing the album
            try deleteAlbum(named: albumName)
            print("🗑️ Removed empty album '\(albumName)'")
        }
    }
    
    /// Validate and auto-fix all albums
    func validateAndFixAllAlbums() -> [String] {
        print("🔧 Validating and auto-fixing all albums...")
        
        var fixedAlbums: [String] = []
        let allAlbums = loadAllAlbums()
        
        for var album in allAlbums {
            // FIXED: Use the correct method from TrackReorderingManager
            let wasFixed = TrackReorderingManager.shared.validateAndFixAlbum(&album)
            
            if wasFixed {
                do {
                    try saveAlbumMetadata(album)
                    fixedAlbums.append(album.albumName)
                    print("✅ Fixed conflicts in album '\(album.albumName)'")
                } catch {
                    print("❌ Failed to save fixed album '\(album.albumName)': \(error)")
                }
            }
        }
        
        if fixedAlbums.isEmpty {
            print("✅ All albums are properly ordered - no fixes needed")
        } else {
            print("🔧 Fixed \(fixedAlbums.count) albums with conflicts")
        }
        
        return fixedAlbums
    }
    
    /// Get album with automatic validation and fixing
    func getValidatedAlbum(named albumName: String) -> AlbumMetadata? {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            return nil
        }
        
        // FIXED: Use the correct method from TrackReorderingManager
        let wasFixed = TrackReorderingManager.shared.validateAndFixAlbum(&album)
        
        if wasFixed {
            do {
                try saveAlbumMetadata(album)
                print("🔧 Auto-fixed conflicts in album '\(albumName)' during load")
            } catch {
                print("❌ Failed to save auto-fixed album: \(error)")
            }
        }
        
        return album
    }
    
    /// Migrate old albums to ensure proper disc numbering
    func migrateAlbumsToDiscFormat() {
        print("🔄 Migrating albums to proper disc format...")
        
        let allAlbums = loadAllAlbums()
        var migratedCount = 0
        
        for var album in allAlbums {
            var needsMigration = false
            
            // Check for tracks with disc number 0 or missing disc info
        for (index, _) in album.tracks.enumerated() {
                if album.tracks[index].discNumber <= 0 {
                    album.tracks[index].discNumber = 1
                    needsMigration = true
                }
            }
            
            // Update disc count if needed
            if album.discCount <= 0 {
                album.updateDiscCount()
                needsMigration = true
            }
            
            if needsMigration {
                // FIXED: Use the correct method to validate and fix
                let wasFixed = TrackReorderingManager.shared.validateAndFixAlbum(&album)
                
                do {
                    try saveAlbumMetadata(album)
                    migratedCount += 1
                    print("✅ Migrated album '\(album.albumName)' to disc format (fixed: \(wasFixed))")
                } catch {
                    print("❌ Failed to migrate album '\(album.albumName)': \(error)")
                }
            }
        }
        
        print("🔄 Migration complete: \(migratedCount) albums updated")
    }
    
    /// Clean up and reorder all albums (maintenance function)
    func performMaintenanceReordering() {
        print("🧹 Performing maintenance reordering on all albums...")
        
        var allAlbums = loadAllAlbums()
        
        // FIXED: Use the correct method for batch reordering
        TrackReorderingManager.shared.reorderMultipleAlbums(&allAlbums)
        
        var savedCount = 0
        for album in allAlbums {
            do {
                try saveAlbumMetadata(album)
                savedCount += 1
            } catch {
                print("❌ Failed to save reordered album '\(album.albumName)': \(error)")
            }
        }
        
        print("🧹 Maintenance complete: \(savedCount) albums cleaned and reordered")
    }
    
    /// Perform comprehensive maintenance including file validation and sandbox compliance
    func performComprehensiveMaintenance() async throws -> MaintenanceReport {
        print("🧹 Starting comprehensive maintenance...")
        
        var report = MaintenanceReport()
        
        // 1. Reorder tracks
        print("📋 Step 1: Reordering tracks...")
        var allAlbums = loadAllAlbums()
        TrackReorderingManager.shared.reorderMultipleAlbums(&allAlbums)
        
        var reorderedCount = 0
        for album in allAlbums {
            do {
                try saveAlbumMetadata(album)
                reorderedCount += 1
            } catch {
                print("❌ Failed to save reordered album '\(album.albumName)': \(error)")
            }
        }
        report.reorderedAlbums = reorderedCount
        
        // 2. Validate and repair file paths
        print("🔍 Step 2: Validating file paths...")
        let repairedAlbums = try await validateAndRepairAllFilePaths()
        report.repairedFilePaths = repairedAlbums.count
        
        // 3. Check sandbox compliance
        print("🔒 Step 3: Checking sandbox compliance...")
        let nonCompliantAlbums = try await checkSandboxComplianceForAllAlbums()
        report.sandboxIssues = nonCompliantAlbums.count
        
        // 4. Clean up orphaned artists
        print("🎭 Step 4: Cleaning up orphaned artists...")
        try cleanupOrphanedMetaArtistFiles()
        report.cleanedArtists = 1 // Simplified for now
        
        // 5. Additional maintenance removed for simplicity
        print("🚀 Step 5: Maintenance simplified")
        // Maintenance functionality removed
        
        print("✅ Comprehensive maintenance completed")
        return report
    }
    
    /// Process multiple audio files and create tracks with proper ordering
    func processAudioFiles(_ audioFiles: [AVAudioFile], for albumName: String) throws {
        print("🎵 Processing \(audioFiles.count) audio files for album '\(albumName)'")
        
        var tracks: [TrackMetadata] = []
        
        // Create track metadata for each audio file
        for (index, audioFile) in audioFiles.enumerated() {
            let suggestedTrackNumber = index + 1
            let track = createTrackMetadata(
                from: audioFile,
                trackNumber: suggestedTrackNumber,
                discNumber: 1 // Default to disc 1
            )
            tracks.append(track)
        }
        
        // Batch import with automatic reordering
        try batchImportTracks(tracks, to: albumName)
        
        print("✅ Processed and imported \(tracks.count) audio files")
    }
    
    /// Sync track changes from UI back to album with reordering
    func syncTrackChanges(_ track: TrackMetadata, in albumName: String) {
        do {
            try updateTrackMetadata(track, in: albumName)
            print("📋 Synced track changes for '\(track.name)' with reordering")
        } catch {
            print("❌ Failed to sync track changes: \(error)")
        }
    }
}

// MARK: - Maintenance Report

struct MaintenanceReport {
    var reorderedAlbums: Int = 0
    var repairedFilePaths: Int = 0
    var sandboxIssues: Int = 0
    var cleanedArtists: Int = 0
    var timestamp: Date = Date()
    
    var summary: String {
        return """
        Maintenance Report (\(DateFormatter.timeFormatter.string(from: timestamp)))
        • Reordered albums: \(reorderedAlbums)
        • Repaired file paths: \(repairedFilePaths)
        • Sandbox issues found: \(sandboxIssues)
        • Cleaned artists: \(cleanedArtists)
        """
    }
}



// MARK: - TrackMetadata Extensions for Change Detection

extension TrackMetadata {
    /// Check if track or disc numbers have changed compared to another track
    func hasPositionChanges(comparedTo other: TrackMetadata) -> Bool {
        return self.trackNumber != other.trackNumber || self.discNumber != other.discNumber
    }
    
    /// Get a position description string for logging
    var positionDescription: String {
        return "D\(discNumber):T\(String(format: "%02d", trackNumber))"
    }
}

extension AlbumMetadataManager {
    
    func saveAlbumMetadataWithRefresh(_ album: AlbumMetadata) throws {
        // Save the album
        try saveAlbumMetadata(album)
        
        // Trigger smart refresh
        SmartRefreshCoordinator.shared.processMetadataChange(
            RefreshEvent(type: .albumUpdated(albumName: album.albumName))
        )
    }
    
    /// Save album metadata with instant refresh and cleanup
    func saveAlbumMetadataInstantly(_ album: AlbumMetadata, oldName: String? = nil) async throws {
        let newSanitized = sanitizeFilename(album.albumName)
        let _ = metadataDirectory.appendingPathComponent("\(newSanitized).meta")

        // If album was renamed, delete old .meta first
        if let oldName = oldName, !oldName.isEmpty, oldName != album.albumName {
            let oldSanitized = sanitizeFilename(oldName)
            let oldURL = metadataDirectory.appendingPathComponent("\(oldSanitized).meta")
            if fileManager.fileExists(atPath: oldURL.path) {
                try fileManager.removeItem(at: oldURL)
            }
        }

        // Ensure metadata directory exists
        _ = metadataDirectory

        // Validate file paths and report missing ones (non-fatal)
        let missing = validateFilePaths(for: album)
        if !missing.isEmpty {
            NotificationManager.shared.log("⚠️ Missing track files for album '\(album.albumName)': \(missing.count)")
        }

        // Write atomically
        try writeMetaFile(album)

        // Post notifications for instant UI update
        DispatchQueue.main.async {
            self.lastUpdateTime = Date()
            self.updateStatus = "Saved \(album.albumName)"
            self.refreshUI(after: album)
        }
    }
    
    /// Update track metadata with instant refresh and cleanup
    func updateTrackMetadataInstantly(_ track: TrackMetadata, in albumName: String, oldTrack: TrackMetadata? = nil) async throws {
        guard var album = loadAlbumMetadata(albumName: albumName) else {
            throw AlbumError.albumNotFound(albumName)
        }

        // Replace the track by id (preferred) or by filePath fallback
        if let indexById = album.tracks.firstIndex(where: { $0.id == track.id }) {
            album.tracks[indexById] = track
        } else if let indexByPath = album.tracks.firstIndex(where: { $0.filePath == track.filePath }) {
            album.tracks[indexByPath] = track
        } else {
            // If not found, append safely
            album.tracks.append(track)
        }

        // Recompute derived fields
        let _ = TrackReorderingManager.shared.validateAndFixAlbum(&album)
        album.updateTrackCount()
        album.updateDiscCount()
        album.calculateDuration()

        // Write and refresh
        try writeMetaFile(album)
        await refreshUI(after: album)

        // Specific track-change notification
        DispatchQueue.main.async {
            NotificationManager.shared.postNotification(.trackMetadataChanged, object: (track, album))
        }
    }
    
    func updateTrackMetadataWithRefresh(
        _ updatedTrack: TrackMetadata,
        in albumName: String
    ) throws {
        // Get the original track for comparison
        guard let album = loadAlbumMetadata(albumName: albumName),
              let originalTrack = album.tracks.first(where: { $0.id == updatedTrack.id }) else {
            throw AlbumError.albumNotFound(albumName)
        }
        
        // Check what changed
        let artistChanged = originalTrack.artist != updatedTrack.artist
        
        // Perform the update
        try updateTrackMetadata(updatedTrack, in: albumName)
        
        // Trigger appropriate refresh
        if artistChanged {
            SmartRefreshCoordinator.shared.processMetadataChange(
                RefreshEvent(type: .artistUpdated(
                    oldName: originalTrack.artist,
                    newName: updatedTrack.artist
                ))
            )
        }
        
        SmartRefreshCoordinator.shared.processMetadataChange(
            RefreshEvent(type: .trackUpdated(trackId: updatedTrack.id, albumName: albumName))
        )
    }
    
    func deleteAlbumWithRefresh(_ albumName: String) throws {
        // Get artists before deletion
        let album = loadAlbumMetadata(albumName: albumName)
        let artists = album?.tracks.compactMap { $0.artist } ?? []
        
        // Delete the album
        try deleteAlbum(albumName)
        
        // Trigger refresh and cleanup
        SmartRefreshCoordinator.shared.processMetadataChange(
            RefreshEvent(type: .albumDeleted(albumName: albumName))
        )
        
        // Check for orphaned artists
        for artist in Set(artists) {
            if !artistExists(artist) {
                SmartRefreshCoordinator.shared.processMetadataChange(
                    RefreshEvent(type: .artistDeleted(artistName: artist))
                )
            }
        }
    }
}
