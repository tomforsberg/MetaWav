// TrackReorderingManager.swift - Comprehensive track reordering system
import Foundation
import SwiftUI

class TrackReorderingManager: ObservableObject {
    static let shared = TrackReorderingManager()
    
    private init() {}
    
    // MARK: - Core Reordering Logic
    
    /// Reorder tracks within an album and update track numbers automatically
    func reorderTracks(
        in album: inout AlbumMetadata,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> Bool {
        print("🔄 Starting track reorder operation")
        print("   From indices: \(Array(source))")
        print("   To destination: \(destination)")
        
        // Group tracks by disc for proper handling
        let tracksByDisc = album.tracksByDisc()
        _ = album.sortedDiscNumbers()
        
        // Find which disc we're working with based on the drag operation
        guard let targetDisc = determineTargetDisc(
            from: source,
            to: destination,
            in: album
        ) else {
            print("❌ Could not determine target disc for reorder operation")
            return false
        }
        
        print("   Operating on disc \(targetDisc)")
        
        // Get tracks for the target disc only
        guard var discTracks = tracksByDisc[targetDisc] else {
            print("❌ No tracks found for disc \(targetDisc)")
            return false
        }
        
        // Sort tracks by current track number
        discTracks.sort { $0.trackNumber < $1.trackNumber }
        
        // Validate that the source indices are within bounds
        let validatedSource = IndexSet(source.filter { $0 < discTracks.count })
        guard !validatedSource.isEmpty else {
            print("❌ No valid source indices for reordering")
            return false
        }
        
        // Clamp destination to valid range
        let clampedDestination = min(max(destination, 0), discTracks.count)
        
        // Perform the reorder on the disc's tracks
        var reorderedTracks = discTracks
        let movedTracks = validatedSource.map { reorderedTracks[$0] }
        
        // Remove tracks from their current positions (reverse order to maintain indices)
        for index in validatedSource.sorted(by: >) {
            reorderedTracks.remove(at: index)
        }
        
        // Calculate adjusted destination after removals
        let adjustedDestination = clampedDestination - validatedSource.filter { $0 < clampedDestination }.count
        
        // Insert tracks at new position
        for (offset, track) in movedTracks.enumerated() {
            reorderedTracks.insert(track, at: adjustedDestination + offset)
        }
        
        // Update track numbers sequentially
        for (index, var track) in reorderedTracks.enumerated() {
            track.trackNumber = index + 1
            reorderedTracks[index] = track
        }
        
        // Replace the tracks in the album
        updateAlbumWithReorderedDiscTracks(
            album: &album,
            discNumber: targetDisc,
            newTracks: reorderedTracks
        )
        
        print("✅ Track reordering completed successfully")
        printTrackOrder(album: album, discNumber: targetDisc)
        
        return true
    }
    
    // MARK: - Manual Track Number Updates
    
    /// Update a specific track's position and reorder others accordingly
    func updateTrackPosition(
        trackId: UUID,
        newTrackNumber: Int? = nil,
        newDiscNumber: Int? = nil,
        in album: inout AlbumMetadata
    ) -> Bool {
        guard let trackIndex = album.tracks.firstIndex(where: { $0.id == trackId }) else {
            print("❌ Track not found for position update")
            return false
        }
        
        let originalTrack = album.tracks[trackIndex]
        let originalDiscNumber = originalTrack.discNumber
        let originalTrackNumber = originalTrack.trackNumber
        
        let targetDiscNumber = newDiscNumber ?? originalDiscNumber
        let targetTrackNumber = newTrackNumber ?? originalTrackNumber
        
        print("🎯 Updating track position:")
        print("   Track: \(originalTrack.name)")
        print("   From: Disc \(originalDiscNumber), Track \(originalTrackNumber)")
        print("   To: Disc \(targetDiscNumber), Track \(targetTrackNumber)")
        
        // If moving to a different disc
        if targetDiscNumber != originalDiscNumber {
            return moveTrackToNewDisc(
                trackId: trackId,
                fromDisc: originalDiscNumber,
                toDisc: targetDiscNumber,
                toTrackNumber: targetTrackNumber,
                in: &album
            )
        }
        
        // If staying on same disc but changing track number
        if targetTrackNumber != originalTrackNumber {
            return reorderTrackWithinDisc(
                trackId: trackId,
                newTrackNumber: targetTrackNumber,
                in: &album
            )
        }
        
        // No change needed
        return true
    }
    
    // MARK: - Conflict Resolution
    
    /// Check for and resolve track number conflicts
    func validateAndFixAlbum(_ album: inout AlbumMetadata) -> Bool {
        var wasFixed = false
        
        print("🔧 Validating album track numbering: \(album.albumName)")
        
        let tracksByDisc = album.tracksByDisc()
        
        for (discNumber, discTracks) in tracksByDisc {
            if hasTrackNumberConflicts(tracks: discTracks) {
                print("⚠️ Found conflicts in disc \(discNumber), fixing...")
                
                // Sort by track number and reassign sequentially
                let sortedTracks = discTracks.sorted { $0.trackNumber < $1.trackNumber }
                var fixedTracks = sortedTracks
                
                for (index, var track) in fixedTracks.enumerated() {
                    let newTrackNumber = index + 1
                    if track.trackNumber != newTrackNumber {
                        track.trackNumber = newTrackNumber
                        fixedTracks[index] = track
                        wasFixed = true
                    }
                }
                
                updateAlbumWithReorderedDiscTracks(
                    album: &album,
                    discNumber: discNumber,
                    newTracks: fixedTracks
                )
                
                print("✅ Fixed conflicts in disc \(discNumber)")
            }
        }
        
        return wasFixed
    }
    
    /// Check if tracks have numbering conflicts
    func hasTrackNumberConflicts(in album: AlbumMetadata) -> Bool {
        let tracksByDisc = album.tracksByDisc()
        
        for (_, discTracks) in tracksByDisc {
            if hasTrackNumberConflicts(tracks: discTracks) {
                return true
            }
        }
        
        return false
    }
    
    private func hasTrackNumberConflicts(tracks: [TrackMetadata]) -> Bool {
        let trackNumbers = tracks.map { $0.trackNumber }
        let uniqueNumbers = Set(trackNumbers)
        
        // Check for duplicates
        if trackNumbers.count != uniqueNumbers.count {
            return true
        }
        
        // Check for gaps (should be sequential 1, 2, 3, ...)
        let expectedNumbers = Set(1...tracks.count)
        if uniqueNumbers != expectedNumbers {
            return true
        }
        
        return false
    }
    
    // MARK: - Helper Methods
    
    private func determineTargetDisc(
        from source: IndexSet,
        to destination: Int,
        in album: AlbumMetadata
    ) -> Int? {
        // For now, assume all operations are within the same disc
        // This could be enhanced to support cross-disc moves
        
        guard let firstSourceIndex = source.first,
              firstSourceIndex < album.tracks.count else {
            return nil
        }
        
        // Get the disc of the first source track
        let sortedTracks = album.tracks.sorted { track1, track2 in
            if track1.discNumber != track2.discNumber {
                return track1.discNumber < track2.discNumber
            }
            return track1.trackNumber < track2.trackNumber
        }
        
        if firstSourceIndex < sortedTracks.count {
            return sortedTracks[firstSourceIndex].discNumber
        }
        
        return 1 // Default to disc 1
    }
    
    private func moveTrackToNewDisc(
        trackId: UUID,
        fromDisc: Int,
        toDisc: Int,
        toTrackNumber: Int,
        in album: inout AlbumMetadata
    ) -> Bool {
        print("🔄 Moving track between discs: \(fromDisc) → \(toDisc)")
        
        guard let trackIndex = album.tracks.firstIndex(where: { $0.id == trackId }) else {
            return false
        }
        
        var movingTrack = album.tracks[trackIndex]
        movingTrack.discNumber = toDisc
        movingTrack.trackNumber = toTrackNumber
        
        // Update the track in the album
        album.tracks[trackIndex] = movingTrack
        
        // Fix numbering on both source and destination discs
        resequenceDiscTracks(album: &album, discNumber: fromDisc)
        resequenceDiscTracks(album: &album, discNumber: toDisc)
        
        return true
    }
    
    private func reorderTrackWithinDisc(
        trackId: UUID,
        newTrackNumber: Int,
        in album: inout AlbumMetadata
    ) -> Bool {
        guard let trackIndex = album.tracks.firstIndex(where: { $0.id == trackId }) else {
            return false
        }
        
        let originalTrack = album.tracks[trackIndex]
        let discNumber = originalTrack.discNumber
        let originalTrackNumber = originalTrack.trackNumber
        
        // Get all tracks on this disc
        var discTracks = album.tracks.filter { $0.discNumber == discNumber }
        discTracks.sort { $0.trackNumber < $1.trackNumber }
        
        // Validate new track number
        let clampedTrackNumber = min(max(newTrackNumber, 1), discTracks.count)
        
        if originalTrackNumber == clampedTrackNumber {
            return true // No change needed
        }
        
        // Shift other tracks
        for i in 0..<discTracks.count {
            if discTracks[i].id == trackId {
                discTracks[i].trackNumber = clampedTrackNumber
            } else {
                let currentNumber = discTracks[i].trackNumber
                
                if originalTrackNumber < clampedTrackNumber {
                    // Moving down: shift tracks up
                    if currentNumber > originalTrackNumber && currentNumber <= clampedTrackNumber {
                        discTracks[i].trackNumber = currentNumber - 1
                    }
                } else {
                    // Moving up: shift tracks down
                    if currentNumber >= clampedTrackNumber && currentNumber < originalTrackNumber {
                        discTracks[i].trackNumber = currentNumber + 1
                    }
                }
            }
        }
        
        // Update album with reordered tracks
        updateAlbumWithReorderedDiscTracks(
            album: &album,
            discNumber: discNumber,
            newTracks: discTracks
        )
        
        return true
    }
    
    private func resequenceDiscTracks(album: inout AlbumMetadata, discNumber: Int) {
        let discTracks = album.tracks.filter { $0.discNumber == discNumber }
        let sortedTracks = discTracks.sorted { $0.trackNumber < $1.trackNumber }
        
        var resequencedTracks = sortedTracks
        for (index, var track) in resequencedTracks.enumerated() {
            track.trackNumber = index + 1
            resequencedTracks[index] = track
        }
        
        updateAlbumWithReorderedDiscTracks(
            album: &album,
            discNumber: discNumber,
            newTracks: resequencedTracks
        )
    }
    
    private func updateAlbumWithReorderedDiscTracks(
        album: inout AlbumMetadata,
        discNumber: Int,
        newTracks: [TrackMetadata]
    ) {
        // Remove all tracks from this disc
        album.tracks.removeAll { $0.discNumber == discNumber }
        
        // Add the reordered tracks
        album.tracks.append(contentsOf: newTracks)
        
        // Update album metadata
        album.updateTrackCount()
        album.updateDiscCount()
        album.calculateDuration()
    }
    
    private func printTrackOrder(album: AlbumMetadata, discNumber: Int) {
        let discTracks = album.tracks.filter { $0.discNumber == discNumber }
        let sortedTracks = discTracks.sorted { $0.trackNumber < $1.trackNumber }
        
        print("📋 Final track order for disc \(discNumber):")
        for track in sortedTracks {
            print("   \(track.trackNumber). \(track.name)")
        }
    }
    
    // MARK: - Batch Operations
    
    /// Reorder multiple albums at once
    func reorderMultipleAlbums(_ albums: inout [AlbumMetadata]) {
        var fixedCount = 0
        
        for i in 0..<albums.count {
            if validateAndFixAlbum(&albums[i]) {
                fixedCount += 1
            }
        }
        
        print("🔧 Batch reordering complete: \(fixedCount) albums fixed")
    }
    
    /// Get next available track number for a disc
    func getNextAvailableTrackNumber(forDisc discNumber: Int, in album: AlbumMetadata) -> Int {
        let discTracks = album.tracks.filter { $0.discNumber == discNumber }
        let maxTrackNumber = discTracks.map { $0.trackNumber }.max() ?? 0
        return maxTrackNumber + 1
    }
    
    /// Process imported tracks and assign proper numbering
    func processImportedTracks(_ newTracks: [TrackMetadata], into album: inout AlbumMetadata) {
        print("📦 Processing \(newTracks.count) imported tracks")
        
        // Group new tracks by disc
        let newTracksByDisc = Dictionary(grouping: newTracks) { $0.discNumber }
        
        for (discNumber, discNewTracks) in newTracksByDisc {
            let nextTrackNumber = getNextAvailableTrackNumber(forDisc: discNumber, in: album)
            
            var processedTracks = discNewTracks
            for (index, var track) in processedTracks.enumerated() {
                track.trackNumber = nextTrackNumber + index
                processedTracks[index] = track
            }
            
            album.tracks.append(contentsOf: processedTracks)
            print("✅ Added \(processedTracks.count) tracks to disc \(discNumber) starting at track \(nextTrackNumber)")
        }
        
        // Update album metadata
        album.updateTrackCount()
        album.updateDiscCount()
        album.calculateDuration()
    }
}

// MARK: - Notifications for UI Updates

extension Notification.Name {
    static let albumReordered = Notification.Name("albumReordered")
    static let tracksImported = Notification.Name("tracksImported")
}
