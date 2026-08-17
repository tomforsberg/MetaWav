// ArtistProfile.swift - COMPLETE: Organized Discography with Conditional Sections
import SwiftUI

// MARK: - Artist Profile Data Structure
struct ArtistProfile: Codable, Identifiable {
    let id = UUID()
    var name: String
    var profileImagePath: String?
    var bio: String?
    var roles: [String] = []
    var albumCount: Int
    var trackCount: Int
    var associatedAlbums: [String]
    
    mutating func updateCounts(from albums: [AlbumMetadata]) {
        let artistAlbums = albums.filter { album in
            album.tracks.contains { $0.artist == self.name }
        }
        
        self.albumCount = artistAlbums.count
        self.trackCount = artistAlbums.reduce(0) { total, album in
            total + album.tracks.filter { $0.artist == self.name }.count
        }
        
        self.associatedAlbums = artistAlbums.map { $0.albumName }
    }
    
    enum CodingKeys: String, CodingKey {
        case name, profileImagePath, bio, roles, albumCount, trackCount, associatedAlbums
    }
}

// MARK: - Artist Roles
struct ArtistRoles {
    static let predefinedRoles = [
        "Singer", "Rapper", "Producer", "Songwriter", "Composer", "Musician",
        "Vocalist", "Instrumentalist", "DJ", "Beat Maker", "Sound Engineer",
        "Mixing Engineer", "Mastering Engineer", "Arranger", "Conductor",
        "Multi-instrumentalist", "Session Musician", "Recording Artist", "Performer", "Artist"
    ].sorted()
}

// MARK: - Enhanced Artist Manager
class ArtistManager: ObservableObject {
    static let shared = ArtistManager()
    
    @Published var artists: [ArtistProfile] = []
    
    private init() {}
    
    private var artistsDirectoryURL: URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let artistsDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Artists")
        
        if !FileManager.default.fileExists(atPath: artistsDir.path) {
            do {
                try FileManager.default.createDirectory(at: artistsDir, withIntermediateDirectories: true)
                print("📁 Created MetaWav/Artists directory")
            } catch {
                print("⚠️ Failed to create Artists directory: \(error)")
            }
        }
        
