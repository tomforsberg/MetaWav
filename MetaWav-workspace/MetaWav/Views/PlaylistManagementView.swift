// PlaylistManagementView.swift - Comprehensive playlist management dialogs
import SwiftUI

// MARK: - Add Tracks to Playlist Dialog

struct AddTracksToPlaylistView: View {
    let tracks: [TrackMetadata]
    let albums: [AlbumMetadata]
    @Binding var isPresented: Bool
    
    @StateObject private var playlistManager = PlaylistManager.shared
    @State private var selectedPlaylist: PlaylistMetadata?
    @State private var showCreatePlaylistDialog = false
    @State private var showSmartPlaylistDialog = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistDescription = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Add to Playlist")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s") selected")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.7))
            }
            
            // Playlist selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Playlist")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if playlistManager.playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 32))
                            .foregroundColor(Color(white: 0.4))
                        
                        Text("No playlists found")
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.6))
                        
                        Button("Create New Playlist") {
                            showCreatePlaylistDialog = true
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(playlistManager.playlists) { playlist in
                                PlaylistSelectionRow(
                                    playlist: playlist,
                                    isSelected: selectedPlaylist?.id == playlist.id,
                                    onSelect: {
                                        selectedPlaylist = playlist
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.2))
                .cornerRadius(8)
                
                Button("Create New") {
                    showCreatePlaylistDialog = true
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.2))
                .cornerRadius(8)
                
                Button("Smart Playlist") {
                    showSmartPlaylistDialog = true
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.2))
                .cornerRadius(8)
                
                Button("Add to Playlist") {
                    addTracksToSelectedPlaylist()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(selectedPlaylist != nil ? Color(red: 0, green: 0.75, blue: 0.39) : Color(white: 0.3))
                .cornerRadius(8)
                .disabled(selectedPlaylist == nil)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color.clear)
        .liquidGlass(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $showCreatePlaylistDialog) {
            CreatePlaylistView(
                isPresented: $showCreatePlaylistDialog,
                onPlaylistCreated: { newPlaylist in
                    selectedPlaylist = newPlaylist
                }
            )
        }
        .sheet(isPresented: $showSmartPlaylistDialog) {
            SmartPlaylistView(
                isPresented: $showSmartPlaylistDialog,
                onPlaylistCreated: { newPlaylist in
                    selectedPlaylist = newPlaylist
                }
            )
        }
    }
    
    private func addTracksToSelectedPlaylist() {
        guard let playlist = selectedPlaylist else { return }
        
        do {
            try playlistManager.addTracksToPlaylist(tracks, to: playlist.name)
            isPresented = false
        } catch {
            print("❌ Failed to add tracks to playlist: \(error)")
        }
    }
}

// MARK: - Playlist Selection Row

struct PlaylistSelectionRow: View {
    let playlist: PlaylistMetadata
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Playlist icon
            Image(systemName: "music.note.list")
                .font(.system(size: 16))
                .foregroundColor(isSelected ? Color(red: 0, green: 0.75, blue: 0.39) : Color(white: 0.6))
                .frame(width: 20)
            
            // Playlist info
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? Color(red: 0, green: 0.75, blue: 0.39) : .white)
                    .lineLimit(1)
                
                Text("\(playlist.trackCount) tracks")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.6))
            }
            
            Spacer()
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0, green: 0.75, blue: 0.39), lineWidth: 1)
                        )
                } else if isHovered {
                    Color.clear
                        .secondaryGlass(cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.clear)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Create Playlist Dialog

struct CreatePlaylistView: View {
    @Binding var isPresented: Bool
    let onPlaylistCreated: (PlaylistMetadata) -> Void
    
    @StateObject private var playlistManager = PlaylistManager.shared
    @State private var playlistName = ""
    @State private var playlistDescription = ""
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Create New Playlist")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            // Form fields
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlist Name")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    TextField("Enter playlist name", text: $playlistName)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color(white: 0.2))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (Optional)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    TextField("Enter description", text: $playlistDescription)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color(white: 0.2))
                        .cornerRadius(8)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.2))
                .cornerRadius(8)
                
                Button("Create") {
                    createPlaylist()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(playlistName.isEmpty ? Color(white: 0.3) : Color(red: 0, green: 0.75, blue: 0.39))
                .cornerRadius(8)
                .disabled(playlistName.isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(white: 0.15))
        .cornerRadius(12)
    }
    
    private func createPlaylist() {
        guard !playlistName.isEmpty else { return }
        
        isCreating = true
        
        do {
            let newPlaylist = try playlistManager.createPlaylist(
                name: playlistName,
                description: playlistDescription.isEmpty ? nil : playlistDescription
            )
            
            onPlaylistCreated(newPlaylist)
            isPresented = false
        } catch {
            print("❌ Failed to create playlist: \(error)")
            isCreating = false
        }
    }
}

