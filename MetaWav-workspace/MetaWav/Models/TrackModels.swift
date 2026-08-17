// TrackModels.swift
import Foundation
import AVFoundation

// MARK: - Track Metadata
struct TrackMetadata: Codable, Identifiable {
    // FIXED: Computed property to prevent metadata recursion - only computed when accessed
    // This avoids triggering metadata generation during struct initialization
    var id: UUID {
        return filePath.persistentHash
    }
    var filePath: String
    var discNumber: Int // Which disc this track belongs to
    var trackNumber: Int // Track number within the disc
    var name: String
    var artist: String?
    var key: String?
    var bpm: Int?
    var version: String? // Track version (Demo, Mixed, Mastered, etc.)
    var isExplicit: Bool?
    var duration: TimeInterval?
    var format: String? // e.g., "WAV", "MP3"
    var channelCount: Int?
    var sampleRate: Double?
    var bitDepth: String?
    var bitrateKbps: Int?
    var isrc: String? // ISRC (International Standard Recording Code)
    var credits: [Credit]?
    var lyrics: [LyricLine]?
    var notes: String? // General notes field
    var relatedFiles: [RelatedFile]? // Related files for organization
    
    // MARK: - Nested Credit Structure
    struct Credit: Codable, Identifiable {
        // FIXED: Computed property to prevent metadata recursion - only computed when accessed
        var id: UUID {
            return "\(role)|\(name)".persistentHash
        }
        var role: String
        var name: String
        
        init(role: String, name: String) {
            self.role = role
            self.name = name
            // id is computed property, will be generated when accessed
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(String.self, forKey: .role)
            name = try container.decode(String.self, forKey: .name)
            // id is computed property, will be generated when accessed
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(name, forKey: .name)
        }
        
        enum CodingKeys: String, CodingKey {
            case role, name
        }
    }
    
    // MARK: - Nested Lyric Line Structure
    struct LyricLine: Codable, Identifiable {
        let time: TimeInterval
        var text: String
        var id: TimeInterval { time }
    }
    
        // MARK: - Nested Related File Structure
    struct RelatedFile: Codable, Identifiable {
        // FIXED: Computed property to prevent metadata recursion - only computed when accessed
        var id: UUID {
            return filePath.persistentHash
        }
        var filePath: String
        var displayName: String? // Optional custom name
        var fileType: FileType
        
        init(filePath: String, displayName: String? = nil, fileType: FileType) {
            self.filePath = filePath
            self.displayName = displayName
            self.fileType = fileType
            // id is computed property, will be generated when accessed
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filePath = try container.decode(String.self, forKey: .filePath)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            fileType = try container.decode(FileType.self, forKey: .fileType)
            // id is computed property, will be generated when accessed
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(filePath, forKey: .filePath)
            try container.encodeIfPresent(displayName, forKey: .displayName)
            try container.encode(fileType, forKey: .fileType)
        }
        
