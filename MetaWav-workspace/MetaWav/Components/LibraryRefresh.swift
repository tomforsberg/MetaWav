// SmartRefreshSystem.swift - New intelligent refresh system for MetaWav
import Foundation
import SwiftUI
import Combine

// MARK: - Refresh Event Types
enum RefreshEventType {
    case trackUpdated(trackId: UUID, albumName: String)
    case albumUpdated(albumName: String)
    case artistUpdated(oldName: String?, newName: String?)
    case albumArtChanged(albumName: String, isFront: Bool)
    case trackDeleted(trackId: UUID, albumName: String)
    case albumDeleted(albumName: String)
    case artistDeleted(artistName: String)
    case fullLibraryRefresh
}

// MARK: - Refresh Event
struct RefreshEvent {
    let id = UUID()
    let type: RefreshEventType
    let timestamp = Date()
    let metadata: [String: Any]?
    
    init(type: RefreshEventType, metadata: [String: Any]? = nil) {
        self.type = type
        self.metadata = metadata
    }
}

// MARK: - Smart Refresh Coordinator
class SmartRefreshCoordinator: ObservableObject {
    static let shared = SmartRefreshCoordinator()
    
    // Published properties for views to observe
    @Published var lastRefreshEvent: RefreshEvent?
    @Published var albumsNeedingRefresh: Set<String> = []
    @Published var artistsNeedingRefresh: Set<String> = []
    @Published var tracksNeedingRefresh: Set<UUID> = []
    @Published var isPerformingFullRefresh = false
    
    // Cache for quick lookups
    private var albumCache: [String: AlbumMetadata] = [:]
    private var artistCache: [String: ArtistProfile] = [:]
    private var trackToAlbumMap: [UUID: String] = [:]
    private var artistToAlbumsMap: [String: Set<String>] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private let refreshQueue = DispatchQueue(label: "com.metawav.refresh", qos: .userInitiated)
    
    private init() {
        setupNotificationObservers()
        rebuildCache()
    }
    
    // MARK: - Public Methods
    
    /// Process a metadata change and trigger appropriate updates
    func processMetadataChange(_ event: RefreshEvent) {
        print("🔥 SmartRefreshCoordinator: Processing refresh event: \(event.type)")
        
        refreshQueue.async { [weak self] in
            guard let self = self else { return }
            
            switch event.type {
            case .trackUpdated(let trackId, let albumName):
                print("🔥 SmartRefreshCoordinator: Handling track update: \(trackId) in \(albumName)")
                self.handleTrackUpdate(trackId: trackId, albumName: albumName)
                
            case .albumUpdated(let albumName):
                print("🔥 SmartRefreshCoordinator: Handling album update: \(albumName)")
                self.handleAlbumUpdate(albumName: albumName)
                
            case .artistUpdated(let oldName, let newName):
                self.handleArtistUpdate(oldName: oldName, newName: newName)
                
            case .albumArtChanged(let albumName, _):
                self.handleAlbumArtChange(albumName: albumName)
                
            case .trackDeleted(let trackId, let albumName):
                self.handleTrackDeletion(trackId: trackId, albumName: albumName)
                
            case .albumDeleted(let albumName):
                self.handleAlbumDeletion(albumName: albumName)
                
            case .artistDeleted(let artistName):
                self.handleArtistDeletion(artistName: artistName)
                
            case .fullLibraryRefresh:
                self.performFullLibraryRefresh()
            }
            
            // Update the last event for observers
            DispatchQueue.main.async {
                        print("🔥 SmartRefreshCoordinator: Setting lastRefreshEvent")
                        self.lastRefreshEvent = event
            }
        }
    }
    
