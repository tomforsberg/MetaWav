import SwiftUI

// Centralized styling helpers for track rows across Album, Artist, Playlist, and All Tracks views
enum TrackRowStyle {
    static let accent = Color(red: 0, green: 0.75, blue: 0.39)

    static func numberColor(isSelected: Bool, isPlaying: Bool) -> Color {
        if isPlaying { return accent }
        return .white
    }

    static func titleColor(isSelected: Bool, isPlaying: Bool) -> Color {
        if isPlaying { return accent }
        return .white
    }

    static func secondaryTextColor() -> Color {
        return Color(white: 0.6)
    }

    static func tertiaryTextColor() -> Color {
        return Color(white: 0.5)
    }
}

struct PlayingBars: View {
    var body: some View {
        PlayingVisualizer()
            .frame(width: 24, height: 10)
    }
}


