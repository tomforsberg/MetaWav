// UTType+Extensions.swift
import UniformTypeIdentifiers

extension UTType {
    static let metaAlbum = UTType(filenameExtension: "metaalbum")!
    static let metaAmp = UTType(filenameExtension: "metaamp")!
    static let lrc = UTType(filenameExtension: "lrc")!
    static let metaArtist = UTType(filenameExtension: "metaartist")!
}


// NSNotification+Extensions.swift
// Add this file to your project to define the missing notification names

import Foundation

extension NSNotification.Name {
    // Menu-triggered actions
    static let menuLoadFiles = NSNotification.Name("menuLoadFiles")
    static let togglePanels = NSNotification.Name("togglePanels")
    static let externalFilesOpened = NSNotification.Name("externalFilesOpened")
    
    // Track and library management
    static let trackRepathed = NSNotification.Name("trackRepathed")
    static let libraryDidUpdate = NSNotification.Name("libraryDidUpdate")
    
    // Player state changes
    static let playerStateChanged = NSNotification.Name("playerStateChanged")
    static let trackChanged = NSNotification.Name("trackChanged")
    
    // Playlist operations
    static let playlistCreated = NSNotification.Name("playlistCreated")
    static let playlistUpdated = NSNotification.Name("playlistUpdated")
    static let playlistDeleted = NSNotification.Name("playlistDeleted")
    
    // Album operations
    static let albumLoaded = NSNotification.Name("albumLoaded")
    static let albumUpdated = NSNotification.Name("albumUpdated")
    static let albumDeleted = NSNotification.Name("albumDeleted")
    
    // Track operations
    static let trackMetadataChanged = NSNotification.Name("trackMetadataChanged")
    
    // Artist operations
    static let artistUpdated = NSNotification.Name("artistUpdated")
    static let artistDeleted = NSNotification.Name("artistDeleted")
    
    // Settings changes
    static let settingsChanged = NSNotification.Name("settingsChanged")
    
    // Window management
    static let windowStateChanged = NSNotification.Name("windowStateChanged")
    
    // Global save action
    static let saveRequested = NSNotification.Name("saveRequested")
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}