        // Computed properties
        var fileName: String {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        
        var fileNameWithoutExtension: String {
            return URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        }
        
        var actualDisplayName: String {
            return displayName ?? fileNameWithoutExtension
        }
        
        var fileExists: Bool {
            return FileManager.default.fileExists(atPath: filePath)
        }
        
        // Exclude id from CodingKeys (like Credit does)
        enum CodingKeys: String, CodingKey {
            case filePath, displayName, fileType
        }
        
        // MARK: - Enhanced FileType enum
        enum FileType: String, CaseIterable {
            case dawProject = "DAW Project"
            case audio = "Audio"
            case video = "Video"
            case image = "Image"
            case document = "Document"
            case archive = "Archive"
            case folder = "Folder"
            case other = "Other"

            // Detect file type from extension
            static func detect(from filePath: String) -> FileType {
                let url = URL(fileURLWithPath: filePath)
                let ext = url.pathExtension.lowercased()

                // If there's no extension, check if this is a folder on disk
                if ext.isEmpty {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                       isDir.boolValue {
                        return .folder
                    }
                }
                
                switch ext {
                // DAW Projects
                case "logicx", "logic", "logicxtemplatesproject":
                    return .dawProject
                // Pro Tools
                case "ptf", "ptx", "pts", "ptl", "ptt":
                    return .dawProject
                // Ableton Live
                case "als", "alc", "adg", "adv":
                    return .dawProject
                // Cubase/Nuendo
                case "cpr", "npr", "bak", "steinberg-project":
                    return .dawProject
                // Studio One
                case "song", "presetpackage":
                    return .dawProject
                // Reaper
                case "rpp", "rpp-bak", "reapeaks":
                    return .dawProject
                // FL Studio
                case "flp", "flm":
                    return .dawProject
                // Reason
                case "reason", "rns", "rex":
                    return .dawProject
                // Digital Performer
                case "motu":
                    return .dawProject
                // Bitwig Studio
                case "bwproject":
                    return .dawProject
                // Mixcraft
                case "mx6", "mx7", "mx8", "mx9":
                    return .dawProject
                // Samplitude/Sequoia
                case "vip":
                    return .dawProject
                // Ardour
                case "ardour":
                    return .dawProject
                // GarageBand
                case "band":
                    return .dawProject
                // Tracktion Waveform
                case "tracktionedit":
                    return .dawProject
                // Hindenburg Pro
                case "nhsx":
                    return .dawProject
                // Adobe Audition
                case "sesx", "ses":
                    return .dawProject
                // Audacity
                case "aup", "aup3":
                    return .dawProject
                    
                // Audio Files
                case "wav", "aiff", "aif", "flac", "mp3", "aac", "m4a", "ogg", "wma":
                    return .audio
                case "caf", "au", "snd", "sd2", "mp2", "opus", "amr":
                    return .audio
                // Audio stems and specialized formats
                case "stem", "rx2", "acid", "syx", "mid", "midi":
                    return .audio
                    
                // Video Files
                case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v":
                    return .video
                case "mpg", "mpeg", "m2v", "3gp", "3g2", "asf", "rm", "rmvb":
                    return .video
                case "vob", "ts", "mts", "m2ts", "mxf", "dv", "divx", "xvid":
                    return .video
                // Professional video formats
                case "prores", "dnxhd", "dnxhr", "avchd", "r3d", "braw":
                    return .video
                    
                // Image Files
                case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp":
                    return .image
                case "psd", "ai", "eps", "svg", "ico", "icns", "raw", "cr2", "nef":
                    return .image
                case "dng", "arw", "orf", "rw2", "pef", "srw", "raf", "3fr":
                    return .image
                // Design files
                case "sketch", "fig", "xd", "indd":
                    return .image
                    
                // Document Files
                case "txt", "rtf", "doc", "docx", "pages", "odt":
                    return .document
                case "pdf", "xls", "xlsx", "numbers", "ods", "ppt", "pptx", "key", "odp":
                    return .document
                case "md", "markdown", "tex", "latex", "html", "htm", "xml", "json":
                    return .document
                // Lyrics and music-specific documents
                case "lrc", "srt", "vtt", "kar", "cdg", "musicxml", "mxl":
                    return .document
                    
                // Archive Files
                case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso":
                    return .archive
                case "pkg", "deb", "rpm", "msi", "exe", "app", "sit", "sitx":
                    return .archive
                case "lzh", "ace", "cab", "lz", "lzma", "z", "tgz", "tbz2":
                    return .archive
                    
                default:
                    return .other
                }
            }
            
            // Icon for file type
            var icon: String {
                switch self {
                case .dawProject: return "music.mic"
                case .audio: return "waveform"
                case .video: return "video.fill"
                case .image: return "photo.fill"
                case .document: return "doc.text.fill"
                case .archive: return "archivebox.fill"
                case .folder: return "folder.fill"
                case .other: return "doc.questionmark"
                }
            }
            
            // Color for file type
            var color: String {
                switch self {
                case .dawProject: return "systemPurple"
                case .audio: return "systemBlue"
                case .video: return "systemRed"
                case .image: return "systemGreen"
                case .document: return "systemOrange"
                case .archive: return "systemYellow"
                case .folder: return "systemTeal"
                case .other: return "systemGray"
                }
            }
            
            // Helper computed property for UI sorting/grouping
            var sortOrder: Int {
                switch self {
                case .dawProject: return 0
                case .audio: return 1
                case .video: return 2
                case .image: return 3
                case .document: return 4
                case .archive: return 5
                case .folder: return 6
                case .other: return 7
                }
            }
            
            // Description for tooltips/help
            var description: String {
                switch self {
                case .dawProject: return "Digital Audio Workstation project files"
                case .audio: return "Audio files, stems, samples, and MIDI"
                case .video: return "Video files, music videos, behind-the-scenes"
                case .image: return "Images, artwork, photos, and design files"
                case .document: return "Text documents, lyrics, contracts, and notes"
                case .archive: return "Compressed archives and installers"
                case .folder: return "Folders containing related project assets, stems, or documents"
                case .other: return "Other file types"
                }
            }
            
            // Common file extensions for this type (for UI hints)
            var commonExtensions: [String] {
                switch self {
                case .dawProject:
                    return ["logicx", "als", "cpr", "rpp", "flp", "ptf", "song"]
                case .audio:
                    return ["wav", "aiff", "mp3", "flac", "m4a", "mid", "midi"]
                case .video:
                    return ["mp4", "mov", "avi", "mkv", "wmv"]
                case .image:
                    return ["jpg", "png", "psd", "ai", "tiff", "raw"]
                case .document:
                    return ["txt", "pdf", "doc", "pages", "lrc", "md"]
                case .archive:
                    return ["zip", "rar", "7z", "dmg", "iso"]
                case .folder:
                    return []
                case .other:
                    return []
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    // Computed property for full track identifier
    var fullTrackIdentifier: String {
        return "\(discNumber).\(String(format: "%02d", trackNumber))"
    }
    
    // Computed property for stable track ID (used for play counts)
    var stableTrackId: String {
        return filePath
    }
    
    // Computed property for display in tracklist
    var discTrackDisplay: String {
        if discNumber > 1 {
            return "D\(discNumber):\(String(format: "%02d", trackNumber))"
        } else {
            return String(format: "%02d", trackNumber)
        }
    }
    
    // Computed properties
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var fileName: String {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    // Memberwise initializer - id is computed property, no need to initialize
    init(
        filePath: String,
        discNumber: Int,
        trackNumber: Int,
        name: String,
        artist: String? = nil,
        key: String? = nil,
        bpm: Int? = nil,
        version: String? = nil,
        isExplicit: Bool? = nil,
        duration: TimeInterval? = nil,
        format: String? = nil,
        channelCount: Int? = nil,
        sampleRate: Double? = nil,
        bitDepth: String? = nil,
        bitrateKbps: Int? = nil,
        isrc: String? = nil,
        credits: [Credit]? = nil,
        lyrics: [LyricLine]? = nil,
        notes: String? = nil,
        relatedFiles: [RelatedFile]? = nil
    ) {
        self.filePath = filePath
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.name = name
        self.artist = artist
        self.key = key
        self.bpm = bpm
        self.version = version
        self.isExplicit = isExplicit
        self.duration = duration
        self.format = format
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.bitrateKbps = bitrateKbps
        self.isrc = isrc
        self.credits = credits
        self.lyrics = lyrics
        self.notes = notes
        self.relatedFiles = relatedFiles
    }
    
    // Custom Codable implementation - id is computed, no need to decode it
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filePath = try container.decode(String.self, forKey: .filePath)
        // id is computed property, will be generated from filePath when accessed
        discNumber = try container.decode(Int.self, forKey: .discNumber)
        trackNumber = try container.decode(Int.self, forKey: .trackNumber)
        name = try container.decode(String.self, forKey: .name)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        bpm = try container.decodeIfPresent(Int.self, forKey: .bpm)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount)
        sampleRate = try container.decodeIfPresent(Double.self, forKey: .sampleRate)
        bitDepth = try container.decodeIfPresent(String.self, forKey: .bitDepth)
        bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps)
        isrc = try container.decodeIfPresent(String.self, forKey: .isrc)
        credits = try container.decodeIfPresent([Credit].self, forKey: .credits)
        lyrics = try container.decodeIfPresent([LyricLine].self, forKey: .lyrics)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        relatedFiles = try container.decodeIfPresent([RelatedFile].self, forKey: .relatedFiles)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(discNumber, forKey: .discNumber)
        try container.encode(trackNumber, forKey: .trackNumber)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(bpm, forKey: .bpm)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(isExplicit, forKey: .isExplicit)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(channelCount, forKey: .channelCount)
        try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
        try container.encodeIfPresent(bitDepth, forKey: .bitDepth)
        try container.encodeIfPresent(bitrateKbps, forKey: .bitrateKbps)
        try container.encodeIfPresent(isrc, forKey: .isrc)
        try container.encodeIfPresent(credits, forKey: .credits)
        try container.encodeIfPresent(lyrics, forKey: .lyrics)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(relatedFiles, forKey: .relatedFiles)
    }
    
    enum CodingKeys: String, CodingKey {
        case filePath, discNumber, trackNumber, name, artist, key, bpm, version, isExplicit
        case duration, format, channelCount, sampleRate, bitDepth, bitrateKbps, isrc, credits, lyrics, notes, relatedFiles
    }
}
