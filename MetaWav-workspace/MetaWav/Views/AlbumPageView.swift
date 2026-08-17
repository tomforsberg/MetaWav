// AlbumPageView.swift - UPDATED: Added Album Type field
import SwiftUI
import AVFoundation
import Foundation
import Combine
import AppKit

// MARK: - DragState class for tracking drag operations (unchanged)
class DragState: ObservableObject {
    @Published var isDragging: Bool = false
    @Published var draggedItemId: UUID?
    @Published var draggedItem: String?
    @Published var dropTargetIndex: Int?
    @Published var dropTargetDisc: Int?
    @Published var discCounts: [Int: Int] = [:]
    @Published var discFrames: [Int: CGRect] = [:]
    @Published var currentLocation: CGPoint? = nil
    
    func startDrag(itemId: UUID, item: String) {
        isDragging = true
        draggedItemId = itemId
        draggedItem = item
    }
    
    func updateDropTarget(index: Int) {
        dropTargetIndex = index
    }
    
    func updateDropTarget(index: Int, discNumber: Int) {
        dropTargetIndex = index
        dropTargetDisc = discNumber
    }
    
    func endDrag() {
        isDragging = false
        draggedItemId = nil
        draggedItem = nil
        dropTargetIndex = nil
        dropTargetDisc = nil
        currentLocation = nil
    }
}

// Track disc frames to enable cross-disc hit testing during drag
private struct DiscFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Named coordinate space for album tracklist drag hit-testing
private let albumTracklistSpaceName = "AlbumTracklistSpace"

struct AlbumPageView: View {
    let album: AlbumMetadata
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentFileIndex: Int?
    @Binding var currentTime: TimeInterval
    @Binding var selectedTrack: TrackMetadata?
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var isPoweredOn: Bool
    
    let onBack: () -> Void
    let onPlayAlbum: (AlbumMetadata) -> Void
    let onNavigateToArtist: (String) -> Void
    
    @State private var isEditingAlbum = false
    @State private var editableAlbum: AlbumMetadata
    @State private var frontArtworkImage: NSImage?
    @State private var backArtworkImage: NSImage?
    @State private var showArtworkPicker = false
    @State private var isShowingFront = true
    @State private var flipRotation: Double = 0
    @StateObject private var dragState = DragState()
    @State private var discFrames: [Int: CGRect] = [:]
    @State private var showPowerAlert = false
    @State private var artistProfileImage: NSImage?
    @State private var hoveredAlbumArtist: Bool = false
    @State private var selectedAlbumTrackIDs: Set<UUID> = []
    @State private var albumSelectionAnchor: (disc: Int, index: Int)? = nil
    // Always render from the freshest album available
    private var displayedAlbum: AlbumMetadata {
        currentAlbum ?? album
    }

    
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    @ObservedObject private var queueManager = QueueManager.shared
    
