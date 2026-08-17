import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import MediaPlayer

class AppDelegate: NSObject, NSApplicationDelegate {
    // Track the primary SwiftUI window so we can reliably reuse it
    weak var mainWindow: NSWindow?
    
    func registerMainWindow(_ window: NSWindow) {
        // Only capture the first main window; ignore any secondary ones
        if mainWindow == nil {
            mainWindow = window
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 App finished launching")
        // Force app-wide dark appearance regardless of system setting
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Initialize Now Playing / Remote Command handling early so F7/F8/F9 work globally
        // MPRemoteCommandCenter: https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
        // MPNowPlayingInfoCenter: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
        _ = NowPlayingManager.shared
        
        // Wire MPRemoteCommandCenter handlers to the core playback engine so they work even
        // when the transport UI hasn't been created yet. This follows Apple's guidance to
        // use MPRemoteCommandCenter instead of NSEvent for media keys.
        // Media Player overview: https://developer.apple.com/documentation/mediaplayer
        do {
            let np = NowPlayingManager.shared
            let qm = QueueManager.shared
            let ap = AudioProcessor.shared
            
            np.onPlayCommand = {
                // Mirror TransportControls UI behavior: animate + sound
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .init("MetaWav.Transport.PlayPressedAnimation"), object: nil)
                }
                if ap.duration > 0 {
                    if !ap.isPlaying {
                        ap.play()
                        np.setPlaybackState(isPlaying: true)
                    }
                } else if !qm.isQueueEmpty {
                    qm.playCurrentTrack()
                    if let item = qm.currentItem {
                        var artwork: MPMediaItemArtwork?
                        if let album = item.album, let artPath = album.frontArtPath {
                            artwork = np.createArtwork(from: artPath)
                        }
                        np.updateNowPlayingInfo(
                            title: item.displayName,
                            artist: item.artistName,
                            album: item.album?.albumName,
                            duration: ap.duration,
                            currentTime: ap.currentTime,
                            playbackRate: 1.0,
                            artwork: artwork
                        )
                    }
                }
            }
            
            np.onPauseCommand = {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .init("MetaWav.Transport.PausePressedAnimation"), object: nil)
                }
                if ap.isPlaying {
                    ap.pause()
                    np.setPlaybackState(isPlaying: false)
                }
            }
            
            np.onNextCommand = {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .init("MetaWav.Transport.NextPressedAnimation"), object: nil)
                }
                qm.nextTrack()
                if let item = qm.currentItem {
                    var artwork: MPMediaItemArtwork?
                    if let album = item.album, let artPath = album.frontArtPath {
                        artwork = np.createArtwork(from: artPath)
                    }
                    np.updateNowPlayingInfo(
                        title: item.displayName,
                        artist: item.artistName,
                        album: item.album?.albumName,
                        duration: ap.duration,
                        currentTime: ap.currentTime,
                        playbackRate: ap.isPlaying ? 1.0 : 0.0,
                        artwork: artwork
                    )
                }
            }
            
            np.onPreviousCommand = {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .init("MetaWav.Transport.PreviousPressedAnimation"), object: nil)
                }
                qm.previousTrack()
                if let item = qm.currentItem {
                    var artwork: MPMediaItemArtwork?
                    if let album = item.album, let artPath = album.frontArtPath {
                        artwork = np.createArtwork(from: artPath)
                    }
                    np.updateNowPlayingInfo(
                        title: item.displayName,
                        artist: item.artistName,
                        album: item.album?.albumName,
                        duration: ap.duration,
                        currentTime: ap.currentTime,
                        playbackRate: ap.isPlaying ? 1.0 : 0.0,
                        artwork: artwork
                    )
                }
            }
            
            np.onStopCommand = {
                qm.stopPlayback()
                np.clearNowPlayingInfo()
            }
            
            np.onChangePlaybackPosition = { newTime in
                ap.seek(to: newTime)
                np.updateElapsedTime(newTime)
            }
        }
        
        // Kick off artist profile maintenance cleanup on startup (non-blocking)
        DispatchQueue.global(qos: .utility).async {
            do {
                try AlbumMetadataManager.shared.performArtistMaintenanceCleanup()
                try AlbumMetadataManager.shared.cleanupOrphanedMetaArtistFiles()
            } catch {
                print("⚠️ Artist cleanup failed on startup: \(error)")
            }
        }

        // Configure window with proper constraints
        DispatchQueue.main.async {
            let targetWindow = self.mainWindow ?? NSApplication.shared.windows.first
            if let window = targetWindow {
                self.mainWindow = window
                WindowManager.shared.configureWindow(for: window)
                window.setFrameAutosaveName("")
                window.center()
                // Ensure the window also uses dark appearance
                window.appearance = NSAppearance(named: .darkAqua)
                print("🔧 Window configured with size constraints")
            } else {
                print("❌ No main window found during didFinishLaunching")
            }
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        print("🔥 App will finish launching")
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        print("✨ App became active - ensuring menu is correct")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Prefer an existing tracked main window (or any existing app window) to avoid extra SwiftUI scenes
        if let existing = mainWindow ?? sender.windows.first {
            mainWindow = existing
            NSApp.activate(ignoringOtherApps: true)
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
            WindowManager.shared.configureWindow(for: existing)
            // We handled reopen ourselves – tell the system not to create a new WindowGroup window
            return false
        }
        
        // If there are *no* windows at all (e.g. user closed the main window),
        // return true so SwiftUI is allowed to create a fresh WindowGroup scene.
        print("❗️applicationShouldHandleReopen: No existing window – allowing system to create a new one")
        return true
    }
    
    // NEW: Handle window focus changes
    func applicationWillBecomeActive(_ notification: Notification) {
        // Validate window constraints when app becomes active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // WindowManager.shared.validateWindowSize()
            print("🎯 App active")
        }
    }

    // MARK: - Handle files opened from Finder / Dock / Drag-onto-app
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .externalFilesOpened, object: [url])
        }
        return true
    }

    func application(_ app: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .externalFilesOpened, object: urls)
        }
        app.reply(toOpenOrPrint: .success)
    }
}


