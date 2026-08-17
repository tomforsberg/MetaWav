// PlayCountManager.swift - Track play count management for MetaWav
import Foundation
import Combine

// MARK: - Play Count Data Model
struct PlayCountData: Codable {
    var plays: Int
    var lastPlayed: Date?
    
    init(plays: Int = 0, lastPlayed: Date? = nil) {
        self.plays = plays
        self.lastPlayed = lastPlayed
    }
}

// MARK: - Play Count Manager
class PlayCountManager: ObservableObject {
    static let shared = PlayCountManager()
    
    @Published var playCounts: [String: PlayCountData] = [:]
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let playDataDirectory: URL
    private let playDataFile: URL
    private let defaults = UserDefaults.standard
    private let defaultsKey = "PlayCounts.v1"
    
    private init() {
        // Set up file paths
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        playDataDirectory = documentsDirectory.appendingPathComponent("MetaWav/info")
        playDataFile = playDataDirectory.appendingPathComponent("playdata.json")
        
        // Create directory if it doesn't exist (for legacy migration path)
        createDirectoryIfNeeded()
        
        // Migrate legacy JSON storage into UserDefaults (once)
        migrateLegacyJSONIfNeeded()
        
        // Load existing play data from UserDefaults
        loadFromDefaults()
    }
    
    // MARK: - Public Interface
    
    /// Increment play count for a track
    func incrementPlayCount(trackId: String) {
        let currentData = playCounts[trackId] ?? PlayCountData()
        let newPlayCount = currentData.plays + 1
        
        playCounts[trackId] = PlayCountData(
            plays: newPlayCount,
            lastPlayed: Date()
        )
        
        // Persist to UserDefaults
        saveToDefaults()
        
        // Notify UI of changes
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        print("📊 Incremented play count for track \(trackId): \(newPlayCount) plays (was \(currentData.plays))")
    }
    
    /// Get play count for a track
    func getPlayCount(trackId: String) -> Int {
        return playCounts[trackId]?.plays ?? 0
    }
    
    /// Get play count data for a track
    func getPlayCountData(trackId: String) -> PlayCountData? {
        return playCounts[trackId]
    }
    
    /// Get top tracks by artist (sorted by play count, descending)
    func getTopTracksByArtist(artistId: String, limit: Int = 5) -> [(trackId: String, playCount: Int)] {
        // Get all tracks for this artist from the album manager
        let albums = AlbumMetadataManager.shared.loadAllAlbums()
        var artistTracks: [(trackId: String, playCount: Int)] = []
        
        for album in albums {
            for track in album.tracks {
                if track.artist == artistId {
                    let trackId = track.stableTrackId
                    let playCount = getPlayCount(trackId: trackId)
                    artistTracks.append((trackId: trackId, playCount: playCount))
                }
            }
        }
        
        // Sort by play count (descending) and limit results
        return artistTracks
            .sorted { $0.playCount > $1.playCount }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Get all play counts (for debugging/admin purposes)
    func getAllPlayCounts() -> [String: PlayCountData] {
        return playCounts
    }
    
    /// Reset play count for a specific track
    func resetPlayCount(trackId: String) {
        playCounts.removeValue(forKey: trackId)
        saveToDefaults()
        print("🔄 Reset play count for track \(trackId)")
    }
    
    /// Reset all play counts
    func resetAllPlayCounts() {
        playCounts.removeAll()
        saveToDefaults()
        print("🔄 Reset all play counts")
    }
    
    // MARK: - File Operations
    
    private func createDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: playDataDirectory, withIntermediateDirectories: true, attributes: nil)
            print("📁 Created play data directory: \(playDataDirectory.path)")
        } catch {
            print("❌ Failed to create play data directory: \(error)")
        }
    }
    
    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: defaultsKey) else {
            playCounts = [:]
            return
        }
        do {
            let decoder = JSONDecoder()
            playCounts = try decoder.decode([String: PlayCountData].self, from: data)
            print("📊 Loaded play data (UserDefaults) for \(playCounts.count) tracks")
        } catch {
            print("❌ Failed to decode play data from defaults: \(error)")
            playCounts = [:]
        }
    }
    
    private func saveToDefaults() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(playCounts)
            defaults.set(data, forKey: defaultsKey)
            defaults.synchronize()
            print("💾 Saved play data (UserDefaults) for \(playCounts.count) tracks")
        } catch {
            print("❌ Failed to encode play data to defaults: \(error)")
        }
    }
    
    private func migrateLegacyJSONIfNeeded() {
        // Only migrate if defaults are empty and legacy file exists
        if defaults.data(forKey: defaultsKey) != nil { return }
        guard fileManager.fileExists(atPath: playDataFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: playDataFile)
            let decoder = JSONDecoder()
            let legacy = try decoder.decode([String: PlayCountData].self, from: data)
            playCounts = legacy
            saveToDefaults()
            print("📦 Migrated legacy playdata.json (\(legacy.count) entries) to UserDefaults")
            
            // Optionally remove or archive the legacy file
            try? fileManager.removeItem(at: playDataFile)
        } catch {
            print("❌ Migration failed, continuing with empty store: \(error)")
            playCounts = [:]
        }
    }
}

// MARK: - Track ID Generation Helpers
extension PlayCountManager {
    
    /// Generate a stable track ID from TrackMetadata
    func generateTrackId(from track: TrackMetadata) -> String {
        // Prefer industry-standard ISRC when available; fallback to file path
        if let isrc = track.isrc, !isrc.isEmpty {
            return "isrc:" + isrc
        }
        return track.filePath
    }
    
    /// Generate a stable track ID from file path
    func generateTrackId(from filePath: String) -> String {
        return filePath
    }
    
    /// Generate a stable track ID from QueueItem
    func generateTrackId(from queueItem: QueueItem) -> String {
        if let track = queueItem.track {
            return generateTrackId(from: track)
        } else {
            return queueItem.audioFile.url.path
        }
    }
}
