import SwiftUI
import AVFoundation

struct LyricsView: View {
    @Binding var currentFileIndex: Int?
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentTime: TimeInterval
    @Binding var isEditing: Bool
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var selectedTrack: TrackMetadata?
    @ObservedObject private var audioProcessor = AudioProcessor.shared
    
    @State private var currentLyrics: [TrackMetadata.LyricLine] = []
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var activeLyricIndex: Int? = nil
    @State private var viewingTrack: TrackMetadata? = nil
    @State private var hoveredLyricIndex: Int? = nil
    @State private var editedTimeStrings: [TimeInterval: String] = [:]
    
    // FIXED: Use AudioProcessor's loaded URL first; fallback to currentFileIndex
    private var playingFilePath: String? {
        if let url = audioProcessor.loadedFileURL?.path {
            return url
        }
        guard let index = currentFileIndex, index < audioFiles.count else { return nil }
        return audioFiles[index].url.path
    }
    
    // FIXED: Only use selectedTrack - no fallback to playing track
    private var displayTrack: TrackMetadata? {
        return selectedTrack
    }
    
    // Should we sync lyrics with playback time?
    private var shouldSyncWithPlayback: Bool {
        guard let selectedTrack = selectedTrack,
              let playingPath = playingFilePath else {
            // If no track selected, we don't sync (because we show nothing)
            return false
        }
        // Only sync if the selected track's file matches the playing file (normalize paths)
        let sel = normalizedPath(selectedTrack.filePath)
        let ply = normalizedPath(playingPath)
        let matches = sel.caseInsensitiveCompare(ply) == .orderedSame
        #if DEBUG
        if !matches {
            print("🎼 Lyrics not synced. Selected path:\n  \(sel)\nPlaying path:\n  \(ply)")
        }
        #endif
        return matches
    }