// MARK: - User Preferences Manager (Simplified Single File)
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    private let eulaAcceptedKey = "EULA_Accepted"
    private let eulaVersionKey = "EULA_Version"
    private let currentEULAVersion = "1.0"
    
    @Published var hasAcceptedEULA: Bool = false
    
    private init() {
        checkEULAStatus()
    }
    
    private var eulaFileURL: URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Info")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: metaWavDir.path) {
            do {
                try FileManager.default.createDirectory(at: metaWavDir, withIntermediateDirectories: true)
                print("📁 Created MetaWav/Info directory")
            } catch {
                print("❌ Failed to create MetaWav/Info directory: \(error)")
            }
        }
        
        return metaWavDir.appendingPathComponent("EULA.plist")
    }
    
    private func checkEULAStatus() {
        guard FileManager.default.fileExists(atPath: eulaFileURL.path) else {
            print("📋 No EULA.plist found - first launch")
            hasAcceptedEULA = false
            return
        }
        
        do {
            let data = try Data(contentsOf: eulaFileURL)
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
            
            let accepted = plist[eulaAcceptedKey] as? Bool ?? false
            let version = plist[eulaVersionKey] as? String ?? ""
            
            // Check if EULA is accepted AND version is current
            hasAcceptedEULA = accepted && version == currentEULAVersion
            
            print("📋 EULA Status - Accepted: \(accepted), Version: \(version), Current: \(hasAcceptedEULA)")
        } catch {
            print("❌ Failed to read EULA.plist: \(error)")
            hasAcceptedEULA = false
        }
    }
    
    func acceptEULA() {
        let preferences: [String: Any] = [
            eulaAcceptedKey: true,
            eulaVersionKey: currentEULAVersion,
            "acceptedDate": Date().timeIntervalSince1970
        ]
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
            try data.write(to: eulaFileURL)
            hasAcceptedEULA = true
            print("✅ EULA accepted and saved to: \(eulaFileURL.path)")
        } catch {
            print("❌ Failed to save EULA acceptance: \(error)")
        }
    }
    
    func resetEULA() {
        do {
            try FileManager.default.removeItem(at: eulaFileURL)
            hasAcceptedEULA = false
            print("🔄 EULA.plist deleted and status reset")
        } catch {
            print("❌ Failed to delete EULA.plist: \(error)")
        }
    }
}

