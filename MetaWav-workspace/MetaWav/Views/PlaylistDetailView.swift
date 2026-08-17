// PlaylistDetailView.swift - Comprehensive playlist view with drag-and-drop support
import SwiftUI
import AVFoundation

// Using the same DragState as AlbumPageView for identical behavior

struct PlaylistDetailView: View {
    let playlist: PlaylistMetadata
    @Binding var isPoweredOn: Bool
    @Binding var selectedTrack: TrackMetadata?
    @Binding var currentAlbum: AlbumMetadata?
    
    let onBack: () -> Void
    let onNavigateToArtist: (String) -> Void
    
    @State private var isEditingPlaylist = false
    @State private var editablePlaylist: PlaylistMetadata
    @State private var draggedItem: PlaylistTrack?
    @State private var showAddTracksDialog = false
    @State private var showDeleteConfirmation = false
    @State private var trackToDelete: PlaylistTrack?
    @State private var showArtworkPicker = false
    @State private var artworkImage: NSImage?
    @State private var showPowerAlert = false
    @State private var selectedPlaylistTrackIDs: Set<UUID> = []
    @State private var playlistSelectionAnchorIndex: Int? = nil
    
    @ObservedObject private var playlistManager = PlaylistManager.shared
    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    @StateObject private var dragState = DragState()
    
    init(
        playlist: PlaylistMetadata,
        isPoweredOn: Binding<Bool>,
        selectedTrack: Binding<TrackMetadata?>,
        currentAlbum: Binding<AlbumMetadata?>,
        onBack: @escaping () -> Void,
        onNavigateToArtist: @escaping (String) -> Void
    ) {
        self.playlist = playlist
        self._isPoweredOn = isPoweredOn
        self._selectedTrack = selectedTrack
        self._currentAlbum = currentAlbum
        self.onBack = onBack
        self.onNavigateToArtist = onNavigateToArtist
        self._editablePlaylist = State(initialValue: playlist)
    }
    