        return artistsDir
    }
    
    // MARK: - Security-Scoped Bookmark Storage for External Image URLs
    private let artistImageBookmarksKey = "ArtistImageBookmarks"
    
    private func loadImageBookmarks() -> [String: Data] {
        let defaults = UserDefaults.standard
        return defaults.dictionary(forKey: artistImageBookmarksKey) as? [String: Data] ?? [:]
    }
    
    private func saveImageBookmarks(_ dict: [String: Data]) {
        let defaults = UserDefaults.standard
        defaults.set(dict, forKey: artistImageBookmarksKey)
    }
    
    func saveImageBookmark(for artistName: String, url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            var dict = loadImageBookmarks()
            dict[artistName] = data
            saveImageBookmarks(dict)
        } catch {
            print("⚠️ Failed to save image bookmark for \(artistName): \(error)")
        }
    }
    
    func resolveBookmarkedImageURL(for artistName: String) -> URL? {
        let dict = loadImageBookmarks()
        guard let data = dict[artistName] else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            print("⚠️ Failed to resolve image bookmark for \(artistName): \(error)")
            return nil
        }
    }
    
    // Resolve missing profileImagePath values from previously saved security-scoped bookmarks.
    // This lets grid views display images immediately without requiring a visit to the detail view.
    func resolveMissingProfileImagePaths() {
        let bookmarks = loadImageBookmarks()
        guard !bookmarks.isEmpty else { return }
        var updatedAny = false
        var updatedArtists: [ArtistProfile] = []
        for var artist in artists {
            // Skip artists that already have a valid, existing path
            if let path = artist.profileImagePath, FileManager.default.fileExists(atPath: path) {
                continue
            }
            // Try to resolve bookmarked URL
            if let url = resolveBookmarkedImageURL(for: artist.name) {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if FileManager.default.fileExists(atPath: url.path) {
                    artist.profileImagePath = url.path
                    saveArtistProfile(artist)
                    updatedAny = true
                    updatedArtists.append(artist)
                }
            }
        }
        if updatedAny {
            DispatchQueue.main.async {
                // Ensure in-memory list reflects latest saved profiles
                self.loadAllArtists()
            }
        }
    }
    
    // Removed copying helper; we now store the original file path chosen by the user
    
    // REPLACE the existing discoverAndCreateArtists method in ArtistManager with this enhanced version:

    func discoverAndCreateArtists(from albums: [AlbumMetadata]) {
        print("🎭 Discovering artists from \(albums.count) albums")
        
        var discoveredArtists: Set<String> = []
        
        // 1. Discover main artists (existing logic)
        for album in albums {
            for track in album.tracks {
                if let artistName = track.artist, !artistName.isEmpty {
                    discoveredArtists.insert(artistName)
                }
            }
        }
        
        // 2. NEW: Discover featured artists from credits
        for album in albums {
            for track in album.tracks {
                let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
                for featuredArtist in featuredArtists {
                    if !featuredArtist.isEmpty {
                        discoveredArtists.insert(featuredArtist)
                    }
                }
            }
        }
        
        print("🔍 Discovered \(discoveredArtists.count) unique artists (main + featured)")
        
        // Load artists from disk FIRST to get latest data including biographies
        // CRITICAL: Load synchronously from disk files, don't rely on async loadAllArtists
        let artistFiles = try? FileManager.default.contentsOfDirectory(at: artistsDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "metaartist" }
        
        var loadedArtists: [ArtistProfile] = []
        if let files = artistFiles {
            print("📚 Loading \(files.count) artist files from disk for discovery")
            for file in files {
                if let profile = loadArtistProfile(from: file) {
                    loadedArtists.append(profile)
                }
            }
            loadedArtists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            // Update in-memory array synchronously (but don't overwrite - merge carefully)
            // Only add artists that aren't already in the array
            for loadedArtist in loadedArtists {
                if !artists.contains(where: { $0.name == loadedArtist.name }) {
                    artists.append(loadedArtist)
                } else if let index = artists.firstIndex(where: { $0.name == loadedArtist.name }) {
                    // Update existing artist with data from disk (preserves bio)
                    artists[index] = loadedArtist
                }
            }
            artists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            print("📚 Loaded \(loadedArtists.count) artists from disk, total in memory: \(artists.count)")
        }
        
        let existingArtistNames = Set(artists.map { $0.name })
        
        // Create profiles for all discovered artists (main and featured)
        for artistName in discoveredArtists {
            if !existingArtistNames.contains(artistName) {
                // CRITICAL: Check if file exists on disk first (might have been created but not loaded)
                let filename = sanitizeFilename(artistName) + ".metaartist"
                let fileURL = artistsDirectoryURL.appendingPathComponent(filename)
                
                var newProfile: ArtistProfile
                
                // If file exists, load it first to preserve any existing data (like bio)
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let existingProfile = loadArtistProfile(from: fileURL) {
                    print("   📖 Found existing file for \(artistName), loading to preserve data")
                    newProfile = existingProfile
                } else {
                    // Create new profile
                    newProfile = ArtistProfile(
                        name: artistName,
                        profileImagePath: nil,
                        bio: nil,
                        albumCount: 0,
                        trackCount: 0,
                        associatedAlbums: []
                    )
                }
                
                // Update counts using enhanced counting that includes featured appearances
                let oldAlbumCount = newProfile.albumCount
                let oldTrackCount = newProfile.trackCount
                let oldAssociatedAlbums = newProfile.associatedAlbums
                updateArtistCounts(&newProfile, from: albums)
                
                // Only save if counts changed (preserves existing bio)
                let countsChanged = newProfile.albumCount != oldAlbumCount || 
                                   newProfile.trackCount != oldTrackCount ||
                                   newProfile.associatedAlbums != oldAssociatedAlbums
                
                if countsChanged {
                    saveArtistProfile(newProfile)
                } else {
                    print("   ✅ Counts unchanged for \(artistName), skipping save")
                }
                
                artists.append(newProfile)
                
                // Check if this is a featured-only artist
                let hasOwnAlbums = albums.contains { album in
                    album.tracks.contains { $0.artist == artistName }
                }
                
                if hasOwnAlbums {
                    print("✨ Created/updated artist profile: \(artistName) (main artist)")
                } else {
                    print("🎤 Created/updated featured artist profile: \(artistName) (featured only)")
                }
            }
        }
        
        // Update all existing artist profiles with enhanced counting
        // CRITICAL: DO NOT overwrite files unless counts actually changed
        // Load directly from disk files (don't trust in-memory array which might be stale)
        print("🔄 Updating existing artist profiles (preserving user data)")
        
        // Get all artist files from disk directly
        guard let artistFiles = try? FileManager.default.contentsOfDirectory(at: artistsDirectoryURL, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "metaartist" }) else {
            print("   ⚠️ Could not read artist directory")
            return
        }
        
        print("   Found \(artistFiles.count) artist files on disk")
        
        // Process each file on disk
        for fileURL in artistFiles {
            guard let savedProfile = loadArtistProfile(from: fileURL) else {
                print("   ⚠️ Could not load artist from \(fileURL.lastPathComponent), skipping")
                continue
            }
            
            let artistName = savedProfile.name
            
            // Check if saved profile has biography
            let hasBio = savedProfile.bio != nil && !savedProfile.bio!.isEmpty
            if hasBio {
                print("   ✅ Loaded \(artistName) from disk WITH biography (\(savedProfile.bio!.count) chars)")
            } else {
                print("   📖 Loaded \(artistName) from disk WITHOUT biography")
            }
            
            // Merge: Keep ALL saved data (bio, profileImagePath, roles) but update counts
            var mergedProfile = savedProfile  // Start with saved version (preserves bio)
            let oldAlbumCount = mergedProfile.albumCount
            let oldTrackCount = mergedProfile.trackCount
            let oldAssociatedAlbums = mergedProfile.associatedAlbums
            
            // Update only counts (this should NOT touch bio, profileImagePath, or roles)
            updateArtistCounts(&mergedProfile, from: albums)
            
            // Verify biography is still present after update
            let stillHasBio = mergedProfile.bio != nil && !mergedProfile.bio!.isEmpty
            if hasBio && !stillHasBio {
                print("   ❌ CRITICAL ERROR: Biography lost during updateCounts!")
                print("      Original bio length: \(savedProfile.bio!.count)")
                print("      Merged bio: \(mergedProfile.bio?.count ?? 0)")
                // Restore biography if it was lost
                mergedProfile.bio = savedProfile.bio
            }
            
            // Only save if counts actually changed (avoid unnecessary overwrites)
            let countsChanged = mergedProfile.albumCount != oldAlbumCount || 
                               mergedProfile.trackCount != oldTrackCount ||
                               mergedProfile.associatedAlbums != oldAssociatedAlbums
            
            if countsChanged {
                print("   💾 Counts changed for \(artistName), saving...")
                print("      Album count: \(oldAlbumCount) → \(mergedProfile.albumCount)")
                print("      Track count: \(oldTrackCount) → \(mergedProfile.trackCount)")
                
                // CRITICAL: Double-check biography is still present before saving
                if hasBio {
                    if let bio = mergedProfile.bio, !bio.isEmpty {
                        print("      ✅ Biography preserved: \(bio.count) chars")
                    } else {
                        print("      ❌ CRITICAL: Biography was lost! Restoring before save...")
                        mergedProfile.bio = savedProfile.bio
                        print("      ✅ Biography restored: \(savedProfile.bio!.count) chars")
                    }
                }
                
                saveArtistProfile(mergedProfile)
                
                // Update in-memory array
                if let index = artists.firstIndex(where: { $0.name == artistName }) {
                    artists[index] = mergedProfile
                } else {
                    artists.append(mergedProfile)
                    artists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            } else {
                // Counts unchanged, just update in-memory array (don't overwrite file)
                print("   ✅ Counts unchanged for \(artistName), skipping save (preserving file)")
                if let index = artists.firstIndex(where: { $0.name == artistName }) {
                    artists[index] = savedProfile  // Use saved version, not merged
                } else {
                    artists.append(savedProfile)
                    artists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            }
        }
        
        print("🎭 Artist discovery complete: \(artists.count) total artists")
    }

    // ADD this new enhanced counting method after the existing discoverAndCreateArtists method:

    // MARK: - Enhanced Artist Counting (includes featured appearances)
    // REPLACE the existing updateArtistCounts method in ArtistProfile.swift with this simple fix:

    // MARK: - Enhanced Artist Counting (includes featured appearances)
    private func updateArtistCounts(_ profile: inout ArtistProfile, from albums: [AlbumMetadata]) {
        // CRITICAL: Preserve user-edited fields before updating counts
        let preservedBio = profile.bio
        let preservedProfileImagePath = profile.profileImagePath
        let preservedRoles = profile.roles
        
        // Get albums where artist is the main artist
        let mainArtistAlbums = albums.filter { album in
            album.tracks.contains { $0.artist == profile.name }
        }
        
        // Get albums where artist appears as featured artist
        let featuredOnAlbums = albums.filter { album in
            album.tracks.contains { track in
                let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
                return featuredArtists.contains(profile.name)
            }
        }
        
        // Count tracks where artist is main artist
        let mainArtistTracks = albums.reduce(0) { total, album in
            total + album.tracks.filter { $0.artist == profile.name }.count
        }
        
        // Count tracks where artist is featured
        let featuredTracks = albums.reduce(0) { total, album in
            total + album.tracks.filter { track in
                let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
                return featuredArtists.contains(profile.name)
            }.count
        }
        
        // Update profile with main artist data (albums they're the primary artist on)
        profile.albumCount = mainArtistAlbums.count
        profile.trackCount = mainArtistTracks
        
        // FIXED: Include BOTH main artist albums AND featured albums
        var allAssociatedAlbums = Set<String>()
        
        // Add main artist albums
        for album in mainArtistAlbums {
            allAssociatedAlbums.insert(album.albumName)
        }
        
        // Add featured albums
        for album in featuredOnAlbums {
            allAssociatedAlbums.insert(album.albumName)
        }
        
        profile.associatedAlbums = Array(allAssociatedAlbums).sorted()
        
        // CRITICAL: Restore preserved user-edited fields (in case they were accidentally cleared)
        profile.bio = preservedBio
        profile.profileImagePath = preservedProfileImagePath
        profile.roles = preservedRoles
        
        // Log enhanced info for debugging (only when there are featured tracks)
        if featuredTracks > 0 {
            print("🎤 \(profile.name): Featured on \(featuredTracks) tracks across \(featuredOnAlbums.count) albums")
        }
    }
    // ADD this helper method to get all albums where an artist appears (main OR featured):

    // MARK: - Get All Albums Where Artist Appears (Main + Featured)
    func getAllAlbumsForArtist(_ artistName: String, from allAlbums: [AlbumMetadata]) -> (mainArtist: [AlbumMetadata], featuredOn: [AlbumMetadata]) {
        let mainArtistAlbums = allAlbums.filter { album in
            album.tracks.contains { $0.artist == artistName }
        }
        
        let featuredOnAlbums = allAlbums.filter { album in
            album.tracks.contains { track in
                let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
                return featuredArtists.contains(artistName)
            }
        }
        
        return (mainArtist: mainArtistAlbums, featuredOn: featuredOnAlbums)
    }
    
    func saveArtistProfile(_ profile: ArtistProfile) {
        let filename = sanitizeFilename(profile.name) + ".metaartist"
        let fileURL = artistsDirectoryURL.appendingPathComponent(filename)
        
        print("💾 Saving artist profile: \(profile.name)")
        print("   File path: \(fileURL.path)")
        
        // CRITICAL: Check if file exists and has biography before overwriting
        var existingBio: String? = nil
        if FileManager.default.fileExists(atPath: fileURL.path),
           let existingData = try? Data(contentsOf: fileURL),
           let existingProfile = try? PropertyListDecoder().decode(ArtistProfile.self, from: existingData),
           let bio = existingProfile.bio, !bio.isEmpty {
            existingBio = bio
            print("   ⚠️ File exists with biography (\(bio.count) chars) - will preserve if new profile lacks it")
        }
        
        // Prepare profile to save
        var profileToSave = profile
        
        // CRITICAL: If profile being saved has no bio but file had one, preserve it
        if (profileToSave.bio == nil || profileToSave.bio!.isEmpty) && existingBio != nil {
            print("   🔄 RESTORING biography from existing file (\(existingBio!.count) chars)")
            profileToSave.bio = existingBio
        }
        
        if let bio = profileToSave.bio {
            print("   Biography: \(bio.prefix(50))... (length: \(bio.count))")
        } else {
            print("   Biography: nil")
        }
        
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(profileToSave)
            try data.write(to: fileURL, options: [.atomic])
            
            // Verify file was written
            if FileManager.default.fileExists(atPath: fileURL.path) {
                print("✅ Artist profile saved successfully to: \(fileURL.path)")
                
                // Verify we can read it back
                if let verifyData = try? Data(contentsOf: fileURL),
                   let verifyProfile = try? PropertyListDecoder().decode(ArtistProfile.self, from: verifyData) {
                    print("✅ Verified: Can read back saved profile")
                    if let verifyBio = verifyProfile.bio {
                        print("   ✅ Verified biography length: \(verifyBio.count) chars")
                    } else {
                        print("   ❌ ERROR: Biography missing after save!")
                    }
                } else {
                    print("⚠️ Warning: Could not verify saved profile")
                }
            } else {
                print("❌ Error: File does not exist after save!")
            }
            
            // Update in-memory array synchronously on main thread
            DispatchQueue.main.async {
                if let index = self.artists.firstIndex(where: { $0.name == profile.name }) {
                    self.artists[index] = profile
                    print("✅ Updated in-memory artist at index \(index)")
                } else {
                    self.artists.append(profile)
                    self.artists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    print("✅ Added new artist to in-memory array")
                }
                
                NotificationManager.shared.postNotification(.artistUpdated, object: profile)
            }
            
        } catch {
            print("❌ Failed to save artist profile \(profile.name): \(error)")
            print("   Error details: \(error.localizedDescription)")
            showError("Failed to save artist profile: \(error.localizedDescription)")
        }
    }
    
    private func updateInMemoryArtist(_ updatedProfile: ArtistProfile) {
        DispatchQueue.main.async {
            if let index = self.artists.firstIndex(where: { $0.name == updatedProfile.name }) {
                self.artists[index] = updatedProfile
            } else {
                self.artists.append(updatedProfile)
                self.artists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }
    
    func loadAllArtists() {
        print("📚 loadAllArtists() called - loading from: \(artistsDirectoryURL.path)")
        do {
            let artistFiles = try FileManager.default.contentsOfDirectory(at: artistsDirectoryURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "metaartist" }
            
            print("   Found \(artistFiles.count) .metaartist files")
            
            var loaded: [ArtistProfile] = []
            for file in artistFiles {
                if let profile = loadArtistProfile(from: file) {
                    loaded.append(profile)
                    // Debug: Check if biography is present
                    if let bio = profile.bio, !bio.isEmpty {
                        print("   ✅ Loaded \(profile.name) WITH biography (\(bio.count) chars)")
                    } else {
                        print("   ⚠️ Loaded \(profile.name) WITHOUT biography")
                    }
                }
            }
            
            loaded.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                // CRITICAL: Merge carefully - preserve biographies from disk
                // Don't just overwrite - merge existing artists with loaded ones
                for loadedArtist in loaded {
                    if let index = self.artists.firstIndex(where: { $0.name == loadedArtist.name }) {
                        // Artist exists - merge carefully to preserve bio
                        var existingArtist = self.artists[index]
                        // If loaded has bio but existing doesn't, use loaded
                        if let loadedBio = loadedArtist.bio, !loadedBio.isEmpty {
                            if existingArtist.bio == nil || existingArtist.bio!.isEmpty {
                                existingArtist.bio = loadedBio
                                print("   🔄 Restored biography for \(loadedArtist.name) from disk")
                            }
                        }
                        // Update other fields from disk (they're more current)
                        existingArtist.profileImagePath = loadedArtist.profileImagePath
                        existingArtist.roles = loadedArtist.roles
                        existingArtist.albumCount = loadedArtist.albumCount
                        existingArtist.trackCount = loadedArtist.trackCount
                        existingArtist.associatedAlbums = loadedArtist.associatedAlbums
                        self.artists[index] = existingArtist
                    } else {
                        // New artist - add it
                        self.artists.append(loadedArtist)
                    }
                }
                self.artists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                print("📚 Loaded \(loaded.count) artist profiles into memory (merged with existing)")
            }
            
        } catch {
            print("⚠️ Failed to load artist profiles: \(error)")
            showError("Failed to load artist profiles: \(error.localizedDescription)")
        }
    }
    
    // Removed resolver that rewrote paths into the Artists directory
    
    private func loadArtistProfile(from url: URL) -> ArtistProfile? {
        do {
            let data = try Data(contentsOf: url)
            
            // Debug: Check raw plist content for bio field
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                if let bioValue = plist["bio"] {
                    print("   🔍 Raw plist has bio field: \(type(of: bioValue)) = \(bioValue)")
                } else {
                    print("   ⚠️ Raw plist MISSING bio field!")
                    print("   Available keys: \(plist.keys.sorted())")
                }
            }
            
            let decoder = PropertyListDecoder()
            let profile = try decoder.decode(ArtistProfile.self, from: data)
            
            // Debug: Log biography when loading
            if let bio = profile.bio, !bio.isEmpty {
                print("📖 Loaded artist \(profile.name) - Biography: \(bio.prefix(50))... (length: \(bio.count))")
            } else {
                print("📖 Loaded artist \(profile.name) - No biography (bio is \(profile.bio == nil ? "nil" : "empty"))")
            }
            
            return profile
        } catch {
            print("⚠️ Failed to load artist profile from \(url.lastPathComponent): \(error)")
            print("   Error details: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Missing key: \(key.stringValue) - \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("   Type mismatch: \(type) - \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value not found: \(type) - \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
            return nil
        }
    }
    
    func deleteArtistProfile(_ profile: ArtistProfile) {
        let filename = sanitizeFilename(profile.name) + ".metaartist"
        let fileURL = artistsDirectoryURL.appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            
            DispatchQueue.main.async {
                self.artists.removeAll { $0.id == profile.id }
                NotificationManager.shared.postNotification(.artistDeleted, object: profile.name)
            }
            
            print("🗑️ Deleted artist profile: \(profile.name)")
        } catch {
            print("⚠️ Failed to delete artist profile: \(error)")
            showError("Failed to delete artist profile: \(error.localizedDescription)")
        }
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    func getArtistAlbums(_ artistName: String, from allAlbums: [AlbumMetadata]) -> [AlbumMetadata] {
        return allAlbums.filter { album in
            album.tracks.contains { $0.artist == artistName }
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Artist Manager Errors
enum ArtistManagerError: LocalizedError {
    case invalidName
    case duplicateName
    case artistNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Artist name cannot be empty"
        case .duplicateName:
            return "An artist with this name already exists"
        case .artistNotFound:
            return "Artist not found"
        }
    }
}

// MARK: - Artist Navigation State
enum ArtistViewState {
    case grid
    case detail(ArtistProfile)
}

// MARK: - Artist Grid View
struct ArtistGridView: View {
    let artists: [ArtistProfile]
    let onArtistSelected: (ArtistProfile) -> Void
    let searchText: String
    
    private var filteredArtists: [ArtistProfile] {
        if searchText.isEmpty {
            return artists
        } else {
            return artists.filter { artist in
                artist.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        ScrollView {
            if filteredArtists.isEmpty {
                emptyStateView
            } else {
                artistGrid
            }
        }
    }
    
    // MARK: - Extracted Components
    
    private var artistGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)
        ], spacing: 12) {
            ForEach(filteredArtists) { artist in
                ArtistGridItem(
                    artist: artist,
                    onTap: { onArtistSelected(artist) }
                )
            }
        }
        .padding(10)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3")
                .font(.system(size: 28))
                .foregroundColor(Color(white: 0.4))
            
            Text("NO ARTISTS")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.6))
            
            Text(searchText.isEmpty ? "Load some albums to see artists" : "No artists match your search")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