// MARK: - Main App (Updated with Responsive Splash Screen)
@main
struct MetaWavApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var showingSplash = true
    @State private var splashOpacity: Double = 1.0
    @State private var hasSetupMainMenu = false // NEW: Track if we've set up the main menu
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Always show the next screen underneath
                if !userPreferences.hasAcceptedEULA {
                    // Show EULA if not accepted
                    EULAView { accepted in
                        if accepted {
                            UserPreferences.shared.acceptEULA()
                        } else {
                            declineEULA()
                        }
                    }
                    .frame(minWidth: 800, idealWidth: 1224, maxWidth: .infinity,
                           minHeight: 600, idealHeight: 725, maxHeight: .infinity)
                    .onAppear {}
                } else {
                    // Show main app - DYNAMIC FRAME SIZE
                    ContentView()
                        .frame(minWidth: 800, minHeight: 200)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {}
                }
                
                // Splash overlay that fills entire window and fades out
                if showingSplash && !settingsManager.skipLogoOnStartup {
                    SplashView()
                        .opacity(splashOpacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            print("🎬 Showing splash screen")
                            // Show splash for 2.0 seconds, then fade out
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    splashOpacity = 0.0
                                }
                                
                                // Hide splash after fade animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showingSplash = false
                                    hasSetupMainMenu = true
                                    print("✅ Splash removed")
                                }
                            }
                        }
                }
            }
            .ignoresSafeArea(.all)
            .background(WindowAccessor { window in
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.registerMainWindow(window)
                }
                WindowManager.shared.applyHiddenTitleBar(to: window)
            })
            .onAppear {
                // Handle immediate skip to main app if both splash skip AND EULA accepted
                if settingsManager.skipLogoOnStartup {
                    showingSplash = false
                    hasSetupMainMenu = true
                    print("⚙️ Skip logo enabled - launching directly")
                }
            }
            // Force SwiftUI views to use dark color scheme
            .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        // Attach commands to define the app's main menu per SwiftUI guidelines
        // Docs: Building and customizing the menu bar with SwiftUI
        // https://developer.apple.com/documentation/SwiftUI/Building-and-customizing-the-menu-bar-with-SwiftUI
        .commands {
            MetaWavCommands()
        }
    }
    
    private func declineEULA() {
        let alert = NSAlert()
        alert.messageText = "License Agreement Required"
        alert.informativeText = "You must accept the license agreement to use MetaWav Professional Audio Library."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - App State Manager for Current Album
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentAlbum: AlbumMetadata?
    
    private init() {}
}

// MARK: - Splash Screen View (Updated to be Fully Responsive)
struct SplashView: View {
    @State private var logoOpacity: Double = 0.0
    @StateObject private var settingsManager = SettingsManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background image - fills entire window
                Image("background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                
                // Main logo with fade-in animation
                // Logo scales based on window size while maintaining aspect ratio
                Image("loadlogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: geometry.size.width * 0.8,  // Logo takes up to 80% of window width
                           maxHeight: geometry.size.height * 0.6) // and up to 60% of window height
                    .opacity(logoOpacity)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    
                // Optional: Skip indicator in bottom corner
                if !settingsManager.skipLogoOnStartup {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("You can skip this screen in Settings")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.trailing, 20)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Logo fades in quickly
            withAnimation(.easeInOut(duration: 0.8)) {
                logoOpacity = 1.0
            }
        }
    }
}

