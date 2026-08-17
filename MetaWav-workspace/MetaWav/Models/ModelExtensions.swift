// ModelExtensions.swift
import Foundation

// MARK: - Bottom Panel View Types
enum BottomPanelViewType {
    case lyrics, metadata, amp, queue
}

// MARK: - Stable Hash Extension for Preventing Metadata Recursion
extension String {
    /// Generates a stable UUID from string content to prevent infinite metadata recursion
    /// Uses ONLY primitive operations - NO arrays, NO strings, NO generic types
    /// This prevents triggering metadata generation during Codable decoding
    var persistentHash: UUID {
        // Use djb2 hash - primitive operations only
        var hash1: UInt64 = 5381
        var hash2: UInt64 = 2166136261
        var hash3: UInt64 = 0
        
        // Single pass through UTF-8 bytes - no array creation
        let utf8View = self.utf8
        var byteCount = 0
        for byte in utf8View {
            hash1 = ((hash1 << 5) &+ hash1) &+ UInt64(byte)
            hash2 = (hash2 ^ UInt64(byte)) &* 16777619
            hash3 = hash3 &+ UInt64(byte) &* UInt64(byteCount + 1)
            byteCount += 1
        }
        
        // Combine hashes into 16 bytes using bit operations only
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
            UInt8(truncatingIfNeeded: hash1 >> 56),
            UInt8(truncatingIfNeeded: hash1 >> 48),
            UInt8(truncatingIfNeeded: hash1 >> 40),
            UInt8(truncatingIfNeeded: hash1 >> 32),
            UInt8(truncatingIfNeeded: hash1 >> 24),
            UInt8(truncatingIfNeeded: hash1 >> 16),
            UInt8(truncatingIfNeeded: hash1 >> 8),
            UInt8(truncatingIfNeeded: hash1),
            UInt8(truncatingIfNeeded: hash2 >> 56),
            UInt8(truncatingIfNeeded: hash2 >> 48),
            UInt8(truncatingIfNeeded: hash2 >> 40),
            UInt8(truncatingIfNeeded: hash2 >> 32),
            UInt8(truncatingIfNeeded: hash3 >> 24),
            UInt8(truncatingIfNeeded: hash3 >> 16),
            UInt8(truncatingIfNeeded: hash3 >> 8),
            UInt8(truncatingIfNeeded: hash3)
        )
        
        // Set version (4) and variant bits
        bytes.6 = (bytes.6 & 0x0F) | 0x40 // Version 4
        bytes.8 = (bytes.8 & 0x3F) | 0x80 // Variant 10
        
        // Create UUID directly from tuple - NO string operations, NO array allocations
        return UUID(uuid: bytes)
    }
}

// MARK: - Custom Codable Implementation for FileType
extension TrackMetadata.RelatedFile.FileType: Codable {
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        
        // Try exact match first
        if let fileType = TrackMetadata.RelatedFile.FileType(rawValue: stringValue) {
            self = fileType
            return
        }
        
        // Try case-insensitive match
        if let fileType = TrackMetadata.RelatedFile.FileType.allCases.first(where: { $0.rawValue.lowercased() == stringValue.lowercased() }) {
            self = fileType
            return
        }
        
        // Legacy mapping for old values
        switch stringValue.lowercased() {
        case "daw project", "dawproject":
            self = .dawProject
            return
        case "other file", "unknown":
            self = .other
            return
        default:
            break
        }
        
        // If we can't decode it, log the issue and default to .other
        print("⚠️ Could not decode FileType from '\(stringValue)', defaulting to .other")
        print("   Available values: \(TrackMetadata.RelatedFile.FileType.allCases.map { $0.rawValue }.joined(separator: ", "))")
        
        self = .other
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

// MARK: - Equatable Conformance
extension AlbumMetadata: Equatable {
    static func == (lhs: AlbumMetadata, rhs: AlbumMetadata) -> Bool {
        // Compare by albumName only to avoid deep array comparisons that trigger metadata generation
        // This prevents infinite recursion during type metadata generation
        return lhs.albumName == rhs.albumName
    }
}

extension TrackMetadata: Equatable {
    static func == (lhs: TrackMetadata, rhs: TrackMetadata) -> Bool {
        // Compare by filePath only to avoid deep nested array comparisons that trigger metadata generation
        // This prevents infinite recursion during type metadata generation
        return lhs.filePath == rhs.filePath
    }
}

extension TrackMetadata.Credit: Equatable {
    static func == (lhs: TrackMetadata.Credit, rhs: TrackMetadata.Credit) -> Bool {
        return lhs.role == rhs.role && lhs.name == rhs.name
    }
}

extension TrackMetadata.LyricLine: Equatable {
    static func == (lhs: TrackMetadata.LyricLine, rhs: TrackMetadata.LyricLine) -> Bool {
        return lhs.time == rhs.time && lhs.text == rhs.text
    }
}

extension TrackMetadata.RelatedFile: Equatable {
    static func == (lhs: TrackMetadata.RelatedFile, rhs: TrackMetadata.RelatedFile) -> Bool {
        return lhs.filePath == rhs.filePath &&
               lhs.displayName == rhs.displayName &&
               lhs.fileType == rhs.fileType
    }
}
