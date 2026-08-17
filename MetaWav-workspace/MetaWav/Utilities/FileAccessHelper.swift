import Foundation
import AppKit

class FileAccessHelper {
    static func requestFolderAccess(for url: URL, completion: @escaping (Bool) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.message = "Please select the folder to grant write access"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = url.deletingLastPathComponent()
        
        openPanel.begin { response in
            DispatchQueue.main.async {
                completion(response == .OK)
            }
        }
    }
    
    static func saveMetadata(for audioFileURL: URL, metadata: [String: Any]) -> Bool {
        // Option 1: Save in app's Application Support directory (recommended)
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ Can't access Application Support directory")
            return false
        }
        
        let appMetadataDir = appSupportURL.appendingPathComponent("MetaWav/Metadata")
        
        do {
            try FileManager.default.createDirectory(at: appMetadataDir, withIntermediateDirectories: true)
            
            // Create a unique filename based on the audio file
            let filename = audioFileURL.lastPathComponent + ".meta"
            let metadataURL = appMetadataDir.appendingPathComponent(filename)
            
            let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            try data.write(to: metadataURL)
            print("✅ Metadata saved to: \(metadataURL.path)")
            return true
        } catch {
            print("❌ Failed to save metadata: \(error)")
            return false
        }
    }
    
    static func saveMetadataInSameFolder(for audioFileURL: URL, metadata: [String: Any]) -> Bool {
        let metadataURL = audioFileURL.appendingPathExtension("meta")
        
        // Check if we can access the parent directory
        let parentURL = metadataURL.deletingLastPathComponent()
        guard parentURL.startAccessingSecurityScopedResource() else {
            print("❌ No access to parent directory")
            return false
        }
        defer { parentURL.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            try data.write(to: metadataURL)
            print("✅ Metadata saved to: \(metadataURL.path)")
            return true
        } catch {
            print("❌ Failed to save metadata: \(error)")
            return false
        }
    }
}