// MARK: - EULA View (Updated for Better Responsiveness)
struct EULAView: View {
    let onCompletion: (Bool) -> Void
    
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    
    // Calculate if user has scrolled to (approximately) the bottom
    private var hasScrolledEnough: Bool {
        guard contentHeight > scrollViewHeight else { return true }
        let bottomVisible = scrollOffset + scrollViewHeight
        let tolerance: CGFloat = 8
        return bottomVisible >= (contentHeight - tolerance)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // No background for EULA per request
                Color.clear
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("METAWAV PROFESSIONAL AUDIO LIBRARY")
                            .font(Font.custom("Copperplate", size: 18))
                            .tracking(1.0)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .shadow(color: .black, radius: 1, x: 1, y: 1)
                        
                        Text("LICENSE AGREEMENT")
                            .font(Font.custom("Copperplate", size: 14))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black, radius: 1, x: 1, y: 1)
                    }
                    .padding(.top, 30)
                    
                    // Legal text in scrollable area - adjusts to window height
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(eulaText)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.95))
                                .lineSpacing(4)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 20)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onAppear {
                                                contentHeight = geo.size.height
                                                print("📏 Content height: \(contentHeight)")
                                            }
                                            .onChange(of: geo.size.height) { _, newHeight in
                                                contentHeight = newHeight
                                            }
                                    }
                                )
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scrollView")).minY)
                            }
                        )
                    }
                    // Dynamically sized scroll area based on window height
                    .frame(height: max(300, geometry.size.height * 0.6))
                    .padding(.horizontal, max(20, geometry.size.width * 0.05))
                    .coordinateSpace(name: "scrollView")
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    scrollViewHeight = geo.size.height
                                    print("📏 ScrollView height: \(scrollViewHeight)")
                                }
                                .onChange(of: geo.size.height) { _, newHeight in
                                    scrollViewHeight = newHeight
                                }
                        }
                    )
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = max(0, -value)
                        let bottomVisible = scrollOffset + scrollViewHeight
                        let percentage = contentHeight > 0 ? min(100, (bottomVisible / contentHeight) * 100) : 100
                        print("📜 Scroll: \(Int(percentage))% (bottom \(Int(bottomVisible))/content \(Int(contentHeight)))")
                    }
                    
                    // Scroll indicator with percentage
                    if !hasScrolledEnough {
                        let bottomVisible = scrollOffset + scrollViewHeight
                        let percentage = contentHeight > 0 ? min(100, (bottomVisible / contentHeight) * 100) : 100
                        
                        VStack(spacing: 4) {
                            HStack {
                                Image(systemName: "arrow.down")
                                    .foregroundColor(.yellow)
                                Text("Please scroll to read the complete agreement (\(Int(percentage))%)")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                            
                            // Progress bar
                            HStack {
                                Rectangle()
                                    .fill(Color.yellow)
                                    .frame(width: CGFloat(percentage) * 2, height: 2)
                                
                                Rectangle()
                                    .fill(Color.gray)
                                    .frame(width: (100 - CGFloat(percentage)) * 2, height: 2)
                            }
                            .frame(width: 200, height: 2)
                        }
                        .padding(.horizontal)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                    } else {
                        Text("✓ You may now accept the agreement")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal)
                            .shadow(color: .black, radius: 1, x: 1, y: 1)
                    }
                    
                    // Action buttons
                    HStack(spacing: 20) {
                        Button("DECLINE") {
                            onCompletion(false)
                        }
                        .font(Font.custom("Copperplate", size: 12))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(6)
                        .buttonStyle(PlainButtonStyle())
                        
                        Button("ACCEPT") {
                            print("🎯 Accept button tapped")
                            onCompletion(true)
                        }
                        .font(Font.custom("Copperplate", size: 12))
                        .tracking(0.5)
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(hasScrolledEnough ? Color.white : Color.gray.opacity(0.5))
                        .cornerRadius(6)
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!hasScrolledEnough)
                    }
                    .padding(.bottom, 30)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - EULA Text Content