    private func normalizedPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        // Standardize and resolve symlinks for robust comparison
        return url.standardized.resolvingSymlinksInPath().path
    }

    var body: some View {
        ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)
            
            Group {
                if let track = displayTrack {
                    mainContentView(for: track)
                } else {
                    noTrackSelectedView
                }
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(maxHeight: .infinity)
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Subviews
    
    private func mainContentView(for track: TrackMetadata) -> some View {
        VStack(spacing: 0) {
            // Track info header
            trackInfoHeader(for: track)
            
            if isEditing {
                editView(for: track)
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // ENSURE FULL EXPANSION
            } else {
                displayView
            }
        }
        .onAppear {
            loadCurrentLyrics(for: track)
            viewingTrack = track
        }
        .onChange(of: displayTrack?.id) { _, _ in
            if isEditing, let previous = viewingTrack {
                // Autosave lyrics for the previous track before switching
                Task { await saveCurrentLyrics(for: previous) }
            }
            if let track = displayTrack {
                loadCurrentLyrics(for: track)
                viewingTrack = track
                isEditing = false
                print("🔄 Track changed to: \(track.name) - loaded \(currentLyrics.count) lyrics")
            }
        }
        .onChange(of: selectedTrack?.id) { _, _ in
            if isEditing, let previous = viewingTrack {
                Task { await saveCurrentLyrics(for: previous) }
            }
            if let track = displayTrack {
                loadCurrentLyrics(for: track)
                isEditing = false
                print("🎯 Selected track changed - reloading lyrics for: \(track.name)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
                if isEditing, let track = displayTrack {
                    Task { await saveCurrentLyrics(for: track) }
            }
        }
        .onChange(of: currentTime) { _, _ in
            // Only update active lyric if we should sync with playback
            if shouldSyncWithPlayback {
                updateActiveLyricIndex()
            }
        }
    }
    
    // Track info header - UPDATED to match MetadataView style
    private func trackInfoHeader(for track: TrackMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // Section header
                    Text(isEditing ? "EDITING LYRICS FOR:" : "VIEWING LYRICS FOR:")
                        .font(.system(size: PanelTheme.captionFontSize, weight: .bold))
                        .foregroundColor(PanelTheme.textSecondary)
                        .tracking(1)
                    
                    // Track name
                    Text(track.name)
                        .font(.system(size: PanelTheme.titleFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Artist
                    if let artist = track.artist {
                        Text(artist)
                            .font(.system(size: PanelTheme.subtitleFontSize))
                            .foregroundColor(PanelTheme.accent)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Edit Controls - UPDATED to use secondary glass buttons
                VStack(spacing: 4) {
                    if isEditing {
                        HStack(spacing: 8) {
                            Button(action: {
                                cancelEditing()
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .secondaryGlass(cornerRadius: 6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                if let track = displayTrack {
                                    Task {
                                        await saveCurrentLyrics(for: track)
                                    }
                                }
                                isEditing = false
                            }) {
                                Text("Save")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .secondaryGlass(cornerRadius: 6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        Button(action: {
                            isEditing = true
                            print("📝 Started editing lyrics for: \(displayTrack?.name ?? "unknown track")")
                            print("   Current lyrics count: \(currentLyrics.count)")
                        }) {
                            Text("Edit")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .secondaryGlass(cornerRadius: 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Sync status indicator - UPDATED styling
            if !isEditing {
                HStack {
                    if shouldSyncWithPlayback {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(PanelTheme.accent)
                                .frame(width: 6, height: 6)
                            Text("SYNCED WITH PLAYBACK")
                                .font(.system(size: PanelTheme.captionFontSize, weight: .bold))
                                .foregroundColor(PanelTheme.accent)
                                .tracking(0.5)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 6, height: 6)
                            Text("NOT SYNCED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                                .tracking(0.5)
                            
                            if playingFilePath != nil {
                                Text("(Different track playing)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, PanelTheme.horizontalPadding)
        .padding(.top, PanelTheme.topPadding)
        .padding(.bottom, PanelTheme.bottomPadding)
    }
    
    private var noTrackSelectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.4))
            
            Text("NO TRACK SELECTED")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Color(white: 0.6))
            
            Text("Select a track from the tracklist to view or edit lyrics")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // FIXED: Edit view with proper height management and expandable lyrics list
    private func editView(for track: TrackMetadata) -> some View {
        VStack(spacing: 0) {
            // Current lyrics list - EXPANDABLE
            if currentLyrics.isEmpty {
                VStack(spacing: 12) {
                    Text("No lyrics yet")
                        .font(.system(size: 16))
                        .foregroundColor(Color(white: 0.6))
                    
                    Text("Add your first lyric below")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
            } else {
                // Lyrics list that expands to fill available space
                List {
                    ForEach(currentLyrics.sorted { $0.time < $1.time }, id: \.id) { line in
                        HStack(spacing: 12) {
                            TextField(
                                "0:00.000",
                                text: Binding(
                                    get: { editedTimeStrings[line.id] ?? formattedTimeWithMs(line.time) },
                                    set: { editedTimeStrings[line.id] = $0 }
                                )
                            )
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PanelTheme.accent)
                            .textFieldStyle(PlainTextFieldStyle())
                            .frame(width: 80, alignment: .leading)
                            .onSubmit {
                                applyTimeEdit(for: line)
                            }
                            
                            TextField("Lyric text", text: Binding(
                                get: { line.text },
                                set: { newText in
                                    if let index = currentLyrics.firstIndex(where: { $0.id == line.id }) {
                                        currentLyrics[index] = TrackMetadata.LyricLine(time: currentLyrics[index].time, text: newText)
                                    }
                                }
                            ))
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(6)
                                .selectedGlass(cornerRadius: 6)
                            
                            Button(action: {
                                if let index = currentLyrics.firstIndex(where: { $0.id == line.id }) {
                                    currentLyrics.remove(at: index)
                                    editedTimeStrings.removeValue(forKey: line.id)
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // FILL AVAILABLE SPACE
                .padding(.horizontal, 20)
            }
            
            // Add new lyric controls - FIXED to stay at bottom
            addLyricSection()
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
    
    // UPDATED: Add lyric section with consistent styling - no extra padding
    private func addLyricSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section divider
            Rectangle()
                .fill(Color(white: 0.25))
                .frame(height: 1)
                .padding(.vertical, 8)
            
            // Section header
            Text("ADD NEW LYRIC")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .tracking(1)
            
            // Input fields
            VStack(spacing: 12) {
                // Time input row
                HStack(spacing: 8) {
                    // Minutes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MIN")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(white: 0.6))
                            .tracking(1)
                        TextField("0", text: $newMinutes)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(6)
                            .glass3(cornerRadius: 6)
                            .frame(width: 50)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: newMinutes) { _, value in
                                newMinutes = value.filter { $0.isNumber }
                            }
                    }
                    
                    Text(":")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 16)
                    
                    // Seconds
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SEC")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(white: 0.6))
                            .tracking(1)
                        TextField("00", text: $newSeconds)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(6)
                            .glass3(cornerRadius: 6)
                            .frame(width: 50)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: newSeconds) { _, value in
                                let filtered = value.filter { $0.isNumber }
                                if filtered.count <= 2, let seconds = Int(filtered), seconds <= 59 {
                                    newSeconds = filtered
                                } else if let seconds = Int(String(filtered.prefix(2))), seconds <= 59 {
                                    newSeconds = String(filtered.prefix(2))
                                } else {
                                    newSeconds = String(newSeconds.prefix(2))
                                }
                            }
                    }
                    
                    Text(".")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 16)
                    
                    // Milliseconds
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(white: 0.6))
                            .tracking(1)
                        TextField("000", text: $newMilliseconds)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(6)
                            .glass3(cornerRadius: 6)
                            .frame(width: 60)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: newMilliseconds) { _, value in
                                let filtered = value.filter { $0.isNumber }
                                newMilliseconds = String(filtered.prefix(3))
                            }
                    }
                    
                    Spacer()
                    
                    // Capture current playback time into the time fields
                    Button(action: setNewTimeFromCurrentPlayback) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Use current playback time")
                }
                
                // Lyric text input
                VStack(alignment: .leading, spacing: 4) {
                    Text("LYRIC TEXT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                        .tracking(1)
                    
                    HStack(spacing: 8) {
                        TextField("Enter lyric text...", text: $newText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .glass3(cornerRadius: 6)
                            .font(.system(size: 13))
                        
                        Button(action: addLyric) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(PanelTheme.accent)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(newText.isEmpty || (newMinutes.isEmpty && newSeconds.isEmpty))
                    }
                }
            }
            .padding(12)
        }
        .background(Color.clear)
    }
    
    @State private var newMinutes: String = ""
    @State private var newSeconds: String = ""
    @State private var newMilliseconds: String = ""
    @State private var newText: String = ""
    
    private var displayView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        Color.clear
                            .frame(height: geometry.size.height / 3)
                            .id("topSpacer")
                        
                        if currentLyrics.isEmpty {
                            // Show placeholder when no lyrics - UPDATED styling
                            VStack(spacing: 12) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 32))
                                    .foregroundColor(Color(white: 0.4))
                                
                                Text("No lyrics available")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(white: 0.6))
                                
                                Text("Click 'Edit' to add lyrics")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(white: 0.5))
                            }
                            .padding(20)
                        } else {
                            ForEach(currentLyrics.indices, id: \.self) { index in
                                lyricLineView(for: index)
                                    .id(index)
                                    .animation(.easeInOut(duration: 0.4), value: activeLyricIndex)
                            }
                        }
                        
                        Color.clear
                            .frame(height: geometry.size.height / 3)
                            .id("bottomSpacer")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                }
                .scrollDisabled(false)
                .onAppear { scrollProxy = proxy }
                .onChange(of: activeLyricIndex) { _, newIndex in
                    // Only auto-scroll if we're syncing with playback
                    if shouldSyncWithPlayback {
                        scrollToActiveLyric(newIndex)
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }
    
    private func lyricLineView(for index: Int) -> some View {
        let isCurrent = shouldSyncWithPlayback && isCurrentLyric(index: index)
        let isPast = shouldSyncWithPlayback && isLyricPast(index: index)
        let isUpcoming = shouldSyncWithPlayback && isLyricUpcoming(index: index)
        let isHovered = hoveredLyricIndex == index
        let isClickable = shouldSyncWithPlayback
        
        return Text(currentLyrics[index].text)
            .font(.system(size: 16, weight: isCurrent ? .bold : .medium, design: .default))
            .foregroundColor(lyricColor(isCurrent: isCurrent, isPast: isPast, isUpcoming: isUpcoming))
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .scaleEffect(isCurrent ? 1.05 : 1.0)
            .opacity(lyricOpacity(isCurrent: isCurrent, isPast: isPast, isUpcoming: isUpcoming) * ((isHovered && !isCurrent) ? 0.9 : 1.0))
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .animation(.easeInOut(duration: 0.3), value: isCurrent)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveredLyricIndex = hovering ? index : (hoveredLyricIndex == index ? nil : hoveredLyricIndex)
            }
            .onTapGesture {
                if isClickable {
                    handleLyricClick(at: index)
                }
            }
            .cursor(isClickable ? .pointingHand : .arrow)
    }
    
    // MARK: - Helper Functions
    
    private func lyricColor(isCurrent: Bool, isPast: Bool, isUpcoming: Bool) -> Color {
        if !shouldSyncWithPlayback {
            return Color.white // No color coding when not synced
        }
        
        if isCurrent {
            return PanelTheme.accent
        } else if isPast {
            return Color.white.opacity(0.4)
        } else if isUpcoming {
            return Color.white.opacity(0.7)
        } else {
            return Color.white.opacity(0.6)
        }
    }
    
    private func lyricOpacity(isCurrent: Bool, isPast: Bool, isUpcoming: Bool) -> Double {
        if !shouldSyncWithPlayback {
            return 1.0 // Full opacity when not synced
        }
        
        if isCurrent {
            return 1.0
        } else if isUpcoming {
            return 0.8
        } else if isPast {
            return 0.5
        } else {
            return 0.6
        }
    }
    
    private func scrollToActiveLyric(_ index: Int?) {
        guard let index = index else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            scrollProxy?.scrollTo(index, anchor: .center)
        }
    }
    
    private func updateActiveLyricIndex() {
        guard !currentLyrics.isEmpty, shouldSyncWithPlayback else {
            activeLyricIndex = nil
            return
        }
        
        let newIndex = currentLyrics.lastIndex(where: { $0.time <= currentTime })
        if newIndex != activeLyricIndex {
            activeLyricIndex = newIndex
        }
    }

    private func handleLyricClick(at index: Int) {
        guard index >= 0 && index < currentLyrics.count else { return }
        let targetTime = currentLyrics[index].time
        audioProcessor.seek(to: targetTime)
        // Update bindings/UI immediately for responsiveness
        currentTime = targetTime
        if shouldSyncWithPlayback {
            activeLyricIndex = index
            scrollToActiveLyric(index)
        }
    }
    
    private func loadCurrentLyrics(for track: TrackMetadata) {
        print("📖 LOADING lyrics for track: \(track.name) (ID: \(track.id))")
        
        // Clear existing lyrics first to prevent showing wrong data
        currentLyrics.removeAll()
        activeLyricIndex = nil
        
        // Load fresh lyrics from the track
        if let trackLyrics = track.lyrics {
            currentLyrics = trackLyrics.sorted { $0.time < $1.time }
            print("   ✅ Loaded \(currentLyrics.count) lyrics from track data")
        } else {
            print("   ❌ Track has no lyrics")
        }
        // Reset any edited time strings for fresh state
        editedTimeStrings.removeAll()
        
        // Debug: Print first few lyrics to verify correct loading
        if !currentLyrics.isEmpty {
            print("   First lyric: \(currentLyrics[0].text) at \(currentLyrics[0].time)s")
        }
    }
    
    // NEW: Cancel editing function
    private func cancelEditing() {
        print("❌ Cancelled lyrics editing, reloading original lyrics")
        if let track = displayTrack {
            loadCurrentLyrics(for: track) // Reload original lyrics
        }
        isEditing = false
    }
    
    // FIXED: Completely rewritten saving logic
    private func saveCurrentLyrics(for track: TrackMetadata) async {
        guard var album = currentAlbum else {
            print("❌ No current album to save lyrics to")
            return
        }
        
        print("💾 SAVING lyrics for track: \(track.name)")
        print("   Track ID: \(track.id)")
        print("   Lyrics count to save: \(currentLyrics.count)")
        
        // Find and update the track in the album using the track ID
        guard let trackIndex = album.tracks.firstIndex(where: { $0.id == track.id }) else {
            print("❌ Track not found in album for saving lyrics")
            return
        }
        
        print("   Found track at index: \(trackIndex)")
        
        // Apply any pending time edits
        var applied = currentLyrics
        for (key, value) in editedTimeStrings {
            if let idx = applied.firstIndex(where: { $0.id == key }), let t = parseTimeString(value) {
                let text = applied[idx].text
                applied[idx] = TrackMetadata.LyricLine(time: t, text: text)
            }
        }
        editedTimeStrings.removeAll()
        // Sort lyrics by time before saving
        let sortedLyrics = applied.sorted { $0.time < $1.time }
        
        // Update the track's lyrics in the album
        album.tracks[trackIndex].lyrics = sortedLyrics.isEmpty ? nil : sortedLyrics
        
        print("   ✅ Updated track lyrics in album data")
        
        do {
            // ENHANCED: Save the updated album to disk with instant metadata
            try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(album)
            print("   ✅ Saved album metadata to disk instantly")
            
            // Update all our bindings with the saved data
            currentAlbum = album
            // Keep global menu/queue state in sync so other views see the latest lyrics
            MenuBarManager.shared.updateCurrentAlbum(album)
            QueueManager.shared.refreshAlbumInQueue(album)
            
            // Emit targeted refresh event for this track and album
            NotificationManager.shared.postNotification(.trackMetadataChanged, object: (album.tracks[trackIndex], album))
            
            // Update the selected track if it's the one we just saved
            if selectedTrack?.id == track.id {
                selectedTrack = album.tracks[trackIndex]
                print("   ✅ Updated selectedTrack binding")
            }
            
            print("✅ Successfully saved \(sortedLyrics.count) lyrics for track: \(track.name)")
            
        } catch {
            print("❌ Failed to save lyrics: \(error)")
            
            // Show error alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Save Failed"
                alert.informativeText = "Could not save lyrics: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func addLyric() {
        let minutes = Int(newMinutes.isEmpty ? "0" : newMinutes) ?? 0
        let seconds = Int(newSeconds.isEmpty ? "0" : newSeconds) ?? 0
        let milliseconds = Int(newMilliseconds.isEmpty ? "0" : newMilliseconds) ?? 0
        
        let time = TimeInterval(minutes * 60 + seconds) + TimeInterval(milliseconds) / 1000.0
        let newLyric = TrackMetadata.LyricLine(time: time, text: newText)
        currentLyrics.append(newLyric)
        currentLyrics.sort { $0.time < $1.time }
        
        newMinutes = ""
        newSeconds = ""
        newMilliseconds = ""
        newText = ""
        
        print("✅ Added lyric at \(time)s: \(newText)")
    }
    
    // Fill the new lyric time fields from the current playback position
    private func setNewTimeFromCurrentPlayback() {
        let totalMs = Int(currentTime * 1000)
        let minutes = totalMs / 60000
        let seconds = (totalMs % 60000) / 1000
        let milliseconds = totalMs % 1000
        
        newMinutes = "\(minutes)"
        newSeconds = String(format: "%02d", seconds)
        newMilliseconds = String(format: "%03d", milliseconds)
    }
    
    private func isCurrentLyric(index: Int) -> Bool {
        guard index < currentLyrics.count - 1 else {
            return currentTime >= currentLyrics[index].time
        }
        return currentTime >= currentLyrics[index].time && currentTime < currentLyrics[index+1].time
    }
    
    private func isLyricPast(index: Int) -> Bool {
        return currentTime > currentLyrics[index].time &&
              (index == currentLyrics.count - 1 || currentTime >= currentLyrics[index+1].time)
    }
    
    private func isLyricUpcoming(index: Int) -> Bool {
        return currentTime < currentLyrics[index].time
    }
    
    // Format time with milliseconds for display
    private func formattedTimeWithMs(_ time: TimeInterval) -> String {
        let totalMs = Int(time * 1000)
        let minutes = totalMs / 60000
        let seconds = (totalMs % 60000) / 1000
        let milliseconds = totalMs % 1000
        
        return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }

    private func parseTimeString(_ input: String) -> TimeInterval? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var minutes = 0
        var secondsPart: Substring

        if parts.count == 2 {
            if let m = Int(parts[0]) { minutes = m } else { return nil }
            secondsPart = parts[1]
        } else {
            secondsPart = parts[0]
        }

        let secParts = secondsPart.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let secStr = secParts.first, let secs = Int(secStr) else { return nil }
        var ms = 0
        if secParts.count == 2 {
            let msStr = secParts[1]
            // Normalize to milliseconds (up to 3 digits)
            let padded = msStr.count >= 3 ? String(msStr.prefix(3)) : String(msStr) + String(repeating: "0", count: 3 - msStr.count)
            if let parsedMs = Int(padded) { ms = parsedMs } else { return nil }
        }

        let totalSeconds = TimeInterval(minutes * 60 + secs) + TimeInterval(ms) / 1000.0
        return totalSeconds
    }

    private func applyTimeEdit(for line: TrackMetadata.LyricLine) {
        guard let str = editedTimeStrings[line.id], let newTime = parseTimeString(str) else { return }
        if let index = currentLyrics.firstIndex(where: { $0.id == line.id }) {
            let text = currentLyrics[index].text
            currentLyrics[index] = TrackMetadata.LyricLine(time: newTime, text: text)
            // Reorder to keep sequential display
            currentLyrics.sort { $0.time < $1.time }
            // Move edited string under new key and normalize the display text
            editedTimeStrings.removeValue(forKey: line.id)
            editedTimeStrings[newTime] = formattedTimeWithMs(newTime)
        }
    }
}