    // Always render from the freshest playlist available
    private var displayedPlaylist: PlaylistMetadata {
        if isEditingPlaylist {
            return editablePlaylist
        }
        if let live = playlistManager.playlists.first(where: { $0.playlistId == playlist.playlistId }) {
            return live
        }
        return editablePlaylist
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header section
                headerSection(width: geometry.size.width)
                
                // Main content
                HStack(spacing: 0) {
                    // Left side: Playlist info - 30% width
                    playlistInfoSection(width: (geometry.size.width - 60) * 0.3, height: geometry.size.height - 80)
                        .frame(width: (geometry.size.width - 60) * 0.3)
                    
                    // Right side: Track list - 70% width
                    tracklistSection(playlist: displayedPlaylist, width: (geometry.size.width - 60) * 0.7, height: geometry.size.height - 80)
                        .frame(width: (geometry.size.width - 60) * 0.7)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 30) // Add horizontal padding to the entire HStack
                .padding(.top, 16)
            }
        }
        .onAppear {
            editablePlaylist = playlist
        }
        .alert("Power Required", isPresented: $showPowerAlert) {
            Button("OK") { }
        } message: {
            Text("Please switch on power to play music.")
        }
        .alert("Delete Track", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let track = trackToDelete {
                    deleteTrack(track)
                }
            }
        } message: {
            Text("Are you sure you want to remove this track from the playlist?")
        }
    }
    
    private func dropIndicator() -> some View {
        HStack {
            Circle()
                .fill(Color(red: 0, green: 0.75, blue: 0.39))
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color(red: 0, green: 0.75, blue: 0.39))
                .frame(height: 2)
            Circle()
                .fill(Color(red: 0, green: 0.75, blue: 0.39))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.2), value: dragState.dropTargetIndex)
        .transition(.scale.combined(with: .opacity))
    }

    private func dropGap() -> some View {
        VStack(spacing: 6) {
            dropIndicator()
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 10)
                .cornerRadius(4)
        }
        .padding(.horizontal, 4)
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
    
    // MARK: - Playlist Info Section
    
    private func playlistInfoSection(width: CGFloat, height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Playlist artwork placeholder
                playlistArtworkView(size: min(width * 0.85, 240))
                
                // Playlist details
                playlistDetailsView(maxWidth: width)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private func playlistArtworkView(size: CGFloat) -> some View {
        ZStack {
            // Playlist artwork or placeholder
            if let artworkPath = editablePlaylist.artworkPath,
               FileManager.default.fileExists(atPath: artworkPath),
               let image = NSImage(contentsOfFile: artworkPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .cornerRadius(12)
            } else if let artworkImage = artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .cornerRadius(12)
            } else {
                // Use first track's artwork or default
                if let firstTrack = editablePlaylist.tracks.first,
                   let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: firstTrack.filePath, name: firstTrack.trackName),
                   let artworkPath = album.frontArtPath,
                   FileManager.default.fileExists(atPath: artworkPath),
                   let image = NSImage(contentsOfFile: artworkPath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .cornerRadius(12)
                } else {
                    // Default playlist artwork
                    Rectangle()
                        .fill(Color(white: 0.2))
                        .frame(width: size, height: size)
                        .cornerRadius(12)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: size * 0.2))
                                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                                Text("PLAYLIST")
                                    .font(.system(size: max(8, size * 0.05), weight: .bold))
                                    .foregroundColor(.gray)
                            }
                        )
                }
            }
            
            // Edit mode overlay
            if isEditingPlaylist {
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
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .fileImporter(
            isPresented: $showArtworkPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleArtworkSelection(result)
        }
        .contextMenu {
            Button(action: {
                showArtworkPicker = true
            }) {
                Label("Change Artwork", systemImage: "photo")
            }
            
            if editablePlaylist.artworkPath != nil {
                Button(action: {
                    removeArtwork()
                }) {
                    Label("Remove Artwork", systemImage: "trash")
                }
            }
        }
    }
    
    private func playlistDetailsView(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Playlist name (unified view/edit, underline only in edit)
            ZStack(alignment: .bottomLeading) {
                Text(displayedPlaylist.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: maxWidth - 20, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isEditingPlaylist ? 0 : 1)
                TextField("Playlist Name", text: $editablePlaylist.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .textFieldStyle(PlainTextFieldStyle())
                    .frame(maxWidth: maxWidth - 20, alignment: .leading)
                    .opacity(isEditingPlaylist ? 1 : 0)
            }
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 1)
                    .opacity(isEditingPlaylist ? 1 : 0)
                , alignment: .bottomLeading
            )
            
            // Playlist description (dynamic height like MetadataView notes)
            ZStack(alignment: .bottomLeading) {
                Text(displayedPlaylist.description ?? "")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.7))
                    .frame(maxWidth: maxWidth - 20, alignment: .leading)
                    .opacity(isEditingPlaylist ? 0 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Description (optional)", text: Binding(
                    get: { editablePlaylist.description ?? "" },
                    set: { editablePlaylist.description = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .textFieldStyle(PlainTextFieldStyle())
                .lineLimit(1...8)
                .opacity(isEditingPlaylist ? 1 : 0)
            }
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 1)
                    .opacity(isEditingPlaylist ? 1 : 0)
                , alignment: .bottomLeading
            )
            
            // Playlist stats
            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYLIST INFO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.6))
                    .tracking(1)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(displayedPlaylist.trackCount) tracks")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    
                    if let duration = displayedPlaylist.duration, duration > 0 {
                        let hours = Int(duration) / 3600
                        let minutes = Int(duration) % 3600 / 60
                        let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                        
                        HStack {
                            Text(durationText)
                                .font(.system(size: 14))
                                .foregroundColor(Color(white: 0.7))
                            Spacer()
                        }
                    }
                    
                    HStack {
                        Text("Created \(displayedPlaylist.createdDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.6))
                        Spacer()
                    }
                }
            }

            // Action buttons (consistent placement with Album/Artist panels)
            HStack(spacing: 12) {
                Button(action: {
                    if isPoweredOn {
                        playlistManager.playPlaylist(displayedPlaylist)
                    } else {
                        showPowerAlert = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                        Text("Play Playlist")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isPoweredOn ? .black : Color(white: 0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isPoweredOn ? Color(red: 0, green: 0.75, blue: 0.39) : Color(white: 0.3))
                    .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())

                Button(isEditingPlaylist ? "Save" : "Edit") {
                    if isEditingPlaylist {
                        savePlaylistChanges()
                    } else {
                        isEditingPlaylist = true
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .buttonStyle(PlainButtonStyle())

                if isEditingPlaylist {
                    Button("Cancel") {
                        isEditingPlaylist = false
                        editablePlaylist = displayedPlaylist
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
    
    // MARK: - Track List Section
    
    private func tracklistSection(playlist: PlaylistMetadata, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Track list header
            HStack {
                Text("TRACKS (\(playlist.trackCount))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
                
                Spacer()
                
                // No extra header badges in album view; keep consistent
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            
            // Scrollable track list (original SwiftUI reordering UI)
            ScrollView {
                VStack(spacing: 6) {
                    let sortedTracks = playlist.tracks.sorted { $0.playlistPosition < $1.playlistPosition }
                    ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                        VStack(spacing: 1) {
                            if isEditingPlaylist && dragState.isDragging && dragState.dropTargetIndex == index {
                                dropGap()
                            }

                            PlaylistTrackRow(
                                track: track,
                                index: index,
                                totalTracks: sortedTracks.count,
                                isSelected: selectedPlaylistTrackIDs.contains(track.id) || selectedTrack?.filePath == track.filePath,
                                isEditingMode: isEditingPlaylist,
                                dragState: dragState,
                                onSelect: { handlePlaylistTrackClick(track: track, index: index, tracks: sortedTracks) },
                                onPlay: { playTrackFromPlaylist(track, at: index) },
                                onReorder: { fromIndex, toIndex in
                                    if isEditingPlaylist {
                                        reorderPlaylistTracks(fromIndex: fromIndex, toIndex: toIndex)
                                    }
                                },
                                onDelete: {
                                    trackToDelete = track
                                    showDeleteConfirmation = true
                                },
                                onNavigateToArtist: onNavigateToArtist,
                                isPlaying: isTrackPlaying(track)
                            )
                        }
                    }

                    if isEditingPlaylist && dragState.isDragging && dragState.dropTargetIndex == sortedTracks.count {
                        dropGap()
                    }
                }
            }
            .coordinateSpace(name: "PlaylistTracklistSpace")
            .overlay(alignment: .topLeading) {
                if isEditingPlaylist, dragState.isDragging, let loc = dragState.currentLocation, let label = dragState.draggedItem {
                    HStack(spacing: 10) {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .position(x: loc.x, y: loc.y)
                    .allowsHitTesting(false)
                    .zIndex(999)
                }
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
    
    // MARK: - Helper Methods
    
    private func selectTrack(_ track: PlaylistTrack) {
        if let (_, trackMetadata) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.trackName) {
            selectedTrack = trackMetadata
            // Update multi-selection state to include this item only when user single-selects
            selectedPlaylistTrackIDs = [track.id]
            // Build selected tracks array for menu manager
            let selected = selectedPlaylistTrackIDs.compactMap { id in
                if let (_, tm) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.trackName), id == track.id {
                    return tm
                }
                return nil
            }
            MenuBarManager.shared.updateSelectedTracks(selected)
        }
    }

    // Multi-selection handler for playlist rows
    private func handlePlaylistTrackClick(track: PlaylistTrack, index: Int, tracks: [PlaylistTrack]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)
        
        if isShift, let anchor = playlistSelectionAnchorIndex {
            let lower = min(anchor, index)
            let upper = max(anchor, index)
            let rangeIDs = Set(tracks[lower...upper].map { $0.id })
            selectedPlaylistTrackIDs.formUnion(rangeIDs)
        } else if isCommand {
            if selectedPlaylistTrackIDs.contains(track.id) {
                selectedPlaylistTrackIDs.remove(track.id)
            } else {
                selectedPlaylistTrackIDs.insert(track.id)
            }
            playlistSelectionAnchorIndex = index
        } else {
            selectedPlaylistTrackIDs = [track.id]
            playlistSelectionAnchorIndex = index
        }
        
        // Update selectedTrack and menu
        if let (_, trackMetadata) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.trackName) {
            selectedTrack = trackMetadata
        }
        let selectedMeta = selectedPlaylistTrackIDs.compactMap { id in
            if let pt = tracks.first(where: { $0.id == id }), let (_, tm) = AlbumMetadataManager.shared.findTrack(filePath: pt.filePath, name: pt.trackName) {
                return tm
            }
            return nil
        }
        MenuBarManager.shared.updateSelectedTracks(selectedMeta)
    }
    
    private func playTrackFromPlaylist(_ track: PlaylistTrack, at index: Int) {
        guard isPoweredOn else { showPowerAlert = true; return }
        
        // Play playlist from this track
        playlistManager.playPlaylistFromTrack(playlist, startingAt: index)
        
        // Update selected track
        if let (_, trackMetadata) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.trackName) {
            selectedTrack = trackMetadata
            MenuBarManager.shared.updateSelectedTrack(trackMetadata)
        }
    }
    
    private func deleteTrack(_ track: PlaylistTrack) {
        do {
            if let (_, trackMetadata) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.trackName) {
                try playlistManager.removeTracksFromPlaylist([trackMetadata], from: playlist.name)
                if let updated = playlistManager.getPlaylist(named: playlist.name) {
                    editablePlaylist = updated
                }
            }
        } catch {
            print("❌ Failed to remove track from playlist: \(error)")
        }
    }
    
    private func savePlaylistChanges() {
        do {
            try playlistManager.updatePlaylistMetadata(id: playlist.playlistId, newName: editablePlaylist.name, newDescription: editablePlaylist.description)
            // Sync local editable state with saved
            if let updated = playlistManager.playlists.first(where: { $0.playlistId == playlist.playlistId }) {
                editablePlaylist = updated
            }
            isEditingPlaylist = false
        } catch {
            print("❌ Failed to save playlist changes: \(error)")
        }
    }

    private func isTrackPlaying(_ track: PlaylistTrack) -> Bool {
        guard let currentItem = queueManager.currentItem else { return false }
        return currentItem.track?.filePath == track.filePath && audioProcessor.isPlaying
    }

    private func reorderPlaylistTracks(fromIndex: Int, toIndex: Int) {
        let name = displayedPlaylist.name
        if let updated = ReorderManager.shared.reorderPlaylist(
            playlistName: name,
            fromIndex: fromIndex,
            toIndex: toIndex
        ) {
            // Reflect instantly while editing
            editablePlaylist = updated
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dragState.endDrag()
        }
    }
    
    // MARK: - Artwork Management
    
    private func handleArtworkSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let imageURL = urls.first else { return }
            
            do {
                try playlistManager.savePlaylistArtwork(imageURL, for: editablePlaylist.playlistId)
                
                // Load the image for immediate display
                if let image = NSImage(contentsOf: imageURL) {
                    artworkImage = image
                }
                
                // Update the editable playlist
                if let updatedPlaylist = playlistManager.playlists.first(where: { $0.playlistId == editablePlaylist.playlistId }) {
                    editablePlaylist = updatedPlaylist
                }
                
                print("✅ Saved artwork for playlist: \(editablePlaylist.name)")
            } catch {
                print("❌ Failed to save playlist artwork: \(error)")
            }
            
        case .failure(let error):
            print("❌ Failed to select artwork: \(error)")
        }
    }
    
    private func removeArtwork() {
        do {
            try playlistManager.removePlaylistArtwork(for: editablePlaylist.playlistId)
            
            // Clear the artwork image
            artworkImage = nil
            
            // Update the editable playlist
            if let updatedPlaylist = playlistManager.playlists.first(where: { $0.playlistId == editablePlaylist.playlistId }) {
                editablePlaylist = updatedPlaylist
            }
            
            print("✅ Removed artwork for playlist: \(editablePlaylist.name)")
        } catch {
            print("❌ Failed to remove playlist artwork: \(error)")
        }
    }
}

// MARK: - Playlist Track Row

struct PlaylistTrackRow: View {
    let track: PlaylistTrack
    let index: Int
    let totalTracks: Int
    let isSelected: Bool
    let isEditingMode: Bool
    let dragState: DragState
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onReorder: (Int, Int) -> Void
    let onDelete: () -> Void
    let onNavigateToArtist: (String) -> Void
    let isPlaying: Bool
    
    @State private var hoveredArtist: String? = nil
    @State private var isDragging: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Track number (playlist order) or playing indicator
            HStack {
                if isPlaying {
                    PlayingVisualizer()
                        .frame(width: 24, height: 10)
                } else {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TrackRowStyle.numberColor(isSelected: isSelected, isPlaying: isPlaying))
                        .frame(width: 24, alignment: .center)
                }
            }
            
            // Track info
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.trackName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TrackRowStyle.titleColor(isSelected: isSelected, isPlaying: isPlaying))
                        .lineLimit(1)
                    
                    // Artist name with navigation
                    if let artist = track.artistName {
                        Text(artist)
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.6))
                            .underline(hoveredArtist == artist, color: Color(white: 0.6))
                            .onHover { isHovered in
                                hoveredArtist = isHovered ? artist : nil
                            }
                            .onTapGesture {
                                onNavigateToArtist(artist)
                            }
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Duration
                Text(track.formattedDuration)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
            }
            
            // Edit affordances
            if isEditingMode {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 16)
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.4))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(0.7)
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
        .opacity(isDragging ? 0.9 : 1.0)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .offset(dragOffset)
        .compositingGroup()
        .zIndex(isDragging ? 100 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            if !(isDragging || dragState.isDragging) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onPlay()
                }
        )
        .gesture(
            isEditingMode ?
            DragGesture(coordinateSpace: .named("PlaylistTracklistSpace"))
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        dragState.startDrag(itemId: track.id, item: track.trackName)
                        isHovered = false
                    }
                    dragOffset = gesture.translation
                    dragState.currentLocation = gesture.location
                    let rowHeight: CGFloat = 40
                    let verticalMovement = gesture.translation.height
                    let targetChange = Int(round(verticalMovement / rowHeight))
                    let newTarget = max(0, min(totalTracks, index + targetChange))
                    if dragState.dropTargetIndex != newTarget {
                        dragState.updateDropTarget(index: newTarget)
                    }
                }
                .onEnded { _ in
                    let finalTarget = dragState.dropTargetIndex ?? index
                    if finalTarget != index {
                        onReorder(index, finalTarget)
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = .zero
                        isDragging = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dragState.endDrag()
                    }
                }
            : nil
        )
    }

    private func getBackgroundColor() -> Color {
        if isDragging { return Color(white: 0.25) }
        if isSelected { return Color(white: 0.15) }
        if isHovered { return Color(white: 0.075) }
        return Color.clear
    }
}

