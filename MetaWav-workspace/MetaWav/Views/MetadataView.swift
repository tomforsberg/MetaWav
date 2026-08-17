// MetadataView.swift - FIXED: Character encoding issues
import SwiftUI
import AVFoundation
import Foundation
import AppKit
import UniformTypeIdentifiers

struct AlbumMetadataView: View {
    @Binding var currentFileIndex: Int?
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var selectedTrack: TrackMetadata?
    
    @State private var editableTrack = TrackMetadata(
        filePath: "", discNumber: 1, trackNumber: 1, name: "", artist: nil, key: nil, bpm: nil,
        version: nil, isExplicit: nil, duration: nil, format: nil, channelCount: nil,
        sampleRate: nil, bitDepth: nil, isrc: nil, credits: nil, lyrics: nil, notes: nil, relatedFiles: nil
    )
    @State private var isEditing = false
    
    // Force SwiftUI to rebuild credits/related-files sections when entries change
    @State private var creditsRenderToken = UUID()
    @State private var relatedFilesRenderToken = UUID()
    
    // Consistent sizing
    private let notesMinHeight: CGFloat = 120
    private let rowMinHeight: CGFloat = 44
    
    private let musicalKeys = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        "Cm", "C#m", "Dm", "D#m", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "A#m", "Bm"
    ]
    
    private let creditRoles = [
        "Artist", "Producer", "Writer", "Songwriter", "Composer",
        "Mixing Engineer", "Mastering Engineer", "Recording Engineer",
        "Vocalist", "Lead Vocals", "Backing Vocals", "Harmony Vocals",
        "Guitar", "Bass", "Drums", "Piano", "Keyboards", "Synthesizer",
        "Saxophone", "Trumpet", "Violin", "Cello", "Flute",
        "Executive Producer", "Co-Producer", "Assistant Producer",
        "Sound Designer", "Arranger", "Orchestrator", "Conductor",
        "Session Musician", "Featured Artist", "Guest Artist",
        "Lyricist", "Beat Maker", "Programmer", "Sampler", "Photographer", "Record Label"
    ].sorted()

    // Only use selectedTrack, no fallback to playing track
    var currentTrack: TrackMetadata? {
        return selectedTrack
    }
    
    var body: some View {
        if let track = currentTrack {
            metadataContent(for: track)
        } else {
            noTrackSelectedView
        }
    }
    
    private func enhancedRelatedFilesHeader() -> some View {
        HStack {
            Text("RELATED FILES")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .tracking(1)
            
            Spacer()
            
            if !isEditing && !(editableTrack.relatedFiles?.isEmpty ?? true) {
                // Group by type toggle
                Button(action: { toggleGroupByType() }) {
                    Image(systemName: groupByType ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.7))
                }
                .buttonStyle(PlainButtonStyle())
                .help(groupByType ? "Show as list" : "Group by type")
            }
            
            if isEditing {
                Menu {
                    ForEach(TrackMetadata.RelatedFile.FileType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { type in
                        Button(action: { addRelatedFileOfType(type) }) {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(colorFromString(type.color))
                                Text(type.rawValue)
                                if !type.commonExtensions.isEmpty {
                                    Text("(\(type.commonExtensions.prefix(2).joined(separator: ", ")))")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add related file")
            }
        }
        .padding(.bottom, 4)
    }

    // 2. Grouped display option
    @State private var groupByType = false

    private func groupedRelatedFilesView() -> some View {
        let relatedFiles = editableTrack.relatedFiles ?? []
        let groupedFiles = Dictionary(grouping: relatedFiles) { $0.fileType }
        let sortedTypes = groupedFiles.keys.sorted { $0.sortOrder < $1.sortOrder }
        
        return VStack(spacing: 12) {
            ForEach(sortedTypes, id: \.self) { fileType in
                if let filesOfType = groupedFiles[fileType] {
                    VStack(alignment: .leading, spacing: 6) {
                        // Type header
                        HStack(spacing: 8) {
                            Image(systemName: fileType.icon)
                                .font(.system(size: 12))
                                .foregroundColor(colorFromString(fileType.color))
                            
                            Text(fileType.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(colorFromString(fileType.color))
                                .tracking(1)
                            
                            Text("(\(filesOfType.count))")
                                .font(.system(size: 10))
                                .foregroundColor(Color(white: 0.6))
                            
                            Spacer()
                        }
                        
                        // Files of this type
                        ForEach(filesOfType.indices, id: \.self) { fileIndex in
                            if let globalIndex = relatedFiles.firstIndex(where: { $0.id == filesOfType[fileIndex].id }) {
                                compactRelatedFileRow(index: globalIndex)
                            }
                        }
                    }
                    .padding(8)
                    .background(colorFromString(fileType.color).opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
    }

    // 3. Compact file row for grouped display
    private func compactRelatedFileRow(index: Int) -> some View {
        guard let relatedFiles = editableTrack.relatedFiles, index < relatedFiles.count else {
            return AnyView(EmptyView())
        }
        
        let relatedFile = relatedFiles[index]
        let fileExists = relatedFile.fileExists
        
        return AnyView(
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(fileExists ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                
                // File name
                Text(relatedFile.actualDisplayName)
                    .font(.system(size: 12))
                    .foregroundColor(fileExists ? .white : Color(white: 0.5))
                    .lineLimit(1)
                
                Spacer()
                
                // Quick actions
                if fileExists {
                    Button(action: { showInFinder(relatedFile.filePath) }) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 2)
        )
    }

    // 4. File type statistics
    private func relatedFilesStats() -> some View {
        let relatedFiles = editableTrack.relatedFiles ?? []
        let typeStats = Dictionary(grouping: relatedFiles) { $0.fileType }
            .mapValues { $0.count }
        
        return HStack(spacing: 12) {
            ForEach(TrackMetadata.RelatedFile.FileType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { type in
                if let count = typeStats[type], count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .font(.system(size: 10))
                            .foregroundColor(colorFromString(type.color))
                        
                        Text("\(count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(colorFromString(type.color))
                    }
                }
            }
            
            if relatedFiles.isEmpty {
                Text("No files")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.5))
            }
        }
    }

    // 5. Enhanced add file method with type preselection
    private func addRelatedFileOfType(_ fileType: TrackMetadata.RelatedFile.FileType) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select \(fileType.rawValue)"
        openPanel.message = fileType.description
        
        if fileType == .folder {
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.allowsMultipleSelection = false
            openPanel.allowedContentTypes = [.folder]
        } else {
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = true
            
            // Set allowed file types based on the selected type
            let extensions = fileType.commonExtensions
            if !extensions.isEmpty {
                openPanel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
            }
        }
        
        openPanel.begin { response in
            if response == .OK {
                DispatchQueue.main.async {
                    // IMPORTANT: Reassign `editableTrack` to guarantee SwiftUI refresh (nested in-place mutation can be flaky)
                    var updatedTrack = self.editableTrack
                    var updatedFiles = updatedTrack.relatedFiles ?? []

                    for selectedURL in openPanel.urls {
                        let detectedType = TrackMetadata.RelatedFile.FileType.detect(from: selectedURL.path)
                        let finalType = (detectedType == fileType) ? fileType : detectedType
                        updatedFiles.append(
                            TrackMetadata.RelatedFile(
                                filePath: selectedURL.path,
                                displayName: nil,
                                fileType: finalType
                            )
                        )
                    }

                    updatedTrack.relatedFiles = updatedFiles.isEmpty ? nil : updatedFiles
                    self.editableTrack = updatedTrack
                    self.relatedFilesRenderToken = UUID()
                }
            }
        }
    }

    // Helper methods
    private func toggleGroupByType() {
        groupByType.toggle()
    }

    
    private func metadataContent(for track: TrackMetadata) -> some View {
        let audioFile = audioFiles.first { $0.url.path == track.filePath }
        let duration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? (track.duration ?? 0)
        
        return ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Fixed header (unscrollable)
                trackInfoHeader(track: track, audioFile: audioFile)
                    .padding(.horizontal, PanelTheme.horizontalPadding)
                    .padding(.top, PanelTheme.topPadding)
                    .padding(.bottom, PanelTheme.bottomPadding)
                
                // Scrollable content below
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Editable Metadata Grid
                        metadataGrid(track: track, audioFile: audioFile, duration: duration)
                        
                        // Credits Section
                        creditsSection()
                        
                        // Notes Section
                        notesSection()
                        
                        // Related Files Section
                        relatedFilesSection()
                    }
                    .padding(.horizontal, PanelTheme.horizontalPadding)
                    .padding(.bottom, PanelTheme.bottomPadding)
                }
            }
        }
        .onAppear {
            loadTrackData(track)
            // Listen for global Save (⌘S) while editing track metadata
            NotificationCenter.default.addObserver(forName: .saveRequested, object: nil, queue: .main) { _ in
                if isEditing {
                    Task { await saveTrack() }
                }
            }
        }
        .onChange(of: selectedTrack) { oldTrack, newTrack in
            if isEditing {
                // Autosave pending edits for previous selection before switching
                let previousEditingPath = editableTrack.filePath
                Task {
                    if let album = currentAlbum {
                        if let idx = album.tracks.firstIndex(where: { $0.filePath == previousEditingPath }) {
                            var updatedAlbum = album
                            updatedAlbum.tracks[idx] = editableTrack
                            updatedAlbum.calculateDuration()
                            updatedAlbum.updateTrackCount()
                            updatedAlbum.updateDiscCount()
                            do {
                                try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(updatedAlbum)
                                // Propagate globally so all views/transport use latest metadata
                                AppState.shared.currentAlbum = updatedAlbum
                                MenuBarManager.shared.updateCurrentAlbum(updatedAlbum)
                                QueueManager.shared.refreshAlbumInQueue(updatedAlbum)
                            } catch {
                                NotificationManager.shared.log("Autosave on track change failed: \(error)")
                            }
                        }
                    }
                }
            }
            if let track = newTrack {
                loadTrackData(track)
                isEditing = false
                print("🎯 MetadataView: Updated to selected track: \(track.name)")
            }
        }
    }

    // MARK: - Track Info Header
    
    private func trackInfoHeader(track: TrackMetadata, audioFile: AVAudioFile?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // Track title with explicit indicator inline next to text (view mode)
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            if isEditing {
                                TextField("Track Title", text: $editableTrack.name)
                                    .font(.system(size: PanelTheme.titleFontSize, weight: .bold))
                                    .foregroundColor(.white)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                                    .frame(height: 24)
                                    .disabled(!isEditing)
                                    .editUnderline(isEditing)
                            } else {
                                HStack(spacing: 8) {
                                    Text(track.name)
                                        .font(.system(size: PanelTheme.titleFontSize, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .frame(height: 24, alignment: .leading)
                                    if (track.isExplicit ?? false) {
                                        ExplicitIndicatorTraditional(size: 16)
                                    }
                                }
                            }
                        }
                        

                        Spacer()
                    }
                    
                    // Artist - Wrap in HStack to match track name layout
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            TextField("Artist", text: Binding(
                                get: { editableTrack.artist ?? "" },
                                set: { editableTrack.artist = $0.isEmpty ? nil : $0 }
                            ))
                            .font(.system(size: PanelTheme.subtitleFontSize))
                            .foregroundColor(PanelTheme.accent)
                            .textFieldStyle(PlainTextFieldStyle())
                            .opacity(isEditing ? 1 : 0)
                            .controlSize(.small)
                            .frame(height: 22)
                            .disabled(!isEditing)
                            .editUnderline(isEditing)
                            Text(track.artist ?? "Unknown Artist")
                                .font(.system(size: PanelTheme.subtitleFontSize))
                                .foregroundColor(PanelTheme.accent)
                                .opacity(isEditing ? 0 : 1)
                                .frame(height: 22, alignment: .leading)
                        }
                        

                        Spacer()
                    }
                }
                
                // Edit Controls
                VStack(spacing: 4) {
                    Button(action: {
                        if isEditing {
                            NotificationManager.shared.log("Save button pressed - starting save process")
                            Task {
                                await saveTrack()
                            }
                        } else {
                            NotificationManager.shared.log("Edit button pressed - entering edit mode")
                            isEditing = true
                        }
                    }) {
                        Text(isEditing ? "Save" : "Edit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .secondaryGlass(cornerRadius: 6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(height: 24)

                    Button(action: {
                        loadTrackData(track)
                        isEditing = false
                    }) {
                        Text("Cancel")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .secondaryGlass(cornerRadius: 6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(isEditing ? 1 : 0)
                    .disabled(!isEditing)
                    .frame(height: 24)
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    private var noTrackSelectedView: some View {
        ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundColor(Color(white: 0.4))
                
                Text("NO TRACK SELECTED")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                
                Text("Select a track from the tracklist to view or edit metadata")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata Grid
    
    private func metadataGrid(track: TrackMetadata, audioFile: AVAudioFile?, duration: Double) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            
            // Disc number (editable)
            editableDiscNumberItem()
            
            // Track number (editable)
            editableTrackNumberItem()
            
            // Key (editable)
            editableKeyItem()
            
            // BPM (editable)
            editableBPMItem()
            
            // Version (editable)
            editableVersionItem()
            
            // Explicit (editable)
            explicitItem()
            
            // Format (read-only) - from track or file
            metadataItem(label: "FORMAT", value: track.format ?? audioFile?.url.pathExtension.uppercased() ?? "—")
            
            // Duration (read-only)
            metadataItem(label: "DURATION", value: formattedDuration(duration))
            
            // Sample rate (read-only) - from track or file
            if let sampleRate = track.sampleRate {
                metadataItem(label: "SAMPLE RATE", value: "\(Int(sampleRate)) Hz")
            } else if let audioFile = audioFile {
                metadataItem(label: "SAMPLE RATE", value: "\(Int(audioFile.fileFormat.sampleRate)) Hz")
            } else {
                metadataItem(label: "SAMPLE RATE", value: "—")
            }
            
            // Channels (read-only) - from track or file
            if let channels = track.channelCount {
                metadataItem(label: "CHANNELS", value: "\(channels)")
            } else if let audioFile = audioFile {
                metadataItem(label: "CHANNELS", value: "\(audioFile.fileFormat.channelCount)")
            } else {
                metadataItem(label: "CHANNELS", value: "—")
            }
            
            // Bitrate/Bit depth display using format classification
            switch track.audioFormatClass {
            case .lossy:
                let kbps: Int? = {
                    if let stored = track.bitrateKbps { return stored }
                    // Best-effort compute from container if accessible
                    let url = audioFile?.url ?? URL(fileURLWithPath: track.filePath)
                    return getEstimatedBitrateKbps(fileURL: url)
                }()
                let value = (kbps ?? 0) > 0 ? "\(kbps!) kbps" : "-"
                metadataItem(label: "BIT RATE", value: value)
            case .losslessOrUncompressed:
                if let bitDepth = track.bitDepth, !bitDepth.isEmpty {
                    metadataItem(label: "BIT DEPTH", value: bitDepth)
                } else if let audioFile = audioFile {
                    let depth = audioFile.fileFormat.bitDepthString(for: audioFile.url) ?? track.displayFormatFallback
                    metadataItem(label: "BIT DEPTH", value: depth)
                } else {
                    metadataItem(label: "BIT DEPTH", value: track.displayFormatFallback)
                }
            case .unknown:
                // If we can't determine which label to use, show format name
                metadataItem(label: "FORMAT", value: track.displayFormatFallback)
            }
            
            // ISRC at bottom of grid (editable)
            editableISRCItem()
        }
    }
    
    // MARK: - Individual Components
    
    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    // Editable disc number item
    private func editableDiscNumberItem() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DISC")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            ZStack(alignment: .leading) {
                TextField("Disc #", text: Binding(
                    get: { String(editableTrack.discNumber) },
                    set: {
                        if let discNum = Int($0), discNum > 0 {
                            editableTrack.discNumber = discNum
                        }
                    }
                ))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .textFieldStyle(PlainTextFieldStyle())
                .controlSize(.small)
                .opacity(isEditing ? 1 : 0)
                .disabled(!isEditing)
                .frame(height: 22)
                .onChange(of: editableTrack.discNumber) { _, newValue in
                    if newValue <= 0 {
                        editableTrack.discNumber = 1
                    }
                }
                .editUnderline(isEditing)
                Text(String(currentTrack?.discNumber ?? 1))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .opacity(isEditing ? 0 : 1)
                    .frame(height: 22, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    // Editable track number item
    private func editableTrackNumberItem() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRACK")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            ZStack(alignment: .leading) {
                TextField("Track #", text: Binding(
                    get: { String(editableTrack.trackNumber) },
                    set: {
                        if let trackNum = Int($0), trackNum > 0 {
                            editableTrack.trackNumber = trackNum
                        }
                    }
                ))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .textFieldStyle(PlainTextFieldStyle())
                .controlSize(.small)
                .opacity(isEditing ? 1 : 0)
                .disabled(!isEditing)
                .frame(height: 22)
                .onChange(of: editableTrack.trackNumber) { _, newValue in
                    if newValue <= 0 {
                        editableTrack.trackNumber = 1
                    }
                }
                .editUnderline(isEditing)
                Text(String(format: "%02d", currentTrack?.trackNumber ?? 1))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .opacity(isEditing ? 0 : 1)
                    .frame(height: 22, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    private func editableKeyItem() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KEY")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            if isEditing {
                Picker("Key", selection: Binding(
                    get: { editableTrack.key },
                    set: { editableTrack.key = $0 }
                )) {
                    Text("—").tag(nil as String?)
                    ForEach(musicalKeys, id: \.self) { key in
                        Text(key).tag(key as String?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .controlSize(.small)
                .frame(height: 22)
            } else {
                Text(currentTrack?.key ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(height: 22, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    private func editableBPMItem() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BPM")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            ZStack(alignment: .leading) {
                TextField("BPM", text: Binding(
                    get: { editableTrack.bpm?.description ?? "" },
                    set: { editableTrack.bpm = Int($0) }
                ))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .textFieldStyle(PlainTextFieldStyle())
                .controlSize(.small)
                .opacity(isEditing ? 1 : 0)
                .disabled(!isEditing)
                .frame(height: 22)
                .editUnderline(isEditing)
                Text(currentTrack?.bpm?.description ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .opacity(isEditing ? 0 : 1)
                    .frame(height: 22, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    private func editableVersionItem() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VERSION")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            if isEditing {
                Picker("Version", selection: Binding(
                    get: { editableTrack.version },
                    set: { editableTrack.version = $0 }
                )) {
                    Text("—").tag(nil as String?)
                    ForEach(TrackVersion.options, id: \.self) { version in
                        Text(version).tag(version as String?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .controlSize(.small)
                .frame(height: 22)
            } else {
                Text(currentTrack?.version ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(height: 22, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    // Editable ISRC item
    private func editableISRCItem() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ISRC")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            ZStack(alignment: .leading) {
                TextField("ISRC Code", text: Binding(
                    get: { editableTrack.isrc ?? "" },
                    set: { editableTrack.isrc = $0.isEmpty ? nil : $0.uppercased() }
                ))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .textFieldStyle(PlainTextFieldStyle())
                .controlSize(.small)
                .opacity(isEditing ? 1 : 0)
                .disabled(!isEditing)
                .frame(height: 22)
                .editUnderline(isEditing)
                Text(currentTrack?.isrc ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .opacity(isEditing ? 0 : 1)
                    .frame(height: 22, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    private func explicitItem() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EXPLICIT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.6))
                .tracking(1)
            
            if isEditing {
                Toggle("", isOn: Binding(
                    get: { editableTrack.isExplicit ?? false },
                    set: { editableTrack.isExplicit = $0 }
                ))
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0, green: 0.75, blue: 0.39)))
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)
            } else {
                Text((currentTrack?.isExplicit ?? false) ? "YES" : "NO")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 22, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .selectedGlass(cornerRadius: 6)
    }
    
    // MARK: - Credits Section
    
    private func creditsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("CREDITS")
                    .font(.system(size: PanelTheme.sectionHeaderFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
                
                Spacer()
                
                Group {
                    Button(action: addCredit) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(isEditing ? 1 : 0)
                    .disabled(!isEditing)
                }
            }
            .padding(.bottom, 4)
            
            // Credits list
            if let credits = editableTrack.credits, !credits.isEmpty {
                VStack(spacing: 8) {
                    ForEach(credits.indices, id: \.self) { index in
                        creditRow(index: index)
                    }
                }
                .id(creditsRenderToken) // force refresh when credits change
            } else if !isEditing {
                // Show placeholder when not editing and no credits
                Text("No credits available")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .selectedGlass(cornerRadius: 6)
            }
        }
        .padding(.top, 8)
    }
    
    // Notes Section
    private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("NOTES")
                    .font(.system(size: PanelTheme.sectionHeaderFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
                
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Notes content
            if isEditing {
                ZStack(alignment: .topLeading) {
                    TextField("Add Notes...", text: Binding(
                        get: { editableTrack.notes ?? "" },
                        set: { newValue in
                            editableTrack.notes = newValue.isEmpty ? nil : newValue
                        }
                    ), axis: .vertical)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .textFieldStyle(PlainTextFieldStyle())
                    .lineLimit(1...10)
                    .editUnderline(true)
                    // No fixed min height in edit; auto grows but capped by lineLimit
                }
                .padding(10)
                .selectedGlass(cornerRadius: 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let notes = currentTrack?.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No notes available")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .selectedGlass(cornerRadius: 6)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Related Files Section
    
    private func relatedFilesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("RELATED FILES")
                    .font(.system(size: PanelTheme.sectionHeaderFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
                
                Spacer()
                
                Group {
                    Button(action: addRelatedFile) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(PanelTheme.accent)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(isEditing ? 1 : 0)
                    .disabled(!isEditing)
                }
            }
            .padding(.bottom, 4)
            
            // Related files list
            if let relatedFiles = editableTrack.relatedFiles, !relatedFiles.isEmpty {
                VStack(spacing: 8) {
                    ForEach(relatedFiles.indices, id: \.self) { index in
                        relatedFileRow(index: index)
                    }
                }
                .id(relatedFilesRenderToken) // force refresh when related files change
            } else {
                // Placeholder always present to reserve height; hidden during edit
                Text("No related files")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .selectedGlass(cornerRadius: 6)
                    .opacity(isEditing ? 0 : 1)
            }
        }
        .padding(.top, 8)
    }
    
    // UPDATED: Related file row without notes
    private func relatedFileRow(index: Int) -> some View {
        guard let relatedFiles = editableTrack.relatedFiles, index < relatedFiles.count else {
            return AnyView(EmptyView())
        }
        
        let relatedFile = relatedFiles[index]
        let fileExists = relatedFile.fileExists
        
        return AnyView(
            HStack(spacing: 12) {
                // File type icon
                Image(systemName: relatedFile.fileType.icon)
                    .font(.system(size: 16))
                    .foregroundColor(fileExists ? colorFromString(relatedFile.fileType.color) : Color(white: 0.5))
                    .frame(width: 20)
                
                // File info
                VStack(alignment: .leading, spacing: 2) {
                    // File name
                    if isEditing {
                        TextField("Display Name", text: Binding(
                            get: {
                                return editableTrack.relatedFiles?[index].displayName ?? editableTrack.relatedFiles?[index].fileNameWithoutExtension ?? ""
                            },
                            set: { newName in
                                if editableTrack.relatedFiles != nil {
                                    editableTrack.relatedFiles![index].displayName = newName.isEmpty ? nil : newName
                                }
                            }
                        ))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .controlSize(.small)
                        .frame(height: 22)
                        .editUnderline(isEditing)
                    } else {
                        Text(relatedFile.actualDisplayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(fileExists ? .white : Color(white: 0.5))
                    }
                    
                    // File type and status
                    HStack(spacing: 8) {
                        if isEditing {
                            // File type picker
                            Picker("File Type", selection: Binding(
                                get: {
                                    return editableTrack.relatedFiles?[index].fileType ?? .other
                                },
                                set: { newType in
                                    if editableTrack.relatedFiles != nil {
                                        editableTrack.relatedFiles![index].fileType = newType
                                    }
                                }
                            )) {
                                ForEach(TrackMetadata.RelatedFile.FileType.allCases, id: \.self) { type in
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                    }
                                    .tag(type)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.7))
                        } else {
                            Text(relatedFile.fileType.rawValue)
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.7))
                            
                            if !fileExists {
                                Text("• FILE MISSING")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    if !isEditing && fileExists {
                        // Show in Finder button
                        Button(action: { showInFinder(relatedFile.filePath) }) {
                            Image(systemName: "folder")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 0, green: 0.75, blue: 0.39))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Show in Finder")
                    }
                    
                    if isEditing {
                        // Delete button
                        Button(action: { removeRelatedFile(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .frame(minHeight: rowMinHeight)
            .padding(10)
            .selectedGlass(cornerRadius: 6)
        )
    }
    
    private func creditRow(index: Int) -> some View {
        guard let credits = editableTrack.credits, index < credits.count else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 8) {
                // Role (keeps width constant; picker in edit, label in view)
                ZStack(alignment: .leading) {
                    Picker("Role", selection: Binding(
                        get: { self.editableTrack.credits?[index].role ?? credits[index].role },
                        set: { newRole in
                            var updatedTrack = self.editableTrack
                            var updatedCredits = updatedTrack.credits ?? []
                            guard index < updatedCredits.count else { return }
                            updatedCredits[index].role = newRole
                            updatedTrack.credits = updatedCredits
                            self.editableTrack = updatedTrack
                        }
                    )) {
                        ForEach(creditRoles, id: \.self) { role in
                            Text(role).tag(role)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .controlSize(.small)
                    .frame(height: 22)
                    .labelsHidden()
                    .opacity(isEditing ? 1 : 0)
                    .disabled(!isEditing)
                    
                    Text((self.editableTrack.credits?[index].role ?? credits[index].role).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                        .tracking(1)
                        .opacity(isEditing ? 0 : 1)
                }
                .frame(width: 150, alignment: .leading)
                
                // Name (editable text only underlined)
                ZStack(alignment: .leading) {
                    TextField("Name", text: Binding(
                        get: { self.editableTrack.credits?[index].name ?? credits[index].name },
                        set: { newName in
                            var updatedTrack = self.editableTrack
                            var updatedCredits = updatedTrack.credits ?? []
                            guard index < updatedCredits.count else { return }
                            updatedCredits[index].name = newName
                            updatedTrack.credits = updatedCredits
                            self.editableTrack = updatedTrack
                        }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .textFieldStyle(PlainTextFieldStyle())
                    .controlSize(.small)
                    .frame(height: 22)
                    .opacity(isEditing ? 1 : 0)
                    .disabled(!isEditing)
                    .editUnderline(isEditing)
                    
                    let displayName = (self.editableTrack.credits?[index].name ?? credits[index].name)
                    Text(displayName.isEmpty ? "—" : displayName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .opacity(isEditing ? 0 : 1)
                        .frame(height: 22, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if isEditing {
                    // Delete button
                    Button(action: { removeCredit(at: index) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(10)
            .selectedGlass(cornerRadius: 6)
        )
    }
    
    // MARK: - Helper Methods
    
    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func isMP3(_ track: TrackMetadata) -> Bool {
        let ext = URL(fileURLWithPath: track.filePath).pathExtension.lowercased()
        if ext == "mp3" { return true }
        if let fmt = track.format?.lowercased(), fmt.contains("mp3") { return true }
        return false
    }

    private func snapToStandardMP3Bitrate(_ kbps: Int) -> Int {
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

    private func getEstimatedBitrateKbps(fileURL: URL) -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
        // Use synchronous API to avoid semaphore-based deadlocks on main thread
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        // Prefer AVAudioFile-derived duration to avoid deprecated AVAsset APIs
        if let audioFile = try? AVAudioFile(forReading: fileURL) {
            let seconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            if seconds > 0 {
                if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 {
                    let rawKbps = Int(round((Double(size) * 8.0) / (seconds * 1000.0)))
                    if fileURL.pathExtension.lowercased() == "mp3" { return snapToStandardMP3Bitrate(rawKbps) }
                    return rawKbps
                }
            }
        }
        return 0
    }

    // MARK: - Sync wrappers for AVFoundation async loads (macOS 13+)
    @available(macOS 13.0, *)
    private func loadAudioTracksSync(_ asset: AVURLAsset) -> [AVAssetTrack]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [AVAssetTrack]?
        Task {
            result = try? await asset.loadTracks(withMediaType: .audio)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @available(macOS 13.0, *)
    private func loadEstimatedDataRateSync(_ track: AVAssetTrack) -> Float? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Float?
        Task {
            result = try? await track.load(.estimatedDataRate)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    private func loadTrackData(_ track: TrackMetadata) {
        // Create a complete copy of the track
        editableTrack = TrackMetadata(
            filePath: track.filePath,
            discNumber: track.discNumber,
            trackNumber: track.trackNumber,
            name: track.name,
            artist: track.artist,
            key: track.key,
            bpm: track.bpm,
            version: track.version,
            isExplicit: track.isExplicit,
            duration: track.duration,
            format: track.format,
            channelCount: track.channelCount,
            sampleRate: track.sampleRate,
            bitDepth: track.bitDepth,
            isrc: track.isrc,
            credits: track.credits,
            lyrics: track.lyrics,
            notes: track.notes,
            relatedFiles: track.relatedFiles
        )
        
        print("📖 MetadataView: Loaded track metadata: \(track.name) (Disc \(track.discNumber), Track #\(track.trackNumber))")
        print("   Related Files: \(track.relatedFiles?.count ?? 0)")
        if let relatedFiles = track.relatedFiles {
            for (i, file) in relatedFiles.enumerated() {
                print("     [\(i)] \(file.actualDisplayName) (\(file.fileType.rawValue)) - ID: \(file.id)")
                print("         Path: \(file.filePath)")
                print("         Exists: \(file.fileExists)")
            }
        }
    }

    
    private func saveTrack() async {
        guard let album = currentAlbum else {
            print("⚠️ No album to save track metadata to")
            return
        }
        
        NotificationManager.shared.log("Starting track save for: \(editableTrack.name)")
        NotificationManager.shared.log("Current version: \(editableTrack.version ?? "nil")")
        
        // Ensure bitrate/bit depth fields are stored according to format rules
        let fileURL = URL(fileURLWithPath: editableTrack.filePath)
        switch editableTrack.audioFormatClass {
        case .lossy:
            // Store bitrate, clear bit depth
            if editableTrack.bitrateKbps == nil {
                let kbps = getEstimatedBitrateKbps(fileURL: fileURL)
                editableTrack.bitrateKbps = kbps > 0 ? kbps : nil
            }
            editableTrack.bitDepth = nil
        case .losslessOrUncompressed:
            // Store bit depth, clear bitrate
            if (editableTrack.bitDepth == nil || editableTrack.bitDepth?.isEmpty == true) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let audioFile = try? AVAudioFile(forReading: fileURL) {
                        editableTrack.bitDepth = audioFile.fileFormat.bitDepthString(for: fileURL)
                    }
                }
            }
            editableTrack.bitrateKbps = nil
        case .unknown:
            // Leave as-is; UI will fallback to format name
            break
        }

        // Instant save with automatic refresh
        do {
            guard let trackIndex = album.tracks.firstIndex(where: { $0.filePath == editableTrack.filePath }) else {
                throw NSError(domain: "MetadataView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Track not found in album"])
            }

            var updatedAlbum = album
            updatedAlbum.tracks[trackIndex] = editableTrack
            updatedAlbum.calculateDuration()
            updatedAlbum.updateTrackCount()
            updatedAlbum.updateDiscCount()

            try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(updatedAlbum)

            currentAlbum = updatedAlbum
            selectedTrack = updatedAlbum.tracks[trackIndex]
            editableTrack = updatedAlbum.tracks[trackIndex]
            isEditing = false

            // Propagate globally so transport/menu reflect changes immediately
            AppState.shared.currentAlbum = updatedAlbum
            MenuBarManager.shared.updateCurrentAlbum(updatedAlbum)
            QueueManager.shared.refreshAlbumInQueue(updatedAlbum)

            NotificationManager.shared.log("✅ Track metadata saved instantly and UI refreshed")
        } catch {
            NotificationManager.shared.log("Track save failed: \(error)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Save Failed"
                alert.informativeText = "Could not save track changes: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    private func addCredit() {
        var updatedTrack = editableTrack
        var updatedCredits = updatedTrack.credits ?? []
        updatedCredits.append(TrackMetadata.Credit(role: "Producer", name: ""))
        updatedTrack.credits = updatedCredits
        editableTrack = updatedTrack
        creditsRenderToken = UUID()
    }
    
    private func removeCredit(at index: Int) {
        var updatedTrack = editableTrack
        var updatedCredits = updatedTrack.credits ?? []
        guard index < updatedCredits.count else { return }
        updatedCredits.remove(at: index)
        updatedTrack.credits = updatedCredits.isEmpty ? nil : updatedCredits
        editableTrack = updatedTrack
        creditsRenderToken = UUID()
    }
    
    // MARK: - Related Files Methods (UPDATED)
    
    private func addRelatedFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Related File"
        openPanel.message = "Choose a DAW project or other file related to this track"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let selectedURL = openPanel.url {
                DispatchQueue.main.async {
                    let fileType = TrackMetadata.RelatedFile.FileType.detect(from: selectedURL.path)
                    let newRelatedFile = TrackMetadata.RelatedFile(
                        filePath: selectedURL.path,
                        displayName: nil, // Will use filename without extension
                        fileType: fileType
                    )
                    
                    print("🔎 Creating new related file:")
                    print("   Path: \(selectedURL.path)")
                    print("   Type: \(fileType.rawValue)")
                    print("   ID: \(newRelatedFile.id)")
                    print("   Display Name: \(newRelatedFile.actualDisplayName)")
                    
                    var updatedTrack = self.editableTrack
                    var updatedFiles = updatedTrack.relatedFiles ?? []
                    updatedFiles.append(newRelatedFile)
                    updatedTrack.relatedFiles = updatedFiles.isEmpty ? nil : updatedFiles
                    self.editableTrack = updatedTrack
                    self.relatedFilesRenderToken = UUID()
                    
                    print("🔎 Added related file - total count now: \(self.editableTrack.relatedFiles?.count ?? 0)")
                    
                    // DEBUG: Print all related files
                    if let relatedFiles = self.editableTrack.relatedFiles {
                        for (i, file) in relatedFiles.enumerated() {
                            print("   [\(i)] \(file.actualDisplayName) (\(file.fileType.rawValue)) - ID: \(file.id)")
                        }
                    }
                }
            }
        }
    }
    
    private func removeRelatedFile(at index: Int) {
        guard let relatedFiles = editableTrack.relatedFiles, index < relatedFiles.count else { return }

        var updatedTrack = editableTrack
        var updatedFiles = relatedFiles
        let removedFile = updatedFiles[index]
        updatedFiles.remove(at: index)
        updatedTrack.relatedFiles = updatedFiles.isEmpty ? nil : updatedFiles
        editableTrack = updatedTrack
        
        print("🗑️ Removed related file: \(removedFile.actualDisplayName)")
        relatedFilesRenderToken = UUID()
    }
    
    private func showInFinder(_ filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        print("📁 Showing in Finder: \(url.lastPathComponent)")
    }
    
    private func colorFromString(_ colorString: String) -> Color {
        switch colorString {
        case "systemPurple": return .purple
        case "systemBlue": return .blue
        case "systemRed": return .red
        case "systemGreen": return .green
        case "systemOrange": return .orange
        case "systemYellow": return .yellow
        case "systemGray": return .gray
        default: return .gray
        }
    }
}

// MARK: - Extensions

private struct EditUnderlineModifier: ViewModifier {
    let isEditing: Bool
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 1)
                    .opacity(isEditing ? 1 : 0)
                    .padding(.top, 0)
                , alignment: .bottom
            )
    }
}

private extension View {
    func editUnderline(_ isEditing: Bool) -> some View {
        modifier(EditUnderlineModifier(isEditing: isEditing))
    }
}

extension AVAudioFormat {
    var bitDepthString: String? {
        switch commonFormat {
        case .pcmFormatFloat32: return "32-bit float"
        case .pcmFormatInt16: return "16-bit"
        case .pcmFormatInt32: return "32-bit"
        case .pcmFormatFloat64: return "64-bit float"
        default:
            guard let descPtr = Optional(streamDescription) else { return nil }
            let streamDesc = descPtr.pointee
            
            switch streamDesc.mBitsPerChannel {
            case 8: return "8-bit"
            case 16: return "16-bit"
            case 24: return "24-bit"
            case 32 where (streamDesc.mFormatFlags & kAudioFormatFlagIsFloat) != 0:
                return "32-bit float"
            case 32: return "32-bit int"
            case 64: return "64-bit"
            default: return nil
            }
        }
    }
    
    func bitDepthString(for fileURL: URL) -> String? {
        // Check if this is an MP3 file by examining the file URL
        // MP3 files should always be treated as 16-bit internally
        if fileURL.pathExtension.lowercased() == "mp3" {
            return "16-bit"
        }
        
        return bitDepthString
    }
}