private let eulaText = """
END USER LICENSE AGREEMENT

MetaWav Professional Audio Library
© 2024–2025 Fors Audio. All rights reserved.

IMPORTANT – READ CAREFULLY:
This End User License Agreement ("Agreement") is a legal agreement between you (either an individual or a single entity) and Fors Audio for the use of the MetaWav Professional Audio Library software ("Software"). By installing, copying, or using the Software, you agree to be bound by the terms of this Agreement.

1. LICENSE GRANT
Fors Audio grants you a limited, non-exclusive, non-transferable, revocable license to install and use the Software on devices you own or control, solely for lawful purposes, and in accordance with the terms of this Agreement.

2. PERMITTED USES
You may:
• Install and use the Software on personal or professional devices under your control
• Create, edit, and manage metadata and album information for lawful, non-infringing audio content
• Export data in supported formats for personal, professional, or collaborative use
• Share .metaalbum files with other licensed users who also lawfully possess the corresponding audio content

3. RESTRICTIONS
You may not:
• Reverse engineer, decompile, disassemble, or otherwise attempt to derive the source code
• Sell, rent, lease, sublicense, redistribute, or otherwise commercially exploit the Software
• Remove, obscure, or alter any copyright, trademark, or other proprietary notices
• Use the Software to store, distribute, or manage pirated, unauthorized, or infringing music or metadata
• Use the Software in any way that violates applicable laws or third-party rights

4. USER CONTENT AND LEGAL COMPLIANCE
You are solely responsible for ensuring that all audio files, metadata, and content used with the Software are legally obtained and do not infringe upon the intellectual property rights of any third party.
You must own or have the legal right to use, reproduce, or distribute any content managed or shared through MetaWav.
Fors Audio does not condone piracy, and any use of the Software to manage or distribute pirated or illegal content is strictly prohibited and grounds for immediate license termination.

5. PRIVACY AND DATA
• The Software operates locally and does not transmit personal data to Fors Audio servers
• All files, metadata, and session data remain under your local control
• The Software does not contain tracking, telemetry, or analytics systems

6. INTELLECTUAL PROPERTY
The Software is licensed, not sold. All intellectual property rights—including copyrights, trademarks, trade secrets, and related rights—are owned by Fors Audio. This Agreement does not grant you any ownership interest in the Software.

7. WARRANTY DISCLAIMER
THE SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED. FORS AUDIO DISCLAIMS ALL WARRANTIES INCLUDING BUT NOT LIMITED TO MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

8. LIMITATION OF LIABILITY
IN NO EVENT SHALL FORS AUDIO BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF PROFITS, DATA, OR USE, ARISING OUT OF OR RELATED TO YOUR USE OR INABILITY TO USE THE SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

9. TERMINATION
This license is effective until terminated. It will terminate automatically without notice if you breach any term of this Agreement. Upon termination, you must cease all use and delete all copies of the Software.

10. GOVERNING LAW
This Agreement shall be governed by and construed in accordance with the laws of the jurisdiction where Fors Audio is headquartered, without regard to conflict of law principles.

BY CLICKING "ACCEPT," YOU ACKNOWLEDGE THAT YOU HAVE READ THIS AGREEMENT, UNDERSTOOD ITS TERMS, AND AGREE TO BE LEGALLY BOUND BY THEM.
"""

// MARK: - Excel Exporter (Unchanged from original)
class ExcelExporter: ObservableObject {
    static let shared = ExcelExporter()
    
    @Published var isExporting = false
    @Published var exportStatus = ""
    
    private init() {}
    
    // Export current album loaded in the player
    func exportCurrentAlbum() {
        guard let album = getCurrentAlbum() else {
            exportStatus = "No album currently loaded in player"
            print("❌ No album loaded in player to export")
            return
        }
        
        exportAlbum(album)
    }
    
    // Get current album from the app state
    private func getCurrentAlbum() -> AlbumMetadata? {
        return AppState.shared.currentAlbum
    }
    