// MARK: - Drop Delegate

struct PlaylistDropDelegate: DropDelegate {
    let destinationTrack: PlaylistTrack
    let playlistManager: PlaylistManager
    let playlistName: String
    @Binding var draggedItem: PlaylistTrack?
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem != destinationTrack else { return }
        
        // Find indices and reorder
        if let draggedIndex = playlistManager.playlists.first(where: { $0.name == playlistName })?.tracks.firstIndex(where: { $0.id == draggedItem.id }),
           let destinationIndex = playlistManager.playlists.first(where: { $0.name == playlistName })?.tracks.firstIndex(where: { $0.id == destinationTrack.id }) {
            _ = ReorderManager.shared.reorderPlaylist(
                playlistName: playlistName,
                fromIndex: draggedIndex,
                toIndex: destinationIndex
            )
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}

// MARK: - Preview

struct PlaylistDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let samplePlaylist = PlaylistMetadata(name: "My Playlist", description: "A sample playlist")
        
        PlaylistDetailView(
            playlist: samplePlaylist,
            isPoweredOn: .constant(true),
            selectedTrack: .constant(nil),
            currentAlbum: .constant(nil),
            onBack: {},
            onNavigateToArtist: { _ in }
        )
        .frame(width: 800, height: 600)
    }
}
