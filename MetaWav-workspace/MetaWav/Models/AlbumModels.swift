// AlbumModels.swift
import Foundation
import AVFoundation

// MARK: - Album-Level Metadata Structure
struct AlbumMetadata: Codable {
    var albumName: String
    var albumType: String? // Album type (Single, Album, EP, Mixtape, Compilation)
    var frontArtPath: String?
    var backArtPath: String?
    var duration: TimeInterval? // Total album duration
    var genre: String?
    var year: String?
    var trackCount: Int
    var discCount: Int // Number of discs in the album
    var discNames: [String: String]? = nil // Optional mapping from disc number (as string) to a custom name
    var tracks: [TrackMetadata]
    
    // Computed property for display
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Calculate total duration from tracks
    mutating func calculateDuration() {
        duration = tracks.compactMap { $0.duration }.reduce(0, +)
    }
    
    // Update track count
    mutating func updateTrackCount() {
        trackCount = tracks.count
    }
    
    // Update disc count based on tracks
    mutating func updateDiscCount() {
        let maxDiscNumber = tracks.map { $0.discNumber }.max() ?? 1
        discCount = maxDiscNumber
    }
    
    // Get tracks grouped by disc
    func tracksByDisc() -> [Int: [TrackMetadata]] {
        return Dictionary(grouping: tracks) { $0.discNumber }
    }
    
    // Get sorted disc numbers
    func sortedDiscNumbers() -> [Int] {
        return Array(Set(tracks.map { $0.discNumber })).sorted()
    }

    // MARK: - Disc Name Helpers
    func discName(for discNumber: Int) -> String? {
        guard let raw = discNames?[String(discNumber)]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    mutating func setDiscName(_ name: String?, for discNumber: Int) {
        let key = String(discNumber)
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var map = discNames ?? [:]
        if trimmed.isEmpty {
            map.removeValue(forKey: key)
        } else {
            map[key] = trimmed
        }
        discNames = map.isEmpty ? nil : map
    }
}

// MARK: - Album Type Options
struct AlbumTypes {
    static let options = [
        "Single",
        "Album",
        "EP",
        "Mixtape",
        "Compilation"
    ]
    
    static func displayName(for type: String?) -> String? {
        guard let type = type, !type.isEmpty else { return nil }
        return options.contains(type) ? type : type
    }
}