    // Export single album to CSV (two-table format)
    private func exportAlbum(_ album: AlbumMetadata) {
        isExporting = true
        exportStatus = "Preparing export..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let csvContent = self.generateAlbumCSV(album)
                
                DispatchQueue.main.async {
                    self.saveFile(
                        content: csvContent,
                        filename: "\(self.sanitizeFilename(album.albumName))_Export.csv",
                        contentType: .commaSeparatedText
                    )
                }
            }
        }
    }
    
    // Generate CSV content for a single album
    private func generateAlbumCSV(_ album: AlbumMetadata) -> String {
        var csv = ""
        
        // Sort tracks by track number for consistent ordering
        let sortedTracks = album.tracks.sorted { t1, t2 in
            if t1.discNumber != t2.discNumber { return t1.discNumber < t2.discNumber }
            return t1.trackNumber < t2.trackNumber
        }
        
        // ALBUM DATA TABLE
        csv += "ALBUM INFORMATION\n"
        csv += "Property,Value\n"
        csv += "Album Name,"
        csv += escapeCSV(album.albumName)
        csv += "\n"
        csv += "Genre,"
        csv += escapeCSV(album.genre ?? "")
        csv += "\n"
        csv += "Year,"
        csv += escapeCSV(album.year ?? "")
        csv += "\n"
        csv += "Total Duration,"
        csv += escapeCSV(album.formattedDuration ?? "")
        csv += "\n"
        csv += "Track Count,"
        csv += escapeCSV(String(album.trackCount))
        csv += "\n"
        csv += "Front Artwork Path,"
        csv += escapeCSV(album.frontArtPath ?? "")
        csv += "\n"
        csv += "Back Artwork Path,"
        csv += escapeCSV(album.backArtPath ?? "")
        csv += "\n"
        
        // COLUMN BREAK
        csv += "\n\n"
        
        // TRACK DETAILS TABLE (rows = tracks)
        csv += "TRACK INFORMATION\n"
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

        for track in sortedTracks {
            let creditsJoined: String = {
                guard let credits = track.credits, !credits.isEmpty else { return "" }
                return credits.map { "\($0.role): \($0.name)" }.joined(separator: "; ")
            }()

            let relatedCount = track.relatedFiles?.count ?? 0
            let relatedDetail: String = {
                guard let files = track.relatedFiles, !files.isEmpty else { return "" }
                return files.map { "\($0.actualDisplayName) (\($0.fileType.rawValue)): \($0.filePath)" }.joined(separator: "; ")
            }()

            let lyricsCount = track.lyrics?.count ?? 0
            let lyricsDetail: String = {
                guard let lyrics = track.lyrics, !lyrics.isEmpty else { return "" }
                let sorted = lyrics.sorted { $0.time < $1.time }
                return sorted.map { "[\(formatTime($0.time))] \($0.text)" }.joined(separator: " | ")
            }()

            let row: [String] = [
                forceLeft(String(track.discNumber)),
                forceLeft(String(track.trackNumber)),
                forceLeft(track.name),
                forceLeft(track.artist ?? ""),
                forceLeft(track.formattedDuration ?? ""),
                forceLeft(track.key ?? ""),
                forceLeft(track.bpm?.description ?? ""),
                forceLeft(track.version ?? ""),
                forceLeft(track.isExplicit == true ? "Yes" : "No"),
                forceLeft(track.format ?? ""),
                forceLeft(track.channelCount?.description ?? ""),
                forceLeft(track.sampleRate?.description ?? ""),
                forceLeft(track.bitDepth ?? ""),
                forceLeft(track.bitrateKbps?.description ?? ""),
                forceLeft(track.isrc ?? ""),
                forceLeft(creditsJoined),
                forceLeft(String(relatedCount)),
                forceLeft(relatedDetail),
                forceLeft(String(lyricsCount)),
                forceLeft(lyricsDetail),
                forceLeft(track.notes ?? ""),
                forceLeft(track.filePath)
            ]
            csv += row.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    // Helper functions
    private func escapeCSV(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    private func forceLeft(_ value: String) -> String {
        if value.isEmpty { return "" }
        return escapeCSV("'" + value)
    }
    
    // Save file using NSSavePanel
    private func saveFile(content: String, filename: String, contentType: UTType) {
        let savePanel = NSSavePanel()
        savePanel.begin { response in
            DispatchQueue.main.async {
                if response == .OK, let url = savePanel.url {
                    do {
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        self.exportStatus = "Export successful: \(url.lastPathComponent)"
                        print("✅ Export saved to: \(url.path)")
                        
                        // Optionally reveal in Finder
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        
                    } catch {
                        self.exportStatus = "Failed to save file: \(error.localizedDescription)"
                        print("❌ Save failed: \(error)")
                    }
                } else {
                    self.exportStatus = "Export cancelled"
                }
                
                self.isExporting = false
            }
        }
    }
}

// MARK: - Export Status View (Optional - for showing export progress)
struct ExportStatusView: View {
    
    @ObservedObject private var exporter = ExcelExporter.shared
    
    var body: some View {
        if exporter.isExporting {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text(exporter.exportStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .transition(.opacity)
        } else if !exporter.exportStatus.isEmpty {
            Text(exporter.exportStatus)
                .font(.system(size: 12))
                .foregroundColor(exporter.exportStatus.contains("successful") ? .green : .red)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .transition(.opacity)
        }
    }
}