// MARK: - Artist Grid Item (Extracted Component)
struct ArtistGridItem: View {
    let artist: ArtistProfile
    let onTap: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            artistImage
            artistInfo
        }
        .padding(8)
        .background(
            Group {
                if isHovered {
                    Color.clear
                        .secondaryGlass(cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                }
            }
        )
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 4 : 0)
        .offset(x: isHovered ? 4 : 0)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var artistImage: some View {
        Group {
            if let profileImage = loadProfileImage() {
                Image(nsImage: profileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                defaultArtistImage
            }
        }
    }
    
    private var defaultArtistImage: some View {
        Circle()
            .fill(Color(white: 0.2))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39).opacity(0.7))
            )
    }
    
    private var artistInfo: some View {
        VStack(spacing: 2) {
            Text(artist.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            
            Text("\(artist.albumCount) albums")
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.6))
        }
    }
    
    // MARK: - Helper Method
    private func loadProfileImage() -> NSImage? {
        guard let path = artist.profileImagePath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        // Load image on background queue to avoid blocking main thread
        return DispatchQueue.global(qos: .utility).sync(execute: {
            NSImage(contentsOfFile: path)
        })
    }
}

// MARK: - COMPLETE Artist Detail View with Organized Discography
struct ArtistDetailView: View {
    let artist: ArtistProfile
    let allAlbums: [AlbumMetadata]
    let onBack: () -> Void
    let onEdit: () -> Void
    let onNavigateToAlbum: (AlbumMetadata) -> Void
    
