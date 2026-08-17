// ArtistDetection.swift - Logic using credits metadata for featured artists
import Foundation

struct ArtistDetection {
    
    // MARK: - Album Artist Detection
    
    /// Determine the album artist based on main artist field only (ignoring credits)
    static func determineAlbumArtist(from tracks: [TrackMetadata]) -> String {
        guard !tracks.isEmpty else { return "Unknown Artist" }
        
        // Get main artists from the artist field
        let mainArtists = tracks.compactMap { (track: TrackMetadata) -> String? in
            guard let artist = track.artist, !artist.isEmpty else { return nil }
            return artist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !mainArtists.isEmpty else { return "Unknown Artist" }
        
        // Check if all tracks have the same main artist
        let uniqueMainArtists = Set(mainArtists.map { $0.lowercased() })
        
        if uniqueMainArtists.count == 1 {
            // All tracks have the same main artist
            return mainArtists.first!
        } else {
            // Multiple different main artists = Various Artists
            return "Various Artists"
        }
    }
    
    /// Check if an album should be considered "Various Artists"
    static func isVariousArtistsAlbum(tracks: [TrackMetadata]) -> Bool {
        return determineAlbumArtist(from: tracks) == "Various Artists"
    }
    
    /// Get all unique main artists from tracks (for Various Artists albums)
    static func getAllMainArtists(from tracks: [TrackMetadata]) -> [String] {
        let mainArtists = tracks.compactMap { (track: TrackMetadata) -> String? in
            guard let artist = track.artist, !artist.isEmpty else { return nil }
            return artist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let uniqueArtists = Array(Set(mainArtists))
        return uniqueArtists.sorted()
    }
    
    // MARK: - Featured Artist Detection (from credits)
    
    /// Get featured artists from track credits
    static func getFeaturedArtists(from track: TrackMetadata) -> [String] {
        guard let credits = track.credits else { return [] }
        
        let featuredRoles = ["Featured Artist"]
        
        return credits.compactMap { (credit: TrackMetadata.Credit) -> String? in
            if featuredRoles.contains(credit.role) && !credit.name.isEmpty {
                return credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
    }
    
    /// Check if a track has featured/guest artists
    static func trackHasFeaturedArtists(_ track: TrackMetadata) -> Bool {
        return !getFeaturedArtists(from: track).isEmpty
    }
    
    /// Get all featured/guest artists from an album
    static func getAllFeaturedArtists(from tracks: [TrackMetadata]) -> [String] {
        var allFeatured: Set<String> = []
        
        for track in tracks {
            let featured = getFeaturedArtists(from: track)
            for artist in featured {
                allFeatured.insert(artist)
            }
        }
        
        return Array(allFeatured).sorted()
    }
    
    // MARK: - Display Helpers
    
    /// Get main artist for display
    static func getMainArtist(from track: TrackMetadata) -> String {
        return track.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Artist"
    }
    
    /// Get formatted artist string for track display
    static func getFormattedArtistDisplay(from track: TrackMetadata) -> (main: String, featured: [String]) {
        let mainArtist = getMainArtist(from: track)
        let featuredArtists = getFeaturedArtists(from: track)
        
        return (main: mainArtist, featured: featuredArtists)
    }
    
    /// Get a single line artist display (main + featured)
    static func getSingleLineArtistDisplay(from track: TrackMetadata) -> String {
        let artistInfo = getFormattedArtistDisplay(from: track)
        
        if artistInfo.featured.isEmpty {
            return artistInfo.main
        } else {
            let featuredString = artistInfo.featured.joined(separator: ", ")
            return "\(artistInfo.main) feat. \(featuredString)"
        }
    }
}

// MARK: - Extensions

extension AlbumMetadata {
    /// Get the computed album artist (handles Various Artists logic)
    var computedAlbumArtist: String {
        return ArtistDetection.determineAlbumArtist(from: tracks)
    }
    
    /// Check if this is a Various Artists album
    var isVariousArtists: Bool {
        return ArtistDetection.isVariousArtistsAlbum(tracks: tracks)
    }
    
    /// Get all unique main artists in this album
    var uniqueMainArtists: [String] {
        return ArtistDetection.getAllMainArtists(from: tracks)
    }
    
    /// Get all featured/guest artists in this album
    var allFeaturedArtists: [String] {
        return ArtistDetection.getAllFeaturedArtists(from: tracks)
    }
}

extension TrackMetadata {
    /// Get featured/guest artists from credits
    var featuredArtists: [String] {
        return ArtistDetection.getFeaturedArtists(from: self)
    }
    
    /// Check if track has featured/guest artists
    var hasFeaturedArtists: Bool {
        return ArtistDetection.trackHasFeaturedArtists(self)
    }
    
    /// Get formatted artist display (main + featured separately)
    var formattedArtistDisplay: (main: String, featured: [String]) {
        return ArtistDetection.getFormattedArtistDisplay(from: self)
    }
    
    /// Get single line artist display
    var singleLineArtistDisplay: String {
        return ArtistDetection.getSingleLineArtistDisplay(from: self)
    }
}
