// LRCParser.swift
// Parses .lrc lyric files into timestamped lyric lines for TrackMetadata

import Foundation

/// Utility to parse LRC files into `TrackMetadata.LyricLine` arrays.
/// Supports multiple timestamps per line and fractional seconds up to millisecond precision.
final class LRCParser {
    static let shared = LRCParser()

    private init() {}

    /// Parse an LRC file at the given URL.
    /// - Returns: Sorted array of lyric lines by time.
    func parse(url: URL) throws -> [TrackMetadata.LyricLine] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw NSError(domain: "LRCParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported LRC file encoding"])
        }
        return parse(text: content)
    }

    /// Parse LRC text content.
    func parse(text: String) -> [TrackMetadata.LyricLine] {
        var lines: [TrackMetadata.LyricLine] = []

        // Regex patterns
        // Time tags like [mm:ss], [mm:ss.xx], [mm:ss.xxx]
        let timeTagPattern = #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]"#
        // Metadata tags like [ar:artist], [ti:title], [al:album]
        let metaTagPattern = #"\[(ar|ti|al|by|offset|re|ve):[^\]]*\]"#

        let timeRegex = try? NSRegularExpression(pattern: timeTagPattern, options: [])
        let metaRegex = try? NSRegularExpression(pattern: metaTagPattern, options: [.caseInsensitive])

        text.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }

            // Skip pure metadata lines
            if let metaRegex = metaRegex,
               metaRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count))?.range.location == 0,
               metaRegex.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) == 1,
               (timeRegex?.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) ?? 0) == 0 {
                return
            }

            guard let timeRegex = timeRegex else { return }
            let fullRange = NSRange(location: 0, length: line.utf16.count)
            let matches = timeRegex.matches(in: line, options: [], range: fullRange)
            guard !matches.isEmpty else { return }

            // Remove all time tags to get the lyric text
            let lyricText: String = {
                var mutable = line
                for m in matches.reversed() { // remove from end to keep indices valid
                    if let r = Range(m.range, in: mutable) {
                        mutable.removeSubrange(r)
                    }
                }
                return mutable.trimmingCharacters(in: .whitespacesAndNewlines)
            }()

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let mmRange = match.range(at: 1)
                let ssRange = match.range(at: 2)
                let ffRange = match.range(at: 3)

                if let mm = self.timeComponent(from: line, range: mmRange),
                   let ss = self.timeComponent(from: line, range: ssRange) {
                    let fraction = self.fractionComponent(from: line, range: ffRange)
                    let totalSeconds = Double(mm * 60 + ss) + fraction
                    let textOut = lyricText
                    guard !textOut.isEmpty else { continue }
                    lines.append(TrackMetadata.LyricLine(time: totalSeconds, text: textOut))
                }
            }
        }

        // Sort and deduplicate any identical time/text pairs
        lines.sort { $0.time < $1.time }
        var unique: [TrackMetadata.LyricLine] = []
        var seen: Set<String> = []
        for l in lines {
            let key = String(format: "%.3f\u{1f}|%@", l.time, l.text)
            if !seen.contains(key) {
                unique.append(l)
                seen.insert(key)
            }
        }
        return unique
    }

    private func timeComponent(from line: String, range: NSRange) -> Int? {
        guard let r = Range(range, in: line) else { return nil }
        return Int(line[r])
    }

    private func fractionComponent(from line: String, range: NSRange) -> Double {
        guard range.location != NSNotFound, let r = Range(range, in: line) else { return 0 }
        let s = String(line[r])
        // If 2 digits, treat as centiseconds; if 3, milliseconds; else fractional seconds directly
        if s.count == 2, let cs = Int(s) { return Double(cs) / 100.0 }
        if s.count == 3, let ms = Int(s) { return Double(ms) / 1000.0 }
        return Double("0." + s) ?? 0
    }
}