    init(
        album: AlbumMetadata,
        audioFiles: Binding<[AVAudioFile]>,
        currentFileIndex: Binding<Int?>,
        currentTime: Binding<TimeInterval>,
        selectedTrack: Binding<TrackMetadata?>,
        currentAlbum: Binding<AlbumMetadata?>,
        isPoweredOn: Binding<Bool>,
        onBack: @escaping () -> Void,
        onPlayAlbum: @escaping (AlbumMetadata) -> Void,
        onNavigateToArtist: @escaping (String) -> Void
    ) {
        self.album = album
        self._audioFiles = audioFiles
        self._currentFileIndex = currentFileIndex
        self._currentTime = currentTime
        self._selectedTrack = selectedTrack
        self._currentAlbum = currentAlbum
        self._isPoweredOn = isPoweredOn
        self.onBack = onBack
        self.onPlayAlbum = onPlayAlbum
        self.onNavigateToArtist = onNavigateToArtist
        self._editableAlbum = State(initialValue: album)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with back button only
                headerSection(width: geometry.size.width)
                
                // FIXED: Main content with proper HStack containers instead of ZStack+offset
                HStack(spacing: 0) {
                    // Left side: Album Art + Details - 30% width
                    leftSideSection(album: displayedAlbum, width: (geometry.size.width - 60) * 0.3, height: geometry.size.height - 80)
                        .frame(width: (geometry.size.width - 60) * 0.3)
                    
                    // Right side: Track List - 70% width
                    tracklistSection(album: displayedAlbum, width: (geometry.size.width - 60) * 0.7, height: geometry.size.height - 80)
                        .frame(width: (geometry.size.width - 60) * 0.7)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 30) // Add horizontal padding to the entire HStack
                .padding(.top, 16)
            }
        }
        .onAppear {
            loadArtwork(for: displayedAlbum)
            loadArtistProfileImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
                if isEditingAlbum {
                    Task { await saveAlbumMetadata() }
            }
        }
        .alert("Power Required", isPresented: $showPowerAlert) {
            Button("OK") { }
        } message: {
            Text("Please switch on power to play music.")
        }

    }
    
    // MARK: - Header Section (unchanged)
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
    
    // MARK: - FIXED Left Side Section with Proper Constraints
    private func leftSideSection(album: AlbumMetadata, width: CGFloat, height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // FIXED: Album artwork with constrained sizing
                albumArtworkView(size: min(width * 0.85, 240)) // Max 240px, responsive to container
                
                // FIXED: Album details with proper width constraints
                albumDetailsView(album: album, maxWidth: width)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - FIXED Album Artwork View with Constrained Size
    private func albumArtworkView(size: CGFloat) -> some View {
        ZStack {
            // Main artwork display with constrained sizing
            ZStack {
                Group {
                    if let frontImage = frontArtworkImage {
                        Image(nsImage: frontImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(width: size, height: size)
                            .overlay(
                                VStack {
                                    Image(systemName: "music.note")
                                        .font(.system(size: size * 0.2))
                                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                                    Text("FRONT")
                                        .font(.system(size: max(8, size * 0.05), weight: .bold))
                                        .foregroundColor(.gray)
                                }
                            )
                    }
                }
                .rotation3DEffect(
                    .degrees(flipRotation),
                    axis: (x: 0, y: 1, z: 0)
                )
                .opacity(isShowingFront ? 1 : 0)
                
                Group {
                    if let backImage = backArtworkImage {
                        Image(nsImage: backImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.15))
                            .frame(width: size, height: size)
                            .overlay(
                                VStack {
                                    Image(systemName: "square.stack")
                                        .font(.system(size: size * 0.2))
                                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                                    Text("BACK")
                                        .font(.system(size: max(8, size * 0.05), weight: .bold))
                                        .foregroundColor(.gray)
                                }
                            )
                    }
                }
                .rotation3DEffect(
                    .degrees(flipRotation + 180),
                    axis: (x: 0, y: 1, z: 0)
                )
                .opacity(!isShowingFront ? 1 : 0)
            }
            .cornerRadius(12)
            .contentShape(Rectangle())
            .onTapGesture {
                flipArtwork()
            }
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Edit mode overlay
            if isEditingAlbum {
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
    
    private func albumDetailsView(album: AlbumMetadata, maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Album title and metadata sections remain the same until artist section...
            
            VStack(alignment: .leading, spacing: 16) {
                // Album name - identical layout, only underline appears in edit
                ZStack(alignment: .bottomLeading) {
                    Text(album.albumName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: maxWidth - 20, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(isEditingAlbum ? 0 : 1)
                    TextField("Album Name", text: $editableAlbum.albumName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .frame(maxWidth: maxWidth - 20, alignment: .leading)
                        .opacity(isEditingAlbum ? 1 : 0)
                }
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 1)
                        .opacity(isEditingAlbum ? 1 : 0)
                    , alignment: .bottomLeading
                )
                
                
                
                // UPDATED: Artist section using credits-based Various Artists logic
                VStack(alignment: .leading, spacing: 12) {
                    if false {
                        // Edit mode sections (album type, genre, year - unchanged)
                        VStack(alignment: .leading, spacing: 12) {
                            // Album type picker
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ALBUM TYPE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(white: 0.6))
                                    .tracking(1)
                                
                                Picker("Album Type", selection: Binding(
                                    get: { editableAlbum.albumType ?? "" },
                                    set: { editableAlbum.albumType = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Select Type").tag("")
                                    ForEach(AlbumTypes.options, id: \.self) { type in
                                        Text(type).tag(type)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            }
                            
                            // Genre and year pickers remain unchanged...
                            VStack(alignment: .leading, spacing: 6) {
                                Text("GENRE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(white: 0.6))
                                    .tracking(1)
                                
                                Picker("Genre", selection: Binding(
                                    get: { editableAlbum.genre ?? "" },
                                    set: { editableAlbum.genre = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Select Genre").tag("")
                                    ForEach(ID3Genre.allGenres, id: \.id) { genre in
                                        Text(genre.name).tag(genre.name)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("YEAR")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(white: 0.6))
                                    .tracking(1)
                                
                                ZStack(alignment: .bottomLeading) {
                                    Text(album.year ?? "")
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(.white)
                                        .opacity(isEditingAlbum ? 0 : 1)
                                        .frame(height: 22, alignment: .leading)
                                    TextField("Year", text: Binding(
                                        get: { editableAlbum.year ?? "" },
                                        set: { editableAlbum.year = $0.isEmpty ? nil : $0 }
                                    ))
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(.white)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .opacity(isEditingAlbum ? 1 : 0)
                                    .frame(height: 22)
                                }
                                .overlay(
                                    Rectangle()
                                        .fill(Color.white.opacity(0.25))
                                        .frame(height: 1)
                                        .opacity(isEditingAlbum ? 1 : 0)
                                    , alignment: .bottomLeading
                                )
                            }
                        }
                        .frame(maxWidth: maxWidth - 20)
                    } else {
                        // UPDATED: Display mode using credits-based Various Artists logic
                        let albumArtist = album.computedAlbumArtist
                        let isVariousArtists = album.isVariousArtists
                        
                        if isVariousArtists {
                            // Various Artists album
                            Button(action: {
                                showVariousArtistsInfo()
                            }) {
                                HStack(spacing: 12) {
                                    // Various Artists icon
                                    Circle()
                                        .fill(Color(white: 0.2))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "person.3.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Various Artists")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        
                                        let uniqueArtists = album.uniqueMainArtists
                                        Text("\(uniqueArtists.count) artists")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.6))
                                    }
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: maxWidth - 20, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Show contributing artists list (if not too many)
                            if album.uniqueMainArtists.count <= 6 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("CONTRIBUTING ARTISTS")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color(white: 0.5))
                                        .tracking(1)
                                    
                                    ForEach(album.uniqueMainArtists, id: \.self) { artist in
                                        Button(action: {
                                            onNavigateToArtist(artist)
                                        }) {
                                            Text("• \(artist)")
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(white: 0.7))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.top, 8)
                                .frame(maxWidth: maxWidth - 20, alignment: .leading)
                            }
                            
                        } else {
                            // Single artist album - clickable artist name with hover underline
                            HStack(spacing: 12) {
                                // Artist profile picture
                                Group {
                                    if let profileImage = artistProfileImage {
                                        Image(nsImage: profileImage)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color(white: 0.2))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Text(String(albumArtist.prefix(1)))
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                            )
                                    }
                                }
                                
                                Text(albumArtist)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .underline(hoveredAlbumArtist, color: Color(white: 0.6))
                                    .onHover { hovering in
                                        hoveredAlbumArtist = hovering
                                    }
                                    .onTapGesture {
                                        onNavigateToArtist(albumArtist)
                                    }
                                
                                Spacer()
                            }
                            .frame(maxWidth: maxWidth - 20, alignment: .leading)
                        }
                        
                        // Album Type + Genre row (side-by-side) and Year (below)
                        VStack(alignment: .leading, spacing: 6) {
                            // Album Type + Genre side-by-side with interpunct divider
                            HStack(spacing: 8) {
                                // Album Type (content-sized)
                                Group {
                                    if isEditingAlbum {
                                        Picker("", selection: Binding(
                                            get: { editableAlbum.albumType ?? "" },
                                            set: { editableAlbum.albumType = $0.isEmpty ? nil : $0 }
                                        )) {
                                            Text("").tag("")
                                            ForEach(AlbumTypes.options, id: \.self) { type in
                                                Text(type).tag(type)
                                            }
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .labelsHidden()
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(Color(white: 0.7))
                                        .frame(height: 22)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(AlbumTypes.displayName(for: album.albumType) ?? "")
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(Color(white: 0.7))
                                            .fixedSize()
                                    }
                                }

                                // Interpunct divider
                                Text("•")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(white: 0.5))

                                // Genre (content-sized)
                                Group {
                                    if isEditingAlbum {
                                        Picker("", selection: Binding(
                                            get: { editableAlbum.genre ?? "" },
                                            set: { editableAlbum.genre = $0.isEmpty ? nil : $0 }
                                        )) {
                                            Text("").tag("")
                                            ForEach(ID3Genre.allGenres, id: \.id) { genre in
                                                Text(genre.name).tag(genre.name)
                                            }
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .labelsHidden()
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(Color(white: 0.7))
                                        .frame(height: 22)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(displayGenre(album.genre) ?? "")
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(Color(white: 0.7))
                                            .fixedSize()
                                    }
                                }
                            }

                            // Year below
                            ZStack(alignment: .bottomLeading) {
                                Text(album.year ?? "")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(Color(white: 0.7))
                                    .opacity(isEditingAlbum ? 0 : 1)
                                    .frame(height: 22, alignment: .leading)
                                TextField("Year", text: Binding(
                                    get: { editableAlbum.year ?? "" },
                                    set: { editableAlbum.year = $0.isEmpty ? nil : $0 }
                                ))
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(Color(white: 0.7))
                                .textFieldStyle(PlainTextFieldStyle())
                                .opacity(isEditingAlbum ? 1 : 0)
                                .frame(height: 22)
                            }
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(height: 1)
                                    .opacity(isEditingAlbum ? 1 : 0)
                                , alignment: .bottomLeading
                            )
                        }
                        .frame(maxWidth: maxWidth - 20, alignment: .leading)
                    }
                }
            }
            
            // Action buttons remain unchanged...
            HStack(spacing: 12) {
                Button(action: {
                    if isPoweredOn {
                        // Use QueueManager to play album from first track
                        if let firstTrack = displayedAlbum.tracks.first {
                            QueueManager.shared.playAlbumFromTrack(firstTrack, from: displayedAlbum)
                        }
                        onPlayAlbum(displayedAlbum) // Keep for backward compatibility
                    } else {
                        showPowerAlert = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                        Text("Play Album")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isPoweredOn ? .black : Color(white: 0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isPoweredOn ? Color(red: 0, green: 0.75, blue: 0.39) : Color(white: 0.3))
                    .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                

                Button(isEditingAlbum ? "Save" : "Edit") {
                    if isEditingAlbum {
                        Task {
                            await saveAlbumMetadata()
                        }
                    } else {
                        startEditingAlbum(displayedAlbum)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                .buttonStyle(PlainButtonStyle())
                
                if isEditingAlbum {
                    Button("Cancel") {
                        isEditingAlbum = false
                        editableAlbum = album
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
    
    private func showVariousArtistsInfo() {
        let mainArtists = album.uniqueMainArtists
        
        print("🎭 Various Artists album:")
        print("   Main artists: \(mainArtists.joined(separator: ", "))")
    }
    
    // MARK: - FIXED Track List Section with Proper Constraints
    private func tracklistSection(album: AlbumMetadata, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            
            
            // Scrollable track list (original SwiftUI drag/reorder UI)
            ScrollView {
                VStack(spacing: 6) {
                    let workingAlbum = isEditingAlbum ? editableAlbum : (currentAlbum ?? album)
                    let tracksByDisc = workingAlbum.tracksByDisc()
                    let sortedDiscNumbers = workingAlbum.sortedDiscNumbers()

                    ForEach(sortedDiscNumbers, id: \.self) { discNumber in
                        discSection(
                            discNumber: discNumber,
                            tracks: tracksByDisc[discNumber] ?? [],
                            album: workingAlbum
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: DiscFramePreferenceKey.self, value: [discNumber: proxy.frame(in: .named(albumTracklistSpaceName))])
                            }
                        )
                    }
                    
                    // Album total duration footer
                    let totalCount = workingAlbum.tracks.count
                    let totalSeconds = workingAlbum.tracks.compactMap { $0.duration }.reduce(0, +)
                    let totalInt = Int(totalSeconds)
                    let hours = totalInt / 3600
                    let minutes = (totalInt % 3600) / 60
                    let seconds = totalInt % 60
                    let trackLabel = totalCount == 1 ? "track" : "tracks"
                    let displayTime: String = {
                        if hours > 0 {
                            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
                        } else if minutes > 0 {
                            return String(format: "%d:%02d", minutes, seconds)
                        } else {
                            return String(format: "%d", seconds)
                        }
                    }()

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 12)

                    HStack {
                        Spacer()
                        Text("\(totalCount) \(trackLabel) • \(displayTime)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    // Record label line (if any labels credited across tracks)
                    let recordLabels: [String] = {
                        var seen = Set<String>()
                        var ordered: [String] = []
                        for track in workingAlbum.tracks {
                            if let credits = track.credits {
                                for credit in credits {
                                    let role = credit.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                    if role == "record label" {
                                        let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !name.isEmpty && !seen.contains(name) {
                                            seen.insert(name)
                                            ordered.append(name)
                                        }
                                    }
                                }
                            }
                        }
                        return ordered
                    }()

                    if !recordLabels.isEmpty {
                        HStack {
                            Spacer()
                            Text(recordLabels.joined(separator: " • "))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(white: 0.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    else {
                        Spacer().frame(height: 8)
                    }
                }
            }
            .coordinateSpace(name: albumTracklistSpaceName)
            .onPreferenceChange(DiscFramePreferenceKey.self) { frames in
                discFrames = frames
                dragState.discFrames = frames
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .overlay(alignment: .topLeading) {
            if isEditingAlbum, dragState.isDragging, let loc = dragState.currentLocation, let label = dragState.draggedItem {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    .position(x: loc.x, y: loc.y)
                    .allowsHitTesting(false)
                    .zIndex(999)
            }
        }
    }
    
    private func discSection(
        discNumber: Int,
        tracks: [TrackMetadata],
        album: AlbumMetadata
    ) -> some View {
        VStack(spacing: 3) {
            // Disc header (always show, even for a single disc)
            HStack(alignment: .center, spacing: 8) {
				let name = album.discName(for: discNumber) ?? ""
				ZStack(alignment: .leading) {
					// View state
					HStack(spacing: 0) {
						Text("DISC \(discNumber)")
							.font(.system(size: 10, weight: .bold))
							.foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
							.lineLimit(1)
						Text(" - ")
							.font(.system(size: 10, weight: .bold))
							.foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
							.lineLimit(1)
						Text(name)
							.font(.system(size: 10, weight: .bold))
							.foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
							.lineLimit(1)
					}
					.frame(height: 16, alignment: .leading)
					.opacity(isEditingAlbum ? 0 : 1)

					// Edit state
					HStack(spacing: 0) {
						Text("DISC \(discNumber)")
							.font(.system(size: 10, weight: .bold))
							.foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
							.lineLimit(1)
						Text(" - ")
							.font(.system(size: 10, weight: .bold))
							.foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
							.lineLimit(1)
						TextField("Disc \(discNumber) name", text: Binding(
							get: { album.discName(for: discNumber) ?? "" },
							set: { newValue in
								editableAlbum.setDiscName(newValue, for: discNumber)
							}
						))
						.font(.system(size: 10, weight: .bold))
						.foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
						.textFieldStyle(PlainTextFieldStyle())
						.lineLimit(1)
						.frame(height: 16, alignment: .leading)
					}
					.frame(height: 16, alignment: .leading)
					.opacity(isEditingAlbum ? 1 : 0)
				}
				.frame(width: 220, alignment: .leading)
				.padding(6)
				.overlay(
					Rectangle()
						.fill(Color.white.opacity(0.25))
						.frame(height: 1)
						.opacity(isEditingAlbum ? 1 : 0)
					, alignment: .bottomLeading
				)
				Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(.bottom, 6)
            
            // Track rows
            let sortedTracks = tracks.sorted { $0.trackNumber < $1.trackNumber }
            
            ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                VStack(spacing: 1) {
                    // Drop indicator above this position - ONLY show when editing
                    if isEditingAlbum && dragState.isDragging && dragState.dropTargetDisc == discNumber && dragState.dropTargetIndex == index {
                        dropGap()
                    }
                    
                    // The track row
                    AlbumPageTrackRow(
                        track: track,
                        index: index,
                        totalTracks: sortedTracks.count,
                        discNumber: discNumber,
                        isSelected: selectedAlbumTrackIDs.contains(track.id) || selectedTrack?.id == track.id,
                        isPlaying: isTrackPlaying(track),
                        isEditingMode: isEditingAlbum,
                        dragState: dragState,
                        onSelect: { handleAlbumTrackClick(clickedTrack: track, index: index, discNumber: discNumber, tracksInDisc: sortedTracks) },
                        onPlay: { playTrack(track) },
                        onReorder: { fromIndex, toIndex in
                            if isEditingAlbum {
                                reorderTracks(fromIndex: fromIndex, toIndex: toIndex, discNumber: discNumber)
                            }
                        },
                        onCrossDiscReorder: { trackId, fromDisc, toDisc, toIndex in
                            if isEditingAlbum {
                                onCrossDiscMove(trackId, fromDisc, toDisc, toIndex)
                            }
                        },
                        onNavigateToArtist: onNavigateToArtist,

                    )
                }
            }
            
            // Drop indicator at the end - ONLY show when editing
            if isEditingAlbum && dragState.isDragging && dragState.dropTargetDisc == discNumber && dragState.dropTargetIndex == sortedTracks.count {
                dropGap()
            }
        }
        .padding(.bottom, 12)
        .onAppear {
            // Keep counts up to date for this disc for cross-disc drop index clamping
            let sortedTracks = tracks.sorted { $0.trackNumber < $1.trackNumber }
            dragState.discCounts[discNumber] = sortedTracks.count
        }
        .onChange(of: tracks.count) { _, newValue in
            dragState.discCounts[discNumber] = newValue
        }
        .onHover { isHovering in
            if isEditingAlbum && dragState.isDragging && isHovering {
                let count = tracks.count
                if dragState.dropTargetDisc != discNumber || dragState.dropTargetIndex != count {
                    dragState.updateDropTarget(index: count, discNumber: discNumber)
                }
            }
        }
    }

    // MARK: - Multi-selection handling for Album page
    private func handleAlbumTrackClick(clickedTrack: TrackMetadata, index: Int, discNumber: Int, tracksInDisc: [TrackMetadata]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)
        
        if isShift {
            // Range selection within the same disc
            let anchor = albumSelectionAnchor ?? (disc: discNumber, index: index)
            albumSelectionAnchor = anchor
            if anchor.disc == discNumber {
                let lower = min(anchor.index, index)
                let upper = max(anchor.index, index)
                let rangeIDs = Set(tracksInDisc[lower...upper].map { $0.id })
                selectedAlbumTrackIDs.formUnion(rangeIDs)
            } else {
                selectedAlbumTrackIDs.insert(clickedTrack.id)
                albumSelectionAnchor = (disc: discNumber, index: index)
            }
        } else if isCommand {
            // Toggle selection
            if selectedAlbumTrackIDs.contains(clickedTrack.id) {
                selectedAlbumTrackIDs.remove(clickedTrack.id)
            } else {
                selectedAlbumTrackIDs.insert(clickedTrack.id)
            }
            albumSelectionAnchor = (disc: discNumber, index: index)
        } else {
            // Single selection
            selectedAlbumTrackIDs = [clickedTrack.id]
            albumSelectionAnchor = (disc: discNumber, index: index)
        }
        
        // Update legacy single selection and menu
        selectedTrack = clickedTrack
        let allTracks = (currentAlbum ?? album).tracks
        let selected = allTracks.filter { selectedAlbumTrackIDs.contains($0.id) }
        MenuBarManager.shared.updateSelectedTracks(selected)
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
    
    // MARK: - Helper Methods (unchanged but cleaned up)
    
    private func isTrackPlaying(_ track: TrackMetadata) -> Bool {
        guard let currentItem = queueManager.currentItem else { return false }
        return currentItem.track?.filePath == track.filePath && audioProcessor.isPlaying
    }
    
    private func flipArtwork() {
        withAnimation(.easeInOut(duration: 0.6)) {
            flipRotation += 180
            isShowingFront.toggle()
        }
    }
    
    private func loadArtwork(for album: AlbumMetadata) {
        if let frontImage = AlbumMetadataManager.shared.loadFrontArtwork(for: album.albumName) {
            DispatchQueue.main.async {
                self.frontArtworkImage = frontImage
            }
        }
        
        if let backImage = AlbumMetadataManager.shared.loadBackArtwork(for: album.albumName) {
            DispatchQueue.main.async {
                self.backArtworkImage = backImage
            }
        }
    }
    
    private func loadArtistProfileImage() {
        guard let artistName = album.tracks.first?.artist else { return }
        
        if let artist = ArtistManager.shared.artists.first(where: { $0.name == artistName }),
           let profileImagePath = artist.profileImagePath,
           FileManager.default.fileExists(atPath: profileImagePath) {
            
            DispatchQueue.global(qos: .utility).async {
                let image = NSImage(contentsOfFile: profileImagePath)
                DispatchQueue.main.async {
                    self.artistProfileImage = image
                }
            }
        }
    }
    
    private func handleArtworkSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let imageURL = urls.first else { return }
            
            let albumNameForSaving = editableAlbum.albumName.isEmpty ? album.albumName : editableAlbum.albumName
            
            do {
                // Save artwork - this already updates the .meta file with the path
                if isShowingFront {
                    try AlbumMetadataManager.shared.saveFrontArtwork(imageURL, for: albumNameForSaving)
                } else {
                    try AlbumMetadataManager.shared.saveBackArtwork(imageURL, for: albumNameForSaving)
                }
                
                // Reload album from .meta file to get the saved path
                guard let savedAlbum = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumNameForSaving) else {
                    print("⚠️ Could not reload album after saving artwork")
                    showError("Artwork saved but could not refresh display")
                    return
                }
                
                // Update local state with the path from .meta file
                if isShowingFront {
                    editableAlbum.frontArtPath = savedAlbum.frontArtPath
                    currentAlbum?.frontArtPath = savedAlbum.frontArtPath
                    // Load image from the saved path (from .meta file)
                    if let path = savedAlbum.frontArtPath {
                        loadImage(from: URL(fileURLWithPath: path), isFront: true)
                    } else {
                        // Fallback: load from selected URL if path not yet in .meta
                        loadImage(from: imageURL, isFront: true)
                    }
                } else {
                    editableAlbum.backArtPath = savedAlbum.backArtPath
                    currentAlbum?.backArtPath = savedAlbum.backArtPath
                    // Load image from the saved path (from .meta file)
                    if let path = savedAlbum.backArtPath {
                        loadImage(from: URL(fileURLWithPath: path), isFront: false)
                    } else {
                        // Fallback: load from selected URL if path not yet in .meta
                        loadImage(from: imageURL, isFront: false)
                    }
                }
                
                // Update currentAlbum completely to ensure consistency
                currentAlbum = savedAlbum
                
                // Trigger smart refresh for artwork change
                SmartRefreshCoordinator.shared.processMetadataChange(
                    RefreshEvent(type: .albumArtChanged(albumName: albumNameForSaving, isFront: isShowingFront))
                )
                
                print("✅ Saved artwork and updated state from .meta file")
                
            } catch {
                print("❌ Failed to save artwork: \(error)")
                showError("Could not save artwork: \(error.localizedDescription)")
            }
            
        case .failure(let error):
            print("❌ Artwork import failed: \(error)")
            showError("Artwork import failed: \(error.localizedDescription)")
        }
    }
    
    // REMOVED: updateAlbumArtworkPath - redundant since saveFrontArtwork/saveBackArtwork already save to .meta file
    
    
    private func loadImage(from url: URL, isFront: Bool) {
        DispatchQueue.global(qos: .utility).async {
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                if isFront {
                    self.frontArtworkImage = image
                } else {
                    self.backArtworkImage = image
                }
            }
        }
    }
    
    private func startEditingAlbum(_ album: AlbumMetadata) {
        // FIXED: Create a complete copy including artwork paths and album type
        editableAlbum = AlbumMetadata(
            albumName: album.albumName,
            albumType: album.albumType, // NEW: Include album type
            frontArtPath: album.frontArtPath,
            backArtPath: album.backArtPath,
            duration: album.duration,
            genre: album.genre,
            year: album.year,
            trackCount: album.trackCount,
            discCount: album.discCount,
            discNames: album.discNames,
            tracks: album.tracks
        )
        
        isEditingAlbum = true
        print("ðŸŽ¨ Started editing album: \(album.albumName)")
        print("   Current album type: \(album.albumType ?? "nil")")
        print("   Current genre: \(album.genre ?? "nil")")
        print("   Current year: \(album.year ?? "nil")")
        print("   Front art: \(album.frontArtPath ?? "nil")")
        print("   Back art: \(album.backArtPath ?? "nil")")
    }
    
    private func saveAlbumMetadata() async {
        var updatedAlbum = editableAlbum
        
        let oldName = album.albumName
        let newName = editableAlbum.albumName
        
        // No pre-rename needed; instant save handles deletion of old .meta
        
        // Preserve existing data from the latest in-memory album (includes any reordering)
        let sourceAlbum = currentAlbum ?? album
        updatedAlbum.trackCount = sourceAlbum.trackCount
        updatedAlbum.discCount = sourceAlbum.discCount
        updatedAlbum.duration = sourceAlbum.duration
        updatedAlbum.tracks = sourceAlbum.tracks
        // Ensure disc names from the editor are persisted
        updatedAlbum.discNames = editableAlbum.discNames
        
        // Get current artwork paths
        if let savedAlbum = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: updatedAlbum.albumName) {
            updatedAlbum.frontArtPath = savedAlbum.frontArtPath
            updatedAlbum.backArtPath = savedAlbum.backArtPath
        } else {
            updatedAlbum.frontArtPath = album.frontArtPath
            updatedAlbum.backArtPath = album.backArtPath
        }
        
        do {
            // USE THE INSTANT METADATA SAVE METHOD
            try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(updatedAlbum, oldName: oldName != newName ? oldName : nil)
            
            // Update local state
            currentAlbum = updatedAlbum
            AppState.shared.currentAlbum = updatedAlbum
            MenuBarManager.shared.updateCurrentAlbum(updatedAlbum)
            // Also update any queue items that reference this album so transport uses newest metadata
            QueueManager.shared.refreshAlbumInQueue(updatedAlbum, oldName: oldName != newName ? oldName : nil)
            
            // Reload artwork if needed
            DispatchQueue.main.async {
                self.loadArtwork(for: updatedAlbum)
            }
            
            isEditingAlbum = false
            
            print("✅ Successfully saved album metadata instantly")
            
        } catch {
            print("⚠️ Failed to save album: \(error)")
            showError("Failed to save album changes: \(error.localizedDescription)")
        }
    }
    
    private func selectTrack(_ track: TrackMetadata) {
        selectedTrack = track
        MenuBarManager.shared.updateSelectedTrack(track)
        print("ðŸŽ¯ Selected track: \(track.name)")
    }
    
    private func playTrack(_ track: TrackMetadata) {
        print("â–¶ï¸ Playing track: \(track.name)")
        
        guard isPoweredOn else {
            showPowerAlert = true
            return
        }
        
        // Use QueueManager to play album from this track
        // QueueManager handles loading audio files, so we don't need to check audioFiles here
        QueueManager.shared.playAlbumFromTrack(track, from: album)
        
        // Update current album for metadata display
        currentAlbum = album
        
        // Update currentFileIndex if the track is in audioFiles (for UI consistency)
        if let index = audioFiles.firstIndex(where: { $0.url.path == track.filePath }) {
            currentFileIndex = index
        }
        
        print("🎵 Started playing album from track: \(track.name)")
    }
    

    
    private func reorderTracks(fromIndex: Int, toIndex: Int, discNumber: Int) {
        let albumToReorder = displayedAlbum
        print("🔧 ReorderManager: disc \(discNumber) from \(fromIndex) to \(toIndex)")
        if let updated = ReorderManager.shared.reorderAlbum(
            album: albumToReorder,
            discNumber: discNumber,
            fromIndex: fromIndex,
            toIndex: toIndex
        ) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentAlbum = updated
                if isEditingAlbum {
                    editableAlbum = updated
                }
                reloadAudioFilesFromAlbum(updated)
                MenuBarManager.shared.updateCurrentAlbum(updated)
                selectedTrack = nil
                MenuBarManager.shared.updateSelectedTrack(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dragState.endDrag()
        }
    }

    private func onCrossDiscMove(_ trackId: UUID, _ fromDisc: Int, _ toDisc: Int, _ toIndex: Int) {
        let sourceAlbum = displayedAlbum
        if let updated = ReorderManager.shared.moveTrackAcrossDiscs(
            album: sourceAlbum,
            trackId: trackId,
            fromDisc: fromDisc,
            toDisc: toDisc,
            toTrackIndex: toIndex
        ) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentAlbum = updated
                if isEditingAlbum {
                    editableAlbum = updated
                }
                reloadAudioFilesFromAlbum(updated)
                MenuBarManager.shared.updateCurrentAlbum(updated)
                selectedTrack = nil
                MenuBarManager.shared.updateSelectedTrack(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dragState.endDrag()
        }
    }
    
    private func saveReorderedAlbum(_ album: AlbumMetadata) {
        do {
            try AlbumMetadataManager.shared.saveAlbumMetadata(album)
            currentAlbum = album
            reloadAudioFilesFromAlbum(album)
            MenuBarManager.shared.updateCurrentAlbum(album)
            selectedTrack = nil
            MenuBarManager.shared.updateSelectedTrack(nil)
            print("âœ… Successfully saved reordered album")
        } catch {
            print("âŒ Failed to save reordered album: \(error)")
            showError("Failed to save track order: \(error.localizedDescription)")
        }
    }
    
    private func reloadAudioFilesFromAlbum(_ album: AlbumMetadata) {
        AudioProcessor.shared.fullCleanup()
        currentFileIndex = nil
        loadAlbumTracks(album)
        print("ðŸ”„ Reloaded audio files in new track order")
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
                print("âŒ Failed to load: \(track.filePath)")
            }
        }
        
        if !newAudioFiles.isEmpty {
            audioFiles = newAudioFiles
            currentFileIndex = 0
        }
    }
    
    private func displayGenre(_ genre: String?) -> String? {
        guard let genre = genre else { return nil }
        
        if let numericGenre = Int(genre),
           let genreName = ID3Genre.name(for: numericGenre) {
            return genreName
        }
        
        return genre
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

// MARK: - Album Page Track Row (unchanged)

struct AlbumPageTrackRow: View {
    let track: TrackMetadata
    let index: Int
    let totalTracks: Int
    let discNumber: Int
    let isSelected: Bool
    let isPlaying: Bool
    let isEditingMode: Bool
    let dragState: DragState
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onReorder: (Int, Int) -> Void
    // Optional hook to handle cross-disc reorders from the row if needed
    var onCrossDiscReorder: ((UUID, Int, Int, Int) -> Void)? = nil
    let onNavigateToArtist: (String) -> Void  // NEW: Added navigation callback

    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var hoveredArtist: String? = nil  // NEW: Track hovered artist
    @State private var isHovered: Bool = false
    
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    @ObservedObject private var queueManager = QueueManager.shared
    
    var body: some View {
        HStack(spacing: 10) {
            // Track number or playing indicator
            HStack {
                if isPlaying && audioProcessor.isPlaying {
                    PlayingVisualizer()
                        .frame(width: 24, height: 10)
                } else {
                    Text(String(format: "%02d", track.trackNumber))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TrackRowStyle.numberColor(isSelected: isSelected, isPlaying: isPlaying && audioProcessor.isPlaying))
                        .frame(width: 24, alignment: .center)
                }
            }
            
            // UPDATED: Track info with clickable artist names
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
                    
                    // UPDATED: Show clickable artist names with hover underline
                    if let artist = track.artist {
                        HStack(spacing: 0) {
                            // Main artist
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
                            
                            // Add comma and featured artists if any
                            if !track.featuredArtists.isEmpty {
                                Text(", ")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.6))
                                
                                ForEach(Array(track.featuredArtists.enumerated()), id: \.element) { index, featuredArtist in
                                    Text(featuredArtist)
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(white: 0.6))
                                        .underline(hoveredArtist == featuredArtist, color: Color(white: 0.6))
                                        .onHover { isHovered in
                                            hoveredArtist = isHovered ? featuredArtist : nil
                                        }
                                        .onTapGesture {
                                            onNavigateToArtist(featuredArtist)
                                        }
                                    
                                    // Add comma between featured artists
                                    if index < track.featuredArtists.count - 1 {
                                        Text(", ")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(white: 0.6))
                                    }
                                }
                            }
                        }
                        .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if let duration = track.formattedDuration {
                    Text(duration)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            
            // Drag handle - ONLY show when editing
            if isEditingMode {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 16)
            } else {
                Spacer()
                    .frame(width: 16)
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
            TapGesture(count: 2)
                .onEnded { _ in
                    print("🖱️ Double-click gesture triggered for track: \(track.name)")
                    print("   Local isDragging: \(isDragging)")
                    print("   DragState isDragging: \(dragState.isDragging)")
                    print("   isEditingMode: \(isEditingMode)")
                    if !isDragging && !dragState.isDragging {
                        print("🖱️ Double-click detected on track: \(track.name)")
                        onPlay()
                    } else {
                        print("🖱️ Double-click ignored - track is being dragged")
                    }
                }
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    print("🖱️ Single-click gesture triggered for track: \(track.name)")
                    print("   Local isDragging: \(isDragging)")
                    print("   DragState isDragging: \(dragState.isDragging)")
                    if !isDragging && !dragState.isDragging {
                        print("🖱️ Single-click detected on track: \(track.name)")
                        onSelect()
                    } else {
                        print("🖱️ Single-click ignored - track is being dragged")
                    }
                }
        )
        .onHover { hovering in
            if !(isDragging || dragState.isDragging) {
                isHovered = hovering
            }
        }
        .contextMenu {

            Button(action: onPlay) {
                Label("Play Track", systemImage: "play")
            }
            Button(action: {
                var albumForTrack: AlbumMetadata? = queueManager.currentItem?.album
                if albumForTrack == nil {
                    if let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.name) {
                        albumForTrack = album
                    }
                }
                if let album = albumForTrack {
                    QueueManager.shared.addToQueue(track, from: album)
                } else {
                    print("❌ Album not found for track when adding to queue: \(track.name)")
                }
            }) {
                Label("Add to Queue", systemImage: "plus")
            }
        }
        .gesture(
            isEditingMode ?
            DragGesture(coordinateSpace: .named(albumTracklistSpaceName))
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        dragState.startDrag(itemId: track.id, item: track.name)
                        isHovered = false
                    }
                    
                    dragOffset = gesture.translation
                    dragState.currentLocation = gesture.location
                    
                    let rowHeight: CGFloat = 40
                    let point = gesture.location
                    
                    // Determine target disc based on pointer position in named coordinate space
                    var targetDisc = discNumber
                    for (d, frame) in dragState.discFrames {
                        if frame.contains(point) {
                            targetDisc = d
                            break
                        }
                    }
                    
                    // Compute target index within that disc using its frame and row height
                    let destCount = dragState.discCounts[targetDisc] ?? totalTracks
                    let newTarget: Int
                    if let frame = dragState.discFrames[targetDisc] {
                        let clampedY = max(0, min(point.y - frame.minY, frame.height))
                        newTarget = max(0, min(destCount, Int(round(clampedY / rowHeight))))
                    } else {
                        // Fallback to current-disc relative movement
                        let verticalMovement = gesture.translation.height
                        let targetChange = Int(round(verticalMovement / rowHeight))
                        newTarget = max(0, min(destCount, index + targetChange))
                    }
                    
                    if dragState.dropTargetIndex != newTarget || dragState.dropTargetDisc != targetDisc {
                        dragState.updateDropTarget(index: newTarget, discNumber: targetDisc)
                    }
                }
                .onEnded { gesture in
                    let finalTarget = dragState.dropTargetIndex ?? index
                    let finalDisc = dragState.dropTargetDisc ?? discNumber
                    
                    if finalDisc != discNumber {
                        if let trackId = dragState.draggedItemId {
                            onCrossDiscReorder?(trackId, discNumber, finalDisc, finalTarget)
                        }
                    } else if finalTarget != index {
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
    
    private func getTrackNumberColor() -> Color {
        if isDragging || isSelected {
            return Color(red: 0, green: 0.75, blue: 0.39)
        } else {
            return .white
        }
    }
    
    private func getTrackNameColor() -> Color {
        if isDragging || isSelected {
            return Color(red: 0, green: 0.75, blue: 0.39)
        } else {
            return .white
        }
    }
    
    private func getBackgroundColor() -> Color {
        if isDragging { return Color(white: 0.25) }
        if isSelected { return Color(white: 0.15) }
        if isHovered { return Color(white: 0.075) }
        return Color.clear
    }
    

}

// MARK: - Playing Visualizer (unchanged)
struct PlayingVisualizer: View {
    @State private var barHeights: [CGFloat] = [0.3, 0.6, 0.4, 0.8, 0.5]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0, green: 0.75, blue: 0.39))
                    .frame(width: 2, height: barHeights[index] * 12)
                    .animation(.easeInOut(duration: Double.random(in: 0.3...0.8)).repeatForever(autoreverses: true), value: barHeights[index])
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        for index in 0..<5 {
            Timer.scheduledTimer(withTimeInterval: Double.random(in: 0.3...0.8), repeats: true) { _ in
                withAnimation(.easeInOut(duration: Double.random(in: 0.3...0.8))) {
                    barHeights[index] = CGFloat.random(in: 0.2...1.0)
                }
            }
        }
    }
}
