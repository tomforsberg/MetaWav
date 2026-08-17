//LibraryPanel.swift - FIXED: Consistent scrubber positioning across all views + center cropping for artists
import SwiftUI
import AVFoundation
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Async Image Loader Component

struct AsyncImageLoader: View {
    let imagePath: String
    let size: CGSize
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Rectangle()
                    .fill(Color(white: 0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(Color(white: 0.5))
                    )
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        DispatchQueue.global(qos: .utility).async {
            let loadedImage = NSImage(contentsOfFile: imagePath)
            
            DispatchQueue.main.async {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

// MARK: - Liquid Glass Background Modifier
private struct LiquidGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: Rectangle()
            )
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .center
                )
                .allowsHitTesting(false)
            )
    }
}

// MARK: - Required Enums (unchanged)

enum LibraryViewType: String, CaseIterable {
    case albums = "Albums"
    case artists = "Artists"
    case playlists = "Playlists"
    case allTracks = "All Tracks"
    
    var displayName: String {
        switch self {
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        case .allTracks: return "Tracks"
        }
    }
}

enum TrackSortOption: String, CaseIterable {
    case trackName = "Track Name"
    case artistName = "Artist Name"
    case albumName = "Album Name"
    case albumTrack = "Album & Track"
    case duration = "Duration"
    case dateAdded = "Date Added"
    case playCount = "Play Count"
    
    var iconName: String {
        switch self {
        case .trackName: return "music.note"
        case .artistName: return "person"
        case .albumName: return "opticaldisc"
        case .albumTrack: return "list.number"
        case .duration: return "clock"
        case .dateAdded: return "calendar"
        case .playCount: return "play.circle"
        }
    }
}

// Sorting options for the All Tracks table headers
enum TrackTableSortColumn: String {
    case index
    case trackName
    case artistName
    case albumName
    case albumTrack
    case duration
    case playCount
    case bpm
    case key
    case format
    case sampleRate
    case bitrate
    case isExplicit
    case version
}

enum LibraryViewState {
    case grid
    case albumDetail(AlbumMetadata)
    case artistDetail(ArtistProfile)
    case playlistDetail(PlaylistMetadata)
}

// MARK: - Enhanced Playlist Data Structures

struct PlaylistMetadata: Codable, Identifiable {
    let id = UUID()
    let playlistId: String // Unique persistent identifier
    var name: String
    var description: String?
    var createdDate: Date
    var modifiedDate: Date
    var trackCount: Int
    var duration: TimeInterval?
    var tracks: [PlaylistTrack]
    var artworkPath: String? // For future playlist artwork support
    
    init(name: String, description: String? = nil) {
        self.playlistId = UUID().uuidString
        self.name = name
        self.description = description
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.trackCount = 0
        self.duration = 0
        self.tracks = []
        self.artworkPath = nil
    }
    
    mutating func updateTrackCount() {
        trackCount = tracks.count
    }
    
    mutating func calculateDuration() {
        // Calculate actual duration from track metadata
        duration = tracks.compactMap { track in
            // Try to get duration from track metadata
            if let (_, trackMetadata) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.trackName) {
                return trackMetadata.duration
            }
            return 0.0
        }.reduce(0, +)
    }
    
    mutating func addTrack(_ track: TrackMetadata, at position: Int? = nil) {
        let playlistTrack = PlaylistTrack(
            filePath: track.filePath,
            trackName: track.name,
            artistName: track.artist,
            albumName: "Unknown Album", // Will be updated when we find the album
            duration: track.duration
        )
        
        if let position = position, position >= 0 && position <= tracks.count {
            tracks.insert(playlistTrack, at: position)
        } else {
            tracks.append(playlistTrack)
        }
        
        updatePositions()
        updateTrackCount()
        calculateDuration()
        modifiedDate = Date()
    }
    
    mutating func removeTrack(at index: Int) {
        guard index >= 0 && index < tracks.count else { return }
        tracks.remove(at: index)
        updatePositions()
        updateTrackCount()
        calculateDuration()
        modifiedDate = Date()
    }
    
    mutating func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < tracks.count,
              destinationIndex >= 0 && destinationIndex <= tracks.count else { return }
        
        let track = tracks.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tracks.insert(track, at: adjustedDestination)
        
        updatePositions()
        modifiedDate = Date()
    }
    
    mutating func updatePositions() {
        for (index, _) in tracks.enumerated() {
            tracks[index].playlistPosition = index + 1
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, playlistId, name, description, createdDate, modifiedDate, trackCount, duration, tracks, artworkPath
    }
}

struct PlaylistTrack: Codable, Identifiable, Equatable {
    let id = UUID()
    var filePath: String
    var playlistPosition: Int
    var addedDate: Date
    var trackName: String
    var artistName: String?
    var albumName: String
    var duration: TimeInterval?
    
    init(filePath: String, trackName: String, artistName: String?, albumName: String, duration: TimeInterval? = nil) {
        self.filePath = filePath
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.playlistPosition = 0
        self.addedDate = Date()
    }
    
    var formattedDuration: String {
        guard let duration = duration, duration > 0 else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    enum CodingKeys: String, CodingKey {
        case filePath, playlistPosition, addedDate, trackName, artistName, albumName, duration
    }
}

// MARK: - Playlist Statistics

struct PlaylistStats {
    let totalTracks: Int
    let uniqueTracks: Int
    let duplicateTracks: Int
    let uniqueArtists: Int
    let uniqueAlbums: Int
    let totalDuration: TimeInterval
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

// MARK: - Smart Playlist Criteria

struct SmartPlaylistCriteria {
    let artist: String?
    let album: String?
    let genre: String?
    let year: String?
    let minDuration: TimeInterval?
    let maxDuration: TimeInterval?
    let minPlayCount: Int?
    let maxPlayCount: Int?
    let maxTracks: Int?
    let sortBy: SmartPlaylistSortOption
    let description: String?
    
    init(
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        year: String? = nil,
        minDuration: TimeInterval? = nil,
        maxDuration: TimeInterval? = nil,
        minPlayCount: Int? = nil,
        maxPlayCount: Int? = nil,
        maxTracks: Int? = nil,
        sortBy: SmartPlaylistSortOption = .name,
        description: String? = nil
    ) {
        self.artist = artist
        self.album = album
        self.genre = genre
        self.year = year
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.minPlayCount = minPlayCount
        self.maxPlayCount = maxPlayCount
        self.maxTracks = maxTracks
        self.sortBy = sortBy
        self.description = description
    }
}

enum SmartPlaylistSortOption: String, CaseIterable {
    case name = "Track Name"
    case artist = "Artist"
    case album = "Album"
    case duration = "Duration"
    case playCount = "Play Count"
    case random = "Random"
    
    var displayName: String {
        return self.rawValue
    }
}

// MARK: - Manager Classes (unchanged)

class AllTracksManager: ObservableObject {
    static let shared = AllTracksManager()
    
    @Published var allTracks: [TrackWithAlbum] = []
    @Published var sortOption: TrackSortOption = .albumTrack
    @Published var searchFilter: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    
    struct TrackWithAlbum: Identifiable {
        let id = UUID()
        let track: TrackMetadata
        let album: AlbumMetadata
        let albumName: String
        let artistName: String
        
        // Make playCount a computed property so it always reflects current data
        var playCount: Int {
            return PlayCountManager.shared.getPlayCount(trackId: track.stableTrackId)
        }
        
        init(track: TrackMetadata, album: AlbumMetadata, albumName: String, artistName: String) {
            self.track = track
            self.album = album
            self.albumName = albumName
            self.artistName = artistName
        }
    }
    
    var filteredTracks: [TrackWithAlbum] {
        let filtered = searchFilter.isEmpty ? allTracks : allTracks.filter { trackWithAlbum in
            trackWithAlbum.track.name.localizedCaseInsensitiveContains(searchFilter) ||
            trackWithAlbum.artistName.localizedCaseInsensitiveContains(searchFilter) ||
            trackWithAlbum.albumName.localizedCaseInsensitiveContains(searchFilter)
        }
        
        return sortTracks(filtered, by: sortOption)
    }
    
    private init() {
        // Listen for play count changes to trigger UI updates
        PlayCountManager.shared.$playCounts
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }
    
    func refreshAllTracks() {
        let albums = AlbumMetadataManager.shared.loadAllAlbums()
        var tracks: [TrackWithAlbum] = []
        
        for album in albums {
            for track in album.tracks {
                let trackWithAlbum = TrackWithAlbum(
                    track: track,
                    album: album,
                    albumName: album.albumName,
                    artistName: track.artist ?? "Unknown Artist"
                )
                tracks.append(trackWithAlbum)
            }
        }
        
        DispatchQueue.main.async {
            self.allTracks = tracks
        }
    }
    
