// ArtworkRebuilder.swift - Scans albums, relinks artwork, extracts embedded MP3 art
import Foundation
import AppKit
import AVFoundation

class ArtworkRebuilder: ObservableObject {
    static let shared = ArtworkRebuilder()
    
    @Published var logLines: [String] = []
    private var logWindowController: NSWindowController?
    
    private init() {}
    
    func rebuildAllArtwork() {
        logLines.removeAll()
        append("🖼️ Rebuild Artwork started: \(Date())")
        DispatchQueue.global(qos: .userInitiated).async {
            self.performRebuild()
            DispatchQueue.main.async {
                self.append("🖼️ Rebuild Artwork finished: \(Date())")
                self.showLogWindow()
            }
        }
    }
    
    private func performRebuild() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent("Documents/MetaWav")
        let metadataDir = base.appendingPathComponent("Metadata")
        guard fm.fileExists(atPath: metadataDir.path) else {
            append("No Metadata directory found; nothing to rebuild.")
            return
        }
        
        let albums = AlbumMetadataManager.shared.loadAllAlbums()
        append("Found \(albums.count) albums.")
        
        for album in albums {
            autoreleasepool {
                self.processAlbum(album, base: base)
            }
        }
    }
    
    private func processAlbum(_ album: AlbumMetadata, base: URL) {
        var updated = false
        let fm = FileManager.default
        let albumDir = base.appendingPathComponent(album.albumName)
        let artDir = albumDir.appendingPathComponent("Art")
        let audioDir = albumDir.appendingPathComponent("Audio")
        
        // Ensure Art directory exists if we'll write files
        func ensureArtDir() {
            if !fm.fileExists(atPath: artDir.path) {
                try? fm.createDirectory(at: artDir, withIntermediateDirectories: true)
            }
        }
        
        // 1) Try to relink from Art folder
        if album.frontArtPath == nil || !(album.frontArtPath?.isEmpty == false && fm.fileExists(atPath: album.frontArtPath!)) {
            if let path = findFirstImage(in: artDir) {
                var mutable = album
                mutable.frontArtPath = path
                if (try? AlbumMetadataManager.shared.saveAlbumMetadata(mutable)) != nil {
                    append("Linked front art for \(album.albumName) -> \(path)")
                    updated = true
                }
            }
        }
        if album.backArtPath == nil || !(album.backArtPath?.isEmpty == false && fm.fileExists(atPath: album.backArtPath!)) {
            // find second image if available
            if let path = findImage(in: artDir, skipFirst: true) {
                var mutable = album
                mutable.backArtPath = path
                if (try? AlbumMetadataManager.shared.saveAlbumMetadata(mutable)) != nil {
                    append("Linked back art for \(album.albumName) -> \(path)")
                    updated = true
                }
            }
        }
        
        // 2) If still missing, extract from MP3 embedded art in album's Audio folder
        if (album.frontArtPath == nil || !(album.frontArtPath?.isEmpty == false && fm.fileExists(atPath: album.frontArtPath!))) {
            if let image = extractEmbeddedArtFromFirstMP3(in: audioDir) {
                ensureArtDir()
                let outPath = artDir.appendingPathComponent("front.jpg")
                if save(image: image, to: outPath) {
                    var mutable = album
                    mutable.frontArtPath = outPath.path
                    if (try? AlbumMetadataManager.shared.saveAlbumMetadata(mutable)) != nil {
                        append("Extracted embedded front art for \(album.albumName) -> \(outPath.lastPathComponent)")
                        updated = true
                    }
                }
            }
        }
        
        // 3) If album Audio folder lacked MP3 or no artwork, try embedded art from album's track file paths
        if (updated == false) && (album.frontArtPath == nil || !(album.frontArtPath?.isEmpty == false && fm.fileExists(atPath: album.frontArtPath!))) {
            if let image = extractEmbeddedArtFromAlbumTracks(album) {
                ensureArtDir()
                let outPath = artDir.appendingPathComponent("front.jpg")
                if save(image: image, to: outPath) {
                    var mutable = album
                    mutable.frontArtPath = outPath.path
                    if (try? AlbumMetadataManager.shared.saveAlbumMetadata(mutable)) != nil {
                        append("Extracted embedded front art from tracks for \(album.albumName) -> \(outPath.lastPathComponent)")
                        updated = true
                    }
                }
            }
        }
        
        if updated == false {
            append("No changes for \(album.albumName)")
        }
    }
    
    private func findFirstImage(in dir: URL) -> String? {
        return findImage(in: dir, skipFirst: false)
    }
    
    private func findImage(in dir: URL, skipFirst: Bool) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path), let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let images = items.filter { ["jpg","jpeg","png","tif","tiff"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if images.isEmpty { return nil }
        if skipFirst {
            return images.count > 1 ? images[1].path : nil
        } else {
            return images[0].path
        }
    }
    
    private func extractEmbeddedArtFromFirstMP3(in dir: URL) -> NSImage? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path), let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        // Iterate all mp3s until we find artwork
        for file in items where file.pathExtension.lowercased() == "mp3" {
            if let img = extractEmbeddedArt(from: file) { return img }
        }
        return nil
    }
    
    private func extractEmbeddedArtFromAlbumTracks(_ album: AlbumMetadata) -> NSImage? {
        // Iterate MP3 tracks referenced by album metadata
        for track in album.tracks {
            let path = track.filePath
            guard path.lowercased().hasSuffix(".mp3") else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // Handle sandbox-scoped access if needed
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            if let img = extractEmbeddedArt(from: url) {
                return img
            }
        }
        return nil
    }
    
    // MARK: - Sync wrappers for modern AVFoundation metadata loading
    @available(macOS 13.0, *)
    private func loadCommonMetadataSync(_ asset: AVURLAsset) -> [AVMetadataItem]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [AVMetadataItem]?
        Task {
            result = try? await asset.load(.commonMetadata)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    @available(macOS 13.0, *)
    private func loadAvailableMetadataFormatsSync(_ asset: AVURLAsset) -> [AVMetadataFormat]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [AVMetadataFormat]?
        Task {
            result = try? await asset.load(.availableMetadataFormats)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    @available(macOS 13.0, *)
    private func loadMetadataSync(_ asset: AVURLAsset, for format: AVMetadataFormat) -> [AVMetadataItem]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [AVMetadataItem]?
        Task {
            result = try? await asset.loadMetadata(for: format)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    @available(macOS 13.0, *)
    private func loadDataValueSync(_ item: AVMetadataItem) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        Task {
            result = try? await item.load(.dataValue)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    private func extractEmbeddedArt(from url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        // Prefer modern AVFoundation metadata loading APIs while preserving sync behavior
        if #available(macOS 13.0, *) {
            // 1) Try common metadata for artwork
            if let common = loadCommonMetadataSync(asset) {
                for item in common {
                    if item.commonKey == .commonKeyArtwork,
                       let data = loadDataValueSync(item),
                       let img = NSImage(data: data) {
                        return img
                    }
                }
            }
            // 2) Try specific metadata formats
            if let formats = loadAvailableMetadataFormatsSync(asset) {
                for format in formats {
                    if let items = loadMetadataSync(asset, for: format) {
                        for item in items {
                            let id = item.identifier?.rawValue ?? ""
                            let wantedIds: Set<String> = [
                                AVMetadataIdentifier.id3MetadataAttachedPicture.rawValue,
                                AVMetadataIdentifier.iTunesMetadataCoverArt.rawValue,
                                AVMetadataIdentifier.commonIdentifierArtwork.rawValue
                            ]
                            if wantedIds.contains(id),
                               let data = loadDataValueSync(item),
                               let img = NSImage(data: data) {
                                return img
                            }
                            if item.commonKey == .commonKeyArtwork,
                               let data = loadDataValueSync(item),
                               let img = NSImage(data: data) {
                                return img
                            }
                        }
                    }
                }
            }
            return nil
        } else {
            // Fallback for older macOS
            // 1) Common artwork
            for item in asset.commonMetadata {
                if item.commonKey == .commonKeyArtwork, let data = item.dataValue, let img = NSImage(data: data) {
                    return img
                }
            }
            // 2) Known identifiers (ID3/iTunes)
            let wantedIds: Set<String> = [
                AVMetadataIdentifier.id3MetadataAttachedPicture.rawValue,
                AVMetadataIdentifier.iTunesMetadataCoverArt.rawValue,
                AVMetadataIdentifier.commonIdentifierArtwork.rawValue
            ]
            for format in asset.availableMetadataFormats {
                for item in asset.metadata(forFormat: format) {
                    let id = item.identifier?.rawValue ?? ""
                    if wantedIds.contains(id), let data = item.dataValue, let img = NSImage(data: data) {
                        return img
                    }
                    if item.commonKey == .commonKeyArtwork, let data = item.dataValue, let img = NSImage(data: data) {
                        return img
                    }
                }
            }
            return nil
        }
    }
    
    private func save(image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return false }
        do { try data.write(to: url); return true } catch { append("Failed to write image: \(error)"); return false }
    }
    
    private func append(_ line: String) {
        DispatchQueue.main.async { self.logLines.append(line) }
    }
    
    private func showLogWindow() {
        logWindowController?.close()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rebuild Artwork Log"
        window.center()
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        let controller = NSWindowController(window: window)
        logWindowController = controller
        let view = ArtworkRebuildLogView()
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        controller.showWindow(nil)
    }
}

import SwiftUI

struct ArtworkRebuildLogView: View {
    @ObservedObject private var manager = ArtworkRebuilder.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rebuild Artwork Log")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            ScrollView {
                Text(manager.logLines.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                    .background(Color.gray.opacity(0.10))
                    .cornerRadius(12)
            }
            HStack(spacing: 12) {
                Button("Rerun") { ArtworkRebuilder.shared.rebuildAllArtwork() }
                Button("Copy") {
                    let paste = NSPasteboard.general
                    paste.clearContents()
                    paste.setString(manager.logLines.joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Close") { NSApp.keyWindow?.close() }
            }
        }
        .padding(20)
        .background(Color.clear)
        .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}


