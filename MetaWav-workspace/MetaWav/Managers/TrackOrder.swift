import SwiftUI
import AVFoundation

struct TrackOrder {
    static func getTrackNumber(for url: URL, in album: AlbumMetadata? = nil) -> Int? {
        // 1. First check album metadata if provided
        if let album = album,
           let track = album.tracks.first(where: { $0.filePath == url.path }) {
            return track.trackNumber
        }
        
        // 2. Special handling for MP3s
        if url.pathExtension.lowercased() == "mp3" {
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }

            let asset = AVURLAsset(url: url)
            if #available(macOS 13.0, *) {
                if let items = loadMetadataItemsSync(asset) {
                    for item in items {
                        if let key = item.key as? String, key.contains("TRCK") || key.contains("Track") {
                            if let stringValue = loadStringValueSync(item) ?? nil {
                                let parts = stringValue.components(separatedBy: "/")
                                if let number = Int(parts[0]) { return number }
                                if let number = Int(stringValue) { return number }
                            }
                        }
                    }
                }
            } else {
                for item in asset.metadata {
                    if let key = item.key as? String, key.contains("TRCK") || key.contains("Track") {
                        if let stringValue = item.stringValue {
                            let parts = stringValue.components(separatedBy: "/")
                            if let number = Int(parts[0]) { return number }
                            if let number = Int(stringValue) { return number }
                        }
                    }
                }
            }
        }

        // 3. Fallback to filename (e.g., "01 Track.mp3" → 1)
        let numbers = url.deletingPathExtension().lastPathComponent
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .joined()
        return numbers.isEmpty ? nil : Int(numbers)
    }

    // Rest of your existing TrackOrder code remains unchanged...
    static func orderedTracks(from files: [AVAudioFile], album: AlbumMetadata? = nil) -> [AVAudioFile] {
        if let album = album {
            return orderedTracksFromAlbum(files: files, album: album)
        }
        
        return files.sorted { a, b in
            let aNum = getTrackNumber(for: a.url)
            let bNum = getTrackNumber(for: b.url)
            
            // Handle nil cases first
            switch (aNum, bNum) {
            case (nil, nil): return false // Maintain original order
            case (nil, _): return false
            case (_, nil): return true
            case let (a?, b?): return a < b
            }
        }
    }
    
    // NEW: Order tracks using album metadata
    static func orderedTracksFromAlbum(files: [AVAudioFile], album: AlbumMetadata) -> [AVAudioFile] {
        print("🎼 Ordering tracks using album metadata")
        
        // Create a map for quick lookup
        let fileMap = Dictionary(uniqueKeysWithValues: files.map { ($0.url.path, $0) })
        
        // Get tracks sorted by track number
        let sortedTracks = album.tracks.sorted { $0.trackNumber < $1.trackNumber }
        
        // Build ordered array using album metadata
        var orderedFiles: [AVAudioFile] = []
        
        for track in sortedTracks {
            if let audioFile = fileMap[track.filePath] {
                orderedFiles.append(audioFile)
                print("  \(track.trackNumber). \(track.name) ✅")
            } else {
                print("  \(track.trackNumber). \(track.name) ❌ (file not found)")
            }
        }
        
        // Add any remaining files not found in album metadata
        let albumFilePaths = Set(album.tracks.map { $0.filePath })
        for file in files {
            if !albumFilePaths.contains(file.url.path) {
                orderedFiles.append(file)
                print("  ??. \(file.url.lastPathComponent) (not in album)")
            }
        }
        
        print("📋 Album-based order complete: \(orderedFiles.count) files")
        return orderedFiles
    }

    // Helper function to check if we should handle this as a track number
    private static func shouldHandleTrackNumber(identifier: String) -> Bool {
        let trackIdentifiers = [
            "id3/TRCK", "org.id3.TRCK", "org.id3.TRK", "itsk/%A9trk",
            "id3/TRK", "TRCK", "TRK"
        ]
        
        return trackIdentifiers.contains(identifier) ||
               identifier.lowercased().contains("track") ||
               identifier.lowercased().contains("trck") ||
               identifier.lowercased().contains("trk")
    }
    
    // Convert ordered index to original array index
    static func originalIndex(for orderedIndex: Int, in files: [AVAudioFile], album: AlbumMetadata? = nil) -> Int? {
        let orderedFiles = orderedTracks(from: files, album: album)
        guard orderedIndex >= 0 && orderedIndex < orderedFiles.count else { return nil }
        
        let targetFile = orderedFiles[orderedIndex]
        return files.firstIndex { $0.url == targetFile.url }
    }
    
    // Convert original array index to ordered index
    static func orderedIndex(for originalIndex: Int, in files: [AVAudioFile], album: AlbumMetadata? = nil) -> Int? {
        guard originalIndex >= 0 && originalIndex < files.count else { return nil }
        
        let targetFile = files[originalIndex]
        let orderedFiles = orderedTracks(from: files, album: album)
        return orderedFiles.firstIndex { $0.url == targetFile.url }
    }
    
    // Get display track number (the actual track number from metadata, not array position)
    static func getDisplayTrackNumber(for originalIndex: Int, in files: [AVAudioFile], album: AlbumMetadata? = nil) -> String {
        guard originalIndex >= 0 && originalIndex < files.count else { return "--" }
        
        let file = files[originalIndex]
        if let trackNum = getTrackNumber(for: file.url, in: album) {
            return String(format: "%02d", trackNum)
        }
        
        // Fallback to ordered position + 1
        if let orderedPos = orderedIndex(for: originalIndex, in: files, album: album) {
            return String(format: "%02d", orderedPos + 1)
        }
        
        return String(format: "%02d", originalIndex + 1)
    }
    
    // NEW: Get track metadata from album if available
    static func getTrackMetadata(for url: URL, in album: AlbumMetadata? = nil) -> TrackMetadata? {
        if let album = album {
            return album.tracks.first { $0.filePath == url.path }
        }
        
        // Search all albums
        return AlbumMetadataManager.shared.findTrack(filePath: url.path, name: url.deletingPathExtension().lastPathComponent)?.track
    }
    
    // NEW: Sort tracks across multiple albums (for library view)
    static func sortedTracksFromMultipleAlbums(_ albums: [AlbumMetadata]) -> [(album: AlbumMetadata, track: TrackMetadata)] {
        var allTracks: [(album: AlbumMetadata, track: TrackMetadata)] = []
        
        // Sort albums alphabetically
        let sortedAlbums = albums.sorted { $0.albumName < $1.albumName }
        
        for album in sortedAlbums {
            // Sort tracks within album by track number
            let sortedTracks = album.tracks.sorted { $0.trackNumber < $1.trackNumber }
            
            for track in sortedTracks {
                allTracks.append((album: album, track: track))
            }
        }
        
        return allTracks
    }
}

// MARK: - Modern AVFoundation loaders (sync wrappers)
extension TrackOrder {
    @available(macOS 13.0, *)
    private static func loadMetadataItemsSync(_ asset: AVURLAsset) -> [AVMetadataItem]? {
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
    private static func loadStringValueSync(_ item: AVMetadataItem) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        Task {
            result = try? await item.load(.stringValue)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}

// Helper extension for array partitioning (unchanged)
extension Sequence {
    func partitioned(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        var trueElements: [Element] = []
        var falseElements: [Element] = []
        
        for element in self {
            if predicate(element) {
                trueElements.append(element)
            } else {
                falseElements.append(element)
            }
        }
        
        return (trueElements, falseElements)
    }
}