    func setSortOption(_ option: TrackSortOption) {
        sortOption = option
    }
    
    
    private func sortTracks(_ tracks: [TrackWithAlbum], by option: TrackSortOption) -> [TrackWithAlbum] {
        switch option {
        case .trackName:
            return tracks.sorted { $0.track.name.localizedCaseInsensitiveCompare($1.track.name) == .orderedAscending }
        case .artistName:
            return tracks.sorted { $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending }
        case .albumName:
            return tracks.sorted { $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending }
        case .albumTrack:
            return tracks.sorted { lhs, rhs in
                if lhs.albumName != rhs.albumName {
                    return lhs.albumName.localizedCaseInsensitiveCompare(rhs.albumName) == .orderedAscending
                }
                if lhs.track.discNumber != rhs.track.discNumber {
                    return lhs.track.discNumber < rhs.track.discNumber
                }
                return lhs.track.trackNumber < rhs.track.trackNumber
            }
        case .duration:
            return tracks.sorted {
                let duration1 = $0.track.duration ?? 0
                let duration2 = $1.track.duration ?? 0
                return duration1 < duration2
            }
        case .dateAdded:
            return tracks.sorted { $0.album.albumName < $1.album.albumName }
        case .playCount:
            return tracks.sorted { $0.playCount > $1.playCount } // Descending order (most played first)
        }
    }
}

// MARK: - FIXED Main LibraryPanel View with Consistent Scrubber Positioning
struct LibraryPanel: View {
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentFileIndex: Int?
    @Binding var currentTime: TimeInterval
    @Binding var selectedTrack: TrackMetadata?
    @Binding var isPoweredOn: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    
    @StateObject private var albumManager = AlbumMetadataManager.shared
    @StateObject private var playlistManager = PlaylistManager.shared
    @StateObject private var allTracksManager = AllTracksManager.shared
    @StateObject private var artistManager = ArtistManager.shared
    @StateObject private var queueManager = QueueManager.shared
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    
    @State private var selectedLibraryView: LibraryViewType = .albums
    @State private var viewState: LibraryViewState = .grid
    @State private var selectedAlbum: AlbumMetadata? = nil
    @State private var selectedPlaylist: PlaylistMetadata? = nil
    @State private var selectedArtist: ArtistProfile? = nil
    @State private var hoveredItem: String? = nil
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadingMessage = ""
    @State private var navigationTarget: NavigationTarget? = nil
    @State private var albumsRefreshTrigger: Int = 0  // Add this to force view updates
    @State private var showPlaylistManagement = false
    @State private var selectedTracksForPlaylist: [TrackMetadata] = []
    @State private var selectedAlbumForPlaylist: AlbumMetadata? = nil
    @State private var trackSortColumn: TrackTableSortColumn = .albumTrack
    @State private var trackSortAscending: Bool = true
    @State private var hoveredTrackId: UUID? = nil
    @State private var bitrateCache: [String: Int] = [:] // filePath -> kbps (MP3 only)
    @State private var wavBitDepthCache: [String: String] = [:] // filePath -> "16-bit" etc (WAV only)
    @State private var showPowerAlert: Bool = false
    // Multi-selection state for All Tracks view
    @State private var selectedTrackIDs: Set<UUID> = []
    @State private var hoveredTrackID: UUID? = nil
    // Precise hover states for inline hyperlinks
    @State private var hoveredTrackNameID: UUID? = nil
    @State private var hoveredArtistNameID: UUID? = nil
    @State private var hoveredAlbumNameID: UUID? = nil
    @State private var selectionAnchorIndex: Int? = nil
    @State private var hoveredLibraryView: LibraryViewType? = nil
    // Drag-and-drop state
    @State private var isDragTargeted: Bool = false
    @State private var isProcessingDrop: Bool = false
    @State private var dropSucceeded: Bool = false
    
    enum NavigationTarget {
        case artist(String)
        case album(AlbumMetadata)
    }
    
    let onNavigateToArtist: (String) -> Void
    
    // FIXED: More precise height calculations
    // NPS scrubber panel has been removed; no reserved height needed.
    private let scrubberHeight: CGFloat = 0
    private let headerHeight: CGFloat = 80        // Fixed header height
    private let dividerHeight: CGFloat = 1        // Fixed divider height
    
    private var filteredContent: [Any] {
        // Use albumsRefreshTrigger to force re-evaluation when albums change
        let _ = albumsRefreshTrigger
        
        switch selectedLibraryView {
        case .albums:
            if searchText.isEmpty {
                return albumManager.loadAllAlbums()
            } else {
                return albumManager.loadAllAlbums().filter { album in
                    album.albumName.localizedCaseInsensitiveContains(searchText) ||
                    (album.tracks.first?.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            }
        case .playlists:
            if searchText.isEmpty {
                return playlistManager.playlists
            } else {
                return playlistManager.playlists.filter { playlist in
                    playlist.name.localizedCaseInsensitiveContains(searchText) ||
                    (playlist.description?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            }
        case .allTracks:
            // Build from base tracks to avoid manager's extra sort; apply local search and sort once
            let base = allTracksManager.allTracks
            let filtered = searchText.isEmpty ? base : base.filter { twa in
                twa.track.name.localizedCaseInsensitiveContains(searchText) ||
                twa.artistName.localizedCaseInsensitiveContains(searchText) ||
                twa.albumName.localizedCaseInsensitiveContains(searchText)
            }
            let sorted = sortAllTracks(filtered)
            return Array(sorted.prefix(10000))
        case .artists:
            if searchText.isEmpty {
                return artistManager.artists
            } else {
                return artistManager.artists.filter { artist in
                    artist.name.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
     
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Show navigation based on view state
                switch viewState {
                case .grid:
                    // Standard library header
                    compactLibraryHeader(width: geometry.size.width)
                        .frame(height: headerHeight)
                    
                    // Grid content with calculated height (no reserved NPS scrubber space)
                    standardLibraryContent(
                        width: geometry.size.width,
                        height: geometry.size.height - headerHeight - dividerHeight - (isPoweredOn ? scrubberHeight : 0)
                    )
                    
                case .albumDetail(let album):
                    AlbumPageView(
                        album: album,
                        audioFiles: $audioFiles,
                        currentFileIndex: $currentFileIndex,
                        currentTime: $currentTime,
                        selectedTrack: $selectedTrack,
                        currentAlbum: $currentAlbum,
                        isPoweredOn: $isPoweredOn,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewState = .grid
                                selectedAlbum = nil
                            }
                        },
                        onPlayAlbum: { album in
                            playAlbum(album)
                        },
                        onNavigateToArtist: { artistName in
                            print("🔄 LibraryPanel received artist navigation request: \(artistName)")
                            
                            if let artist = artistManager.artists.first(where: { $0.name == artistName }) {
                                print("✅ Found artist, navigating to detail view")
                                selectArtistForDetailView(artist)
                            } else {
                                print("⚠️ Artist not found: \(artistName)")
                                print("📋 Available artists: \(artistManager.artists.map { $0.name })")
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .playlistDetail(let playlist):
                    PlaylistDetailView(
                        playlist: playlist,
                        isPoweredOn: $isPoweredOn,
                        selectedTrack: $selectedTrack,
                        currentAlbum: $currentAlbum,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewState = .grid
                                selectedPlaylist = nil
                            }
                        },
                        onNavigateToArtist: { artistName in
                            if let artist = artistManager.artists.first(where: { $0.name == artistName }) {
                                selectArtistForDetailView(artist)
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .artistDetail(let artist):
                    ArtistDetailView(
                        artist: artist,
                        allAlbums: albumManager.loadAllAlbums(),
                        selectedTrack: $selectedTrack,
                        currentAlbum: $currentAlbum,
                        isPoweredOn: $isPoweredOn,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewState = .grid
                                selectedArtist = nil
                            }
                        },
                        onEdit: {
                            print("Edit artist: \(artist.name)")
                        },
                        onNavigateToAlbum: { album in
                            selectAlbumForDetailView(album)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                
                }
                
                // NPS Panel removed visually; streaming deck + dynamic header now own scrubber and now-playing UI.
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // Fill entire container
        // Transparent to show global glass background
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color.white.opacity(0.08))
                .allowsHitTesting(false),
            alignment: .leading
        )
        .overlay(
            Color.clear
                .allowsHitTesting(false)
        )
        .overlay(
            Group {
                if showPlaylistManagement {
                    PlaylistManagementSheet(
                        tracks: selectedTracksForPlaylist.isEmpty ? nil : selectedTracksForPlaylist,
                        album: selectedAlbumForPlaylist,
                        isPresented: $showPlaylistManagement
                    )
                }
            }
        )
        .onAppear {
            refreshAllContent()
            artistManager.discoverAndCreateArtists(from: albumManager.loadAllAlbums())
        }
        .onChange(of: selectedLibraryView) { _, newView in
            if newView == .allTracks {
                loadAllTracksLazily()
            } else if newView == .artists {
                selectedArtist = nil
                artistManager.discoverAndCreateArtists(from: albumManager.loadAllAlbums())
            }
            
            viewState = .grid
        }
        // ADD THE SMART REFRESH RECEIVERS HERE
        .onReceive(SmartRefreshCoordinator.shared.$albumsNeedingRefresh) { albumNames in
            print("🔥 LibraryPanel: Received albumsNeedingRefresh: \(albumNames)")
            handleAlbumRefreshes(albumNames)
        }
        .onReceive(SmartRefreshCoordinator.shared.$artistsNeedingRefresh) { artistNames in
            print("🔥 LibraryPanel: Received artistsNeedingRefresh: \(artistNames)")
            handleArtistRefreshes(artistNames)
        }
        .onReceive(SmartRefreshCoordinator.shared.$isPerformingFullRefresh) { isRefreshing in
            print("🔥 LibraryPanel: Received isPerformingFullRefresh: \(isRefreshing)")
            if !isRefreshing {
                refreshAllContent()
            }
        }
        // ADD DIRECT NOTIFICATION HANDLERS FOR INSTANT UPDATES
        .onReceive(NotificationCenter.default.publisher(for: .fullLibraryRefresh)) { _ in
            print("📚 LibraryPanel: Full library refresh notification received")
            refreshAllContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .albumUpdated)) { notification in
            print("🔄 LibraryPanel: Album updated notification received")
            if let album = notification.object as? AlbumMetadata {
                // Update the current album if it matches
                if currentAlbum?.albumName == album.albumName {
                    currentAlbum = album
                }
                // Minimal view update; avoid broad refresh
                albumsRefreshTrigger += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .albumLoaded)) { notification in
            print("📥 LibraryPanel: albumLoaded notification received")
            if let album = notification.object as? AlbumMetadata {
                // Open the album detail view without touching playback/queue
                selectAlbumForDetailView(album)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .albumReordered)) { notification in
            print("📀 LibraryPanel: albumReordered notification received")
            if let album = notification.object as? AlbumMetadata {
                if currentAlbum?.albumName == album.albumName {
                    currentAlbum = album
                }
                // Trigger minimal content update
                albumsRefreshTrigger += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistCreated)) { _ in
            print("📁 LibraryPanel: playlistCreated notification received")
            playlistManager.loadAllPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistUpdated)) { _ in
            print("📁 LibraryPanel: playlistUpdated notification received")
            playlistManager.loadAllPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistDeleted)) { _ in
            print("🗑️ LibraryPanel: playlistDeleted notification received")
            playlistManager.loadAllPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackMetadataChanged)) { notification in
            print("🎵 LibraryPanel: Track metadata changed notification received")
            if let (_, album) = notification.object as? (TrackMetadata, AlbumMetadata) {
                if currentAlbum?.albumName == album.albumName {
                    currentAlbum = album
                }
            } else if let (_, albumName) = notification.object as? (TrackMetadata, String) {
                // Backward compatibility
                if currentAlbum?.albumName == albumName {
                    // No disk reload needed; currentAlbum already holds latest in-memory
                }
                }
            // Scoped refresh: only what we need
            if selectedLibraryView == .allTracks {
                loadAllTracksLazily()
            } else {
                albumsRefreshTrigger += 1
            }
        }
        .alert("Power Required", isPresented: $showPowerAlert) {
            Button("OK") { }
        } message: {
            Text("Please switch on power to play music.")
        }
    }
    
    // MARK: - All other methods remain exactly the same, just updated standardLibraryContent to use exact height
    
    @ViewBuilder
    private func standardLibraryContent(width: CGFloat, height: CGFloat) -> some View {
        if #available(macOS 13.0, *) {
            libraryPanelBaseContent(width: width, height: height)
                .dropDestination(for: URL.self) { items, _ in
                    isProcessingDrop = true
                    Task { await processDroppedURLs(items) }
                    return true
                } isTargeted: { targeted in
                    isDragTargeted = targeted
                }
        } else {
            libraryPanelBaseContent(width: width, height: height)
                .onDrop(of: [UTType.fileURL], isTargeted: $isDragTargeted) { providers in
                    handleDrop(providers: providers)
                }
        }
    }

    private func libraryPanelBaseContent(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Group {
                switch selectedLibraryView {
                case .albums:
                    albumsGridView(width: width, height: height)
                case .playlists:
                    playlistsView(width: width, height: height)
                case .allTracks:
                    allTracksView(width: width, height: height)
                case .artists:
                    artistsView(width: width, height: height)
                }
            }
            .blur(radius: isDragTargeted ? 3 : 0)
            
            if isLoading {
                ZStack {
                    Color.black.opacity(0.18)
                    
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0, green: 0.75, blue: 0.39)))
                        
                        Text(loadingMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08)))
                    .cornerRadius(12)
                }
            }

