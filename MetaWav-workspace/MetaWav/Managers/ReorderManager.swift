// ReorderManager.swift - Centralized album and playlist reordering
import Foundation
import SwiftUI

class ReorderManager: ObservableObject {
    static let shared = ReorderManager()

    private init() {}

    // MARK: - Album Reordering

    /// Reorder tracks within an album (disc-aware), resequence track numbers, and persist.
    /// - Returns: The updated album on success, otherwise nil.
    @discardableResult
    func reorderAlbum(
        album: AlbumMetadata,
        discNumber: Int,
        fromIndex: Int,
        toIndex: Int
    ) -> AlbumMetadata? {
        var mutableAlbum = album

        // Get tracks for the specified disc, sorted by current track number
        var discTracks = mutableAlbum.tracks
            .filter { $0.discNumber == discNumber }
            .sorted { $0.trackNumber < $1.trackNumber }

        // Validate indices
        guard fromIndex >= 0, fromIndex < discTracks.count else { return nil }
        let clampedTo = max(0, min(toIndex, discTracks.count))

        // Remove and insert at new position (adjust destination when moving down)
        let movingTrack = discTracks.remove(at: fromIndex)
        let adjustedDestination = clampedTo > fromIndex ? clampedTo - 1 : clampedTo
        discTracks.insert(movingTrack, at: adjustedDestination)

        // Resequence track numbers starting from 1
        for (i, var track) in discTracks.enumerated() {
            track.trackNumber = i + 1
            discTracks[i] = track
        }

        // Replace disc tracks in the album
        mutableAlbum.tracks.removeAll { $0.discNumber == discNumber }
        mutableAlbum.tracks.append(contentsOf: discTracks)

        // Recompute derived fields
        mutableAlbum.updateTrackCount()
        mutableAlbum.updateDiscCount()
        mutableAlbum.calculateDuration()

        // Validate file paths (non-fatal)
        _ = validateFilePaths(for: mutableAlbum)

        do {
            try AlbumMetadataManager.shared.saveAlbumMetadata(mutableAlbum)
            return mutableAlbum
        } catch {
            print("❌ Failed to persist reordered album: \(error)")
            return nil
        }
    }

    /// Move a track across discs, resequence both source and destination discs, and persist.
    @discardableResult
    func moveTrackAcrossDiscs(
        album: AlbumMetadata,
        trackId: UUID,
        fromDisc: Int,
        toDisc: Int,
        toTrackIndex: Int
    ) -> AlbumMetadata? {
        var mutableAlbum = album

        // Extract source and destination disc tracks
        var sourceTracks = mutableAlbum.tracks
            .filter { $0.discNumber == fromDisc }
            .sorted { $0.trackNumber < $1.trackNumber }
        var destTracks = mutableAlbum.tracks
            .filter { $0.discNumber == toDisc }
            .sorted { $0.trackNumber < $1.trackNumber }

        // Find and remove the moving track from source
        guard let sourceIdx = sourceTracks.firstIndex(where: { $0.id == trackId }) else { return nil }
        var moving = sourceTracks.remove(at: sourceIdx)
        moving.discNumber = toDisc

        // Insert into destination at target index (clamped)
        let clampedDest = max(0, min(toTrackIndex, destTracks.count))
        destTracks.insert(moving, at: clampedDest)

        // Resequence both discs starting at 1
        for (i, var t) in sourceTracks.enumerated() { t.trackNumber = i + 1; sourceTracks[i] = t }
        for (i, var t) in destTracks.enumerated() { t.trackNumber = i + 1; destTracks[i] = t }

        // Rebuild album tracks: remove both discs and append updated arrays
        mutableAlbum.tracks.removeAll { $0.discNumber == fromDisc || $0.discNumber == toDisc }
        mutableAlbum.tracks.append(contentsOf: sourceTracks)
        mutableAlbum.tracks.append(contentsOf: destTracks)

        // Derived fields and persist
        mutableAlbum.updateTrackCount()
        mutableAlbum.updateDiscCount()
        mutableAlbum.calculateDuration()

        do {
            try AlbumMetadataManager.shared.saveAlbumMetadata(mutableAlbum)
            return mutableAlbum
        } catch {
            print("❌ Failed to persist cross-disc move: \(error)")
            return nil
        }
    }

    // MARK: - Playlist Reordering

    /// Reorder tracks inside a playlist and persist.
    /// - Returns: The updated playlist on success, otherwise nil.
    @MainActor @discardableResult
    func reorderPlaylist(
        playlistName: String,
        fromIndex: Int,
        toIndex: Int
    ) -> PlaylistMetadata? {
        do {
            try PlaylistManager.shared.reorderPlaylistTracks(in: playlistName, from: fromIndex, to: toIndex)
            return PlaylistManager.shared.getPlaylist(named: playlistName)
        } catch {
            print("❌ Failed to reorder playlist '\(playlistName)': \(error)")
            return nil
        }
    }

    // MARK: - Utilities

    /// Validate that all track file paths exist. Returns missing file paths (if any).
    private func validateFilePaths(for album: AlbumMetadata) -> [String] {
        var missing: [String] = []
        for track in album.tracks {
            if !FileManager.default.fileExists(atPath: track.filePath) {
                missing.append(track.filePath)
            }
        }
        if !missing.isEmpty {
            print("⚠️ Missing track files for album '\(album.albumName)': \(missing.count)")
        }
        return missing
    }
}


