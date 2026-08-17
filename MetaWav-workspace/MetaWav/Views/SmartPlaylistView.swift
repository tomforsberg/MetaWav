// SmartPlaylistView.swift - Smart playlist creation dialog
import SwiftUI

struct SmartPlaylistView: View {
    @Binding var isPresented: Bool
    let onPlaylistCreated: (PlaylistMetadata) -> Void
    
    @StateObject private var playlistManager = PlaylistManager.shared
    @State private var playlistName = ""
    @State private var playlistDescription = ""
    @State private var isCreating = false
    
    // Criteria
    @State private var artist = ""
    @State private var album = ""
    @State private var genre = ""
    @State private var year = ""
    @State private var minDuration: TimeInterval = 0
    @State private var maxDuration: TimeInterval = 600 // 10 minutes
    @State private var minPlayCount = 0
    @State private var maxPlayCount = 1000
    @State private var maxTracks = 100
    @State private var sortBy: SmartPlaylistSortOption = .name
    
    // UI State
    @State private var showDurationSettings = false
    @State private var showPlayCountSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Create Smart Playlist")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Basic Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PLAYLIST INFO")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(white: 0.6))
                            .tracking(1)
                        
                        VStack(spacing: 8) {
                            TextField("Playlist Name", text: $playlistName)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(12)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                            
                            TextField("Description (optional)", text: $playlistDescription)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(12)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Search Criteria
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SEARCH CRITERIA")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(white: 0.6))
                            .tracking(1)
                        
                        VStack(spacing: 8) {
                            TextField("Artist (optional)", text: $artist)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(12)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                            
                            TextField("Album (optional)", text: $album)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(12)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                            
                            TextField("Genre (optional)", text: $genre)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(12)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                            
                            TextField("Year (optional)", text: $year)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(12)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Advanced Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ADVANCED SETTINGS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(white: 0.6))
                            .tracking(1)
                        
                        VStack(spacing: 8) {
                            // Duration settings
                            Button(action: {
                                showDurationSettings.toggle()
                            }) {
                                HStack {
                                    Text("Duration Filter")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text("\(formatDuration(minDuration)) - \(formatDuration(maxDuration))")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(white: 0.6))
                                    
                                    Image(systemName: showDurationSettings ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(white: 0.6))
                                }
                                .padding(12)
                                .background(
                                    Color.clear.secondaryGlass(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if showDurationSettings {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Min Duration")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.7))
                                        
                                        Spacer()
                                        
                                        TextField("0", value: $minDuration, format: .number)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .frame(width: 60)
                                            .padding(4)
                                            .background(Color(white: 0.15))
                                            .cornerRadius(4)
                                    }
                                    
                                    HStack {
                                        Text("Max Duration")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.7))
                                        
                                        Spacer()
                                        
                                        TextField("600", value: $maxDuration, format: .number)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .frame(width: 60)
                                            .padding(4)
                                            .background(Color(white: 0.15))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            
                            // Play count settings
                            Button(action: {
                                showPlayCountSettings.toggle()
                            }) {
                                HStack {
                                    Text("Play Count Filter")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text("\(minPlayCount) - \(maxPlayCount)")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(white: 0.6))
                                    
                                    Image(systemName: showPlayCountSettings ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(white: 0.6))
                                }
                                .padding(12)
                                .background(
                                    Color.clear.secondaryGlass(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if showPlayCountSettings {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Min Plays")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.7))
                                        
                                        Spacer()
                                        
                                        TextField("0", value: $minPlayCount, format: .number)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .frame(width: 60)
                                            .padding(4)
                                            .background(Color(white: 0.15))
                                            .cornerRadius(4)
                                    }
                                    
                                    HStack {
                                        Text("Max Plays")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.7))
                                        
                                        Spacer()
                                        
                                        TextField("1000", value: $maxPlayCount, format: .number)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .frame(width: 60)
                                            .padding(4)
                                            .background(Color(white: 0.15))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            
                            // Max tracks
                            HStack {
                                Text("Max Tracks")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                TextField("100", value: $maxTracks, format: .number)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .frame(width: 60)
                                    .padding(4)
                                    .background(
                                        Color.clear.secondaryGlass(cornerRadius: 4)
                                    )
                            }
                            .padding(12)
                            .background(
                                Color.clear.secondaryGlass(cornerRadius: 8)
                            )
                            
                            // Sort by
                            HStack {
                                Text("Sort By")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Picker("Sort By", selection: $sortBy) {
                                    ForEach(SmartPlaylistSortOption.allCases, id: \.self) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 120)
                            }
                            .padding(12)
                            .background(
                                Color.clear.secondaryGlass(cornerRadius: 8)
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 400)
            
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
                
                Button("Create Smart Playlist") {
                    createSmartPlaylist()
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
        .frame(width: 500, height: 600)
        .background(Color.clear)
        .liquidGlass(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func createSmartPlaylist() {
        guard !playlistName.isEmpty else { return }
        
        isCreating = true
        
        let criteria = SmartPlaylistCriteria(
            artist: artist.isEmpty ? nil : artist,
            album: album.isEmpty ? nil : album,
            genre: genre.isEmpty ? nil : genre,
            year: year.isEmpty ? nil : year,
            minDuration: minDuration > 0 ? minDuration : nil,
            maxDuration: maxDuration < 600 ? maxDuration : nil,
            minPlayCount: minPlayCount > 0 ? minPlayCount : nil,
            maxPlayCount: maxPlayCount < 1000 ? maxPlayCount : nil,
            maxTracks: maxTracks,
            sortBy: sortBy,
            description: playlistDescription.isEmpty ? nil : playlistDescription
        )
        
        do {
            let newPlaylist = try playlistManager.createSmartPlaylist(name: playlistName, criteria: criteria)
            onPlaylistCreated(newPlaylist)
            isPresented = false
        } catch {
            print("❌ Failed to create smart playlist: \(error)")
            isCreating = false
        }
    }
}

// MARK: - Preview

struct SmartPlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        SmartPlaylistView(
            isPresented: .constant(true),
            onPlaylistCreated: { _ in }
        )
        .frame(width: 500, height: 600)
    }
}