    /// Request a targeted refresh for specific entities
    func requestRefresh(for entity: RefreshableEntity) {
        switch entity {
        case .track(let id, let albumName):
            processMetadataChange(RefreshEvent(type: .trackUpdated(trackId: id, albumName: albumName)))
        case .album(let name):
            processMetadataChange(RefreshEvent(type: .albumUpdated(albumName: name)))
        case .artist(let name):
            processMetadataChange(RefreshEvent(type: .artistUpdated(oldName: name, newName: name)))
        case .library:
            processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))
        }
    }
    
    // MARK: - Private Update Handlers
    
    private func handleTrackUpdate(trackId: UUID, albumName: String) {
        print("🎵 Handling track update: \(trackId) in album: \(albumName)")
        
        // Mark track for refresh
        DispatchQueue.main.async {
            self.tracksNeedingRefresh.insert(trackId)
            self.albumsNeedingRefresh.insert(albumName)
        }
        
        // Check if artist changed
        if let album = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumName),
           let track = album.tracks.first(where: { $0.id == trackId }) {
            
            // Update track-to-album mapping
            trackToAlbumMap[trackId] = albumName
            
            // Check for artist changes
            if let previousAlbum = albumCache[albumName],
               let previousTrack = previousAlbum.tracks.first(where: { $0.id == trackId }) {
                
                if previousTrack.artist != track.artist {
                    // Artist changed - update both old and new artist
                    if let oldArtist = previousTrack.artist {
                        handleArtistTrackRemoval(artistName: oldArtist, albumName: albumName)
                    }
                    if let newArtist = track.artist {
                        handleArtistTrackAddition(artistName: newArtist, albumName: albumName)
                    }
                }
            }
            
            // Update cache
            albumCache[albumName] = album
        }
        
        // Clean up orphaned entities
        cleanupOrphanedEntities()
    }
    
    private func handleAlbumUpdate(albumName: String) {
        print("💿 Handling album update: \(albumName)")
        
        DispatchQueue.main.async {
            self.albumsNeedingRefresh.insert(albumName)
        }
        
        // Reload album and update cache
        if let album = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumName) {
            let previousAlbum = albumCache[albumName]
            albumCache[albumName] = album
            
            // Check for artist changes at album level
            let previousArtists = extractArtistsFromAlbum(previousAlbum)
            let currentArtists = extractArtistsFromAlbum(album)
            
            // Find artists that were removed
            let removedArtists = previousArtists.subtracting(currentArtists)
            for artist in removedArtists {
                handleArtistTrackRemoval(artistName: artist, albumName: albumName)
            }
            
            // Find artists that were added
            let addedArtists = currentArtists.subtracting(previousArtists)
            for artist in addedArtists {
                handleArtistTrackAddition(artistName: artist, albumName: albumName)
            }
        }
        
        cleanupOrphanedEntities()
    }
    
    private func handleArtistUpdate(oldName: String?, newName: String?) {
        print("🎭 Handling artist update: \(oldName ?? "nil") -> \(newName ?? "nil")")
        
        if let oldName = oldName {
            DispatchQueue.main.async {
                self.artistsNeedingRefresh.insert(oldName)
            }
        }
        
        if let newName = newName {
            DispatchQueue.main.async {
                self.artistsNeedingRefresh.insert(newName)
            }
            
            // Reload artist profile
            ArtistManager.shared.loadAllArtists()
        }
        
        cleanupOrphanedEntities()
    }
    
    private func handleAlbumArtChange(albumName: String) {
        print("🎨 Handling album art change: \(albumName)")
        
        DispatchQueue.main.async {
            self.albumsNeedingRefresh.insert(albumName)
        }
        
        // Update cache with new artwork paths
        if let album = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumName) {
            albumCache[albumName] = album
        }
    }
    
    private func handleTrackDeletion(trackId: UUID, albumName: String) {
        print("🗑️ Handling track deletion: \(trackId) from album: \(albumName)")
        
        DispatchQueue.main.async {
            self.tracksNeedingRefresh.remove(trackId)
            self.albumsNeedingRefresh.insert(albumName)
        }
        
        // Remove from cache
        trackToAlbumMap.removeValue(forKey: trackId)
        
        // Check if album is now empty
        if let album = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumName) {
            if album.tracks.isEmpty {
                handleAlbumDeletion(albumName: albumName)
            } else {
                albumCache[albumName] = album
            }
        }
        
        cleanupOrphanedEntities()
    }
    
    private func handleAlbumDeletion(albumName: String) {
        print("🗑️ Handling album deletion: \(albumName)")
        
        // Get artists from album before deletion
        let artists = extractArtistsFromAlbum(albumCache[albumName])
        
        DispatchQueue.main.async {
            self.albumsNeedingRefresh.remove(albumName)
        }
        
        // Remove from cache
        albumCache.removeValue(forKey: albumName)
        
        // Update artist mappings
        for artist in artists {
            artistToAlbumsMap[artist]?.remove(albumName)
        }
        
        // Clean up orphaned artists
        cleanupOrphanedArtists()
    }
    
    private func handleArtistDeletion(artistName: String) {
        print("🗑️ Handling artist deletion: \(artistName)")
        
        DispatchQueue.main.async {
            self.artistsNeedingRefresh.remove(artistName)
        }
        
        // Remove from cache
        artistCache.removeValue(forKey: artistName)
        artistToAlbumsMap.removeValue(forKey: artistName)
    }
    
    private func handleArtistTrackRemoval(artistName: String, albumName: String) {
        artistToAlbumsMap[artistName]?.remove(albumName)
        
        DispatchQueue.main.async {
            self.artistsNeedingRefresh.insert(artistName)
        }
    }
    
    private func handleArtistTrackAddition(artistName: String, albumName: String) {
        if artistToAlbumsMap[artistName] == nil {
            artistToAlbumsMap[artistName] = Set<String>()
        }
        artistToAlbumsMap[artistName]?.insert(albumName)
        
        DispatchQueue.main.async {
            self.artistsNeedingRefresh.insert(artistName)
        }
    }
    
    // MARK: - Cleanup Methods
    
    private func cleanupOrphanedEntities() {
        cleanupOrphanedAlbums()
        cleanupOrphanedArtists()
    }
    
    private func cleanupOrphanedAlbums() {
        let allAlbums = AlbumMetadataManager.shared.loadAllAlbums()
        
        for album in allAlbums where album.tracks.isEmpty {
            print("🧹 Removing empty album: \(album.albumName)")
            do {
                try AlbumMetadataManager.shared.deleteAlbum(album.albumName)
                handleAlbumDeletion(albumName: album.albumName)
            } catch {
                print("❌ Failed to delete empty album: \(error)")
            }
        }
    }
    
    private func cleanupOrphanedArtists() {
        // Check each artist in the map
        for (artistName, albums) in artistToAlbumsMap {
            if albums.isEmpty {
                print("🧹 Removing orphaned artist: \(artistName)")
                
                // Delete artist profile
                if let artist = ArtistManager.shared.artists.first(where: { $0.name == artistName }) {
                    ArtistManager.shared.deleteArtistProfile(artist)
                }
                
                // Clean up any remaining artist files
                cleanupArtistFiles(artistName)
                
                handleArtistDeletion(artistName: artistName)
            }
        }
    }
    
    private func cleanupArtistFiles(_ artistName: String) {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
        
        let sanitizedName = sanitizeFilename(artistName)
        
        // Clean up various artist-related files
        let directoriesToCheck = [
            metaWavDir.appendingPathComponent("Artists"),
            metaWavDir.appendingPathComponent("ArtistMetadata"),
            metaWavDir.appendingPathComponent("Metadata"),
            metaWavDir.appendingPathComponent("Art")
        ]
        
        for directory in directoriesToCheck {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                for file in files {
                    if file.lastPathComponent.contains(sanitizedName) {
                        try FileManager.default.removeItem(at: file)
                        print("🗑️ Deleted artist file: \(file.lastPathComponent)")
                    }
                }
            } catch {
                // Directory might not exist, that's okay
            }
        }
    }
    
    // MARK: - Full Library Refresh
    
    private func performFullLibraryRefresh() {
        print("🔄 Performing full library refresh")
        
        DispatchQueue.main.async {
            self.isPerformingFullRefresh = true
            self.albumsNeedingRefresh.removeAll()
            self.artistsNeedingRefresh.removeAll()
            self.tracksNeedingRefresh.removeAll()
        }
        
        refreshQueue.async { [weak self] in
            self?.rebuildCache()
            
            DispatchQueue.main.async {
                self?.isPerformingFullRefresh = false
                
                // Notify all views to refresh
                NotificationManager.shared.postNotification(.fullLibraryRefresh, object: nil)
            }
        }
    }
    
    // MARK: - Cache Management
    
    private func rebuildCache() {
        print("🏗️ Rebuilding cache")
        
        albumCache.removeAll()
        artistCache.removeAll()
        trackToAlbumMap.removeAll()
        artistToAlbumsMap.removeAll()
        
        // Load all albums
        let allAlbums = AlbumMetadataManager.shared.loadAllAlbums()
        for album in allAlbums {
            albumCache[album.albumName] = album
            
            // Build track mapping
            for track in album.tracks {
                trackToAlbumMap[track.id] = album.albumName
                
                // Build artist mapping
                if let artist = track.artist {
                    if artistToAlbumsMap[artist] == nil {
                        artistToAlbumsMap[artist] = Set<String>()
                    }
                    artistToAlbumsMap[artist]?.insert(album.albumName)
                }
            }
        }
        
        // Load all artists
        ArtistManager.shared.loadAllArtists()
        for artist in ArtistManager.shared.artists {
            artistCache[artist.name] = artist
        }
        
        print("📊 Cache rebuilt: \(albumCache.count) albums, \(artistCache.count) artists, \(trackToAlbumMap.count) tracks")
    }
    
    // MARK: - Helper Methods
    
    private func extractArtistsFromAlbum(_ album: AlbumMetadata?) -> Set<String> {
        guard let album = album else { return Set<String>() }
        
        var artists = Set<String>()
        for track in album.tracks {
            if let artist = track.artist {
                artists.insert(artist)
            }
            // Also include featured artists from credits
            let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
            for featured in featuredArtists {
                artists.insert(featured)
            }
        }
        return artists
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Listen to existing notifications and convert to refresh events
        NotificationCenter.default.publisher(for: .albumMetadataChanged)
            .compactMap { $0.object as? AlbumMetadata }
            .sink { [weak self] album in
                self?.processMetadataChange(RefreshEvent(type: .albumUpdated(albumName: album.albumName)))
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .trackMetadataChanged)
            .compactMap { $0.object as? (TrackMetadata, AlbumMetadata) }
            .sink { [weak self] trackAndAlbum in
                let (track, album) = trackAndAlbum
                self?.processMetadataChange(RefreshEvent(type: .trackUpdated(trackId: track.id, albumName: album.albumName)))
            }
            .store(in: &cancellables)

        // Backward compatibility: accept (TrackMetadata, String) where String is albumName
        NotificationCenter.default.publisher(for: .trackMetadataChanged)
            .compactMap { $0.object as? (TrackMetadata, String) }
            .sink { [weak self] trackAndName in
                let (track, albumName) = trackAndName
                self?.processMetadataChange(RefreshEvent(type: .trackUpdated(trackId: track.id, albumName: albumName)))
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .albumArtChanged)
            .compactMap { $0.object as? AlbumMetadata }
            .sink { [weak self] album in
                self?.processMetadataChange(RefreshEvent(type: .albumArtChanged(albumName: album.albumName, isFront: true)))
            }
            .store(in: &cancellables)

        // NEW: Album reordered → treat as updated album so views refresh ordering
        NotificationCenter.default.publisher(for: .albumReordered)
            .compactMap { $0.object as? AlbumMetadata }
            .sink { [weak self] album in
                self?.processMetadataChange(RefreshEvent(type: .albumUpdated(albumName: album.albumName)))
            }
            .store(in: &cancellables)

        // NEW: Track repathed → resolve album and emit targeted track update
        NotificationCenter.default.publisher(for: .trackRepathed)
            .compactMap { $0.object as? TrackMetadata }
            .sink { [weak self] track in
                if let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.name) {
                    self?.processMetadataChange(RefreshEvent(type: .trackUpdated(trackId: track.id, albumName: album.albumName)))
                } else {
                    // Fallback: schedule a scoped refresh of tracks; views will handle absence gracefully
                    self?.processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .albumDeleted)
            .compactMap { $0.object as? String }
            .sink { [weak self] albumName in
                self?.processMetadataChange(RefreshEvent(type: .albumDeleted(albumName: albumName)))
            }
            .store(in: &cancellables)

        // NEW: Artist updates/deletes routed to coordinator
        NotificationCenter.default.publisher(for: .artistUpdated)
            .compactMap { $0.object }
            .sink { [weak self] payload in
                if let profile = payload as? ArtistProfile {
                    self?.processMetadataChange(RefreshEvent(type: .artistUpdated(oldName: profile.name, newName: profile.name)))
                } else if let tuple = payload as? (String?, String?) {
                    self?.processMetadataChange(RefreshEvent(type: .artistUpdated(oldName: tuple.0, newName: tuple.1)))
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .artistDeleted)
            .compactMap { $0.object as? String }
            .sink { [weak self] artistName in
                self?.processMetadataChange(RefreshEvent(type: .artistDeleted(artistName: artistName)))
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

enum RefreshableEntity {
    case track(id: UUID, albumName: String)
    case album(name: String)
    case artist(name: String)
    case library
}

// MARK: - Notification Extensions

// MARK: - Notification Extensions

extension Notification.Name {
    static let fullLibraryRefresh = Notification.Name("fullLibraryRefresh")
    static let targetedRefresh = Notification.Name("targetedRefresh")
    
    // Missing notification names that are used in setupNotificationObservers()
    static let albumMetadataChanged = Notification.Name("albumMetadataChanged")
    static let albumArtChanged = Notification.Name("albumArtChanged")
    static let mwPluginsDidChange = Notification.Name("MWPluginsDidChange")
}

// MARK: - View Update Helper

protocol SmartRefreshable {
    func handleRefreshEvent(_ event: RefreshEvent)
    func performTargetedRefresh(for entities: RefreshableEntity...)
}

// MARK: - SwiftUI View Extension for Smart Refresh

extension View {
    func smartRefresh() -> some View {
        self.modifier(SmartRefreshModifier())
    }
}

struct SmartRefreshModifier: ViewModifier {
    @StateObject private var coordinator = SmartRefreshCoordinator.shared
    
    func body(content: Content) -> some View {
        content
            .onReceive(coordinator.$lastRefreshEvent) { event in
                // Views can respond to refresh events
            }
    }
}