// MARK: - Add Album to Playlist Dialog

struct AddAlbumToPlaylistView: View {
    let album: AlbumMetadata
    @Binding var isPresented: Bool
    
    @StateObject private var playlistManager = PlaylistManager.shared
    @State private var selectedPlaylist: PlaylistMetadata?
    @State private var showCreatePlaylistDialog = false
    @State private var showSmartPlaylistDialog = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Add Album to Playlist")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(album.albumName)")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text("\(album.trackCount) tracks")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.6))
            }
            
            // Playlist selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Playlist")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if playlistManager.playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 32))
                            .foregroundColor(Color(white: 0.4))
                        
                        Text("No playlists found")
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.6))
                        
                        Button("Create New Playlist") {
                            showCreatePlaylistDialog = true
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(playlistManager.playlists) { playlist in
                                PlaylistSelectionRow(
                                    playlist: playlist,
                                    isSelected: selectedPlaylist?.id == playlist.id,
                                    onSelect: {
                                        selectedPlaylist = playlist
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.2))
                .cornerRadius(8)
                
                Button("Create New") {
                    showCreatePlaylistDialog = true
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.2))
                .cornerRadius(8)
                
                Button("Smart Playlist") {
                    showSmartPlaylistDialog = true
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.2))
                .cornerRadius(8)
                
                Button("Add Album") {
                    addAlbumToSelectedPlaylist()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(selectedPlaylist != nil ? Color(red: 0, green: 0.75, blue: 0.39) : Color(white: 0.3))
                .cornerRadius(8)
                .disabled(selectedPlaylist == nil)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color.clear)
        .liquidGlass(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $showCreatePlaylistDialog) {
            CreatePlaylistView(
                isPresented: $showCreatePlaylistDialog,
                onPlaylistCreated: { newPlaylist in
                    selectedPlaylist = newPlaylist
                }
            )
        }
        .sheet(isPresented: $showSmartPlaylistDialog) {
            SmartPlaylistView(
                isPresented: $showSmartPlaylistDialog,
                onPlaylistCreated: { newPlaylist in
                    selectedPlaylist = newPlaylist
                }
            )
        }
    }
    
    private func addAlbumToSelectedPlaylist() {
        guard let playlist = selectedPlaylist else { return }
        
        do {
            try playlistManager.addAlbumToPlaylist(album, to: playlist.name)
            isPresented = false
        } catch {
            print("❌ Failed to add album to playlist: \(error)")
        }
    }
}

// MARK: - Playlist Management Sheet

struct PlaylistManagementSheet: View {
    let tracks: [TrackMetadata]?
    let album: AlbumMetadata?
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isPresented = false
                }
            
            if let tracks = tracks {
                AddTracksToPlaylistView(
                    tracks: tracks,
                    albums: [],
                    isPresented: $isPresented
                )
                .background(Color.clear)
                .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let album = album {
                AddAlbumToPlaylistView(
                    album: album,
                    isPresented: $isPresented
                )
                .background(Color.clear)
                .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

// MARK: - Preview

struct PlaylistManagementView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleTracks = [
            TrackMetadata(
                filePath: "/path/to/track1.mp3",
                discNumber: 1,
                trackNumber: 1,
                name: "Sample Track 1",
                artist: "Sample Artist",
                duration: 180
            )
        ]
        
        AddTracksToPlaylistView(
            tracks: sampleTracks,
            albums: [],
            isPresented: .constant(true)
        )
        .frame(width: 400, height: 500)
    }
}