            // Drag/drop overlay
            if isDragTargeted || isProcessingDrop || dropSucceeded {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()

                    VStack(spacing: 10) {
                        if isProcessingDrop {
                            ProgressView()
                                .scaleEffect(0.9)
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.95, green: 0.76, blue: 0.20)))
                            Text("Loading files…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        } else if dropSucceeded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                            Text("Added to Library")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                            Text("Drag and drop audio files to load")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .transition(.opacity)
            }
        }
        .frame(height: height)
    }

    // MARK: - Sorting and Display Helpers for All Tracks
    private func sortableHeader(title: String, column: TrackTableSortColumn) -> some View {
        Button(action: {
            if trackSortColumn == column {
                trackSortAscending.toggle()
            } else {
                trackSortColumn = column
                trackSortAscending = true
            }
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.6))
                if trackSortColumn == column {
                    Image(systemName: trackSortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func sortAllTracks(_ tracks: [AllTracksManager.TrackWithAlbum]) -> [AllTracksManager.TrackWithAlbum] {
        let sorted: [AllTracksManager.TrackWithAlbum]
        switch trackSortColumn {
        case .index:
            sorted = tracks // Original order after AllTracksManager sort
        case .trackName:
            sorted = tracks.sorted { $0.track.name.localizedCaseInsensitiveCompare($1.track.name) == .orderedAscending }
        case .artistName:
            sorted = tracks.sorted { $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending }
        case .albumName:
            sorted = tracks.sorted { $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending }
        case .albumTrack:
            sorted = tracks.sorted { lhs, rhs in
                if lhs.albumName != rhs.albumName { return lhs.albumName.localizedCaseInsensitiveCompare(rhs.albumName) == .orderedAscending }
                if lhs.track.discNumber != rhs.track.discNumber { return lhs.track.discNumber < rhs.track.discNumber }
                return lhs.track.trackNumber < rhs.track.trackNumber
            }
        case .duration:
            sorted = tracks.sorted { ($0.track.duration ?? 0) < ($1.track.duration ?? 0) }
        case .playCount:
            sorted = tracks.sorted { $0.playCount < $1.playCount }
        case .bpm:
            sorted = tracks.sorted { ($0.track.bpm ?? Int.max) < ($1.track.bpm ?? Int.max) }
        case .key:
            sorted = tracks.sorted { ($0.track.key ?? "~").localizedCaseInsensitiveCompare($1.track.key ?? "~") == .orderedAscending }
        case .format:
            sorted = tracks.sorted { displayFormat(for: $0.track).localizedCaseInsensitiveCompare(displayFormat(for: $1.track)) == .orderedAscending }
        case .sampleRate:
            sorted = tracks.sorted { numericSampleRate(for: $0.track) < numericSampleRate(for: $1.track) }
        case .bitrate:
            sorted = tracks.sorted { numericBitrate(for: $0.track) < numericBitrate(for: $1.track) }
        case .isExplicit:
            sorted = tracks.sorted { ($0.track.isExplicit == true ? 1 : 0) < ($1.track.isExplicit == true ? 1 : 0) }
        case .version:
            sorted = tracks.sorted { ($0.track.version ?? "~").localizedCaseInsensitiveCompare($1.track.version ?? "~") == .orderedAscending }
        }
        return trackSortAscending ? sorted : sorted.reversed()
    }

    private func displayFormat(for track: TrackMetadata) -> String {
        // Always show container format/extension here
        if let format = track.format, !format.isEmpty { return format }
        let ext = URL(fileURLWithPath: track.filePath).pathExtension.uppercased()
        return ext.isEmpty ? "?" : ext
    }

    private func rowBackgroundColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return Color(white: 0.15) }
        if isHovered { return Color(white: 0.075) }
        return Color.clear
    }

    private func displaySampleRate(for track: TrackMetadata) -> String {
        if let sr = track.sampleRate {
            if sr >= 1000 { return "\(Int(sr)) Hz" }
            return String(format: "%.1f kHz", sr / 1000.0)
        }
        return "-"
    }

    private func numericSampleRate(for track: TrackMetadata) -> Int {
        if let sr = track.sampleRate { return Int(sr) }
        return 0
    }

    private func displayBitrate(for track: TrackMetadata) -> String {
        // Follow rule: lossy -> show Bitrate; lossless/uncompressed -> show Bit Depth; else show "-"
        switch track.audioFormatClass {
        case .lossy:
            if let kbps = getOrComputeBitrateKbps(for: track), kbps > 0 { return "\(kbps) kbps" }
            return "-"
        case .losslessOrUncompressed:
            if let bitDepth = track.bitDepth, !bitDepth.isEmpty { return bitDepth }
            if isWAV(track) { return getWavBitDepthString(for: track) ?? "-" }
            return "-"
        case .unknown:
            return "-"
        }
    }

    private func numericBitrate(for track: TrackMetadata) -> Int {
        // Sorting key used when column is BIT R/D
        switch track.audioFormatClass {
        case .lossy:
            return getOrComputeBitrateKbps(for: track) ?? Int.max
        case .losslessOrUncompressed:
            if let bitDepthString = track.bitDepth ?? getWavBitDepthString(for: track),
               let numeric = extractBitDepthValue(bitDepthString) {
                return numeric
            }
            return Int.max
        case .unknown:
            return Int.max
        }
    }

    private func getOrComputeBitrateKbps(for track: TrackMetadata) -> Int? {
        // Prefer stored metadata
        if let kbps = track.bitrateKbps, kbps > 0 { return kbps }
        // Use cache
        if let cached = bitrateCache[track.filePath] { return cached }
        // Compute once and cache
        let url = URL(fileURLWithPath: track.filePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var bitrate: Int = 0
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: url)
        if #available(macOS 13.0, *) {
            if let track = AlbumMetadataManager.shared.loadTracksSync(asset, mediaType: .audio)?.first,
               let bps = AlbumMetadataManager.shared.loadEstimatedDataRateSync(track), bps > 0 {
                let rawKbps = Int(round(bps / 1000.0))
                if url.pathExtension.lowercased() == "mp3" { bitrate = snapToStandardMP3Bitrate(rawKbps) } else { bitrate = rawKbps }
            }
        } else {
            if let audioTrack = asset.tracks(withMediaType: .audio).first {
                let bps = audioTrack.estimatedDataRate
                if bps > 0 {
                    let rawKbps = Int(round(bps / 1000.0))
                    if url.pathExtension.lowercased() == "mp3" {
                        bitrate = snapToStandardMP3Bitrate(rawKbps)
                    } else {
                        bitrate = rawKbps
                    }
                }
            }
        }
        // Fallback: compute from file size and existing track duration (no deprecated APIs)
        if bitrate == 0 {
            if let seconds = track.duration, seconds > 0 {
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 {
                    let rawKbps = Int(round((Double(size) * 8.0) / (seconds * 1000.0)))
                    bitrate = url.pathExtension.lowercased() == "mp3" ? snapToStandardMP3Bitrate(rawKbps) : rawKbps
                }
            }
        }
        if bitrate > 0 { bitrateCache[track.filePath] = bitrate }
        return bitrate > 0 ? bitrate : nil
    }

    // Removed per-row bitrate computation to avoid main-thread IO

    private func isMP3(_ track: TrackMetadata) -> Bool {
        let ext = URL(fileURLWithPath: track.filePath).pathExtension.lowercased()
        if ext == "mp3" { return true }
        if let fmt = track.format?.lowercased(), fmt.contains("mp3") { return true }
        return false
    }

    private func isWAV(_ track: TrackMetadata) -> Bool {
        let ext = URL(fileURLWithPath: track.filePath).pathExtension.lowercased()
        if ext == "wav" { return true }
        if let fmt = track.format?.lowercased(), fmt.contains("wav") || fmt.contains("wave") { return true }
        return false
    }

    private func getWavBitDepthString(for track: TrackMetadata) -> String? {
        // Prefer stored metadata
        if let bd = track.bitDepth, !bd.isEmpty { return bd }
        // Cache
        if let cached = wavBitDepthCache[track.filePath] { return cached }
        // Read file format to determine bit depth
        let url = URL(fileURLWithPath: track.filePath)
        guard FileManager.default.fileExists(atPath: track.filePath) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let bitDepth = audioFile.fileFormat.bitDepthString(for: url)
            if let bitDepth = bitDepth {
                wavBitDepthCache[track.filePath] = bitDepth
            }
            return bitDepth
        } catch {
            return nil
        }
    }

    private func extractBitDepthValue(_ bitDepthString: String) -> Int? {
        // Extract numeric value from strings like "16-bit", "24-bit", "32-bit float"
        let pattern = "(\\d+)-bit"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: bitDepthString, range: NSRange(bitDepthString.startIndex..., in: bitDepthString)),
           let range = Range(match.range(at: 1), in: bitDepthString) {
            return Int(String(bitDepthString[range]))
        }
        return nil
    }

    private func snapToStandardMP3Bitrate(_ kbps: Int) -> Int {
        // Nearest standard MP3 bitrates
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
    
    // MARK: - All other helper methods remain unchanged (copy exactly from original)
    
    private func compactLibraryHeader(width: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("LIBRARY")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(0.5)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(LibraryViewType.allCases, id: \.self) { viewType in
                        Button(action: {
                            selectedLibraryView = viewType
                            searchText = ""
                        }) {
                            Group {
                                if selectedLibraryView == viewType {
                                    Text(viewType.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color.black)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(red: 0, green: 0.75, blue: 0.39))
                                        )
                                } else {
                                    Text(viewType.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(white: 0.7))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                            .background(
                                                Group {
                                                    if hoveredLibraryView == viewType {
                                                        Color.clear
                                                            .secondaryGlass(cornerRadius: 6)
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(Color.clear)
                                                    }
                                                }
                                            )
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    hoveredLibraryView = viewType
                                } else if hoveredLibraryView == viewType {
                                    hoveredLibraryView = nil
                                }
                            }
                        .animation(.easeInOut(duration: 0.2), value: selectedLibraryView)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(white: 0.6))
                        .font(.system(size: 9))
                    
                    TextField(searchPlaceholder, text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .onChange(of: searchText) { _, newValue in
                            if selectedLibraryView == .allTracks {
                                allTracksManager.searchFilter = newValue
                            }
                        }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .secondaryGlass(cornerRadius: 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
    
    private var searchPlaceholder: String {
        switch selectedLibraryView {
        case .albums: return "Search albums..."
        case .playlists: return "Search playlists..."
        case .allTracks: return "Search tracks..."
        case .artists: return "Search artists..."
        }
    }
    
    private func albumsGridView(width: CGFloat, height: CGFloat) -> some View {
        let albums = (filteredContent as? [AlbumMetadata]) ?? []
        
        return ZStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
                ], spacing: 16) {
                    ForEach(albums, id: \.albumName) { album in
                        AlbumTileView(
                            album: album,
                            isSelected: (selectedAlbum?.albumName == album.albumName),
                            onSelect: { selectAlbumForDetailView(album) }
                        )
                    }
                }
                .padding(16)
            }
            
            if albums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 44))
                        .foregroundColor(Color(white: 0.45))
                    Text("NO ALBUMS")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(white: 0.7))
                    Text("Load some albums to see albums here")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }

    // Album tile with local hover state
    private struct AlbumTileView: View {
        let album: AlbumMetadata
        let isSelected: Bool
        let onSelect: () -> Void
        @State private var isHovered: Bool = false

        var body: some View {
            VStack(spacing: 8) {
                Group {
                    if let frontPath = album.frontArtPath,
                       FileManager.default.fileExists(atPath: frontPath) {
                        AsyncImageLoader(imagePath: frontPath, size: CGSize(width: 140, height: 140))
                            .frame(width: 140, height: 140)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(width: 140, height: 140)
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39).opacity(0.7))
                            )
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                }

                VStack(spacing: 3) {
                    Text(album.albumName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? Color(red: 0, green: 0.75, blue: 0.39) : .white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)

                    Text(album.computedAlbumArtist)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                }
                .frame(width: 140)
            }
            .padding(8)
            .background(
                Group {
                    if isSelected {
                        Color.clear.selectedGlass(cornerRadius: 10)
                    } else if isHovered {
                        Color.clear.secondaryGlass(cornerRadius: 10)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.clear)
                    }
                }
            )
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 4 : 0)
            .offset(x: isHovered ? 4 : 0)
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture { onSelect() }
            .contextMenu {
                Button(action: { onSelect() }) {
                    Label("View Album", systemImage: "eye")
                }
            }
        }
    }

    private func playlistsView(width: CGFloat, height: CGFloat) -> some View {
        let playlists = (filteredContent as? [PlaylistMetadata]) ?? []
        
        return ZStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
                ], spacing: 16) {
                    ForEach(playlists) { playlist in
                        PlaylistTileView(
                            playlist: playlist,
                            isSelected: (selectedPlaylist?.id == playlist.id),
                            onSelect: { selectPlaylistForDetailView(playlist) }
                        )
                    }
                }
            }
            .padding(16)

            if playlists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44))
                        .foregroundColor(Color(white: 0.45))
                    Text("NO PLAYLISTS")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(white: 0.7))
                    Text("Use Edit menu to create playlists")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }

    // Playlist tile with local hover state
    private struct PlaylistTileView: View {
        let playlist: PlaylistMetadata
        let isSelected: Bool
        let onSelect: () -> Void
        @State private var isHovered: Bool = false
        @State private var loadedImage: NSImage?

        var body: some View {
            VStack(spacing: 8) {
                Group {
                    if let image = loadedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .cornerRadius(8)
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(width: 140, height: 140)
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39).opacity(0.7))
                            )
                    }
                }

                VStack(spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? Color(red: 0, green: 0.75, blue: 0.39) : .white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)

                    Text("\(playlist.trackCount) tracks")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                }
                .frame(width: 140)
            }
            .padding(8)
            .background(
                Group {
                    if isSelected {
                        Color.clear.selectedGlass(cornerRadius: 10)
                    } else if isHovered {
                        Color.clear.secondaryGlass(cornerRadius: 10)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.clear)
                    }
                }
            )
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 4 : 0)
            .offset(x: isHovered ? 4 : 0)
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture { onSelect() }
            .contextMenu {
                Button(action: { onSelect() }) {
                    Label("View Playlist", systemImage: "eye")
                }
            }
            .onAppear {
                if let path = playlist.artworkPath, FileManager.default.fileExists(atPath: path) {
                    ImagePerformanceOptimizer.shared.processAlbumArtAsync(from: path, size: CGSize(width: 140, height: 140)) { image in
                        self.loadedImage = image
                    }
                }
            }
        }
    }

    // MARK: - FIXED Artists View with Center Cropping
    private func artistsView(width: CGFloat, height: CGFloat) -> some View {
        let artists = (filteredContent as? [ArtistProfile]) ?? []
        
        return ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
            ], spacing: 16) {
                ForEach(artists, id: \.id) { artist in
                    ArtistTileView(
                        artist: artist,
                        isSelected: (selectedArtist?.id == artist.id),
                        onSelect: { selectArtistForDetailView(artist) }
                    )
                }
            }
            .padding(16)
        }
        .onAppear {
            // Ensure any bookmarked artist images are resolved to file paths so the grid can show them immediately
            artistManager.resolveMissingProfileImagePaths()
        }
        .overlay(
            Group {
                if artists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person")
                            .font(.system(size: 44))
                            .foregroundColor(Color(white: 0.45))
                        Text("NO ARTISTS")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(white: 0.7))
                        Text("Load some albums to see artists")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
        .frame(height: height)
    }

    // Artist tile with local hover state
    private struct ArtistTileView: View {
        let artist: ArtistProfile
        let isSelected: Bool
        let onSelect: () -> Void
        @State private var isHovered: Bool = false
        @State private var profileImage: NSImage?

        var body: some View {
            VStack(spacing: 10) {
                Group {
                    if let img = profileImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 140, height: 140)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(Color(white: 0.3), lineWidth: 3)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    } else {
                        Circle()
                            .fill(Color(white: 0.2))
                            .frame(width: 140, height: 140)
                            .overlay(
                                Text(String(artist.name.prefix(1)))
                                    .font(.system(size: 50, weight: .bold))
                                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                            )
                            .overlay(
                                Circle().stroke(Color(white: 0.3), lineWidth: 3)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                }
                
                VStack(spacing: 3) {
                    Text(artist.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? Color(red: 0, green: 0.75, blue: 0.39) : .white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                    Text("\(artist.albumCount) albums")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.6))
                }
                .frame(width: 140)
            }
            .padding(8)
            .background(
                Group {
                    if isSelected {
                        Color.clear.selectedGlass(cornerRadius: 10)
                    } else if isHovered {
                        Color.clear.secondaryGlass(cornerRadius: 10)
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(Color.clear)
                    }
                }
            )
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 4 : 0)
            .offset(x: isHovered ? 4 : 0)
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in isHovered = hovering }
            .onTapGesture { onSelect() }
            .onAppear {
                if let path = artist.profileImagePath, FileManager.default.fileExists(atPath: path) {
                    ImagePerformanceOptimizer.shared.processProfileImageAsync(from: path, size: CGSize(width: 140, height: 140)) { image in
                        self.profileImage = image
                    }
                }
            }
        }
    }

    private func allTracksView(width: CGFloat, height: CGFloat) -> some View {
        let tracks = (filteredContent as? [AllTracksManager.TrackWithAlbum]) ?? []
        
        // Ensure the table has a sensible minimum width and scrolls horizontally when needed
        let fixedColumnsWidth: CGFloat = 24 + 80 + 70 + 40 + 35 + 44 + 44 + 60 + 64 + 64 + 36 + 80
        let minTrackNameWidth: CGFloat = 200
        let _ : CGFloat = fixedColumnsWidth + minTrackNameWidth + 32
        
        // Extract header to reduce view-builder complexity
        let header = HStack(spacing: 10) {
            sortableHeader(title: "#", column: .index)
                .frame(width: 24, alignment: .center)
             
            sortableHeader(title: "TRACK", column: .trackName)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            sortableHeader(title: "ARTIST", column: .artistName)
                .frame(width: 80, alignment: .leading)
            
            sortableHeader(title: "ALBUM", column: .albumName)
                .frame(width: 70, alignment: .leading)
            
            sortableHeader(title: "PLAYS", column: .playCount)
                .frame(width: 40, alignment: .trailing)
            
            sortableHeader(title: "TIME", column: .duration)
                .frame(width: 35, alignment: .trailing)
            
            sortableHeader(title: "BPM", column: .bpm)
                .frame(width: 44, alignment: .trailing)
            
            sortableHeader(title: "KEY", column: .key)
                .frame(width: 44, alignment: .leading)
            
            sortableHeader(title: "FORMAT", column: .format)
                .frame(width: 60, alignment: .leading)
            
            sortableHeader(title: "S/RATE", column: .sampleRate)
                .frame(width: 64, alignment: .trailing)
            
            sortableHeader(title: "BIT R/D", column: .bitrate)
                .frame(width: 64, alignment: .trailing)
            
            sortableHeader(title: "EXPL", column: .isExplicit)
                .frame(width: 36, alignment: .center)
            
            sortableHeader(title: "VERSION", column: .version)
                .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        
        // New: Native macOS multi-select List (Cmd-click, Shift-click, Cmd-A)
        let content: AnyView = {
            if tracks.isEmpty {
                return AnyView(
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 28))
                            .foregroundColor(Color(white: 0.4))
                        Text("NO TRACKS")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                        Text("Load some albums to see tracks here")
                            .font(.system(size: 9))
                            .foregroundColor(Color(white: 0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            } else {
                return AnyView(
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(0..<tracks.count, id: \.self) { i in
                                allTracksRow(trackWithAlbum: tracks[i], index: i, tracks: tracks)
                            }
                        }
                    }
                    .onChange(of: selectedTrackIDs) { _, newIDs in
                        let idSet = Set(newIDs)
                        let selected = tracks.compactMap { idSet.contains($0.track.id) ? $0.track : nil }
                        selectedTrack = selected.last
                        MenuBarManager.shared.updateSelectedTracks(selected)
                    }
                )
            }
        }()

        return VStack(spacing: 0) {
            header
            content
        }
        .frame(height: height)
    }

    // MARK: - Row Builder to reduce type-checking load
    @ViewBuilder
    private func allTracksRow(trackWithAlbum: AllTracksManager.TrackWithAlbum, index i: Int, tracks: [AllTracksManager.TrackWithAlbum]) -> some View {
        let playing = isTrackPlaying(trackWithAlbum.track) && audioProcessor.isPlaying
        let isSelectedRow = selectedTrackIDs.contains(trackWithAlbum.track.id)
        HStack(spacing: 10) {
            Group {
                if playing {
                    PlayingVisualizer()
                        .frame(width: 24, height: 10)
                } else {
                    Text(String(i + 1))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TrackRowStyle.numberColor(isSelected: selectedTrack?.id == trackWithAlbum.track.id, isPlaying: playing))
                }
            }
            .frame(width: 24, alignment: .center)

            // Track name: hyperlink to album with this track selected
            HStack(spacing: 0) {
                Text(trackWithAlbum.track.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TrackRowStyle.titleColor(isSelected: selectedTrack?.id == trackWithAlbum.track.id, isPlaying: playing))
                    .lineLimit(1)
                    .underline(hoveredTrackNameID == trackWithAlbum.track.id, color: TrackRowStyle.secondaryTextColor())
                    .onHover { hovering in
                        hoveredTrackNameID = hovering ? trackWithAlbum.track.id : (hoveredTrackNameID == trackWithAlbum.track.id ? nil : hoveredTrackNameID)
                    }
                    .onTapGesture {
                        navigateToAlbumSelectingTrack(trackWithAlbum.album, trackWithAlbum.track)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Artist name: hyperlink to artist profile
            Text(trackWithAlbum.artistName)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.7))
                .underline(hoveredArtistNameID == trackWithAlbum.track.id, color: Color(white: 0.6))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
                .onHover { hovering in
                    hoveredArtistNameID = hovering ? trackWithAlbum.track.id : (hoveredArtistNameID == trackWithAlbum.track.id ? nil : hoveredArtistNameID)
                }
                .onTapGesture {
                    if let artist = artistManager.artists.first(where: { $0.name == trackWithAlbum.artistName }) {
                        selectArtistForDetailView(artist)
                    }
                }

            // Album name: hyperlink to album
            Text(trackWithAlbum.albumName)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.7))
                .underline(hoveredAlbumNameID == trackWithAlbum.track.id, color: Color(white: 0.6))
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)
                .onHover { hovering in
                    hoveredAlbumNameID = hovering ? trackWithAlbum.track.id : (hoveredAlbumNameID == trackWithAlbum.track.id ? nil : hoveredAlbumNameID)
                }
                .onTapGesture {
                    selectAlbumForDetailView(trackWithAlbum.album)
                }

            Text("\(trackWithAlbum.playCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(trackWithAlbum.playCount > 0 ?
                                 Color(red: 0, green: 0.75, blue: 0.39) : Color(white: 0.5))
                .frame(width: 40, alignment: .trailing)

            Text(trackWithAlbum.track.formattedDuration ?? "--:--")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .frame(width: 35, alignment: .trailing)

            Text(trackWithAlbum.track.bpm.map { String($0) } ?? "-")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.6))
                .frame(width: 44, alignment: .trailing)

            Text(trackWithAlbum.track.key ?? "-")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.6))
                .frame(width: 44, alignment: .leading)

            Text(displayFormat(for: trackWithAlbum.track))
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.6))
                .frame(width: 60, alignment: .leading)

            Text(displaySampleRate(for: trackWithAlbum.track))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.6))
                .frame(width: 64, alignment: .trailing)

            Text(displayBitrate(for: trackWithAlbum.track))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.6))
                .frame(width: 64, alignment: .trailing)

            Group {
                if trackWithAlbum.track.isExplicit == true {
                    ExplicitIndicatorTraditional(size: 10)
                } else {
                    Text("-")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.4))
                }
            }
            .frame(width: 36, alignment: .center)

            Text(trackWithAlbum.track.version ?? "-")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.6))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelectedRow {
                    Color.clear
                        .selectedGlass(cornerRadius: 6)
                } else if hoveredTrackID == trackWithAlbum.track.id {
                    Color.clear
                        .secondaryGlass(cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.clear)
                }
            }
        )
        .shadow(color: .black.opacity((hoveredTrackID == trackWithAlbum.track.id) ? 0.25 : 0.0), radius: (hoveredTrackID == trackWithAlbum.track.id) ? 6 : 0, x: 0, y: (hoveredTrackID == trackWithAlbum.track.id) ? 4 : 0)
        .offset(x: (hoveredTrackID == trackWithAlbum.track.id) ? 4 : 0)
        .animation(.easeInOut(duration: 0.16), value: hoveredTrackID)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredTrackID = trackWithAlbum.track.id
            } else if hoveredTrackID == trackWithAlbum.track.id {
                hoveredTrackID = nil
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    playTrackFromAllTracks(trackWithAlbum)
                }
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    handleAllTracksClick(clicked: trackWithAlbum, index: i, tracksInView: tracks)
                }
        )
        .contextMenu {
            if selectedTrackIDs.isEmpty || selectedTrackIDs.contains(trackWithAlbum.track.id) {
                Button(action: {
                    let idSet = Set(selectedTrackIDs.isEmpty ? [trackWithAlbum.track.id] : selectedTrackIDs)
                    let selected = tracks.compactMap { idSet.contains($0.track.id) ? $0.track : nil }
                    selectedTracksForPlaylist = selected
                    showPlaylistManagement = true
                }) {
                    Label(selectedTrackIDs.count > 1 ? "Add Selected to Playlist" : "Add to Playlist", systemImage: "plus")
                }
                Button(action: {
                    let idSet = Set(selectedTrackIDs.isEmpty ? [trackWithAlbum.track.id] : selectedTrackIDs)
                    let selected = tracks.filter { idSet.contains($0.track.id) }
                    if selected.count > 1 {
                        var seen = Set<String>()
                        var added = 0
                        for item in selected {
                            if seen.contains(item.track.filePath) { continue }
                            seen.insert(item.track.filePath)
                            QueueManager.shared.addToQueue(item.track, from: item.album)
                            added += 1
                        }
                        print("✅ Added \(added) selected track(s) to queue from All Tracks context menu")
                    } else {
                        let item = trackWithAlbum
                        QueueManager.shared.addToQueue(item.track, from: item.album)
                    }
                }) {
                    Label(selectedTrackIDs.count > 1 ? "Add Selected to Queue" : "Add to Queue", systemImage: "plus")
                }
                if !selectedTrackIDs.isEmpty {
                    Button(action: {
                        playSelectedTracksFromAllTracks()
                    }) {
                        Label("Play Selected", systemImage: "play")
                    }
                } else {
                    Button(action: {
                        playTrackFromAllTracks(trackWithAlbum)
                    }) {
                        Label("Play", systemImage: "play")
                    }
                }
                Button(action: {
                    selectAlbumForDetailView(trackWithAlbum.album)
                }) {
                    Label("View Album", systemImage: "eye")
                }
            }
        }
    }

    // MARK: - Album-like selection handling for All Tracks
    private func handleAllTracksClick(clicked: AllTracksManager.TrackWithAlbum, index: Int, tracksInView: [AllTracksManager.TrackWithAlbum]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)

        if isShift {
            let anchor = selectionAnchorIndex ?? index
            selectionAnchorIndex = anchor
            let lower = min(anchor, index)
            let upper = max(anchor, index)
            let rangeIDs = Set(tracksInView[lower...upper].map { $0.track.id })
            selectedTrackIDs.formUnion(rangeIDs)
        } else if isCommand {
            if selectedTrackIDs.contains(clicked.track.id) {
                selectedTrackIDs.remove(clicked.track.id)
            } else {
                selectedTrackIDs.insert(clicked.track.id)
            }
            selectionAnchorIndex = index
        } else {
            selectedTrackIDs = [clicked.track.id]
            selectionAnchorIndex = index
        }

        selectedTrack = clicked.track
        currentAlbum = clicked.album
        MenuBarManager.shared.updateSelectedTracks(
            tracksInView.filter { selectedTrackIDs.contains($0.track.id) }.map { $0.track }
        )
    }
    
    // MARK: - Selection Methods (unchanged)
    
    private func selectAlbumForDetailView(_ album: AlbumMetadata) {
        print("🔄 Opening album detail view: \(album.albumName)")
        
        selectedAlbum = album
        selectedPlaylist = nil
        selectedArtist = nil
        
        // UI-only: do not interrupt playback or modify queue
        currentAlbum = album
        selectedTrack = nil
        MenuBarManager.shared.updateCurrentAlbum(album)
        
        // Navigate to detail view
        withAnimation(.easeInOut(duration: 0.3)) {
            viewState = .albumDetail(album)
        }
    }

    private func navigateToAlbumSelectingTrack(_ album: AlbumMetadata, _ track: TrackMetadata) {
        print("🔗 Navigate to album and select track: \(album.albumName) - \(track.name)")
        selectedAlbum = album
        selectedPlaylist = nil
        selectedArtist = nil
        currentAlbum = album
        selectedTrack = track
        MenuBarManager.shared.updateCurrentAlbum(album)
        MenuBarManager.shared.updateSelectedTrack(track)
        withAnimation(.easeInOut(duration: 0.3)) {
            viewState = .albumDetail(album)
        }
    }
    
    private func selectPlaylistForDetailView(_ playlist: PlaylistMetadata) {
        print("🔄 Opening playlist detail view: \(playlist.name)")
        
        selectedPlaylist = playlist
        selectedAlbum = nil
        selectedArtist = nil
        
        // Navigate to detail view
        withAnimation(.easeInOut(duration: 0.3)) {
            viewState = .playlistDetail(playlist)
        }
    }
    
    private func selectArtistForDetailView(_ artist: ArtistProfile) {
        print("🔄 Opening artist detail view: \(artist.name)")
        
        selectedArtist = artist
        selectedAlbum = nil
        selectedPlaylist = nil
        
        withAnimation(.easeInOut(duration: 0.3)) {
            viewState = .artistDetail(artist)
        }
    }
    
    private func selectPlaylist(_ playlist: PlaylistMetadata) {
        print("🔄 Selecting playlist: \(playlist.name)")
        setLoadingState(true, message: "Loading playlist...")
        
        performCompleteUnloadBeforeSwitch()
        selectedPlaylist = playlist
        selectedAlbum = nil
        selectedArtist = nil
        currentAlbum = nil
        selectedTrack = nil
        
        AppState.shared.currentAlbum = nil
        MenuBarManager.shared.updateCurrentAlbum(nil)
        MenuBarManager.shared.updateCurrentPlaylist(playlist)
        
        loadPlaylistTracks(playlist)
        setLoadingState(false)
    }
    
    private func selectTrackFromAllTracks(_ trackWithAlbum: AllTracksManager.TrackWithAlbum) {
        // UI-only selection; do not reload audio or interrupt playback
        selectedTrack = trackWithAlbum.track
        currentAlbum = trackWithAlbum.album
        MenuBarManager.shared.updateSelectedTrack(trackWithAlbum.track)
        
        // Optionally align UI index if the file is already present
        if let index = audioFiles.firstIndex(where: { $0.url.path == trackWithAlbum.track.filePath }) {
            currentFileIndex = index
        }
    }
    
    private func playTrackFromAllTracks(_ trackWithAlbum: AllTracksManager.TrackWithAlbum) {
        print("🎵 playTrackFromAllTracks called for: \(trackWithAlbum.track.name)")
        print("   Album: \(trackWithAlbum.album.albumName)")

        // UI selection persists even if we can't play
        selectTrackFromAllTracks(trackWithAlbum)

        // Gate playback by power state
        guard isPoweredOn else {
            showPowerAlert = true
            print("⚠️ Power is off. Playback blocked.")
            return
        }

        // Create queue from the full, current sort order
        let ordered = sortedAllTracksForQueue()
        let clickedId = trackWithAlbum.track.id

        let qm = QueueManager.shared
        qm.clearQueue()
        for item in ordered {
            qm.addToQueue(item.track, from: item.album)
        }
        print("🎚️ Queue built from All Tracks: \(qm.queueCount) items (sorted by \(trackSortColumn.rawValue))")

        if let idx = ordered.firstIndex(where: { $0.track.id == clickedId }) {
            qm.currentIndex = idx
            qm.playCurrentTrack()
            currentAlbum = ordered[idx].album
            selectedTrack = ordered[idx].track
            print("▶️ Started playback at index \(idx + 1) of \(ordered.count): \(ordered[idx].track.name)")
        } else {
            print("⚠️ Could not find clicked track in ordered list for playback")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Can't Find Track"
                alert.informativeText = "MetaWav can't find the audio file for the selected track.\n\nTry reconnecting external drives, waking network shares, or use Edit → Repath Track… to relink the file."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // NEW: Play all currently selected tracks from All Tracks view
    private func playSelectedTracksFromAllTracks() {
        let idSet = Set(selectedTrackIDs)
        let ordered = sortedAllTracksForQueue().filter { idSet.contains($0.track.id) }
        guard !ordered.isEmpty else { return }
        
        let qm = QueueManager.shared
        qm.clearQueue()
        for item in ordered {
            qm.addToQueue(item.track, from: item.album)
        }
        qm.currentIndex = 0
        qm.playCurrentTrack()
        currentAlbum = ordered.first?.album
        selectedTrack = ordered.first?.track
    }
    
    // MARK: - Album Playback Methods (unchanged)
    
    private func playAlbum(_ album: AlbumMetadata) {
        print("▶️ Playing album: \(album.albumName)")
        
        // Use queue manager to load and play album
        QueueManager.shared.handleAlbumSelection(album, playImmediately: true)
        
        // Update local state for backward compatibility
        currentAlbum = album
        selectedTrack = album.tracks.first
    }
    
    private func loadAlbumForPlayback(_ album: AlbumMetadata) {
        print("🔄 Loading album for playback: \(album.albumName)")
        setLoadingState(true, message: "Loading album...")
        
        performCompleteUnloadBeforeSwitch()
        currentAlbum = album
        selectedTrack = nil
        
        AppState.shared.currentAlbum = album
        MenuBarManager.shared.updateCurrentAlbum(album)
        
        loadAlbumTracks(album)
        setLoadingState(false)
    }
    
    // MARK: - Helper Methods (unchanged)
    
    private func setLoadingState(_ loading: Bool, message: String = "") {
        isLoading = loading
        loadingMessage = message
    }
    
    private func refreshAllContent() {
        // Force view update by incrementing the refresh trigger
        albumsRefreshTrigger += 1
        
        // Album manager handles albums automatically via @StateObject
        playlistManager.loadAllPlaylists()
        
        if selectedLibraryView == .allTracks {
            loadAllTracksLazily()
        }
        
        // Don't refresh artist data during metadata updates to avoid corruption
        // artistManager.discoverAndCreateArtists(from: albumManager.loadAllAlbums())
    }
    
    /// Refresh artist data separately - call this when actually needed
    private func refreshArtistData() {
        print("🎭 Refreshing artist data...")
        artistManager.discoverAndCreateArtists(from: albumManager.loadAllAlbums())
    }
    
    private func loadAllTracksLazily() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.allTracksManager.refreshAllTracks()
        }
    }

    // Build the complete, current-sorted track list for queueing (not capped to UI limit)
    private func sortedAllTracksForQueue() -> [AllTracksManager.TrackWithAlbum] {
        let filtered = allTracksManager.filteredTracks
        let sorted = sortAllTracks(filtered)
        return sorted
    }
    
    private func performCompleteUnloadBeforeSwitch() {
        // Only clear audio files and reset playback state
        // DO NOT clear the queue - it should persist across album navigation
        AudioProcessor.shared.fullCleanup()
        audioFiles.removeAll()
        currentFileIndex = nil
        currentTime = 0
        
        print("🔄 Performed unload before switch - queue preserved")
    }
    
    private func loadAlbumTracks(_ album: AlbumMetadata) {
        var newAudioFiles: [AVAudioFile] = []
        
        let sortedTracks = album.tracks.sorted { track1, track2 in
            if track1.discNumber != track2.discNumber {
                return track1.discNumber < track2.discNumber
            }
            return track1.trackNumber < track2.trackNumber
        }
        
        for track in sortedTracks {
            let url = URL(fileURLWithPath: track.filePath)
            
            guard FileManager.default.fileExists(atPath: track.filePath) else { continue }
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let audioFile = try AVAudioFile(forReading: url)
                newAudioFiles.append(audioFile)
            } catch {
                print("⚠️ Failed to load: \(track.filePath)")
            }
        }
        
        if !newAudioFiles.isEmpty {
            audioFiles = newAudioFiles
            currentFileIndex = 0
        }
    }
    
    private func loadPlaylistTracks(_ playlist: PlaylistMetadata) {
        var newAudioFiles: [AVAudioFile] = []
        
        let sortedTracks = playlist.tracks.sorted { $0.playlistPosition < $1.playlistPosition }
        
        for playlistTrack in sortedTracks {
            let url = URL(fileURLWithPath: playlistTrack.filePath)
            
            guard FileManager.default.fileExists(atPath: playlistTrack.filePath) else { continue }
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let audioFile = try AVAudioFile(forReading: url)
                newAudioFiles.append(audioFile)
            } catch {
                print("⚠️ Failed to load playlist track: \(playlistTrack.filePath)")
            }
        }
        
        if !newAudioFiles.isEmpty {
            audioFiles = newAudioFiles
            currentFileIndex = 0
        }
    }

    private func isTrackPlaying(_ track: TrackMetadata) -> Bool {
        guard let currentItem = queueManager.currentItem else { return false }
        return currentItem.track?.filePath == track.filePath && audioProcessor.isPlaying
    }

    // MARK: - Drag & Drop Handling
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard isPoweredOn else { return false }
        isProcessingDrop = true
        dropSucceeded = false

        Task {
            let urls = await extractFileURLs(from: providers)
            await processDroppedURLs(urls)
        }
        return true
    }

    private func extractFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var collected: [URL] = []
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    group.addTask {
                        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                if let url = item as? URL { continuation.resume(returning: url) }
                                else { continuation.resume(returning: nil) }
                            }
                        }
                    }
                }
            }
            for await maybe in group {
                if let url = maybe { collected.append(url) }
            }
        }
        return collected
    }

    @MainActor
    private func processDroppedURLs(_ urls: [URL]) async {
        defer { DispatchQueue.main.async { self.isProcessingDrop = false } }
        guard !urls.isEmpty else { return }

        // Expand any directories to contained files (recursive)
        let expanded = expandURLsResolvingFolders(urls)
        guard !expanded.isEmpty else { return }
        
        // Separate meta album and audio files
        let metaFiles = expanded.filter { $0.pathExtension.lowercased() == "meta" }
        let audioURLs = expanded.filter { ["wav","flac","mp3","aiff","aif","aac","alac","ogg","m4a","wma","caf"].contains($0.pathExtension.lowercased()) }

        let ap = AudioProcessor.shared
        let qm = QueueManager.shared
        let safeToUnload = !ap.isPlaying && qm.isQueueEmpty
        if safeToUnload {
            await MainActor.run { performCompleteUnloadBeforeSwitch() }
        }

        if !metaFiles.isEmpty {
            for metaURL in metaFiles {
                do {
                    let data = try Data(contentsOf: metaURL)
                    var album = try PropertyListDecoder().decode(AlbumMetadata.self, from: data)
                    album.updateTrackCount()
                    album.updateDiscCount()
                    try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(album)
                    var loaded: [AVAudioFile] = []
                    for track in album.tracks {
                        let url = URL(fileURLWithPath: track.filePath)
                        if let file = try? AVAudioFile(forReading: url) { loaded.append(file) }
                    }
                    await MainActor.run {
                        self.currentAlbum = album
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
            await MainActor.run {
                self.dropSucceeded = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.dropSucceeded = false }
            }
            return
        }

        guard !audioURLs.isEmpty else {
            return
        }

        await processAudioURLsAsNewAlbum(audioURLs)
        await MainActor.run {
            self.dropSucceeded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.dropSucceeded = false }
        }
    }

    private func expandURLsResolvingFolders(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        let allowed = Set(["wav","flac","mp3","aiff","aif","aac","alac","ogg","m4a","wma","caf","meta"]) // include meta
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if allowed.contains(fileURL.pathExtension.lowercased()) {
                            out.append(fileURL)
                        }
                    }
                }
            } else {
                out.append(url)
            }
        }
        return out
    }

    private func processAudioURLsAsNewAlbum(_ urls: [URL]) async {
        var loadedAudioFiles: [AVAudioFile] = []
        var albumName: String?
        var genre: String?
        var year: String?
        var albumArtData: Data?
        var albumArtExtension: String?

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let audioFile = try AVAudioFile(forReading: url)
                loadedAudioFiles.append(audioFile)
                if albumName == nil {
                    let asset = AVURLAsset(url: url)
                    do {
                        let metadataItems = try await asset.load(.metadata)
                        for item in metadataItems {
                            // Use the existing synchronous key property; only value loading needed async.
                            guard let key = item.key as? String else { continue }
                            if (key.contains("Album") || key.contains("TALB")) && albumName == nil {
                                albumName = try await item.load(.stringValue)
                            } else if (key.contains("Genre") || key.contains("TCON")) && genre == nil {
                                genre = try await item.load(.stringValue)
                            } else if (key.contains("Date") || key.contains("TDRC")) && year == nil {
                                if let stringValue: String = try await item.load(.stringValue) {
                                    year = extractYear(from: stringValue)
                                }
                            } else if key == "artwork" || key.contains("APIC") {
                                if let data: Data = try await item.load(.dataValue) {
                                    albumArtData = data
                                    albumArtExtension = determineImageExtension(from: data)
                                }
                            }
                        }
                    } catch {
                        print("⚠️ Failed to load metadata for \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            } catch {
                print("❌ Error loading file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        guard !loadedAudioFiles.isEmpty else { return }

        // Track/disc numbers
        var tracksWithNumbers: [(audioFile: AVAudioFile, track: TrackMetadata)] = []
        var tracksWithoutNumbers: [(audioFile: AVAudioFile, track: TrackMetadata)] = []

        for audioFile in loadedAudioFiles {
            let url = audioFile.url
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let asset = AVURLAsset(url: url)
            var foundTrackNumber: Int?
            var foundDiscNumber: Int = 1
            do {
                let metadataItems = try await asset.load(.metadata)
                for item in metadataItems {
                    guard let key = item.key as? String else { continue }
                    if key.contains("TRCK") || key.contains("Track") {
                        if let stringValue: String = try await item.load(.stringValue) {
                            let components = stringValue.components(separatedBy: "/")
                            if let number = Int(components[0]) { foundTrackNumber = number }
                        }
                    } else if key.contains("TPOS") || key.contains("Disc") {
                        if let stringValue: String = try await item.load(.stringValue) {
                            let components = stringValue.components(separatedBy: "/")
                            if let discNum = Int(components[0]), discNum > 0 { foundDiscNumber = discNum }
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to load track/disc metadata for \(url.lastPathComponent): \(error.localizedDescription)")
            }

            let track = AlbumMetadataManager.shared.createTrackMetadata(
                from: audioFile,
                trackNumber: foundTrackNumber ?? 1,
                discNumber: foundDiscNumber
            )

            if foundTrackNumber != nil { tracksWithNumbers.append((audioFile, track)) } else { tracksWithoutNumbers.append((audioFile, track)) }
        }

        tracksWithNumbers.sort { lhs, rhs in
            if lhs.track.discNumber != rhs.track.discNumber { return lhs.track.discNumber < rhs.track.discNumber }
            return lhs.track.trackNumber < rhs.track.trackNumber
        }

        let tracksWithoutNumbersByDisc = Dictionary(grouping: tracksWithoutNumbers) { $0.track.discNumber }
        var allTuples: [(audioFile: AVAudioFile, track: TrackMetadata)] = tracksWithNumbers
        for (discNumber, discTuples) in tracksWithoutNumbersByDisc {
            let maxTrack = tracksWithNumbers.filter { $0.track.discNumber == discNumber }.map { $0.track.trackNumber }.max() ?? 0
            for (index, var tuple) in discTuples.enumerated() {
                tuple.track.trackNumber = maxTrack + index + 1
                allTuples.append(tuple)
            }
        }

        allTuples.sort { lhs, rhs in
            if lhs.track.discNumber != rhs.track.discNumber { return lhs.track.discNumber < rhs.track.discNumber }
            return lhs.track.trackNumber < rhs.track.trackNumber
        }

        let tracks = allTuples.map { $0.track }
        let sortedAudioFiles = allTuples.map { $0.audioFile }

        let finalAlbumName: String = {
            if let name = albumName, !name.isEmpty { return name }
            let parentNames = Set(urls.map { $0.deletingLastPathComponent().lastPathComponent })
            if parentNames.count == 1, let only = parentNames.first { return only }
            return AlbumMetadataManager.shared.getNextUntitledAlbumName()
        }()

        var frontArtPath: String?
        if let data = albumArtData, let ext = albumArtExtension {
            frontArtPath = saveEmbeddedAlbumArt(data, fileExtension: ext, albumName: finalAlbumName)
        }

        let albumType: String? = {
            switch tracks.count { case 1: return "Single"; case 2...6: return "EP"; case 7...: return "Album"; default: return nil }
        }()

        let defaultGenre = genre ?? "Other"
        let defaultYear = year ?? "2025"

        var newAlbum = AlbumMetadata(
            albumName: finalAlbumName,
            albumType: albumType,
            frontArtPath: frontArtPath,
            backArtPath: nil,
            duration: nil,
            genre: defaultGenre,
            year: defaultYear,
            trackCount: tracks.count,
            discCount: 1,
            discNames: nil,
            tracks: tracks
        )
        newAlbum.calculateDuration()
        newAlbum.updateTrackCount()
        newAlbum.updateDiscCount()

        do {
            try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(newAlbum)
            // Emit targeted album art change for smart refresh
            NotificationManager.shared.postNotification(.albumArtChanged, object: newAlbum)
            let ap = AudioProcessor.shared
            let qm = QueueManager.shared
            let safeToApplyBindings = !ap.isPlaying && qm.isQueueEmpty
            if safeToApplyBindings {
                await MainActor.run {
                    self.currentAlbum = newAlbum
                    self.audioFiles = sortedAudioFiles
                    self.currentFileIndex = 0
                    self.currentTime = 0
                    MenuBarManager.shared.updateCurrentAlbum(newAlbum)
                    MenuBarManager.shared.updateSelectedTrack(nil)
                }
            }
            await MainActor.run {
                NotificationManager.shared.postNotification(.albumLoaded, object: newAlbum)
                self.isDragTargeted = false
            }
        } catch {
            print("❌ Failed to save album: \(error.localizedDescription)")
        }
    }

    // MARK: - Local helpers (mirroring ContentView implementations)
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

    private func extractYear(from dateString: String?) -> String? {
        guard let dateString = dateString else { return nil }
        if let yearRange = dateString.range(of: "\\d{4}", options: .regularExpression) {
            return String(dateString[yearRange])
        }
        return nil
    }

    private func determineImageExtension(from data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
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
}

// MARK: - NPS Panel - Now Playing & Scrubber Panel (Integrated)
struct NPSPanelIntegrated: View {
    @Binding var currentTime: TimeInterval
    @Binding var audioPlayer: AVAudioPlayer?
    @Binding var currentFileIndex: Int?
    @Binding var audioFiles: [AVAudioFile]
    @Binding var isPoweredOn: Bool
    
    let selectedTrack: TrackMetadata?
    let currentAlbum: AlbumMetadata?
    let onNavigateToArtist: (String) -> Void
    let onNavigateToAlbum: (AlbumMetadata) -> Void
    
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    @ObservedObject private var queueManager = QueueManager.shared
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var wasPlayingBeforeSeek = false
    @State private var isArtistHovered: Bool = false
    
    private var duration: TimeInterval {
        audioProcessor.duration
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return scrubbing ? scrubValue : (currentTime / duration)
    }
    
    private var currentTimeString: String {
        let time = scrubbing ? (scrubValue * duration) : currentTime
        return timeString(from: time)
    }
    
    private var totalTimeString: String {
        return timeString(from: duration)
    }
    
    // Get current track info from QueueManager
    private var currentTrack: TrackMetadata? {
        // First try to get from QueueManager's current item
        if let queueItem = queueManager.currentItem {
            return queueItem.track
        }
        
        // Fallback to old method for backward compatibility
        guard let index = currentFileIndex,
              index < audioFiles.count else { return selectedTrack }
        
        let filePath = audioFiles[index].url.path
        
        // Try to find track in current album first
        if let album = currentAlbum {
            return album.tracks.first { $0.filePath == filePath }
        }
        
        return selectedTrack
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(alignment: .center, spacing: 0) {
                    // Now Playing Section (Left - 30%)
                    nowPlayingSection()
                        .frame(width: geometry.size.width * 0.3, height: 56, alignment: .center)
                    
                    // Scrubber Section (Right - 70%)
                    scrubberSection()
                        .frame(width: geometry.size.width * 0.7, height: 56, alignment: .center)
                }
            }
        }
        .frame(height: 56)
        .npsGlass()
        .onChange(of: currentTime) { _, newTime in
            if !scrubbing {
                scrubValue = duration > 0 ? (newTime / duration) : 0
            }
        }
        .onChange(of: queueManager.currentItem?.album?.albumName) { _, newAlbumName in
            print("🎵 NPSPanel: Album changed to: \(newAlbumName ?? "nil")")
        }
    }
    
    // MARK: - Now Playing Section
    private func nowPlayingSection() -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Album Art Thumbnail - Clickable
            Button(action: {
                // Navigate to album view - use QueueManager's current album only
                if let album = queueManager.currentItem?.album {
                    onNavigateToAlbum(album)
                }
            }) {
                Group {
                    // Get album from QueueManager's current item only
                    if let album = queueManager.currentItem?.album,
                       let frontPath = album.frontArtPath,
                       FileManager.default.fileExists(atPath: frontPath) {
                        AsyncImageLoader(imagePath: frontPath, size: CGSize(width: 48, height: 48))
                            .frame(width: 48, height: 48)
                            .aspectRatio(contentMode: .fill)
                            .id("album-art-\(album.albumName)") // Force refresh when album changes
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: 48, height: 48)
                .cornerRadius(4)
                .clipped()
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Open Album")
            
            // Track and Artist Info
            VStack(alignment: .leading, spacing: 2) {
                // "Now Playing:" caption
                Text("Now Playing:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Track name with explicit indicator - bold, truncated
HStack(spacing: 6) {
    Text(currentTrack?.name ?? "No Track")
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)
    
    if currentTrack?.isExplicit == true {
        ExplicitIndicatorTraditional(size: 12)
    }
}
                
                // Artist name - clickable hyperlink
                Button(action: {
                    if let artistName = currentTrack?.artist {
                        onNavigateToArtist(artistName)
                    }
                }) {
                    Text(currentTrack?.artist ?? "Unknown Artist")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                        .underline(isArtistHovered, color: Color(red: 0, green: 0.75, blue: 0.39))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isArtistHovered = hovering
                }
                .accessibilityLabel("View Artist")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Scrubber Section
    private func scrubberSection() -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Current time
            Text(currentTimeString)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
            
            // Scrubber Slider
            Slider(
                value: Binding(
                    get: { progress },
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
                        // Commit the seek when user stops dragging
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
            .accessibilityValue("\(currentTimeString) of \(totalTimeString)")
            .accessibilityLabel("Playback Position")
            
            // Total time
            Text(totalTimeString)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helper Functions
    private func timeString(from time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func seekToTime(_ time: TimeInterval) {
        print("🎯 Seeking to time: \(time)")
        
        // Update the audio processor's position
        audioProcessor.seek(to: time)
        
        // Update the binding to reflect the new time
        currentTime = time
        
        // Update any other necessary state
        if let currentIndex = currentFileIndex,
           currentIndex < audioFiles.count {
            print("✅ Seeked to \(timeString(from: time)) in track \(currentIndex + 1)")
        }
    }

    // (Removed bitrate/bit depth display and related helpers)
}

extension LibraryPanel {
    private func handleAlbumRefreshes(_ albumNames: Set<String>) {
        print("🔥 LibraryPanel: handleAlbumRefreshes called with: \(albumNames)")
        guard !albumNames.isEmpty else {
            print("🔥 LibraryPanel: albumNames is empty, returning")
            return
        }
        
        print("🔀 Refreshing \(albumNames.count) albums")
        
        // Album manager will handle updates automatically via @StateObject
        // Just clear the refresh set
        DispatchQueue.main.async {
            SmartRefreshCoordinator.shared.albumsNeedingRefresh.subtract(albumNames)
            print("🔥 LibraryPanel: Cleared refresh set")
        }
    }
    
    private func handleArtistRefreshes(_ artistNames: Set<String>) {
        guard !artistNames.isEmpty else { return }
        
        print("🎭 Refreshing \(artistNames.count) artists")
        
        // Reload artist manager data
        artistManager.loadAllArtists()
        
        for artistName in artistNames {
            // Update selected artist if in detail view
            if case .artistDetail(let detailArtist) = viewState,
               detailArtist.name == artistName {
                if let updatedArtist = artistManager.artists.first(where: { $0.name == artistName }) {
                    DispatchQueue.main.async {
                        self.viewState = .artistDetail(updatedArtist)
                    }
                } else {
                    // Artist was deleted
                    DispatchQueue.main.async {
                        self.viewState = .grid
                    }
                }
            }
        }
        
        // Clear the refresh set
        DispatchQueue.main.async {
            SmartRefreshCoordinator.shared.artistsNeedingRefresh.subtract(artistNames)
        }
    }
}

