import Foundation

/// Controls what the CD-deck Timecode panel displays.
/// This is intentionally **not** persisted; it should default to `.standard` on app launch and power-on.
enum TimecodePanelMode: String, CaseIterable {
    case standard
    case audio
    case device
    case advanced
}