    @StateObject private var artistManager = ArtistManager.shared
    @State private var isEditingArtist = false
    @State private var editableArtist: ArtistProfile
    
    @State private var showArtworkPicker = false
    @State private var profileArtworkImage: NSImage?
    @State private var showPowerAlert = false
    
    // Track selection and playing state
    @Binding var selectedTrack: TrackMetadata?
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var isPoweredOn: Bool
    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    @ObservedObject private var playCountManager = PlayCountManager.shared
    @StateObject private var dragState = DragState()
    @State private var hoveredAlbumId: String? = nil
    @State private var favHoveredTrackId: String? = nil
    @State private var hoveredAlbumName: String? = nil
    
    init(
        artist: ArtistProfile,
        allAlbums: [AlbumMetadata],
        selectedTrack: Binding<TrackMetadata?>,
        currentAlbum: Binding<AlbumMetadata?>,
        isPoweredOn: Binding<Bool>,
        onBack: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onNavigateToAlbum: @escaping (AlbumMetadata) -> Void
    ) {
        self.artist = artist
        self.allAlbums = allAlbums
        self._selectedTrack = selectedTrack
        self._currentAlbum = currentAlbum
        self._isPoweredOn = isPoweredOn
        self.onBack = onBack
        self.onEdit = onEdit
        self.onNavigateToAlbum = onNavigateToAlbum
        self._editableArtist = State(initialValue: artist)
    }
    
    // Always render from the freshest artist available
    private var displayedArtist: ArtistProfile {
        if let updated = artistManager.artists.first(where: { $0.name == artist.name }) {
            return updated
        }
        return editableArtist
    }
    
    private var artistAlbums: [AlbumMetadata] {
        return artistManager.getArtistAlbums(editableArtist.name, from: allAlbums)
    }
    
    // MARK: - Track Interaction Methods
    
    private func selectTrack(_ track: TrackMetadata) {
        selectedTrack = track
        MenuBarManager.shared.updateSelectedTrack(track)
        if let album = getAlbumForTrack(track) {
            currentAlbum = album
            MenuBarManager.shared.updateCurrentAlbum(album)
        }
        print("🎵 Selected track: \(track.name)")
    }
    
