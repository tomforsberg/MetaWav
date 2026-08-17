import SwiftUI
import AppKit

struct MetaWavCommands: Commands {
    var body: some Commands {
        // App Menu customizations
        CommandGroup(replacing: .appInfo) {
            Button("About MetaWav") { MenuBarManager.shared.showAbout() }
        }
        // Settings (Preferences)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { MenuBarManager.shared.showSettings() }
                .keyboardShortcut(",", modifiers: [.command])
        }

        // File Menu
        CommandGroup(after: .newItem) {
            Button("Load Files…") { MenuBarManager.shared.loadFiles() }
                .keyboardShortcut("o", modifiers: [.command])
            Divider()
            Button("Refresh Library") { MenuBarManager.shared.refreshLibrary() }
                .keyboardShortcut("r", modifiers: [.command])
            Button("Rescan Library from Path…") { MenuBarManager.shared.rescanLibraryFromPath() }
                .keyboardShortcut("R", modifiers: [.command, .option])
            Divider()
            Button("Show Metadata Path") { MenuBarManager.shared.showMetadataPath() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Show Track Path") { MenuBarManager.shared.showTrackPath() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Show Art Path") { MenuBarManager.shared.showArtPath() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        // Edit Menu
        CommandGroup(after: .textEditing) {
            Button("Save") { NotificationManager.shared.postNotification(.saveRequested, object: nil) }
                .keyboardShortcut("s", modifiers: [.command])
            Divider()
            Divider()
            Button("Create Playlist…") { MenuBarManager.shared.createNewPlaylist() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Rebuild Artwork…") { ArtworkRebuilder.shared.rebuildAllArtwork() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
            Button("Add Track(s) to Playlist…") { MenuBarManager.shared.addTrackToPlaylist() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Remove Track(s) from Playlist…") { MenuBarManager.shared.removeTrackFromPlaylist() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Add Track(s) to Queue") { MenuBarManager.shared.addTrackToQueue() }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            Divider()
            Button("Import LRC…") { MenuBarManager.shared.importTrackLyricsFromLRC() }
            Divider()
            Button("Repath Track…") { MenuBarManager.shared.repathSelectedTrack() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Move Track to Album…") { MenuBarManager.shared.moveSelectedTracksToAlbum() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Divider()
            Button("Delete Album…") { MenuBarManager.shared.deleteCurrentAlbum() }
            Button("Delete Playlist…") { MenuBarManager.shared.deleteCurrentPlaylist() }
            Divider()
            Button("Delete Library…") { MenuBarManager.shared.clearLibrary() }
        }

        // About Menu (separate top-level)
        CommandMenu("About") {
            Button("MetaWav") { MenuBarManager.shared.showAboutMetaWav() }
            Divider()
        }

        // Sharing Menu (separate top-level)
        CommandMenu("Sharing") {
            Button("Export MetaAlbum…") { MenuBarManager.shared.exportMetaAlbum() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Import MetaAlbum…") { MenuBarManager.shared.importMetaAlbum() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Export Album to CSV…") { MenuBarManager.shared.exportToCSV() }
                .keyboardShortcut("e", modifiers: [.command])
            Button("Export Track Lyrics as LRC…") { MenuBarManager.shared.exportTrackLyricsAsLRC() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        // Plugins Menu
        CommandMenu("Plugins") {
            Button("Add Plugin…") { MenuBarManager.shared.showAddPluginWindow() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            Button("Save MetaAmp…") { MenuBarManager.shared.saveAmpChain() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Load MetaAmp…") { MenuBarManager.shared.loadAmpChain() }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Divider()
            Button("Rescan Audio Units") { MenuBarManager.shared.rescanAudioUnits() }
                .keyboardShortcut("r", modifiers: [.command, .option])
        }

        // Window Menu additions
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show/Hide Additional Panels") { MenuBarManager.shared.toggleAdditionalPanels() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        // Help Menu (custom Getting Started)
        CommandGroup(after: .help) {
            Button("Getting Started") { MenuBarManager.shared.showHelp() }
            Button("Keyboard Shortcuts") { MenuBarManager.shared.showKeyboardShortcuts() }
            Divider()
            Button("File Organization") { MenuBarManager.shared.showFileOrganization() }
            Divider()
            Button("Troubleshooting") { MenuBarManager.shared.showTroubleshooting() }
        }
    }
}
