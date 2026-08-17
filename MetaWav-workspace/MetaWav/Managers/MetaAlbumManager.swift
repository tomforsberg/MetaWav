// MetaAlbumManager.swift - ENHANCED: Now includes Artist Profiles in MetaAlbums
import Foundation
import AppKit
import Compression
import AVFoundation

class MetaAlbumManager {
    static let shared = MetaAlbumManager()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Enhanced MetaAlbum Export (with Artist Profiles)
    
    func exportAlbum(_ album: AlbumMetadata, to destinationURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("📦 Starting Enhanced MetaAlbum export for: \(album.albumName)")
                if let albumType = album.albumType {
                    print("   Album Type: \(albumType)")
                }
                
                // Create temporary directory for building the MetaAlbum
                let tempDir = self.fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try self.fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // Create the Enhanced MetaAlbum structure
                let audioDir = tempDir.appendingPathComponent("Audio")
                let artDir = tempDir.appendingPathComponent("Art")
                let artistsDir = tempDir.appendingPathComponent("Artists") // NEW: Artists folder
                let relatedDir = tempDir.appendingPathComponent("Related") // NEW: Related files folder
                
                try self.fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
                try self.fileManager.createDirectory(at: artDir, withIntermediateDirectories: true)
                try self.fileManager.createDirectory(at: artistsDir, withIntermediateDirectories: true) // NEW
                try self.fileManager.createDirectory(at: relatedDir, withIntermediateDirectories: true) // NEW
                
                // Process album files and metadata
                let updatedAlbum = try self.processAlbumForExport(album, audioDir: audioDir, artDir: artDir, relatedDir: relatedDir)
                
                // NEW: Process and package artist profiles
                try self.processArtistsForExport(album, artistsDir: artistsDir)
                
                // Create metadata file (includes albumType and artist references)
                let sanitizedAlbumName = self.sanitizeFilename(album.albumName)
                let metaFileURL = tempDir.appendingPathComponent("\(sanitizedAlbumName).meta")
                try self.saveAlbumMetadata(updatedAlbum, to: metaFileURL)
                
                // NEW: Create artists manifest
                let artistsManifestURL = tempDir.appendingPathComponent("artists.manifest")
                try self.createArtistsManifest(for: album, to: artistsManifestURL)
                
                // Create the zip file (.metaalbum)
                try self.createMetaAlbumZip(from: tempDir, to: destinationURL)
                
                // Clean up temporary directory
                try self.fileManager.removeItem(at: tempDir)
                
                print("✅ Enhanced MetaAlbum export completed: \(destinationURL.path)")
                completion(.success(()))
                
            } catch {
                print("❌ Enhanced MetaAlbum export failed: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Enhanced MetaAlbum Import (with Artist Profiles)
    
    func importAlbum(from sourceURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("📥 Starting Enhanced MetaAlbum import from: \(sourceURL.path)")
                
                // Create temporary directory for extraction
                let tempDir = self.fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try self.fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // Extract the MetaAlbum zip
                try self.extractMetaAlbumZip(from: sourceURL, to: tempDir)
                
                // Load the metadata (support both album.meta and album-named .meta; handle nested root dir)
                let metaFileURL = try self.findMetadataFile(in: tempDir)
                let album = try self.loadAlbumMetadata(from: metaFileURL)
                let baseDir = metaFileURL.deletingLastPathComponent()
                
                print("📋 Imported album metadata:")
                print("   Name: \(album.albumName)")
                if let albumType = album.albumType {
                    print("   Type: \(albumType)")
                }
                print("   Genre: \(album.genre ?? "nil")")
                print("   Year: \(album.year ?? "nil")")
                print("   Tracks: \(album.trackCount)")
                print("   Discs: \(album.discCount)")
                
                // NEW: Import artist profiles first (before album processing)
                try self.processArtistsForImport(from: baseDir)
                
                // Create destination directories in MetaWav structure (moved under Library)
                let metaWavDir = self.fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Documents")
                    .appendingPathComponent("MetaWav")
                    .appendingPathComponent("Library")
                    .appendingPathComponent(self.sanitizeFilename(album.albumName))
                
                let destAudioDir = metaWavDir.appendingPathComponent("Audio")
                let destArtDir = metaWavDir.appendingPathComponent("Art")
                
                try self.fileManager.createDirectory(at: destAudioDir, withIntermediateDirectories: true)
                try self.fileManager.createDirectory(at: destArtDir, withIntermediateDirectories: true)
                
                // Move album files and update paths
                let finalAlbum = try self.processAlbumForImport(album, from: baseDir,
                                                              audioDir: destAudioDir, artDir: destArtDir)
                
                // Save the updated album metadata
                try AlbumMetadataManager.shared.saveAlbumMetadata(finalAlbum)
                
                // Clean up temporary directory
                try self.fileManager.removeItem(at: tempDir)
                
                print("✅ Enhanced MetaAlbum import completed: \(finalAlbum.albumName)")
                if let albumType = finalAlbum.albumType {
                    print("   Imported as: \(albumType)")
                }
                
                // NEW: Refresh artist manager to pick up imported artists
                ArtistManager.shared.discoverAndCreateArtists(from: [finalAlbum])
                
                completion(.success(finalAlbum.albumName))
                
            } catch {
                print("❌ Enhanced MetaAlbum import failed: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - NEW: Artist Profile Export Processing
    
    private func processArtistsForExport(_ album: AlbumMetadata, artistsDir: URL) throws {
        print("🎭 Processing artist profiles for export...")
        
        // Get all artists involved in this album (main + featured)
        let allArtistNames = self.getAllArtistsFromAlbum(album)
        print("   Found \(allArtistNames.count) unique artists: \(allArtistNames.joined(separator: ", "))")
        
        // Load artist profiles from ArtistManager
        let artistProfiles = ArtistManager.shared.artists.filter { artist in
            allArtistNames.contains(artist.name)
        }
        
        print("   Packaging \(artistProfiles.count) artist profiles")
        
        for artist in artistProfiles {
            try self.exportArtistProfile(artist, to: artistsDir)
        }
        
        print("✅ Artist profiles export completed")
    }
    
    private func exportArtistProfile(_ artist: ArtistProfile, to artistsDir: URL) throws {
        let sanitizedName = sanitizeFilename(artist.name)
        
        // Create artist profile file
        let artistFileURL = artistsDir.appendingPathComponent("\(sanitizedName).metaartist")
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(artist)
        try data.write(to: artistFileURL)
        
        print("  📄 Exported profile: \(artist.name)")
        
        // Copy artist profile image if it exists
        if let profileImagePath = artist.profileImagePath,
           self.fileManager.fileExists(atPath: profileImagePath) {
            
            let imageSource = URL(fileURLWithPath: profileImagePath)
            let imageFileName = "\(sanitizedName)_profile.\(imageSource.pathExtension)"
            let imageDest = artistsDir.appendingPathComponent(imageFileName)
            
            try self.fileManager.copyItem(at: imageSource, to: imageDest)
            print("  🖼️ Exported profile image: \(imageFileName)")
        }
    }
    
    private func getAllArtistsFromAlbum(_ album: AlbumMetadata) -> [String] {
        var allArtists = Set<String>()
        
        // Get main artists from tracks
        for track in album.tracks {
            if let artist = track.artist, !artist.isEmpty {
                allArtists.insert(artist)
            }
        }
        
        // Get featured artists from track credits
        for track in album.tracks {
            let featuredArtists = ArtistDetection.getFeaturedArtists(from: track)
            for featuredArtist in featuredArtists {
                allArtists.insert(featuredArtist)
            }
        }
        
        return Array(allArtists).sorted()
    }
    
    // MARK: - NEW: Artist Profile Import Processing
    
    private func processArtistsForImport(from baseDir: URL) throws {
        let artistsDir = baseDir.appendingPathComponent("Artists")
        
        // Check if this MetaAlbum has artist profiles
        guard self.fileManager.fileExists(atPath: artistsDir.path) else {
            print("ℹ️ No artist profiles found in MetaAlbum (older format)")
            return
        }
        
        print("🎭 Processing artist profiles for import...")
        
        let artistFiles = try self.fileManager.contentsOfDirectory(at: artistsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "metaartist" }
        
        print("   Found \(artistFiles.count) artist profiles to import")
        
        let existingArtists = ArtistManager.shared.artists
        var importedCount = 0
        var updatedCount = 0
        var skippedCount = 0
        
        for artistFileURL in artistFiles {
            do {
                let result = try self.importArtistProfile(from: artistFileURL, existingArtists: existingArtists, artistsDir: artistsDir)
                
                switch result {
                case .imported:
                    importedCount += 1
                case .updated:
                    updatedCount += 1
                case .skipped:
                    skippedCount += 1
                }
                
            } catch {
                print("  ⚠️ Failed to import artist from \(artistFileURL.lastPathComponent): \(error)")
            }
        }
        
        print("✅ Artist import completed:")
        print("   📥 Imported: \(importedCount) new artists")
        print("   🔄 Updated: \(updatedCount) existing artists")
        print("   ⏭️ Skipped: \(skippedCount) artists")
    }
    
    private func importArtistProfile(from artistFileURL: URL, existingArtists: [ArtistProfile], artistsDir: URL) throws -> ArtistImportResult {
        
        // Load artist profile from MetaAlbum
        let data = try Data(contentsOf: artistFileURL)
        let importedArtist = try PropertyListDecoder().decode(ArtistProfile.self, from: data)
        
        let artistName = importedArtist.name
        print("  🎤 Processing artist: \(artistName)")
        
        // Check if artist already exists
        if let existingArtist = existingArtists.first(where: { $0.name == artistName }) {
            // Ask user whether to overwrite existing artist info
            let overwrite = self.askUserShouldOverwriteArtist(existing: existingArtist, imported: importedArtist)
            if overwrite {
                // Overwrite with imported (with image import handling)
                try self.saveImportedArtist(importedArtist, from: artistsDir)
                print("    🔄 Overwrote existing artist profile")
                return .updated
            } else {
                print("    ⏭️ Skipped (user kept existing profile)")
                return .skipped
            }
        } else {
            // New artist - import directly
            try self.saveImportedArtist(importedArtist, from: artistsDir)
            print("    📥 Imported new artist profile")
            return .imported
        }
    }

    private func askUserShouldOverwriteArtist(existing: ArtistProfile, imported: ArtistProfile) -> Bool {
        var userChoice: Bool = false
        DispatchQueue.main.sync {
            let alert = NSAlert()
            alert.messageText = "Artist Already Exists"
            alert.informativeText = "Artist '\(existing.name)' already exists. Overwrite existing artist info with the imported profile?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Skip")
            let response = alert.runModal()
            userChoice = (response == .alertFirstButtonReturn)
        }
        return userChoice
    }
    
    private func shouldUpdateExistingArtist(existing: ArtistProfile, imported: ArtistProfile) throws -> Bool {
        // Update if imported profile has more complete information
        let importedHasBio = imported.bio != nil && !imported.bio!.isEmpty
        let existingHasBio = existing.bio != nil && !existing.bio!.isEmpty
        
        let importedHasImage = imported.profileImagePath != nil
        let existingHasImage = existing.profileImagePath != nil
        
        let importedHasMoreRoles = imported.roles.count > existing.roles.count
        
        // Update if imported has bio and existing doesn't, or has image and existing doesn't, or has more roles
        return (importedHasBio && !existingHasBio) ||
               (importedHasImage && !existingHasImage) ||
               importedHasMoreRoles
    }
    
    private func mergeArtistProfiles(existing: ArtistProfile, imported: ArtistProfile) -> ArtistProfile {
        var merged = existing
        
        // Use imported bio if it's more complete
        if let importedBio = imported.bio, !importedBio.isEmpty,
           (existing.bio == nil || existing.bio!.isEmpty) {
            merged.bio = importedBio
        }
        
        // Merge roles (combine unique roles)
        let combinedRoles = Array(Set(existing.roles + imported.roles)).sorted()
        merged.roles = combinedRoles
        
        // Use imported profile image if existing doesn't have one
        if imported.profileImagePath != nil && existing.profileImagePath == nil {
            merged.profileImagePath = imported.profileImagePath
        }
        
        return merged
    }
    
    private func saveImportedArtist(_ artist: ArtistProfile, from artistsDir: URL) throws {
        // Handle profile image import
        let sanitizedName = sanitizeFilename(artist.name)
        
        // Look for profile image in the Artists folder
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff"]
        var importedImagePath: String?
        
        for ext in imageExtensions {
            let imageFileName = "\(sanitizedName)_profile.\(ext)"
            let imageURL = artistsDir.appendingPathComponent(imageFileName)
            
            if self.fileManager.fileExists(atPath: imageURL.path) {
                // Copy image to MetaWav Artists directory
                let destPath = try self.importArtistProfileImage(from: imageURL, artistName: artist.name)
                importedImagePath = destPath
                break
            }
        }
        
        // Update artist profile with imported image path
        var updatedArtist = artist
        if let imagePath = importedImagePath {
            updatedArtist.profileImagePath = imagePath
        }
        
        // Save artist profile using ArtistManager
        ArtistManager.shared.saveArtistProfile(updatedArtist)
    }
    
    private func importArtistProfileImage(from sourceURL: URL, artistName: String) throws -> String {
        // Create MetaWav Artists directory structure
        let userHome = self.fileManager.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
        
        let artistsDir = metaWavDir.appendingPathComponent("Artists")
        try self.fileManager.createDirectory(at: artistsDir, withIntermediateDirectories: true)
        
        // Copy image file
        let sanitizedName = sanitizeFilename(artistName)
        let destFileName = "\(sanitizedName)_profile.\(sourceURL.pathExtension)"
        let destURL = artistsDir.appendingPathComponent(destFileName)
        
        // Remove existing image if present
        if self.fileManager.fileExists(atPath: destURL.path) {
            try self.fileManager.removeItem(at: destURL)
        }
        
        try self.fileManager.copyItem(at: sourceURL, to: destURL)
        print("    🖼️ Imported profile image: \(destFileName)")
        
        return destURL.path
    }
    
    // MARK: - NEW: Artists Manifest Creation
    
    private func createArtistsManifest(for album: AlbumMetadata, to url: URL) throws {
        let allArtists = getAllArtistsFromAlbum(album)
        
        let manifest: [String: Any] = [
            "version": "1.0",
            "album": album.albumName,
            "artists": allArtists,
            "exported_date": Date().timeIntervalSince1970,
            "exported_by": "MetaWav Enhanced MetaAlbum"
        ]
        
        let data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        try data.write(to: url)
        
        print("📋 Created artists manifest with \(allArtists.count) artists")
    }
    
    // MARK: - Existing Methods (unchanged but enhanced logging)
    
    private func processAlbumForExport(_ album: AlbumMetadata, audioDir: URL, artDir: URL, relatedDir: URL) throws -> AlbumMetadata {
        var updatedAlbum = album
        var updatedTracks: [TrackMetadata] = []
        
        print("🎵 Processing \(album.tracks.count) tracks for export...")
        
        // Process tracks
        for (_, track) in album.tracks.enumerated() {
            var updatedTrack = track
            
            let sourceURL = URL(fileURLWithPath: track.filePath)
            let filename = sourceURL.lastPathComponent
            let destURL = audioDir.appendingPathComponent(filename)
            
            // Check if source file exists and is accessible
            guard self.fileManager.fileExists(atPath: sourceURL.path) else {
                throw MetaAlbumError.missingAudioFile(track.filePath)
            }
            
            guard sourceURL.startAccessingSecurityScopedResource() else {
                throw MetaAlbumError.fileAccessDenied(track.filePath)
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            
            // Copy audio file
            try self.fileManager.copyItem(at: sourceURL, to: destURL)
            
            // Update track path to relative path within MetaAlbum
            updatedTrack.filePath = "Audio/\(filename)"

            // Copy related files if any
            if let relatedFiles = track.relatedFiles, !relatedFiles.isEmpty {
                var updatedRelated: [TrackMetadata.RelatedFile] = []
                for rf in relatedFiles {
                    let rfSource = URL(fileURLWithPath: rf.filePath)
                    if !self.fileManager.fileExists(atPath: rfSource.path) {
                        print("  ⚠️ Related file not found, skipping: \(rf.filePath)")
                        updatedRelated.append(rf)
                        continue
                    }
                    let preferredName = rfSource.lastPathComponent
                    let rfDest = self.uniqueDestinationURL(in: relatedDir, preferredFileName: preferredName)
                    try self.fileManager.copyItem(at: rfSource, to: rfDest)
                    var rfUpdated = rf
                    rfUpdated.filePath = "Related/\(rfDest.lastPathComponent)"
                    updatedRelated.append(rfUpdated)
                    print("  📎 Copied related: \(preferredName) → \(rfDest.lastPathComponent)")
                }
                updatedTrack.relatedFiles = updatedRelated
            }

            updatedTracks.append(updatedTrack)
            
            print("  ✅ Copied: \(filename)")
        }
        
        updatedAlbum.tracks = updatedTracks
        
        // Process artwork
        if let frontArtPath = album.frontArtPath,
           self.fileManager.fileExists(atPath: frontArtPath) {
            let artSource = URL(fileURLWithPath: frontArtPath)
            let artFilename = artSource.lastPathComponent
            let artDest = artDir.appendingPathComponent(artFilename)
            
            try self.fileManager.copyItem(at: artSource, to: artDest)
            updatedAlbum.frontArtPath = "Art/\(artFilename)"
            print("  🎨 Copied front art: \(artFilename)")
        }
        
        if let backArtPath = album.backArtPath,
           self.fileManager.fileExists(atPath: backArtPath) {
            let artSource = URL(fileURLWithPath: backArtPath)
            let artFilename = artSource.lastPathComponent
            let artDest = artDir.appendingPathComponent(artFilename)
            
            try self.fileManager.copyItem(at: artSource, to: artDest)
            updatedAlbum.backArtPath = "Art/\(artFilename)"
            print("  🎨 Copied back art: \(artFilename)")
        }
        
        return updatedAlbum
    }
    
    private func processAlbumForImport(_ album: AlbumMetadata, from baseDir: URL,
                                     audioDir: URL, artDir: URL) throws -> AlbumMetadata {
        var updatedAlbum = album
        var updatedTracks: [TrackMetadata] = []
        
        print("🎵 Processing \(album.tracks.count) tracks for import...")
        
        // Process tracks
        for track in album.tracks {
            var updatedTrack = track
            
            // Source file in extracted base directory (using relative path from MetaAlbum)
            let tempAudioURL = baseDir.appendingPathComponent(track.filePath)
            
            guard self.fileManager.fileExists(atPath: tempAudioURL.path) else {
                throw MetaAlbumError.missingAudioFile(track.filePath)
            }
            
            // Destination file in MetaWav directory
            let filename = tempAudioURL.lastPathComponent
            let destAudioURL = audioDir.appendingPathComponent(filename)
            
            // Move audio file to final location
            try self.fileManager.moveItem(at: tempAudioURL, to: destAudioURL)
            
            // Update track path to absolute path
            updatedTrack.filePath = destAudioURL.path

            // Move related files if present
            if let relatedFiles = track.relatedFiles, !relatedFiles.isEmpty {
                let relatedSrcDir = baseDir.appendingPathComponent("Related")
                // Create destination Related folder next to Audio/Art
                let destRelatedDir = audioDir.deletingLastPathComponent().appendingPathComponent("Related")
                try self.fileManager.createDirectory(at: destRelatedDir, withIntermediateDirectories: true)

                var updatedRelated: [TrackMetadata.RelatedFile] = []
                for rf in relatedFiles {
                    let srcPath = rf.filePath.hasPrefix("Related/") ? String(rf.filePath.dropFirst("Related/".count)) : URL(fileURLWithPath: rf.filePath).lastPathComponent
                    let srcURL = rf.filePath.hasPrefix("Related/") ? relatedSrcDir.appendingPathComponent(srcPath) : baseDir.appendingPathComponent("Related").appendingPathComponent(srcPath)
                    if !self.fileManager.fileExists(atPath: srcURL.path) {
                        print("  ⚠️ Related file missing in package, keeping original path: \(rf.filePath)")
                        updatedRelated.append(rf)
                        continue
                    }
                    let destURL = self.uniqueDestinationURL(in: destRelatedDir, preferredFileName: srcURL.lastPathComponent)
                    try self.fileManager.moveItem(at: srcURL, to: destURL)
                    var rfUpdated = rf
                    rfUpdated.filePath = destURL.path
                    updatedRelated.append(rfUpdated)
                    print("  📎 Moved related: \(srcURL.lastPathComponent) → \(destURL.lastPathComponent)")
                }
                updatedTrack.relatedFiles = updatedRelated
            }

            updatedTracks.append(updatedTrack)
            
            print("  ✅ Moved: \(filename)")
        }
        
        updatedAlbum.tracks = updatedTracks
        
        // Process artwork
        if let frontArtPath = album.frontArtPath {
            let tempArtURL = baseDir.appendingPathComponent(frontArtPath)
            if self.fileManager.fileExists(atPath: tempArtURL.path) {
                let artFilename = tempArtURL.lastPathComponent
                let destArtURL = artDir.appendingPathComponent(artFilename)
                
                try self.fileManager.moveItem(at: tempArtURL, to: destArtURL)
                updatedAlbum.frontArtPath = destArtURL.path
                print("  🎨 Moved front art: \(artFilename)")
            }
        }
        
        if let backArtPath = album.backArtPath {
            let tempArtURL = baseDir.appendingPathComponent(backArtPath)
            if self.fileManager.fileExists(atPath: tempArtURL.path) {
                let artFilename = tempArtURL.lastPathComponent
                let destArtURL = artDir.appendingPathComponent(artFilename)
                
                try self.fileManager.moveItem(at: tempArtURL, to: destArtURL)
                updatedAlbum.backArtPath = destArtURL.path
                print("  🎨 Moved back art: \(artFilename)")
            }
        }
        
        return updatedAlbum
    }
    
    // MARK: - Zip Operations (unchanged)
    
    private func createMetaAlbumZip(from sourceDir: URL, to destinationURL: URL) throws {
        print("🗜️ Creating Enhanced MetaAlbum zip file...")
        
        // Use NSTask to call the system zip command for reliability
        let task = Process()
        task.launchPath = "/usr/bin/zip"
        task.arguments = ["-r", destinationURL.path, "."]
        task.currentDirectoryPath = sourceDir.path
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MetaAlbumError.zipCreationFailed(output)
        }
        
        print("✅ Enhanced MetaAlbum zip created successfully")
    }
    
    private func extractMetaAlbumZip(from sourceURL: URL, to destinationDir: URL) throws {
        print("📂 Extracting Enhanced MetaAlbum zip file...")
        
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw MetaAlbumError.fileAccessDenied(sourceURL.path)
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        
        // Use NSTask to call the system unzip command for reliability
        let task = Process()
        task.launchPath = "/usr/bin/unzip"
        task.arguments = ["-q", sourceURL.path, "-d", destinationDir.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MetaAlbumError.zipExtractionFailed(output)
        }
        
        print("✅ Enhanced MetaAlbum zip extracted successfully")
    }
    
    // MARK: - Metadata Operations (unchanged)
    
    private func saveAlbumMetadata(_ album: AlbumMetadata, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(album)
        try data.write(to: url, options: [.atomic])
        
        print("💾 Saved album metadata to MetaAlbum")
        print("   Album: \(album.albumName)")
        if let albumType = album.albumType {
            print("   Type: \(albumType)")
        }
        print("   Genre: \(album.genre ?? "nil")")
        print("   Year: \(album.year ?? "nil")")
        print("   Tracks: \(album.trackCount)")
        print("   Discs: \(album.discCount)")
    }
    
    private func loadAlbumMetadata(from url: URL) throws -> AlbumMetadata {
        let data = try Data(contentsOf: url)
        let album = try PropertyListDecoder().decode(AlbumMetadata.self, from: data)
        
        print("📖 Loaded album metadata from MetaAlbum: \(album.albumName)")
        if let albumType = album.albumType {
            print("   Type: \(albumType)")
        }
        
        return album
    }
    
    // MARK: - Helper Methods
    
    private func findMetadataFile(in directory: URL) throws -> URL {
        // 1) Look in the provided directory (non-recursive)
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let metaFiles = files.filter { $0.pathExtension == "meta" }
        let namedMetaFiles = metaFiles.filter { $0.lastPathComponent != "album.meta" }
        if let namedMetaFile = namedMetaFiles.first {
            print("📖 Found album-named metadata file: \(namedMetaFile.lastPathComponent)")
            return namedMetaFile
        }
        let genericMetaFile = directory.appendingPathComponent("album.meta")
        if fileManager.fileExists(atPath: genericMetaFile.path) {
            print("📖 Using generic metadata file for backward compatibility")
            return genericMetaFile
        }

        // 2) If not found, try immediate subdirectories (common case: a single root folder in the zip)
        let subdirs = files.filter { url in
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        for subdir in subdirs {
            // Try non-recursive in the subdir first
            let subFiles = try fileManager.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil)
            let subMetaFiles = subFiles.filter { $0.pathExtension == "meta" }
            let subNamed = subMetaFiles.filter { $0.lastPathComponent != "album.meta" }
            if let found = subNamed.first ?? subMetaFiles.first {
                print("📖 Found metadata file in subdirectory: \(found.path)")
                return found
            }
        }

        // 3) Last resort: recursive search for any .meta file
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            var genericCandidate: URL?
            for case let url as URL in enumerator {
                if url.pathExtension == "meta" {
                    if url.lastPathComponent != "album.meta" {
                        print("📖 Found metadata file via recursive scan: \(url.path)")
                        return url
                    } else if genericCandidate == nil {
                        genericCandidate = url
                    }
                }
            }
            if let generic = genericCandidate {
                print("📖 Using generic metadata via recursive scan: \(generic.path)")
                return generic
            }
        }

        throw MetaAlbumError.invalidMetaAlbum("No metadata file found (.meta)")
    }
    
    // Ensure a unique destination URL by appending a numeric suffix when necessary
    private func uniqueDestinationURL(in directory: URL, preferredFileName: String) -> URL {
        let baseName = URL(fileURLWithPath: preferredFileName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: preferredFileName).pathExtension
        var candidate = directory.appendingPathComponent(preferredFileName)
        var index = 1
        while self.fileManager.fileExists(atPath: candidate.path) {
            let name = "\(baseName) (\(index))"
            candidate = directory.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
            index += 1
        }
        return candidate
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    // MARK: - Enhanced Validation
    
    func validateEnhancedMetaAlbum(at url: URL) throws -> (album: AlbumMetadata, artistCount: Int) {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Extract and validate structure
        try extractMetaAlbumZip(from: url, to: tempDir)
        
        let metaFile = try findMetadataFile(in: tempDir)
        let album = try loadAlbumMetadata(from: metaFile)
        
        // Validate that referenced files exist
        for track in album.tracks {
            let trackURL = tempDir.appendingPathComponent(track.filePath)
            guard fileManager.fileExists(atPath: trackURL.path) else {
                throw MetaAlbumError.invalidMetaAlbum("Missing audio file: \(track.filePath)")
            }
            if let relatedFiles = track.relatedFiles {
                for rf in relatedFiles {
                    // Allow both packaged-relative and absolute legacy paths
                    if rf.filePath.hasPrefix("Related/") {
                        let rfURL = tempDir.appendingPathComponent(rf.filePath)
                        guard fileManager.fileExists(atPath: rfURL.path) else {
                            throw MetaAlbumError.invalidMetaAlbum("Missing related file: \(rf.filePath)")
                        }
                    }
                }
            }
        }
        
        // Check for artist profiles (optional for backward compatibility)
        let artistsDir = tempDir.appendingPathComponent("Artists")
        var artistCount = 0
        
        if fileManager.fileExists(atPath: artistsDir.path) {
            let artistFiles = try fileManager.contentsOfDirectory(at: artistsDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "metaartist" }
            artistCount = artistFiles.count
        }
        
        // Log validation results
        print("✅ Enhanced MetaAlbum validation successful:")
        print("   Album: \(album.albumName)")
        if let albumType = album.albumType {
            print("   Type: \(albumType)")
        }
        print("   Tracks: \(album.trackCount)")
        print("   Discs: \(album.discCount)")
        print("   Artists: \(artistCount) profiles")
        
        return (album: album, artistCount: artistCount)
    }
}

// MARK: - Enhanced Error Types

enum MetaAlbumError: LocalizedError {
    case missingAudioFile(String)
    case fileAccessDenied(String)
    case zipCreationFailed(String)
    case zipExtractionFailed(String)
    case invalidMetaAlbum(String)
    case directoryCreationFailed(String)
    case artistImportFailed(String) // NEW
    
    var errorDescription: String? {
        switch self {
        case .missingAudioFile(let path):
            return "Audio file not found: \(path)"
        case .fileAccessDenied(let path):
            return "Cannot access file: \(path)"
        case .zipCreationFailed(let details):
            return "Failed to create MetaAlbum zip: \(details)"
        case .zipExtractionFailed(let details):
            return "Failed to extract MetaAlbum: \(details)"
        case .invalidMetaAlbum(let reason):
            return "Invalid MetaAlbum file: \(reason)"
        case .directoryCreationFailed(let path):
            return "Failed to create directory: \(path)"
        case .artistImportFailed(let details):
            return "Failed to import artist profiles: \(details)"
        }
    }
}

// MARK: - NEW: Artist Import Result

enum ArtistImportResult {
    case imported   // New artist was imported
    case updated    // Existing artist was updated
    case skipped    // Existing artist was kept unchanged
}

// MARK: - Enhanced AlbumMetadataManager Extensions (unchanged)

extension AlbumMetadataManager {
    
    /// Get front artwork path - always reads from .meta file first, falls back to searching Art directory
    func getFrontArtworkPath(for albumName: String) -> String? {
        // PRIMARY: Read path from .meta file (source of truth)
        if let album = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumName),
           let frontPath = album.frontArtPath,
           FileManager.default.fileExists(atPath: frontPath) {
            return frontPath
        }
        
        // FALLBACK: Search Art directory if .meta file doesn't have path or file doesn't exist
        let sanitizedName = sanitizeFilenamePublic(albumName)
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let artDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Art")
        
        let extensions = ["jpg", "jpeg", "png", "gif"]
        for ext in extensions {
            let artPath = artDir.appendingPathComponent("\(sanitizedName)_cover.\(ext)").path
            if FileManager.default.fileExists(atPath: artPath) {
                return artPath
            }
        }
        return nil
    }
    
    /// Get back artwork path - always reads from .meta file first, falls back to searching Art directory
    func getBackArtworkPath(for albumName: String) -> String? {
        // PRIMARY: Read path from .meta file (source of truth)
        if let album = AlbumMetadataManager.shared.loadAlbumMetadata(albumName: albumName),
           let backPath = album.backArtPath,
           FileManager.default.fileExists(atPath: backPath) {
            return backPath
        }
        
        // FALLBACK: Search Art directory if .meta file doesn't have path or file doesn't exist
        let sanitizedName = sanitizeFilenamePublic(albumName)
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let artDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Art")
        
        let extensions = ["jpg", "jpeg", "png", "gif"]
        for ext in extensions {
            let artPath = artDir.appendingPathComponent("\(sanitizedName)_back.\(ext)").path
            if FileManager.default.fileExists(atPath: artPath) {
                return artPath
            }
        }
        return nil
    }
    
    // Helper method for the extension
    private func sanitizeFilenamePublic(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}