    private func playTrack(_ track: TrackMetadata) {
        print("▶️ Playing track: \(track.name)")
        if !isPoweredOn {
            showPowerAlert = true
            return
        }
        
        // Match AlbumPageView behavior: play the track's album from this track
        guard let album = getAlbumForTrack(track) else {
            print("❌ Could not find album for track: \(track.name)")
            return
        }
        QueueManager.shared.playAlbumFromTrack(track, from: album)
        currentAlbum = album
        
        // Update selection
        selectTrack(track)
        
        print("🎵 Started playing album from track: \(track.name)")
    }
    
    private func addTrackToQueue(_ track: TrackMetadata) {
        print("➕ Adding track to queue: \(track.name)")
        if let album = getAlbumForTrack(track) {
            QueueManager.shared.addToQueue(track, from: album)
        } else {
            print("❌ Could not find album for track: \(track.name)")
        }
    }
    
    private func isTrackPlaying(_ track: TrackMetadata) -> Bool {
        guard let currentItem = queueManager.currentItem else { return false }
        return currentItem.track?.filePath == track.filePath && audioProcessor.isPlaying
    }
    
    private func isTrackSelected(_ track: TrackMetadata) -> Bool {
        guard let selected = selectedTrack else { return false }
        if let selStable = selected.stableTrackId as String?, let trStable = track.stableTrackId as String? {
            if selStable == trStable { return true }
        }
        return selected.filePath == track.filePath
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with back button
                headerSection(width: geometry.size.width)
                
                // Main content with proper proportions and constraints
                HStack(spacing: 0) {
                    // Left side: Artist Art + Details + Biography - 30% width
                    leftSideSection(width: (geometry.size.width - 60) * 0.3)
                        .frame(width: (geometry.size.width - 60) * 0.3)
                    
                    // Right side: Favourite Tracks + Organized Discography - 70% width
                    rightSideSection(width: (geometry.size.width - 60) * 0.7)
                        .frame(width: (geometry.size.width - 60) * 0.7)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 30) // Add horizontal padding to the entire HStack
                .padding(.top, 16)
            }
        }
        .onAppear {
            loadArtwork(for: artist)
            // Reload artists from disk to ensure we have latest data including biography
            artistManager.loadAllArtists()
        }
        .alert("Power Required", isPresented: $showPowerAlert) {
            Button("OK") { }
        } message: {
            Text("Please switch on power to play music.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .artistUpdated)) { notification in
            if let updated = notification.object as? ArtistProfile,
               updated.name == editableArtist.name {
                var merged = updated
                merged.updateCounts(from: allAlbums)
                editableArtist = merged
            }
        }
    }
    
    // MARK: - Header Section
    private func headerSection(width: CGFloat) -> some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Left Side Section with Biography
    private func leftSideSection(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Artist artwork with proper sizing
                artistArtworkView(size: min(width * 0.8, 200))
                
                // Artist details with proper width constraints
                artistDetailsView(maxWidth: width)
                
                // Biography section
                biographySection()
                    .frame(maxWidth: width - 20)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    // Add this method to ArtistDetailView class - around line 400

    // MARK: - Featured Albums Detection (ENHANCED with debugging)

    private func getFeaturedOnAlbums() -> [AlbumMetadata] {
        return allAlbums.filter { album in
            album.tracks.contains { track in
                let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
                return featuredArtists.contains { featuredArtist in
                    featuredArtist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                    editableArtist.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    // REPLACE the existing organizedDiscographySection method with this updated version:

    // MARK: - Organized Discography Section (Works for all artists)
    private func organizedDiscographySection() -> some View {
        let albumsByType = groupAlbumsByType()
        let sectionsToShow = getSectionsToDisplay(albumsByType: albumsByType)
        let featuredOnAlbums = getFeaturedOnAlbums()
        
        return VStack(alignment: .leading, spacing: 20) {
            Text("DISCOGRAPHY")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .tracking(0.5)
            
            // Display main discography sections if they exist
            ForEach(sectionsToShow, id: \.displayName) { section in
                albumTypeSection(title: section.displayName, albums: section.albums)
            }
            
            // Add Featured On section if artist appears as featured artist anywhere
            if !featuredOnAlbums.isEmpty {
                albumTypeSection(title: "FEATURED ON", albums: featuredOnAlbums)
            }
            
            // Show empty state only if no main albums AND no featured albums
            if sectionsToShow.isEmpty && featuredOnAlbums.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 48))
                        .foregroundColor(Color(white: 0.4))
                    
                    Text("NO RELEASES")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                    
                    Text("This artist has no releases or featured appearances")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            debugAlbumTypes(albumsByType: albumsByType)
            debugFeaturedOnAlbums(featuredOnAlbums: featuredOnAlbums)
        }
    }

    // Add this debug method after the existing debugAlbumTypes method:

    // MARK: - Debug Featured On Albums (ENHANCED)
    private func debugFeaturedOnAlbums(featuredOnAlbums: [AlbumMetadata]) {
        print("🎤 Featured On Albums for \(editableArtist.name):")
        print("   Total featured albums: \(featuredOnAlbums.count)")
        
        // Check ALL albums to see which ones have this artist as featured
        print("   Scanning all \(allAlbums.count) albums for featured appearances...")
        
        for album in allAlbums {
            var foundInThisAlbum = false
            var tracksWithFeature: [String] = []
            
            for track in album.tracks {
                let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
                if featuredArtists.contains(where: { $0.lowercased() == editableArtist.name.lowercased() }) {
                    foundInThisAlbum = true
                    tracksWithFeature.append(track.name)
                }
            }
            
            if foundInThisAlbum {
                print("   ✅ \(album.albumName):")
                for trackName in tracksWithFeature {
                    print("      • \(trackName)")
                }
            }
        }
        
        // Also check if there are any issues with the ArtistDetection method
        print("   Testing ArtistDetection.getFeaturedArtists method:")
        for album in allAlbums.prefix(3) { // Test first 3 albums
            for track in album.tracks.prefix(2) { // Test first 2 tracks per album
                let featured = ArtistDetection.getFeaturedArtists(from: track)
                if !featured.isEmpty {
                    print("     Track '\(track.name)' has featured: \(featured)")
                }
            }
        }
    }

    // MARK: - Artist Artwork View
    private func artistArtworkView(size: CGFloat) -> some View {
        ZStack {
            Group {
                if let profileImage = profileArtworkImage {
                    Image(nsImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(white: 0.2))
                        .frame(width: size, height: size)
                        .overlay(
                            VStack {
                                Image(systemName: "person.fill")
                                    .font(.system(size: size * 0.25))
                                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                                Text("PROFILE")
                                    .font(.system(size: max(8, size * 0.06), weight: .bold))
                                    .foregroundColor(.gray)
                            }
                        )
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Edit mode overlay
            if isEditingArtist {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            showArtworkPicker = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: size, height: size)
        .fileImporter(
            isPresented: $showArtworkPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleArtworkSelection(result)
        }
    }
    
    // MARK: - Artist Details
    private func artistDetailsView(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Artist name and info
            VStack(alignment: .leading, spacing: 8) {
                Text(editableArtist.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .frame(maxWidth: maxWidth - 20, alignment: .leading)
                
                // Roles (simplified): always show "Artist"
                Text("Artist")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.7))
                    .lineLimit(1)
                    .frame(maxWidth: maxWidth - 20, alignment: .leading)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(isEditingArtist ? "Save" : "Edit") {
                    if isEditingArtist {
                        saveArtistMetadata()
                    } else {
                        startEditingArtist()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .buttonStyle(PlainButtonStyle())
                
                if isEditingArtist {
                    Button("Cancel") {
                        isEditingArtist = false
                        editableArtist = displayedArtist
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(.vertical, 8)
    }
    
    // MARK: - Roles (simplified)
    
    // (Removed roles editor per spec: always show "Artist")
    
    private var availableRoles: [String] { [] }

    // MARK: - Roles Picker Sheet
    // Removed RolesPickerView per simplification

    // MARK: - Liquid Glass background effect (best-effort fallback)
    private struct LiquidGlassBackground: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08))
                )
        }
    }
    
    // MARK: - Right Side Section - Favourite Tracks + Organized Discography
    private func rightSideSection(width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. FAVOURITE TRACKS SECTION (Always shown - placeholder for now)
                favouriteTracksSection()
                    .frame(maxWidth: width - 40)
                
                // 2. DISCOGRAPHY SECTION - FIXED: Now shows for featured-only artists too
                let featuredOnAlbums = getFeaturedOnAlbums()
                let hasAnyAlbums = !artistAlbums.isEmpty || !featuredOnAlbums.isEmpty
                
                if hasAnyAlbums {
                    organizedDiscographySection()
                        .frame(maxWidth: width - 40)
                } else {
                    // Empty state only when artist has NO albums AND NO featured appearances
                    emptyDiscographyState()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        // Auto-update favorites when play counts change
        .onReceive(playCountManager.$playCounts) { _ in
            // Trigger body refresh; topTracks recomputes from play counts
            _ = getTopTracksForArtist()
        }
    }

    // MARK: - Favourite Tracks Section (Auto-generated from play counts)
    private func favouriteTracksSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FAVOURITE TRACKS")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .tracking(0.5)
            
            let topTracks = getTopTracksForArtist()
            
            if topTracks.isEmpty {
                // No tracks with play counts yet
                VStack(spacing: 12) {
                    Text("No plays yet")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.5))
                        .italic()
                    
                    Text("Play some tracks to see your favorites here")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.4))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(white: 0.05))
                .cornerRadius(4)
            } else {
                // Render rows using AlbumPageTrackRow for identical behavior to album view
                VStack(spacing: 6) {
                    ForEach(Array(topTracks.enumerated()), id: \.offset) { i, trackData in
                        let track = trackData.track
                        let album = getAlbumForTrack(track)
                        FavoriteTrackRow(
                            track: track,
                            rank: i + 1,
                            album: album,
                            isSelected: isTrackSelected(track),
                            isPlaying: isTrackPlaying(track),
                            playCount: trackData.playCount,
                            onSelect: { selectTrack(track) },
                            onPlay: {
                                if !isPoweredOn {
                                    showPowerAlert = true
                                    return
                                }
                                let tracks = topTracks.map { $0.track }
                                let playlistId = "artist-favorites:" + editableArtist.name
                                QueueManager.shared.playVirtualPlaylist(tracks, playlistId: playlistId, startIndex: i, shuffle: false)
                            },
                            onNavigateToAlbum: { album in onNavigateToAlbum(album) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Helper methods for favourite tracks
    private func getTopTracksForArtist() -> [(track: TrackMetadata, playCount: Int)] {
        let topTrackData = PlayCountManager.shared.getTopTracksByArtist(artistId: artist.name, limit: 5)
        var tracksWithPlayCounts: [(track: TrackMetadata, playCount: Int)] = []
        
        // Get all albums to find the tracks
        let albums = AlbumMetadataManager.shared.loadAllAlbums()
        
        for trackData in topTrackData {
            // Find the track metadata for this track ID
            for album in albums {
                if let track = album.tracks.first(where: { $0.stableTrackId == trackData.trackId }) {
                    tracksWithPlayCounts.append((track: track, playCount: trackData.playCount))
                    break
                }
            }
        }
        
        return tracksWithPlayCounts
    }
    
    private func favouriteTrackRow(trackData: (track: TrackMetadata, playCount: Int), rank: Int) -> some View {
        let track = trackData.track
        let isSelected = isTrackSelected(track)
        let isPlaying = isTrackPlaying(track)
        
        return HStack(spacing: 10) {
            // Rank indicator or playing visualizer - styled like track number in album view
            HStack {
                if isPlaying && audioProcessor.isPlaying {
                    PlayingVisualizer()
                        .frame(width: 24, height: 10)
                } else {
                    Text(String(format: "%02d", rank)) // virtual playlist position (1..5)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TrackRowStyle.numberColor(isSelected: isSelected, isPlaying: isPlaying && audioProcessor.isPlaying))
                        .frame(width: 24, alignment: .center)
                }
            }
            
            // Track info - styled like album view
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(track.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(getTrackNameColor(isSelected: isSelected))
                            .lineLimit(1)
                        
                        if track.isExplicit == true {
                            ExplicitIndicatorTraditional(size: 8)
                        }
                    }
                    
                    // Show album name instead of artist (since we're in artist profile) - clickable with hover underline
                    if let album = getAlbumForTrack(track) {
                        Text(album.albumName)
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.6))
                            .underline(hoveredAlbumName == album.albumName, color: Color(white: 0.6))
                            .lineLimit(1)
                            .onHover { isHovered in
                                hoveredAlbumName = isHovered ? album.albumName : (
                                    hoveredAlbumName == album.albumName ? nil : hoveredAlbumName
                                )
                            }
                            .onTapGesture {
                                onNavigateToAlbum(album)
                            }
                    }
                }
                
                Spacer()
                
                // Play count - styled like duration in album view
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                    
                    Text("\(trackData.playCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    Color.clear
                        .selectedGlass(cornerRadius: 6)
                } else if favHoveredTrackId == track.stableTrackId {
                    Color.clear
                        .secondaryGlass(cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.clear)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            favHoveredTrackId = hovering ? track.stableTrackId : (
                favHoveredTrackId == track.stableTrackId ? nil : favHoveredTrackId
            )
        }
        .shadow(
            color: .black.opacity((favHoveredTrackId == track.stableTrackId) ? 0.25 : 0.0),
            radius: (favHoveredTrackId == track.stableTrackId) ? 6 : 0,
            x: 0,
            y: (favHoveredTrackId == track.stableTrackId) ? 4 : 0
        )
        .offset(x: (favHoveredTrackId == track.stableTrackId) ? 4 : 0)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    if !isPoweredOn {
                        showPowerAlert = true
                        return
                    }
                    let topTracks = getTopTracksForArtist()
                    let tracks = topTracks.map { $0.track }
                    let playlistId = "artist-favorites:" + editableArtist.name
                    if let idx = tracks.firstIndex(where: { $0.stableTrackId == track.stableTrackId }) {
                        QueueManager.shared.playVirtualPlaylist(tracks, playlistId: playlistId, startIndex: idx, shuffle: false)
                    }
                }
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    print("🖱️ Single-click detected on favorite track: \(track.name)")
                    selectTrack(track)
                }
        )
        .contextMenu {
            Button(action: { playTrack(track) }) {
                Label("Play Track", systemImage: "play")
            }
            
            Button(action: { addTrackToQueue(track) }) {
                Label("Add to Queue", systemImage: "plus")
            }
            
            if let album = getAlbumForTrack(track) {
                Button(action: { onNavigateToAlbum(album) }) {
                    Label("Go to Album", systemImage: "music.note")
                }
            }
        }
    }
    
    // MARK: - Helper methods for track styling
    
    private func getTrackNumberColor(isSelected: Bool, rank: Int) -> Color {
        if isSelected {
            return Color(red: 0, green: 0.75, blue: 0.39)
        } else if rank <= 3 {
            return Color(red: 0, green: 0.75, blue: 0.39)
        } else {
            return Color(white: 0.6)
        }
    }
    
    private func getTrackNameColor(isSelected: Bool) -> Color {
        return isSelected ? .white : .white
    }
    
    private func getBackgroundColor(isSelected: Bool) -> Color {
        return isSelected ? Color(white: 0.15) : Color.clear
    }
    
    private func getAlbumForTrack(_ track: TrackMetadata) -> AlbumMetadata? {
        let albums = AlbumMetadataManager.shared.loadAllAlbums()
        return albums.first { album in
            album.tracks.contains { $0.stableTrackId == track.stableTrackId }
        }
    }
    
    // MARK: - Helper method to determine which sections to show
    private func getSectionsToDisplay(albumsByType: [String?: [AlbumMetadata]]) -> [(displayName: String, albums: [AlbumMetadata])] {
        var sectionsToShow: [(displayName: String, albums: [AlbumMetadata])] = []
        
        // Define sections in order
        let sectionOrder: [(type: String, displayName: String)] = [
            (type: "Album", displayName: "ALBUMS"),
            (type: "Single", displayName: "SINGLES"),
            (type: "EP", displayName: "EPS"),
            (type: "Mixtape", displayName: "MIXTAPES"),
            (type: "Compilation", displayName: "COMPILATIONS")
        ]
        
        // Add sections that have albums
        for section in sectionOrder {
            let albumsOfThisType = albumsByType[section.type] ?? []
            if !albumsOfThisType.isEmpty {
                sectionsToShow.append((displayName: section.displayName, albums: albumsOfThisType))
            }
        }
        
        // Handle albums with no type
        let unknownAlbums = albumsByType[nil] ?? []
        if !unknownAlbums.isEmpty {
            sectionsToShow.append((displayName: "OTHER", albums: unknownAlbums))
        }
        
        // Handle any unrecognized types
        let knownTypes: Set<String?> = Set(sectionOrder.map { $0.type } + [nil])
        let unknownTypes = Set(albumsByType.keys).subtracting(knownTypes)
        for unknownType in unknownTypes {
            if let type = unknownType, let albums = albumsByType[type], !albums.isEmpty {
                sectionsToShow.append((displayName: type.uppercased(), albums: albums))
            }
        }
        
        return sectionsToShow
    }
    
    // MARK: - Debug method (moved outside ViewBuilder)
    private func debugAlbumTypes(albumsByType: [String?: [AlbumMetadata]]) {
        print("🎭 Artist: \(editableArtist.name)")
        print("   Total albums: \(artistAlbums.count)")
        for album in artistAlbums {
            print("   - \(album.albumName): type = '\(album.albumType ?? "nil")'")
        }
        print("   Grouped types: \(albumsByType.keys.compactMap { $0 })")
        
        // Debug each section
        let sectionOrder: [(type: String, displayName: String)] = [
            (type: "Album", displayName: "ALBUMS"),
            (type: "Single", displayName: "SINGLES"),
            (type: "EP", displayName: "EPS"),
            (type: "Mixtape", displayName: "MIXTAPES"),
            (type: "Compilation", displayName: "COMPILATIONS")
        ]
        
        for section in sectionOrder {
            let albumsOfThisType = albumsByType[section.type] ?? []
            if !albumsOfThisType.isEmpty {
                print("   ✅ Showing \(section.displayName): \(albumsOfThisType.count) albums")
            } else {
                print("   ❌ Hiding \(section.displayName): no albums of type '\(section.type)'")
            }
        }
        
        let unknownAlbums = albumsByType[nil] ?? []
        if !unknownAlbums.isEmpty {
            print("   ✅ Showing OTHER: \(unknownAlbums.count) albums with no type")
        }
    }
    
    // MARK: - Empty Discography State
    private func emptyDiscographyState() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.4))
            
            Text("NO RELEASES")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Color(white: 0.6))
            
            Text("This artist has no releases or featured appearances")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
        }
    }
    // MARK: - Album Type Section (Horizontal row per type)
    // Renders a single content-type section (e.g., ALBUMS, SINGLES) as a horizontally
    // scrollable row. Albums are sorted by release year descending (newest on the left).
    // If the album year is missing, we infer it from track file dates.
    private func albumTypeSection(title: String, albums: [AlbumMetadata]) -> some View {
        let sorted = sortAlbumsByReleaseYearDescending(albums)
        return VStack(alignment: .leading, spacing: 12) {
            // Section title (e.g., "ALBUMS", "SINGLES", etc.)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .tracking(1)

            // Horizontally scrollable row of albums for this type
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(sorted, id: \.albumName) { album in
                        ArtistAlbumTileView(
                            album: album,
                            displayYear: releaseYear(for: album),
                            onTap: { onNavigateToAlbum(album) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Sorting helpers for album rows
    // Determines the release year to use for sorting. Prioritizes the album's stored year,
    // then falls back to inferring from the track files' dates (latest year wins).
    private func releaseYear(for album: AlbumMetadata) -> Int? {
        // 1) Use explicit album year if available (support both "2021" and strings containing a year)
        if let yearString = album.year {
            let digits = yearString.filter { $0.isNumber }
            if digits.count >= 4, let numericYear = Int(digits.prefix(4)) {
                return numericYear
            }
        }

        // 2) Infer from track file dates
        return inferYearFromTrackFiles(album: album)
    }

    // Infers a year from the album's tracks by looking at file creation/modification dates
    // and taking the most recent year. Returns nil if no dates could be determined.
    private func inferYearFromTrackFiles(album: AlbumMetadata) -> Int? {
        var latest: Date? = nil
        for track in album.tracks {
            let path = track.filePath
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let creation = attrs?[.creationDate] as? Date
            let modified = attrs?[.modificationDate] as? Date
            let candidate = max(creation ?? .distantPast, modified ?? .distantPast)
            if latest == nil || candidate > latest! { latest = candidate }
        }
        guard let latestDate = latest, latestDate != .distantPast else { return nil }
        return Calendar.current.dateComponents([.year], from: latestDate).year
    }

    // Sort albums newest to oldest using the derived year. Unknown years are placed at the end.
    private func sortAlbumsByReleaseYearDescending(_ albums: [AlbumMetadata]) -> [AlbumMetadata] {
        return albums.sorted { a, b in
            let ay = releaseYear(for: a) ?? Int.min
            let by = releaseYear(for: b) ?? Int.min
            if ay == by {
                // Tiebreaker: alphabetical by name to keep order stable
                return a.albumName.localizedCaseInsensitiveCompare(b.albumName) == .orderedAscending
            }
            return ay > by
        }
    }
    
    // MARK: - Helper Method to Group Albums by Type
    private func groupAlbumsByType() -> [String?: [AlbumMetadata]] {
        return Dictionary(grouping: artistAlbums) { album in
            // Group by albumType - nil types will be grouped together
            return album.albumType
        }
    }
    
    // MARK: - Biography Section
    private func biographySection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BIOGRAPHY")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .tracking(0.5)
            
            // Unified container to avoid any movement between modes
            ZStack(alignment: .topLeading) {
                Group {
                    if let bio = (isEditingArtist ? editableArtist.bio : displayedArtist.bio), !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.8))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No biography available. Tap Edit to add one.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.5))
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(isEditingArtist ? 0 : 1)

                TextField("Enter biography...", text: Binding(
                    get: { editableArtist.bio ?? "" },
                    set: { editableArtist.bio = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
                .foregroundColor(.white)
                .opacity(isEditingArtist ? 1 : 0)
                .lineLimit(1...12)
                // Removed autosave - biography only saves when user presses Save button
            }
            .padding(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 12))
            .fixedSize(horizontal: false, vertical: true)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 1)
                    .opacity(isEditingArtist ? 1 : 0)
                , alignment: .bottomLeading
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Helper Methods
    
    private func startEditingArtist() {
        editableArtist = displayedArtist
        isEditingArtist = true
    }
    
    private func saveArtistMetadata() {
        var updatedArtist = editableArtist
        updatedArtist.updateCounts(from: allAlbums)
        
        artistManager.saveArtistProfile(updatedArtist)
        
        // Update editableArtist with the saved version to ensure consistency
        editableArtist = updatedArtist
        isEditingArtist = false
        
        print("✅ Saved artist: \(updatedArtist.name)")
        if let bio = updatedArtist.bio {
            print("   Biography length: \(bio.count) characters")
        } else {
            print("   No biography")
        }
    }
    
    // REMOVED: autosaveBiography() - biography now only saves when user presses Save button
    
    private func loadArtwork(for artist: ArtistProfile) {
        if let profilePath = artist.profileImagePath,
           FileManager.default.fileExists(atPath: profilePath) {
            // Load image on background queue to avoid blocking main thread
            DispatchQueue.global(qos: .utility).async {
                let image = NSImage(contentsOfFile: profilePath)
                DispatchQueue.main.async {
                    self.profileArtworkImage = image
                }
            }
        } else if let url = artistManager.resolveBookmarkedImageURL(for: artist.name) {
            // Attempt to load from bookmarked URL and persist the path for future quick access
            DispatchQueue.global(qos: .utility).async {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let image = NSImage(contentsOf: url)
                DispatchQueue.main.async {
                    self.profileArtworkImage = image
                    if image != nil {
                        var updated = self.editableArtist
                        updated.profileImagePath = url.path
                        self.artistManager.saveArtistProfile(updated)
                        self.editableArtist = updated
                    }
                }
            }
        }
    }
    
    private func handleArtworkSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let imageURL = urls.first else { return }
            // Store original file path (no copying) and persist immediately
            editableArtist.profileImagePath = imageURL.path
            artistManager.saveArtistProfile(editableArtist)
            artistManager.saveImageBookmark(for: editableArtist.name, url: imageURL)

            // Load image on background queue to avoid blocking main thread
            DispatchQueue.global(qos: .utility).async {
                let image = NSImage(contentsOf: imageURL)
                DispatchQueue.main.async {
                    self.profileArtworkImage = image
                }
            }

            print("✅ Set profile artwork path: \(imageURL.path)")
            
        case .failure(let error):
            print("Artwork import failed: \(error)")
            showError("Artwork import failed: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Artist Album Tile View (Extracted Component)
private struct ArtistAlbumTileView: View {
    let album: AlbumMetadata
    let displayYear: Int?
    let onTap: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Button(action: { onTap() }) {
                Group {
                    if let frontPath = album.frontArtPath,
                       FileManager.default.fileExists(atPath: frontPath) {
                        AsyncImageLoader(imagePath: frontPath, size: CGSize(width: 120, height: 120))
                            .frame(width: 120, height: 120)
                            .clipped()
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(width: 120, height: 120)
                            .cornerRadius(6)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 30))
                                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39).opacity(0.7))
                            )
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(spacing: 2) {
                Button(action: { onTap() }) {
                    Text(album.albumName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(PlainButtonStyle())

                if let y = displayYear {
                    Text(String(y))
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.6))
                }
            }
            .frame(width: 120)
        }
        .padding(6)
        .background(
            Group {
                if isHovered {
                    Color.clear.secondaryGlass(cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.clear)
                }
            }
        )
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 4 : 0)
        .offset(x: isHovered ? 4 : 0)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct FavoriteTrackRow: View {
    let track: TrackMetadata
    let rank: Int
    let album: AlbumMetadata?
    let isSelected: Bool
    let isPlaying: Bool
    let playCount: Int
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onNavigateToAlbum: (AlbumMetadata) -> Void

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredAlbumName: String? = nil
    @ObservedObject private var audioProcessor = AudioProcessor.shared

    var body: some View {
        HStack(spacing: 10) {
            // Track number or playing indicator
            HStack {
                if isPlaying && audioProcessor.isPlaying {
                    PlayingVisualizer()
                        .frame(width: 24, height: 10)
                } else {
                    Text(String(format: "%02d", rank))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TrackRowStyle.numberColor(isSelected: isSelected, isPlaying: isPlaying && audioProcessor.isPlaying))
                        .frame(width: 24, alignment: .center)
                }
            }

            // Track info with clickable album name
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(track.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TrackRowStyle.titleColor(isSelected: isSelected, isPlaying: isPlaying && audioProcessor.isPlaying))
                            .lineLimit(1)
                        if track.isExplicit == true {
                            ExplicitIndicatorTraditional(size: 8)
                        }
                    }

                    if let album = album {
                        Text(album.albumName)
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.6))
                            .underline(hoveredAlbumName == album.albumName, color: Color(white: 0.6))
                            .lineLimit(1)
                            .onHover { hovering in
                                hoveredAlbumName = hovering ? album.albumName : nil
                            }
                            .onTapGesture { onNavigateToAlbum(album) }
                    }
                }

                Spacer()

                // Play count at right
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                    Text("\(playCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    Color.clear
                        .selectedGlass(cornerRadius: 6)
                } else if isHovered {
                    Color.clear
                        .secondaryGlass(cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.clear)
                }
            }
        )
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 4 : 0)
        .offset(x: isHovered ? 4 : 0)
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0.0), radius: isDragging ? 6 : 0, x: 0, y: isDragging ? 3 : 0)
        .opacity(isDragging ? 0.9 : 1.0)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .offset(dragOffset)
        .compositingGroup()
        .zIndex(isDragging ? 100 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onPlay() }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded { onSelect() }
        )
        .onHover { hovering in
            if !isDragging {
                isHovered = hovering
            }
        }
    }
}



