// AudioFormatClassifier.swift
import Foundation

enum AudioFormatClass {
    case lossy
    case losslessOrUncompressed
    case unknown
}

struct AudioFormatClassifier {
    static func classify(formatString: String?, pathExtension: String?) -> AudioFormatClass {
        let fmt = formatString?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let ext = pathExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Prefer explicit format names if provided
        if let f = fmt {
            if lossyFormats.contains(f) { return .lossy }
            if losslessFormats.contains(f) { return .losslessOrUncompressed }
            // Special case: M4A is typically AAC (lossy) - treat as lossy by default
            if f == "M4A" { return .lossy }
        }

        if let e = ext {
            if lossyExtensions.contains(e) { return .lossy }
            if losslessExtensions.contains(e) { return .losslessOrUncompressed }
        }

        return .unknown
    }

    private static let lossyFormats: Set<String> = [
        "MP3", "AAC", "OGG", "WMA", "OPUS", "AMR", "MP2"
    ]

    private static let losslessFormats: Set<String> = [
        "WAV", "AIFF", "AIF", "FLAC", "ALAC", "PCM", "APE", "CAF"
    ]

    private static let lossyExtensions: Set<String> = [
        "mp3", "aac", "ogg", "opus", "wma", "amr", "mp2", "m4a" // m4a typically AAC (lossy)
    ]

    private static let losslessExtensions: Set<String> = [
        "wav", "aiff", "aif", "flac", "alac", "pcm", "ape", "caf"
    ]
}

extension TrackMetadata {
    var fileExtensionLowercased: String {
        return URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }

    var audioFormatClass: AudioFormatClass {
        return AudioFormatClassifier.classify(formatString: format, pathExtension: fileExtensionLowercased)
    }

    var displayFormatFallback: String {
        if let f = format, !f.isEmpty { return f }
        let ext = URL(fileURLWithPath: filePath).pathExtension.uppercased()
        return ext.isEmpty ? "?" : ext
    }
}


