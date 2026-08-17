// MenuBarManager.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
import Foundation

@MainActor
class MenuBarManager: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = MenuBarManager()
    
    @Published var showingClearLibraryAlert = false
    @Published var showingExportCSV = false
    @Published var showingExportMetaAlbum = false
    @Published var showingImportMetaAlbum = false
    
    // Track current app state for menu updates
    @Published var currentAlbum: AlbumMetadata?
    @Published var currentTrack: TrackMetadata?
    @Published var selectedTrack: TrackMetadata?
    @Published var selectedTracks: [TrackMetadata] = []
    @Published var currentPlaylist: PlaylistMetadata?
    @Published var isPoweredOn: Bool = false
    
    // Keep a strong reference so the window is not deallocated
    private var addPluginWindowController: NSWindowController?
    private var rescanWindowController: NSWindowController?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Plugins Management
    @objc func rescanAudioUnits() {
        print("🔎 Rescanning Audio Units…")
        let manager = AVAudioUnitComponentManager.shared()
        // Invalidate any caches by re-querying; post notification so UIs refresh
        _ = manager.components(matching: NSPredicate(value: true))
        NotificationManager.shared.postNotification(.mwPluginsDidChange, object: nil)
    }
    
    @objc func validateAllAudioUnitsQuick() {
        print("✅ Validating Audio Units (quick instantiate, limited concurrency)…")
        let manager = AVAudioUnitComponentManager.shared()
        let components = manager.components(matching: NSPredicate(value: true)).filter { $0.audioComponentDescription.componentType == kAudioUnitType_Effect }
        
        let maxConcurrent = 2
        let timeoutSec: TimeInterval = 6
        let semaphore = DispatchSemaphore(value: maxConcurrent)
        let group = DispatchGroup()
        let failuresLock = NSLock()
        var failures: [(String, String)] = []
        
        let workQueue = DispatchQueue.global(qos: .userInitiated)
        for comp in components {
            semaphore.wait()
            group.enter()
            workQueue.async {
                let lock = NSLock()
                var finished = false
                
                func finishFailure(_ message: String) {
                    failuresLock.lock(); failures.append((comp.name, message)); failuresLock.unlock()
                }
                
                // Timeout handler
                workQueue.asyncAfter(deadline: .now() + timeoutSec) {
                    lock.lock(); defer { lock.unlock() }
                    if finished { return }
                    finished = true
                    finishFailure("Timed out after \(Int(timeoutSec))s")
                    semaphore.signal(); group.leave()
                }
                
                AVAudioUnit.instantiate(with: comp.audioComponentDescription, options: [.loadOutOfProcess]) { unit, error in
                    lock.lock(); defer { lock.unlock() }
                    if finished { return }
                    finished = true
                    if let error = error {
                        finishFailure(error.localizedDescription)
                    } else if unit == nil {
                        finishFailure("Instantiation returned nil")
                    }
                    semaphore.signal(); group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            if failures.isEmpty {
                self.showAlert(title: "Validation Complete", message: "All Audio Units instantiated successfully.")
            } else {
                let first = failures.first!
                let summary = failures.count == 1 ? "\(first.0): \(first.1)" : "\(failures.count) failures. Example: \(first.0) → \(first.1)"
                self.showAlert(title: "Validation Completed with Issues", message: summary)
            }
        }
    }
    
    // Deprecated: SwiftUI Commands now define the menu. Kept for fallback/testing only.
    func setupMenuBar() { }
    
    // MARK: - Menu Creation (App, File, About, Window, Help remain the same)
    private func createAppMenu() -> NSMenu {
        let menu = NSMenu(title: "MetaWav")
        
        // About MetaWav
        let aboutItem = NSMenuItem(
            title: "About MetaWav",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Services
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu()
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesItem.submenu
        
        menu.addItem(NSMenuItem.separator())
        
        // Hide MetaWav
        let hideItem = NSMenuItem(
            title: "Hide MetaWav",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        menu.addItem(hideItem)
        
        // Hide Others
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthersItem)
        
        // Show All
        let showAllItem = NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(showAllItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit MetaWav
        let quitItem = NSMenuItem(
            title: "Quit MetaWav",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        return menu
    }
    
    private func createFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        
        // Load Files
        let loadFilesItem = NSMenuItem(
            title: "Load Files...",
            action: #selector(loadFiles),
            keyEquivalent: "o"
        )
        loadFilesItem.target = self
        menu.addItem(loadFilesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Refresh Library
        let refreshItem = NSMenuItem(
            title: "Refresh Library",
            action: #selector(refreshLibrary),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show Metadata Path
        let showMetadataItem = NSMenuItem(
            title: "Show Metadata Path",
            action: #selector(showMetadataPath),
            keyEquivalent: "m"
        )
        showMetadataItem.keyEquivalentModifierMask = [.command, .shift]
        showMetadataItem.target = self
        menu.addItem(showMetadataItem)
        
        // Show Track Path
        let showTrackItem = NSMenuItem(
            title: "Show Track Path",
            action: #selector(showTrackPath),
            keyEquivalent: "t"
        )
        showTrackItem.keyEquivalentModifierMask = [.command, .shift]
        showTrackItem.target = self
        menu.addItem(showTrackItem)
        
        // Show Art Path
        let showArtItem = NSMenuItem(
            title: "Show Art Path",
            action: #selector(showArtPath),
            keyEquivalent: "a"
        )
        showArtItem.keyEquivalentModifierMask = [.command, .shift]
        showArtItem.target = self
        menu.addItem(showArtItem)
        
        return menu
    }
    
    // UPDATED: Edit Menu with proper playlist operations + Add To Queue
    private func createEditMenuWithPlaylists() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        
        // Create Playlist
        let createPlaylistItem = NSMenuItem(
            title: "Create Playlist...",
            action: #selector(createNewPlaylist),
            keyEquivalent: "n"
        )
        createPlaylistItem.keyEquivalentModifierMask = [.command, .shift]
        createPlaylistItem.target = self
        menu.addItem(createPlaylistItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add Track(s) to Playlist
        let addToPlaylistItem = NSMenuItem(
            title: "Add Track(s) to Playlist...",
            action: #selector(addTrackToPlaylist),
            keyEquivalent: "l"
        )
        addToPlaylistItem.keyEquivalentModifierMask = [.command, .shift]
        addToPlaylistItem.target = self
        menu.addItem(addToPlaylistItem)
        
        // Remove Track(s) from Playlist
        let removeFromPlaylistItem = NSMenuItem(
            title: "Remove Track(s) from Playlist...",
            action: #selector(removeTrackFromPlaylist),
            keyEquivalent: "r"
        )
        removeFromPlaylistItem.keyEquivalentModifierMask = [.command, .option]
        removeFromPlaylistItem.target = self
        menu.addItem(removeFromPlaylistItem)
        
        // Add Track(s) to Queue (NEW)
        let addToQueueItem = NSMenuItem(
            title: "Add Track(s) to Queue",
            action: #selector(addTrackToQueue),
            keyEquivalent: "q"
        )
        addToQueueItem.keyEquivalentModifierMask = [.command, .shift]
        addToQueueItem.target = self
        menu.addItem(addToQueueItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Repath Track
        let repathTrackItem = NSMenuItem(
            title: "Repath Track...",
            action: #selector(repathSelectedTrack),
            keyEquivalent: "p"
        )
        repathTrackItem.keyEquivalentModifierMask = [.command, .shift]
        repathTrackItem.target = self
        menu.addItem(repathTrackItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Delete Album
        let deleteAlbumItem = NSMenuItem(
            title: "Delete Album...",
            action: #selector(deleteCurrentAlbum),
            keyEquivalent: ""
        )
        deleteAlbumItem.target = self
        menu.addItem(deleteAlbumItem)
        
        // Delete Playlist
        let deletePlaylistItem = NSMenuItem(
            title: "Delete Playlist...",
            action: #selector(deleteCurrentPlaylist),
            keyEquivalent: ""
        )
        deletePlaylistItem.target = self
        menu.addItem(deletePlaylistItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Delete Library
        let deleteLibraryItem = NSMenuItem(
            title: "Delete Library...",
            action: #selector(clearLibrary),
            keyEquivalent: ""
        )
        deleteLibraryItem.target = self
        menu.addItem(deleteLibraryItem)
        
        return menu
    }
    
    private func createAboutMenu() -> NSMenu {
        let menu = NSMenu(title: "About")
        
        let metaWavItem = NSMenuItem(
            title: "MetaWav",
            action: #selector(showAboutMetaWav),
            keyEquivalent: ""
        )
        metaWavItem.target = self
        menu.addItem(metaWavItem)
        
        return menu
    }
    
    private func createSharingMenuWithPlaylists() -> NSMenu {
        let menu = NSMenu(title: "Sharing")
        
        // Export MetaAlbum
        let exportMetaAlbumItem = NSMenuItem(
            title: "Export MetaAlbum...",
            action: #selector(exportMetaAlbum),
            keyEquivalent: "e"
        )
        exportMetaAlbumItem.keyEquivalentModifierMask = [.command, .shift]
        exportMetaAlbumItem.target = self
        exportMetaAlbumItem.isEnabled = (currentAlbum != nil || AppState.shared.currentAlbum != nil)
        menu.addItem(exportMetaAlbumItem)
        
        // Import MetaAlbum
        let importMetaAlbumItem = NSMenuItem(
            title: "Import MetaAlbum...",
            action: #selector(importMetaAlbum),
            keyEquivalent: "i"
        )
        importMetaAlbumItem.keyEquivalentModifierMask = [.command, .shift]
        importMetaAlbumItem.target = self
        menu.addItem(importMetaAlbumItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Export Album to CSV
        let exportCSVItem = NSMenuItem(
            title: "Export Album to CSV...",
            action: #selector(exportToCSV),
            keyEquivalent: "e"
        )
        // Match SwiftUI shortcut (⌘E) for CSV export
        exportCSVItem.keyEquivalentModifierMask = [.command]
        exportCSVItem.target = self
        menu.addItem(exportCSVItem)
        
        // Export Track Lyrics as LRC
        let exportLRCItem = NSMenuItem(
            title: "Export Track Lyrics as LRC...",
            action: #selector(exportTrackLyricsAsLRC),
            keyEquivalent: "l"
        )
        exportLRCItem.keyEquivalentModifierMask = [.command, .shift]
        exportLRCItem.target = self
        menu.addItem(exportLRCItem)
        
        return menu
    }

    // MARK: - NSMenuItemValidation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(exportMetaAlbum):
            return (currentAlbum != nil || AppState.shared.currentAlbum != nil)
        default:
            return true
        }
    }
    
    private func createWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        
        let fullscreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(toggleFullscreen),
            keyEquivalent: "f"
        )
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)
        
        let minimizeItem = NSMenuItem(
            title: "Minimize",
            action: #selector(performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(minimizeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let togglePanelsItem = NSMenuItem(
            title: "Show/Hide Additional Panels",
            action: #selector(toggleAdditionalPanels),
            keyEquivalent: "p"
        )
        togglePanelsItem.keyEquivalentModifierMask = [.command, .shift]
        togglePanelsItem.target = self
        menu.addItem(togglePanelsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let bringAllToFrontItem = NSMenuItem(
            title: "Bring All to Front",
            action: #selector(orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(bringAllToFrontItem)
        
        return menu
    }
    
    private func createHelpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        
        let helpItem = NSMenuItem(
            title: "Getting Started",
            action: #selector(showHelp),
            keyEquivalent: ""
        )
        helpItem.target = self
        menu.addItem(helpItem)
        
        let shortcutsItem = NSMenuItem(
            title: "Keyboard Shortcuts",
            action: #selector(showKeyboardShortcuts),
            keyEquivalent: ""
        )
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let organizationItem = NSMenuItem(
            title: "File Organization",
            action: #selector(showFileOrganization),
            keyEquivalent: ""
        )
        organizationItem.target = self
        menu.addItem(organizationItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let troubleshootingItem = NSMenuItem(
            title: "Troubleshooting",
            action: #selector(showTroubleshooting),
            keyEquivalent: ""
        )
        troubleshootingItem.target = self
        menu.addItem(troubleshootingItem)
        
        return menu
    }

    // MARK: - NEW: Playlist Menu Actions
    @objc func createNewPlaylist() {
        print("📝 Create New Playlist triggered from menu")
        MenuViewManager.shared.showCreatePlaylistDialog()
    }
    
    @objc func addTrackToPlaylist() {
        print("➕ Add Track to Playlist triggered from menu")

        // Bulk add if multiple tracks selected
        if !selectedTracks.isEmpty {
            var seen = Set<String>()
            let uniqueTracks = selectedTracks.filter { track in
                if seen.contains(track.filePath) { return false }
                seen.insert(track.filePath)
                return true
            }
            showPlaylistSelectionDialog(for: uniqueTracks)
            return
        }

        // Single-track fallback
        guard let track = selectedTrack ?? currentTrack else {
            showAlert(title: "No Track Selected", message: "Please select a track first.")
            return
        }
        
        guard let album = currentAlbum else {
            showAlert(title: "No Album Loaded", message: "Please load an album first.")
            return
        }
        
        showPlaylistSelectionDialog(for: track, from: album, action: .add)
    }
    
    @objc func removeTrackFromPlaylist() {
        print("➖ Remove Track from Playlist triggered from menu")
        
        guard let track = selectedTrack ?? currentTrack else {
            showAlert(title: "No Track Selected", message: "Please select a track first.")
            return
        }
        
        if let currentPlaylist = currentPlaylist {
            confirmRemoveTrackFromPlaylist(track, from: currentPlaylist)
        } else {
            showPlaylistsContainingTrack(track)
        }
    }
    
    @objc func deleteCurrentPlaylist() {
        print("🗑️ Delete Current Playlist triggered from menu")
        
        let playlists = PlaylistManager.shared.playlists
        
        if playlists.isEmpty {
            showAlert(title: "No Playlists", message: "There are no playlists to delete.")
            return
        }
        
        showPlaylistSelectionDialog(playlists: playlists, action: .delete)
    }
    
    // MARK: - Playlist Operation Dialogs
    private func showPlaylistSelectionDialog(for track: TrackMetadata, from album: AlbumMetadata, action: PlaylistTrackAction) {
        let playlists = PlaylistManager.shared.playlists
        
        if playlists.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Playlists Found"
            alert.informativeText = "No playlists exist. Create a new playlist for this track?"
            alert.addButton(withTitle: "Create Playlist")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                showCreatePlaylistWithTrackDialog(track: track, album: album)
            }
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Add Track to Playlist"
        alert.informativeText = "Select a playlist to add '\(track.name)' to:"
        
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        
        for playlist in playlists.sorted(by: { $0.name < $1.name }) {
            popup.addItem(withTitle: "\(playlist.name) (\(playlist.trackCount) tracks)")
        }
        
        alert.accessoryView = popup
        alert.addButton(withTitle: "Add to Playlist")
        alert.addButton(withTitle: "Create New Playlist")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            let selectedIndex = popup.indexOfSelectedItem
            let selectedPlaylist = playlists.sorted(by: { $0.name < $1.name })[selectedIndex]
            
            do {
                try PlaylistManager.shared.addTrackToPlaylist(track, from: album, to: selectedPlaylist.name)
                showAlert(title: "Track Added", message: "'\(track.name)' added to '\(selectedPlaylist.name)'.")
                NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
            } catch {
                showAlert(title: "Add Failed", message: "Failed to add track: \(error.localizedDescription)")
            }
            
        case .alertSecondButtonReturn:
            showCreatePlaylistWithTrackDialog(track: track, album: album)
            
        default:
            break
        }
    }

    // Bulk playlist add for multi-selected tracks
    private func showPlaylistSelectionDialog(for tracks: [TrackMetadata]) {
        let playlists = PlaylistManager.shared.playlists

        if playlists.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Playlists Found"
            alert.informativeText = "No playlists exist. Create a new playlist for the selected tracks?"
            alert.addButton(withTitle: "Create Playlist")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let nameAlert = NSAlert()
                nameAlert.messageText = "Create New Playlist"
                nameAlert.informativeText = "Enter a name for the new playlist:"
                let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                textField.stringValue = "New Playlist"
                textField.selectText(nil)
                nameAlert.accessoryView = textField
                nameAlert.addButton(withTitle: "Create")
                nameAlert.addButton(withTitle: "Cancel")
                nameAlert.window.makeFirstResponder(textField)
                if nameAlert.runModal() == .alertFirstButtonReturn {
                    let playlistName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !playlistName.isEmpty else { return }
                    do {
                        let _ = try PlaylistManager.shared.createPlaylist(name: playlistName)
                        NotificationManager.shared.postNotification(.playlistCreated, object: nil)
                        try PlaylistManager.shared.addTracksToPlaylist(tracks, to: playlistName)
                        showAlert(title: "Tracks Added", message: "Added \(tracks.count) track(s) to '\(playlistName)'.")
                        NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
                    } catch {
                        showAlert(title: "Add Failed", message: "Failed to add tracks: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = tracks.count == 1 ? "Add Track to Playlist" : "Add \(tracks.count) Tracks to Playlist"
        alert.informativeText = "Select a playlist to add the selected track(s) to:"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        for playlist in playlists.sorted(by: { $0.name < $1.name }) {
            popup.addItem(withTitle: "\(playlist.name) (\(playlist.trackCount) tracks)")
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Add to Playlist")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let selectedIndex = popup.indexOfSelectedItem
            let selectedPlaylist = playlists.sorted(by: { $0.name < $1.name })[selectedIndex]
            do {
                try PlaylistManager.shared.addTracksToPlaylist(tracks, to: selectedPlaylist.name)
                showAlert(title: "Tracks Added", message: "Added \(tracks.count) track(s) to '\(selectedPlaylist.name)'.")
                NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
            } catch {
                showAlert(title: "Add Failed", message: "Failed to add tracks: \(error.localizedDescription)")
            }
        }
    }
    
    private func showCreatePlaylistWithTrackDialog(track: TrackMetadata, album: AlbumMetadata) {
        let alert = NSAlert()
        alert.messageText = "Create New Playlist"
        alert.informativeText = "Enter a name for the new playlist:"
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "New Playlist"
        textField.selectText(nil)
        
        alert.accessoryView = textField
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        alert.window.makeFirstResponder(textField)
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let playlistName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !playlistName.isEmpty {
                do {
                    let _ = try PlaylistManager.shared.createPlaylist(name: playlistName)
                    NotificationManager.shared.postNotification(.playlistCreated, object: nil)
                    try PlaylistManager.shared.addTrackToPlaylist(track, from: album, to: playlistName)
                    showAlert(title: "Playlist Created",
                             message: "Created '\(playlistName)' and added '\(track.name)'.")
                    NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
                } catch {
                    showAlert(title: "Creation Failed",
                             message: "Failed to create playlist: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func confirmRemoveTrackFromPlaylist(_ track: TrackMetadata, from playlist: PlaylistMetadata) {
        let alert = NSAlert()
        alert.messageText = "Remove Track from Playlist?"
        alert.informativeText = "Remove '\(track.name)' from playlist '\(playlist.name)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            do {
                try PlaylistManager.shared.removeTrackFromPlaylist(track, from: playlist.name)
                showAlert(title: "Track Removed", message: "'\(track.name)' removed from '\(playlist.name)'.")
                NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
            } catch {
                showAlert(title: "Remove Failed", message: "Failed to remove track: \(error.localizedDescription)")
            }
        }
    }
    
    private func showPlaylistsContainingTrack(_ track: TrackMetadata) {
        let allPlaylists = PlaylistManager.shared.playlists
        let containingPlaylists = allPlaylists.filter { playlist in
            playlist.tracks.contains { $0.filePath == track.filePath }
        }
        
        if containingPlaylists.isEmpty {
            showAlert(title: "Track Not in Playlists",
                     message: "'\(track.name)' is not currently in any playlists.")
            return
        }
        
        if containingPlaylists.count == 1 {
            confirmRemoveTrackFromPlaylist(track, from: containingPlaylists[0])
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Remove from Which Playlist?"
        alert.informativeText = "'\(track.name)' is in multiple playlists. Choose which one to remove it from:"
        
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        
        for playlist in containingPlaylists.sorted(by: { $0.name < $1.name }) {
            popup.addItem(withTitle: "\(playlist.name) (\(playlist.trackCount) tracks)")
        }
        
        alert.accessoryView = popup
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let selectedIndex = popup.indexOfSelectedItem
            let selectedPlaylist = containingPlaylists.sorted(by: { $0.name < $1.name })[selectedIndex]
            confirmRemoveTrackFromPlaylist(track, from: selectedPlaylist)
        }
    }
    
    // MARK: - Existing Menu Actions
    @objc func showAbout() {
        print("📋 Show About MetaWav (from app menu)")
        showAboutMetaWav()
    }
    
    @objc func showSettings() {
        print("⚙️ Show Settings")
        MenuViewManager.shared.showSettings()
    }
    
    @objc func showAboutMetaWav() {
        print("📋 Show About MetaWav")
        MenuViewManager.shared.showAboutMetaWav()
    }
    
    @objc func loadFiles() {
        print("📁 Load Files triggered from menu")
        NotificationManager.shared.postNotification(.menuLoadFiles, object: nil)
    }
    
    @objc func refreshLibrary() {
        print("🔄 Refresh Library triggered from menu")
        SmartRefreshCoordinator.shared.processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))
    }

    // MARK: - Rescan Library From Path
    @objc func rescanLibraryFromPath() {
        print("🔎 Rescan Library from Path triggered")
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Library Root Folder"
        openPanel.message = "Choose the folder to scan for audio files to reconcile with existing .meta albums"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false

        openPanel.begin { response in
            if response == .OK, let rootURL = openPanel.url {
                Task { @MainActor in
                    await self.performRescanLibrary(from: rootURL)
                }
            }
        }
    }

	private func performRescanLibrary(from rootURL: URL) async {
        guard rootURL.startAccessingSecurityScopedResource() else {
            showAlert(title: "Access Denied", message: "Cannot access the selected folder.")
            return
        }
        defer { rootURL.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let allAlbums = AlbumMetadataManager.shared.loadAllAlbums()

        // Build quick lookup of candidate files by base filename (lowercased)
        var filenameToURLs: [String: [URL]] = [:]
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .nameKey]

        // Depth-first enumeration, include audio and common art/related extensions
        let allowedExts: Set<String> = [
            // audio
            "wav","aiff","aif","flac","mp3","m4a","aac","alac","ogg","oga","opus","wv","ape","dsf","dff","caf",
            // images/artwork
            "jpg","jpeg","png","gif","bmp","tiff","tif","webp",
            // documents/related
            "txt","rtf","pdf","doc","docx","pages","lrc","md","json","xml",
            // daw projects
            "logicx","als","cpr","rpp","flp","ptf","song"
        ]

        if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            while let item = enumerator.nextObject() as? URL {
                let fileURL = item
                let ext = fileURL.pathExtension.lowercased()
                if !allowedExts.contains(ext) { continue }
                do {
                    let r = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    if r.isRegularFile == true {
                        let key = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                        filenameToURLs[key, default: []].append(fileURL)
                    }
                } catch {
                    // Skip unreadable entries
                }
            }
        }

        var missingCount = 0
        var ambiguous: [(album: String, track: String)] = []
        var proposed: [ProposedChange] = []

		for album in allAlbums {
			for track in album.tracks {
				if fm.fileExists(atPath: track.filePath) { continue }
				let base = URL(fileURLWithPath: track.filePath).deletingPathExtension().lastPathComponent.lowercased()
				if let candidates = filenameToURLs[base], !candidates.isEmpty {
					if candidates.count == 1 {
						let newURL = candidates[0]
						proposed.append(ProposedChange(kind: .trackFile, albumName: album.albumName, trackId: track.id, itemName: track.name, oldPath: track.filePath, newURL: newURL))
					} else {
						ambiguous.append((album.albumName, track.name))
					}
				} else {
					missingCount += 1
				}
			}
		}

		// Album artwork
		for album in allAlbums {
			let artPairs: [(ProposedChangeKind, String?)] = [(.frontArt, album.frontArtPath), (.backArt, album.backArtPath)]
			for (kind, pathOpt) in artPairs {
				guard let oldPath = pathOpt, !oldPath.isEmpty, !fm.fileExists(atPath: oldPath) else { continue }
				let base = URL(fileURLWithPath: oldPath).deletingPathExtension().lastPathComponent.lowercased()
				if let candidates = filenameToURLs[base], candidates.count == 1 {
					let label = (kind == .frontArt) ? "Front Artwork" : "Back Artwork"
					proposed.append(ProposedChange(kind: kind, albumName: album.albumName, trackId: nil, itemName: label, oldPath: oldPath, newURL: candidates[0]))
				}
			}
		}

		// Related files
		for album in allAlbums {
			for track in album.tracks {
				if let related = track.relatedFiles {
					for rf in related {
						if fm.fileExists(atPath: rf.filePath) { continue }
						let base = URL(fileURLWithPath: rf.filePath).deletingPathExtension().lastPathComponent.lowercased()
						if let candidates = filenameToURLs[base], candidates.count == 1 {
							proposed.append(ProposedChange(kind: .relatedFile, albumName: album.albumName, trackId: track.id, itemName: rf.actualDisplayName, oldPath: rf.filePath, newURL: candidates[0]))
						}
					}
				}
			}
		}

		if proposed.isEmpty {
			var message = "No unique matches found."
			if missingCount > 0 { message += "\nStill missing \(missingCount) track(s)." }
			if !ambiguous.isEmpty { message += "\nAmbiguous matches for \(ambiguous.count) track(s)." }
			showAlert(title: "Rescan Complete", message: message)
			return
		}

		presentRescanReview(changes: proposed)
    }

	private func presentRescanReview(changes: [ProposedChange]) {
		// If already open, bring to front
		if let wc = rescanWindowController, let win = wc.window {
			win.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Review Rescan Changes"
		window.center()
		window.isReleasedWhenClosed = false

		let view = RescanReviewView(
			proposedChanges: changes,
			onAccept: { [weak self] accepted in
				self?.applyRescanChanges(accepted)
				self?.rescanWindowController?.close()
				self?.rescanWindowController = nil
			},
			onCancel: { [weak self] in
				self?.rescanWindowController?.close()
				self?.rescanWindowController = nil
			}
		)
		let hosting = NSHostingView(rootView: view)
		window.contentView = hosting

		let controller = NSWindowController(window: window)
		rescanWindowController = controller
		controller.showWindow(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	private func applyRescanChanges(_ changes: [ProposedChange]) {
		let fm = FileManager.default
		var updatedCount = 0
		let grouped = Dictionary(grouping: changes, by: { $0.albumName })
		for (albumName, albumChanges) in grouped {
			guard var album = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumName) else { continue }
			var albumChanged = false
			for change in albumChanges {
				switch change.kind {
				case .trackFile:
					if let idx = album.tracks.firstIndex(where: { $0.id == change.trackId || $0.filePath == change.oldPath }) {
						var t = album.tracks[idx]
						let newURL = change.newURL
						t.filePath = newURL.path
						t.format = newURL.pathExtension.uppercased()
						if fm.fileExists(atPath: newURL.path), let audioFile = try? AVAudioFile(forReading: newURL) {
							t.duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
							t.channelCount = Int(audioFile.fileFormat.channelCount)
							t.sampleRate = audioFile.fileFormat.sampleRate
							if newURL.pathExtension.lowercased() == "mp3" { t.bitDepth = "16-bit" } else { t.bitDepth = audioFile.fileFormat.bitDepthString }
						}
						album.tracks[idx] = t
						albumChanged = true
						updatedCount += 1
					}
				case .frontArt:
					album.frontArtPath = change.newURL.path
					albumChanged = true
					updatedCount += 1
				case .backArt:
					album.backArtPath = change.newURL.path
					albumChanged = true
					updatedCount += 1
				case .relatedFile:
					if let tIndex = album.tracks.firstIndex(where: { $0.id == change.trackId }) {
						if var related = album.tracks[tIndex].relatedFiles, let rIndex = related.firstIndex(where: { $0.filePath == change.oldPath }) {
							related[rIndex].filePath = change.newURL.path
							album.tracks[tIndex].relatedFiles = related
							albumChanged = true
							updatedCount += 1
						}
					}
				}
			}
			if albumChanged {
				album.calculateDuration()
				do { try AlbumMetadataManager.shared.saveAlbumMetadata(album) } catch { print("❌ Save failed: \(albumName) – \(error)") }
			}
		}
        SmartRefreshCoordinator.shared.processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))
		showAlert(title: "Rescan Applied", message: "Updated paths for \(updatedCount) item(s).")
	}
    
    @objc func showMetadataPath() {
        print("📄 Show Metadata Path")
        guard let album = currentAlbum else {
            showAlert(title: "No Album Selected", message: "Please select an album first.")
            return
        }
        
        let metadataPath = AlbumMetadataManager.shared.getMetadataPath(for: album.albumName)
        showPathInFinder(metadataPath.path)
    }
    
    @objc func showTrackPath() {
        print("🎵 Show Track Path")
        guard let track = selectedTrack ?? currentTrack else {
            showAlert(title: "No Track Selected", message: "Please select a track first.")
            return
        }
        
        showPathInFinder(track.filePath)
    }
    
    @objc func showArtPath() {
        print("🎨 Show Art Path")
        guard let album = currentAlbum else {
            showAlert(title: "No Album Selected", message: "Please select an album first.")
            return
        }
        
        if let frontArtPath = album.frontArtPath {
            showPathInFinder(frontArtPath)
        } else {
            showAlert(title: "No Artwork", message: "This album has no artwork.")
        }
    }
    
    @objc func repathSelectedTrack() {
        print("🔗 Repath Track triggered from menu")
        
        guard let track = selectedTrack ?? currentTrack else {
            showAlert(title: "No Track Selected", message: "Please select a track in the tracklist first.")
            return
        }
        
        guard let album = currentAlbum else {
            showAlert(title: "No Album Loaded", message: "Please load an album first.")
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.title = "Select New Location for '\(track.name)'"
        openPanel.message = "Choose the new location for this audio file"
        openPanel.allowedContentTypes = [.audio]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        
        let oldURL = URL(fileURLWithPath: track.filePath)
        if FileManager.default.fileExists(atPath: oldURL.deletingLastPathComponent().path) {
            openPanel.directoryURL = oldURL.deletingLastPathComponent()
        }
        
        openPanel.begin { response in
            if response == .OK, let newURL = openPanel.url {
                Task {
                    await self.performTrackRepath(track: track, album: album, newURL: newURL)
                }
            }
        }
    }
    
    @objc func deleteCurrentAlbum() {
        print("🗑️ Delete Current Album")
        guard let album = currentAlbum else {
            showAlert(title: "No Album Selected", message: "Please select an album to delete.")
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Delete Album '\(album.albumName)'?"
        alert.informativeText = "This will permanently delete the album metadata and all associated files. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Album")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            performAlbumDeletion(album)
        }
    }
    
    @objc func clearLibrary() {
        print("🗑️ Clear Library requested")
        showingClearLibraryAlert = true
        
        let alert = NSAlert()
        alert.messageText = "Delete Entire MetaWav Library?"
        alert.informativeText = "This will permanently delete the ENTIRE MetaWav folder and all its contents. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Everything")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            performCompleteLibraryClear()
        }
    }
    
    @objc func exportToCSV() {
        print("📊 Export to CSV requested")
        showingExportCSV = true
        
        guard let album = currentAlbum ?? AppState.shared.currentAlbum else {
            showAlert(title: "No Album Selected", message: "Please select or load an album to export.")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Album to CSV"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "\(sanitizeFilename(album.albumName))_Export.csv"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                self.performAlbumCSVExport(album: album, to: url)
            }
        }
    }
    
    @objc func exportMetaAlbum() {
        print("📦 Export MetaAlbum requested")
        showingExportMetaAlbum = true
        
        guard let album = currentAlbum ?? AppState.shared.currentAlbum else {
            showAlert(title: "No Album Loaded", message: "Open an album to export.")
            return
        }
        
        showExportLocationDialog(for: album)
    }
    
    @objc func importMetaAlbum() {
        print("📥 Import MetaAlbum requested")
        showingImportMetaAlbum = true
        
        let openPanel = NSOpenPanel()
        openPanel.title = "Import MetaAlbum"
        openPanel.allowedContentTypes = [.metaAlbum]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                self.performMetaAlbumImport(from: url)
            }
        }
    }
    
    @objc func exportTrackLyricsAsLRC() {
        print("🎵 Export Track Lyrics as LRC requested")
        
        guard let track = selectedTrack ?? currentTrack else {
            showAlert(title: "No Track Selected", message: "Please select a track with lyrics to export.")
            return
        }
        
        guard let album = currentAlbum else {
            showAlert(title: "No Album Loaded", message: "Please load an album first.")
            return
        }
        
        guard let lyrics = track.lyrics, !lyrics.isEmpty else {
            showAlert(title: "No Lyrics Available",
                     message: "The selected track '\(track.name)' has no lyrics to export.")
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Export Lyrics for '\(track.name)'"
        alert.informativeText = "This will export \(lyrics.count) lyric lines as an LRC file."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Export LRC")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            LRCExporter.shared.exportTrackLyrics(track, from: album)
        }
    }
    
    @objc func importTrackLyricsFromLRC() {
        print("📥 Import Track Lyrics from LRC requested")
        
        // Resolve track selection
        guard let track = selectedTrack ?? currentTrack else {
            showAlert(title: "No Track Selected", message: "Please select a track to import lyrics into.")
            return
        }
        
        // Resolve album for the selected track
        var albumForTrack: AlbumMetadata?
        if let album = currentAlbum {
            albumForTrack = album
        } else if let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.name) {
            albumForTrack = album
        }
        guard let album = albumForTrack else {
            showAlert(title: "No Album Loaded", message: "Could not resolve the album containing this track.")
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.title = "Import LRC for '\(track.name)'"
        openPanel.message = "Choose an .lrc file to import synchronized lyrics."
        openPanel.allowedContentTypes = [.lrc]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        
        // Default directory to track folder if accessible
        let trackURL = URL(fileURLWithPath: track.filePath)
        if FileManager.default.fileExists(atPath: trackURL.deletingLastPathComponent().path) {
            openPanel.directoryURL = trackURL.deletingLastPathComponent()
        }
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                Task { @MainActor in
                    await self.performImportLRC(from: url, for: track, in: album)
                }
            }
        }
    }
    
    private func performImportLRC(from url: URL, for track: TrackMetadata, in album: AlbumMetadata) async {
        print("📄 Selected LRC: \(url.path)")
        
        guard url.startAccessingSecurityScopedResource() else {
            showAlert(title: "Access Denied", message: "Cannot access the selected LRC file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let parsed = try LRCParser.shared.parse(url: url)
            if parsed.isEmpty {
                showAlert(title: "No Lyrics Found", message: "The selected LRC file contains no timed lyrics.")
                return
            }
            
            var updatedAlbum = album
            guard let idx = updatedAlbum.tracks.firstIndex(where: { $0.id == track.id }) else {
                showAlert(title: "Track Not Found", message: "Could not locate the selected track in the album.")
                return
            }
            
            var updatedTrack = updatedAlbum.tracks[idx]
            updatedTrack.lyrics = parsed
            updatedAlbum.tracks[idx] = updatedTrack
            updatedAlbum.calculateDuration()
            
            do {
                try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(updatedAlbum)
                
                // Update in-memory state
                currentAlbum = updatedAlbum
                if selectedTrack?.id == updatedTrack.id { selectedTrack = updatedTrack }
                if currentTrack?.id == updatedTrack.id { currentTrack = updatedTrack }
                
                // Keep other systems in sync
                QueueManager.shared.refreshAlbumInQueue(updatedAlbum)
                
                // Emit standardized payload for SmartRefreshCoordinator
                NotificationManager.shared.postNotification(.trackMetadataChanged, object: (updatedTrack, updatedAlbum))
                
                showAlert(title: "Lyrics Imported", message: "Imported \(parsed.count) lyric lines into '\(updatedTrack.name)'.")
                print("✅ Imported LRC lyrics: \(parsed.count) lines")
            } catch {
                showAlert(title: "Save Failed", message: "Could not save updated lyrics: \(error.localizedDescription)")
            }
        } catch {
            showAlert(title: "Import Failed", message: "Could not parse the LRC file: \(error.localizedDescription)")
        }
    }
    
    @objc func toggleFullscreen() {
        print("🖥️ Toggle Fullscreen")
        guard let window = NSApplication.shared.windows.first else { return }
        window.toggleFullScreen(nil)
    }
    
    @objc func performMiniaturize(_ sender: Any?) {
        print("📦 Minimize Window")
        guard let window = NSApplication.shared.windows.first else { return }
        window.miniaturize(sender)
    }
    
    @objc func toggleAdditionalPanels() {
        print("📋 Toggle Additional Panels")
        NotificationManager.shared.postNotification(.togglePanels, object: nil)
    }
    
    @objc func orderFrontStandardAboutPanel(_ sender: Any?) {
        NSApplication.shared.arrangeInFront(sender)
    }
    
    @objc func showHelp() {
        MenuViewManager.shared.showQuickStart()
    }
    
    @objc func showKeyboardShortcuts() {
        MenuViewManager.shared.showKeyboardShortcuts()
    }
    
    @objc func showFileOrganization() {
        MenuViewManager.shared.showFileOrganization()
    }
    
    @objc func showTroubleshooting() {
        print("🔧 Show Troubleshooting")
        MenuViewManager.shared.showTroubleshooting()
    }

    // MARK: - Amp Chain Save/Load
    @objc func saveAmpChain() {
        let savePanel = NSSavePanel()
        savePanel.title = "Save MetaAmp"
        savePanel.allowedContentTypes = [.metaAmp]
        savePanel.nameFieldStringValue = "MyChain.metaamp"

        // Default directory: ~/Documents/MetaWav/Amp
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultDir = home.appendingPathComponent("Documents").appendingPathComponent("MetaWav").appendingPathComponent("Amp")
        try? FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
        savePanel.directoryURL = defaultDir

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try UnifiedAudioEngine.shared.saveAmpChain(to: url)
                    self.showAlert(title: "Amp Chain Saved", message: "Saved to:\n\(url.path)")
                } catch {
                    self.showAlert(title: "Save Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @objc func loadAmpChain() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Load MetaAmp"
        openPanel.allowedContentTypes = [.metaAmp]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false

        // Default directory: ~/Documents/MetaWav/Amp
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultDir = home.appendingPathComponent("Documents").appendingPathComponent("MetaWav").appendingPathComponent("Amp")
        if FileManager.default.fileExists(atPath: defaultDir.path) {
            openPanel.directoryURL = defaultDir
        }

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                UnifiedAudioEngine.shared.loadAmpChain(from: url) { success in
                    DispatchQueue.main.async {
                        if success {
                            self.showAlert(title: "Amp Chain Loaded", message: "Loaded from:\n\(url.path)")
                        } else {
                            self.showAlert(title: "Load Failed", message: "Could not load the selected .metaamp file.")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Queue Action (NEW)
    @objc func addTrackToQueue() {
        print("➕ Add Track to Queue triggered from menu")

        // If multiple tracks selected, enqueue all
        if !selectedTracks.isEmpty {
            var enqueued = 0
            var seen = Set<String>()
            for t in selectedTracks {
                if seen.contains(t.filePath) { continue }
                seen.insert(t.filePath)

                var albumForTrack: AlbumMetadata?
                if let current = currentAlbum, current.tracks.contains(where: { $0.filePath == t.filePath }) {
                    albumForTrack = current
                } else if let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: t.filePath, name: t.name) {
                    albumForTrack = album
                }
                if let album = albumForTrack {
                    QueueManager.shared.addToQueue(t, from: album)
                    enqueued += 1
                }
            }
            print("✅ Added \(enqueued) track(s) to Queue via menu")
            return
        }

        // Single track path
        guard let track = selectedTrack ?? currentTrack else {
            showAlert(title: "No Track Selected", message: "Please select a track first.")
            return
        }

        var albumForTrack: AlbumMetadata?
        if let album = currentAlbum {
            albumForTrack = album
        } else if let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.name) {
            albumForTrack = album
        }
        guard let resolvedAlbum = albumForTrack else {
            showAlert(title: "Album Not Found", message: "Could not find the album for this track.")
            return
        }
        QueueManager.shared.addToQueue(track, from: resolvedAlbum)
        print("✅ Added to Queue via menu: \(track.name)")
    }

    // MARK: - Move Track(s) To Another Album
    @objc func moveSelectedTracksToAlbum() {
        print("🚚 Move Track(s) to Album triggered from menu")

        // Build list of tracks to move: prefer multi-select, else single selection/current
        var tracksToMove: [TrackMetadata] = []
        if !selectedTracks.isEmpty {
            // Ensure uniqueness by file path to avoid duplicates
            var seen = Set<String>()
            for t in selectedTracks {
                if !seen.contains(t.filePath) {
                    tracksToMove.append(t)
                    seen.insert(t.filePath)
                }
            }
        } else if let t = selectedTrack ?? currentTrack {
            tracksToMove = [t]
        }

        guard !tracksToMove.isEmpty else {
            showAlert(title: "No Track Selected", message: "Please select one or more tracks first.")
            return
        }

        // Load albums for destination selection
        let albums = AlbumMetadataManager.shared.loadAllAlbums().sorted { $0.albumName < $1.albumName }
        guard !albums.isEmpty else {
            showAlert(title: "No Albums Available", message: "Create or import an album first.")
            return
        }

        // Present a simple album selection dialog
        let alert = NSAlert()
        alert.messageText = tracksToMove.count == 1 ? "Move Track to Album" : "Move \(tracksToMove.count) Tracks to Album"
        alert.informativeText = "Choose the destination album:"

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        for album in albums {
            popup.addItem(withTitle: "\(album.albumName) (\(album.trackCount) tracks)")
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let selectedIndex = popup.indexOfSelectedItem
        let destinationAlbum = albums[selectedIndex]

        // Perform move operation
        var movedCount = 0
        var failed: [(TrackMetadata, String)] = []

        for track in tracksToMove {
            // Resolve source album name
            var sourceAlbumName: String?
            if let current = currentAlbum, current.tracks.contains(where: { $0.id == track.id || $0.filePath == track.filePath }) {
                sourceAlbumName = current.albumName
            } else if let (album, _) = AlbumMetadataManager.shared.findTrack(filePath: track.filePath, name: track.name) {
                sourceAlbumName = album.albumName
            }

            guard let srcName = sourceAlbumName else {
                failed.append((track, "Source album not found"))
                continue
            }

            // If destination equals source, skip gracefully
            if srcName == destinationAlbum.albumName {
                failed.append((track, "Already in destination album"))
                continue
            }

            do {
                // Remove from source with reordering
                try AlbumMetadataManager.shared.removeTrackWithReordering(filePath: track.filePath, from: srcName)

                // Add to destination; preserve metadata, let reordering fix positions
                try AlbumMetadataManager.shared.addOrUpdateTrackWithReordering(track, in: destinationAlbum.albumName)

                movedCount += 1
            } catch {
                failed.append((track, error.localizedDescription))
            }
        }

        // Many albums may have changed: perform coordinated full refresh
        SmartRefreshCoordinator.shared.processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))

        // Summarize result
        if failed.isEmpty {
            showAlert(title: "Move Complete", message: movedCount == 1 ? "Moved 1 track to '\(destinationAlbum.albumName)'." : "Moved \(movedCount) tracks to '\(destinationAlbum.albumName)'.")
        } else {
            let firstErr = failed.first?.1 ?? "Unknown error"
            let summary = failed.count == tracksToMove.count ? "No tracks moved. Example error: \(firstErr)" : "Moved \(movedCount); \(failed.count) failed. Example error: \(firstErr)"
            showAlert(title: "Move Completed with Issues", message: summary)
        }
    }

    // MARK: - Helper Methods
    private func showPathInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func performTrackRepath(track: TrackMetadata, album: AlbumMetadata, newURL: URL) async {
        guard newURL.startAccessingSecurityScopedResource() else {
            showAlert(title: "Access Denied", message: "Cannot access the selected file.")
            return
        }
        defer { newURL.stopAccessingSecurityScopedResource() }
        
        do {
            let testAudioFile = try AVAudioFile(forReading: newURL)
            let newDuration = Double(testAudioFile.length) / testAudioFile.fileFormat.sampleRate
            print("✅ New file validated: \(newURL.lastPathComponent), duration: \(newDuration)s")
        } catch {
            showAlert(title: "Invalid Audio File",
                     message: "The selected file is not a valid audio file: \(error.localizedDescription)")
            return
        }
        
        var updatedAlbum = album
        
        if let trackIndex = updatedAlbum.tracks.firstIndex(where: { $0.id == track.id }) {
            var updatedTrack = updatedAlbum.tracks[trackIndex]
            let oldPath = updatedTrack.filePath
            
            updatedTrack.filePath = newURL.path
            updatedTrack.format = newURL.pathExtension.uppercased()
            updatedTrack.duration = try? {
                let audioFile = try AVAudioFile(forReading: newURL)
                return Double(audioFile.length) / audioFile.fileFormat.sampleRate
            }()
            
            updatedAlbum.tracks[trackIndex] = updatedTrack
            updatedAlbum.calculateDuration()
            
            do {
                try await AlbumMetadataManager.shared.saveAlbumMetadataInstantly(updatedAlbum)
                
                currentAlbum = updatedAlbum
                if selectedTrack?.id == track.id {
                    selectedTrack = updatedTrack
                }
                if currentTrack?.id == track.id {
                    currentTrack = updatedTrack
                }
                
                NotificationManager.shared.postNotification(.trackRepathed, object: updatedTrack)
                
                showAlert(title: "Track Repathed Successfully",
                         message: "Track '\(track.name)' has been relinked to:\n\(newURL.path)")
                
                print("🔗 Track repathed successfully:")
                print("   From: \(oldPath)")
                print("   To: \(newURL.path)")
                
            } catch {
                showAlert(title: "Save Failed",
                         message: "Failed to save updated track information: \(error.localizedDescription)")
            }
        } else {
            showAlert(title: "Track Not Found",
                     message: "Could not find the track in the current album.")
        }
    }
    
    private func performAlbumDeletion(_ album: AlbumMetadata) {
        do {
            try AlbumMetadataManager.shared.deleteAlbum(album.albumName)
            showAlert(title: "Album Deleted", message: "Album '\(album.albumName)' has been deleted.")
            
            NotificationManager.shared.postNotification(.albumDeleted, object: album.albumName)
            
        } catch {
            showAlert(title: "Deletion Failed", message: "Failed to delete album: \(error.localizedDescription)")
        }
    }
    
    private func performCompleteLibraryClear() {
        do {
            let userHome = FileManager.default.homeDirectoryForCurrentUser
            let metaWavDirectory = userHome
                .appendingPathComponent("Documents")
                .appendingPathComponent("MetaWav")
            
            guard FileManager.default.fileExists(atPath: metaWavDirectory.path) else {
                showAlert(title: "Nothing to Clear",
                         message: "The MetaWav directory doesn't exist.")
                return
            }
            
            try FileManager.default.removeItem(at: metaWavDirectory)
            
            showAlert(title: "Library Cleared",
                     message: "Successfully deleted the entire MetaWav directory.")
            
            SmartRefreshCoordinator.shared.processMetadataChange(RefreshEvent(type: .fullLibraryRefresh))
            
        } catch {
            showAlert(title: "Clear Failed",
                     message: "Failed to clear MetaWav directory: \(error.localizedDescription)")
        }
    }
    
    private func performAlbumCSVExport(album: AlbumMetadata, to url: URL) {
        do {
            let csvContent = generateAlbumCSVContent(album: album)
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
            showAlert(title: "Export Complete", message: "Album exported to CSV successfully.")
            print("✅ Album CSV export completed: \(url.path)")
        } catch {
            showAlert(title: "Export Failed", message: "Failed to export CSV: \(error.localizedDescription)")
            print("❌ CSV export failed: \(error)")
        }
    }

    private func generateAlbumCSVContent(album: AlbumMetadata) -> String {
        var csv = ""

        // Table 1: Album details (Property,Value)
        csv += "ALBUM INFORMATION\n"
        csv += "Property,Value\n"
        csv += "Album Name,\(csvForceText(album.albumName))\n"
        if let albumType = album.albumType { csv += "Album Type,\(csvForceText(albumType))\n" }
        if let genre = album.genre { csv += "Genre,\(csvForceText(genre))\n" }
        if let year = album.year { csv += "Year,\(csvForceText(year))\n" }
        if let total = album.formattedDuration { csv += "Total Duration,\(csvForceText(total))\n" }
        csv += "Track Count,\(csvForceText(String(album.trackCount)))\n"
        csv += "Disc Count,\(csvForceText(String(album.discCount)))\n"
        if let front = album.frontArtPath { csv += "Front Artwork Path,\(csvForceText(front))\n" }
        if let back = album.backArtPath { csv += "Back Artwork Path,\(csvForceText(back))\n" }
        
        // Disc names if present
        if let discNames = album.discNames, !discNames.isEmpty {
            let sorted = discNames.keys.compactMap { Int($0) }.sorted()
            for disc in sorted {
                if let name = discNames[String(disc)], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    csv += "Disc \(disc) Name,\(name.csvEscaped)\n"
                }
            }
        }

        // spacer between tables
        csv += "\n\n"

        // Table 2: Track details
        // Header
        csv += [
            "Disc",
            "Track #",
            "Track Name",
            "Artist",
            "Duration",
            "Key",
            "BPM",
            "Version",
            "Explicit",
            "Format",
            "Channels",
            "Sample Rate",
            "Bit Depth",
            "Bitrate (kbps)",
            "ISRC",
            "Credits",
            "Related Files (count)",
            "Related Files",
            "Lyrics (lines)",
            "Lyrics",
            "Notes",
            "File Path"
        ].joined(separator: ",") + "\n"

        let sortedTracks = album.tracks.sorted { t1, t2 in
            if t1.discNumber != t2.discNumber { return t1.discNumber < t2.discNumber }
            return t1.trackNumber < t2.trackNumber
        }

        for track in sortedTracks {
            // Flatten credits to role:name; role:name
            let creditsJoined: String = {
                guard let credits = track.credits, !credits.isEmpty else { return "" }
                return credits.map { "\($0.role): \($0.name)" }.joined(separator: "; ")
            }()

            // Related files
            let relatedCount = track.relatedFiles?.count ?? 0
            let relatedDetail: String = {
                guard let files = track.relatedFiles, !files.isEmpty else { return "" }
                return files.map { "\($0.actualDisplayName) (\($0.fileType.rawValue)): \($0.filePath)" }.joined(separator: "; ")
            }()

            // Lyrics
            let lyricsCount = track.lyrics?.count ?? 0
            let lyricsDetail: String = {
                guard let lyrics = track.lyrics, !lyrics.isEmpty else { return "" }
                let sorted = lyrics.sorted { $0.time < $1.time }
                return sorted.map { "[\(formatTime($0.time))] \($0.text)" }.joined(separator: " | ")
            }()

            let row: [String] = [
                csvForceText(String(track.discNumber)),
                csvForceText(String(track.trackNumber)),
                csvForceText(track.name),
                csvForceText(track.artist ?? ""),
                csvForceText(track.formattedDuration ?? ""),
                csvForceText(track.key ?? ""),
                csvForceText(track.bpm?.description ?? ""),
                csvForceText(track.version ?? ""),
                csvForceText(track.isExplicit == true ? "Yes" : "No"),
                csvForceText(track.format ?? ""),
                csvForceText(track.channelCount?.description ?? ""),
                csvForceText(track.sampleRate?.description ?? ""),
                csvForceText(track.bitDepth ?? ""),
                csvForceText(track.bitrateKbps?.description ?? ""),
                csvForceText(track.isrc ?? ""),
                csvForceText(creditsJoined),
                csvForceText(String(relatedCount)),
                csvForceText(relatedDetail),
                csvForceText(String(lyricsCount)),
                csvForceText(lyricsDetail),
                csvForceText(track.notes ?? ""),
                csvForceText(track.filePath)
            ]
            csv += row.joined(separator: ",") + "\n"
        }

        return csv
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }

    private func csvForceText(_ value: String) -> String {
        if value.isEmpty { return "" }
        return ("'" + value).csvEscaped
    }
    
    private func showPlaylistSelectionDialog(playlists: [PlaylistMetadata], action: PlaylistAction) {
        let alert = NSAlert()
        alert.messageText = "Select Playlist to \(action.rawValue.capitalized)"
        alert.informativeText = "Choose which playlist you want to \(action.rawValue):"
        
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        
        for playlist in playlists.sorted(by: { $0.name < $1.name }) {
            popup.addItem(withTitle: "\(playlist.name) (\(playlist.trackCount) tracks)")
        }
        
        alert.accessoryView = popup
        alert.addButton(withTitle: action.rawValue.capitalized)
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let selectedIndex = popup.indexOfSelectedItem
            let selectedPlaylist = playlists.sorted(by: { $0.name < $1.name })[selectedIndex]
            
            switch action {
            case .delete:
                confirmDeletePlaylist(selectedPlaylist)
            }
        }
    }
    
    private func confirmDeletePlaylist(_ playlist: PlaylistMetadata) {
        let alert = NSAlert()
        alert.messageText = "Delete Playlist '\(playlist.name)'?"
        alert.informativeText = "This will permanently delete the playlist. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Playlist")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            do {
                try PlaylistManager.shared.deletePlaylist(playlist)
                showAlert(title: "Playlist Deleted", message: "Playlist '\(playlist.name)' has been deleted.")
                NotificationManager.shared.postNotification(.playlistDeleted, object: nil)
            } catch {
                showAlert(title: "Deletion Failed", message: "Failed to delete playlist: \(error.localizedDescription)")
            }
        }
    }
    
    private func getPlaylistDirectory() -> URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        return userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Playlists")
    }
    
    private func showAlbumSelectionDialog(albums: [AlbumMetadata], action: AlbumAction) {
        let alert = NSAlert()
        alert.messageText = action == .export ? "Select Album to Export" : "Select Album"
        alert.informativeText = "Choose which album you want to \(action.rawValue):"
        
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        
        for album in albums.sorted(by: { $0.albumName < $1.albumName }) {
            popup.addItem(withTitle: "\(album.albumName) (\(album.trackCount) tracks)")
        }
        
        alert.accessoryView = popup
        alert.addButton(withTitle: action == .export ? "Export" : "OK")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let selectedIndex = popup.indexOfSelectedItem
            let selectedAlbum = albums.sorted(by: { $0.albumName < $1.albumName })[selectedIndex]
            
            if action == .export {
                showExportLocationDialog(for: selectedAlbum)
            }
        }
    }
    
    private func showExportLocationDialog(for album: AlbumMetadata) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export MetaAlbum"
        savePanel.allowedContentTypes = [.metaAlbum]
        savePanel.nameFieldStringValue = "\(sanitizeFilename(album.albumName)).metaalbum"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                self.performMetaAlbumExport(album: album, to: url)
            }
        }
    }
    
    private func performMetaAlbumExport(album: AlbumMetadata, to url: URL) {
        print("📦 Starting MetaAlbum export for: \(album.albumName)")
        
        MetaAlbumManager.shared.exportAlbum(album, to: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.showAlert(title: "Export Complete",
                                   message: "Album '\(album.albumName)' exported successfully as MetaAlbum.")
                case .failure(let error):
                    self.showAlert(title: "Export Failed",
                                   message: "Failed to export album: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func performMetaAlbumImport(from url: URL) {
        print("📥 Starting MetaAlbum import from: \(url.path)")
        
        MetaAlbumManager.shared.importAlbum(from: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let albumName):
                    self.showAlert(title: "Import Complete",
                                   message: "Album '\(albumName)' imported successfully.")
                    
                    SmartRefreshCoordinator.shared.processMetadataChange(RefreshEvent(type: .albumUpdated(albumName: albumName)))
                    
                case .failure(let error):
                    self.showAlert(title: "Import Failed",
                                   message: "Failed to import MetaAlbum: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Add Plugin Window
    @objc func showAddPluginWindow() {
        // If already open, bring to front
        if let wc = addPluginWindowController, let win = wc.window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Plugin"
        window.center()
        window.isReleasedWhenClosed = false
        
        // Glassy look; keep normal level so Finder can appear above when opened
        window.level = .normal
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        
        let hostingView = NSHostingView(rootView: AddPluginView())
        window.contentView = hostingView
        
        let controller = NSWindowController(window: window)
        addPluginWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Cleanup reference on close
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if let self = self, self.addPluginWindowController?.window === window {
                    self.addPluginWindowController = nil
                }
            }
        }
    }
    
    @objc func closeAddPluginWindow() {
        if let wc = addPluginWindowController, let win = wc.window {
            win.close()
            addPluginWindowController = nil
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    // MARK: - State Update Methods
    func updateCurrentAlbum(_ album: AlbumMetadata?) {
        currentAlbum = album
    }
    
    func updateCurrentTrack(_ track: TrackMetadata?) {
        currentTrack = track
    }
    
    func updateSelectedTrack(_ track: TrackMetadata?) {
        selectedTrack = track
        print("🎯 Menu system updated selected track: \(track?.name ?? "none")")
    }
    
    func updateSelectedTracks(_ tracks: [TrackMetadata]) {
        selectedTracks = tracks
    }
    
    func updateCurrentPlaylist(_ playlist: PlaylistMetadata?) {
        currentPlaylist = playlist
        print("📝 Menu system updated current playlist: \(playlist?.name ?? "none")")
    }
    
    func updatePowerState(_ isPoweredOn: Bool) {
        self.isPoweredOn = isPoweredOn
    }
}

// MARK: - Supporting Types
enum AlbumAction: String {
    case export = "export"
    case select = "select"
}

private enum PlaylistAction: String {
    case delete = "delete"
}

private enum PlaylistTrackAction: String {
    case add = "add"
    case remove = "remove"
}

// MARK: - String Extension for CSV
extension String {
    var csvEscaped: String {
        if self.contains(",") || self.contains("\"") || self.contains("\n") {
            return "\"" + self.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return self
    }
}

// MARK: - Playlist Dialogs on MenuViewManager
extension MenuViewManager {
    func showCreatePlaylistDialog() {
        let alert = NSAlert()
        alert.messageText = "Create New Playlist"
        alert.informativeText = "Enter a name for your new playlist:"
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "New Playlist"
        textField.selectText(nil)
        
        let descriptionField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        descriptionField.placeholderString = "Description (optional)"
        
        let stackView = NSStackView(views: [
            createLabel("Name:"),
            textField,
            createLabel("Description:"),
            descriptionField
        ])
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        
        alert.accessoryView = stackView
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        alert.window.makeFirstResponder(textField)
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let playlistName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let playlistDescription = descriptionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !playlistName.isEmpty {
                do {
                    let description = playlistDescription.isEmpty ? nil : playlistDescription
                    let _ = try PlaylistManager.shared.createPlaylist(
                        name: playlistName,
                        description: description
                    )
                    
                    showSimpleAlert(
                        title: "Playlist Created",
                        message: "Created playlist '\(playlistName)' successfully."
                    )
                    
                    NotificationManager.shared.postNotification(.playlistCreated, object: nil)
                    
                } catch {
                    showSimpleAlert(
                        title: "Creation Failed",
                        message: "Failed to create playlist: \(error.localizedDescription)"
                    )
                }
            } else {
                showSimpleAlert(
                    title: "Invalid Name",
                    message: "Please enter a valid playlist name."
                )
            }
        }
    }
    
    func showAddToPlaylistDialog(track: TrackMetadata, album: AlbumMetadata) {
        let playlists = PlaylistManager.shared.playlists
        
        if playlists.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Playlists Found"
            alert.informativeText = "No playlists exist. Create a new playlist for this track?"
            alert.addButton(withTitle: "Create Playlist")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                showCreatePlaylistWithTrackDialog(track: track, album: album)
            }
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Add Track to Playlist"
        alert.informativeText = "Select a playlist to add '\(track.name)' to:"
        
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        
        for playlist in playlists.sorted(by: { $0.name < $1.name }) {
            popup.addItem(withTitle: "\(playlist.name) (\(playlist.trackCount) tracks)")
        }
        
        alert.accessoryView = popup
        alert.addButton(withTitle: "Add to Playlist")
        alert.addButton(withTitle: "Create New Playlist")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            let selectedIndex = popup.indexOfSelectedItem
            let selectedPlaylist = playlists.sorted(by: { $0.name < $1.name })[selectedIndex]
            
            do {
                try PlaylistManager.shared.addTrackToPlaylist(track, from: album, to: selectedPlaylist.name)
                showSimpleAlert(title: "Track Added", message: "'\(track.name)' added to '\(selectedPlaylist.name)'.")
                NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
            } catch {
                showSimpleAlert(title: "Add Failed", message: "Failed to add track: \(error.localizedDescription)")
            }
            
        case .alertSecondButtonReturn:
            showCreatePlaylistWithTrackDialog(track: track, album: album)
            
        default:
            break
        }
    }
    
    private func showCreatePlaylistWithTrackDialog(track: TrackMetadata, album: AlbumMetadata) {
        let alert = NSAlert()
        alert.messageText = "Create New Playlist"
        alert.informativeText = "Enter a name for the new playlist:"
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "New Playlist"
        textField.selectText(nil)
        
        alert.accessoryView = textField
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        alert.window.makeFirstResponder(textField)
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let playlistName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !playlistName.isEmpty {
                do {
                    let _ = try PlaylistManager.shared.createPlaylist(name: playlistName)
                    NotificationManager.shared.postNotification(.playlistCreated, object: nil)
                    try PlaylistManager.shared.addTrackToPlaylist(track, from: album, to: playlistName)
                    showSimpleAlert(title: "Playlist Created",
                                  message: "Created '\(playlistName)' and added '\(track.name)'.")
                    NotificationManager.shared.postNotification(.playlistUpdated, object: nil)
                } catch {
                    showSimpleAlert(title: "Creation Failed",
                                  message: "Failed to create playlist: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.labelColor
        return label
    }
    
    private func showSimpleAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MenuBarManager+Refresh.swift
extension MenuBarManager {
    func addRefreshMenu(to menu: NSMenu) {
        let refreshMenu = NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "")
        let refreshSubmenu = NSMenu(title: "Refresh")
        
        let smartRefreshItem = NSMenuItem(
            title: "Refresh Current View",
            action: #selector(smartRefreshCurrentView),
            keyEquivalent: "r"
        )
        smartRefreshItem.target = self
        refreshSubmenu.addItem(smartRefreshItem)
        
        refreshSubmenu.addItem(NSMenuItem.separator())
        
        let fullRefreshItem = NSMenuItem(
            title: "Rebuild Entire Library",
            action: #selector(performFullLibraryRefresh),
            keyEquivalent: "R"
        )
        fullRefreshItem.keyEquivalentModifierMask = [.command, .shift]
        fullRefreshItem.target = self
        refreshSubmenu.addItem(fullRefreshItem)
        
        refreshMenu.submenu = refreshSubmenu
        menu.addItem(refreshMenu)
    }
    
    @objc private func smartRefreshCurrentView() {
        if let currentAlbum = AppState.shared.currentAlbum {
            SmartRefreshCoordinator.shared.requestRefresh(for: .album(name: currentAlbum.albumName))
        }
    }
    
    @objc private func performFullLibraryRefresh() {
        let alert = NSAlert()
        alert.messageText = "Rebuild Library?"
        alert.informativeText = "This will rescan all metadata and rebuild the entire library. This may take a moment for large libraries."
        alert.addButton(withTitle: "Rebuild")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            SmartRefreshCoordinator.shared.requestRefresh(for: .library)
        }
    }
}
