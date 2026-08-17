// QueueIntegrationHelper.swift - Helper to integrate queue system with existing functionality
import Foundation
import AVFoundation
import SwiftUI

extension QueueManager {
    
    /// Load album into queue using existing album loading logic
    func loadAlbumIntoQueue(_ album: AlbumMetadata, startAt track: TrackMetadata? = nil) {
        print("📀 Loading album into queue: \(album.albumName)")
        
        // Clear existing queue
        clearQueue()
        
        // Sort tracks by disc and track number
        let sortedTracks = album.tracks.sorted { track1, track2 in
            if track1.discNumber != track2.discNumber {
                return track1.discNumber < track2.discNumber
            }
            return track1.trackNumber < track2.trackNumber
        }
        
        // Add all tracks to queue
        for track in sortedTracks {
            addToQueue(track, from: album)
        }
        
        // Set current track
        if let startTrack = track {
            if let index = queue.firstIndex(where: { $0.track?.filePath == startTrack.filePath }) {
                currentIndex = index
            } else {
                currentIndex = 0
            }
        } else {
            currentIndex = 0
        }
        
        print("✅ Album loaded: \(album.albumName) with \(sortedTracks.count) tracks")
    }
    
    /// Add single track to queue and play it
    func playSingleTrack(_ track: TrackMetadata, from album: AlbumMetadata) {
        print("🎵 Playing single track: \(track.name)")
        
        // Check if track is already in queue
        if let existingIndex = queue.firstIndex(where: { $0.track?.filePath == track.filePath }) {
            currentIndex = existingIndex
            playCurrentTrack()
            return
        }
        
        // Add to queue and play
        addToQueue(track, from: album)
        currentIndex = queue.count - 1
        playCurrentTrack()
    }
    
    /// Add album to queue without clearing existing queue
    func addAlbumToExistingQueue(_ album: AlbumMetadata) {
        print("📀 Adding album to existing queue: \(album.albumName)")
        
        // Sort tracks by disc and track number
        let sortedTracks = album.tracks.sorted { track1, track2 in
            if track1.discNumber != track2.discNumber {
                return track1.discNumber < track2.discNumber
            }
            return track1.trackNumber < track2.trackNumber
        }
        
        // Add all tracks to queue
        for track in sortedTracks {
            addToQueue(track, from: album)
        }
        
        print("✅ Album added to queue: \(album.albumName) with \(sortedTracks.count) tracks")
    }
    
    /// Sync with existing audioFiles array (for backward compatibility)
    func syncWithAudioFiles(_ audioFiles: [AVAudioFile], currentIndex: Int?, album: AlbumMetadata?) {
        print("🔄 Syncing queue with existing audioFiles array")
        
        // Clear current queue
        clearQueue()
        
        // Add all audio files to queue
        for audioFile in audioFiles {
            let track = album?.tracks.first { $0.filePath == audioFile.url.path }
            let item = QueueItem(audioFile: audioFile, track: track, album: album)
            queue.append(item)
        }
        
        // Set current index
        if let index = currentIndex, index < queue.count {
            self.currentIndex = index
        }
        
        print("✅ Queue synced with \(audioFiles.count) audio files")
    }
    
    /// Get audioFiles array for backward compatibility
    func getAudioFilesArray() -> [AVAudioFile] {
        return queue.map { $0.audioFile }
    }
    
    /// Get current file index for backward compatibility
    func getCurrentFileIndex() -> Int? {
        return currentIndex
    }
}

// MARK: - Library Panel Integration

extension QueueManager {
    
    /// Handle track selection from library
    func handleTrackSelection(_ track: TrackMetadata, from album: AlbumMetadata, playImmediately: Bool = true) {
        print("🎯 Track selected: \(track.name)")
        
        if playImmediately {
            // Play entire album starting from the selected track
            playAlbumFromTrack(track, from: album)
        } else {
            // Just add to queue
            addToQueue(track, from: album)
        }
    }
    
    /// Handle album selection from library
    func handleAlbumSelection(_ album: AlbumMetadata, startAt track: TrackMetadata? = nil, playImmediately: Bool = true) {
        print("🎯 Album selected: \(album.albumName)")
        
        if playImmediately {
            loadAlbumIntoQueue(album, startAt: track)
            playCurrentTrack()
        } else {
            addAlbumToExistingQueue(album)
        }
    }
    
    /// Handle playlist selection from library
    func handlePlaylistSelection(_ tracks: [TrackMetadata], from album: AlbumMetadata, playImmediately: Bool = true) {
        print("🎯 Playlist selected with \(tracks.count) tracks")
        
        if playImmediately {
            clearQueue()
            addToQueue(tracks, from: album)
            currentIndex = 0
            playCurrentTrack()
        } else {
            addToQueue(tracks, from: album)
        }
    }
}

// MARK: - ContentView Integration

extension QueueManager {
    
    /// Update bindings for backward compatibility
    func updateBindings(audioFiles: Binding<[AVAudioFile]>, currentFileIndex: Binding<Int?>) {
        // Update audioFiles binding
        audioFiles.wrappedValue = getAudioFilesArray()
        
        // Update currentFileIndex binding
        currentFileIndex.wrappedValue = getCurrentFileIndex()
    }
    
    /// Sync from bindings (for when external changes occur)
    func syncFromBindings(audioFiles: [AVAudioFile], currentFileIndex: Int?, album: AlbumMetadata?) {
        // Only sync if the arrays are different to avoid infinite loops
        let currentAudioFiles = getAudioFilesArray()
        if currentAudioFiles.count != audioFiles.count || 
           !zip(currentAudioFiles, audioFiles).allSatisfy({ $0.url == $1.url }) {
            syncWithAudioFiles(audioFiles, currentIndex: currentFileIndex, album: album)
        }
    }
}
