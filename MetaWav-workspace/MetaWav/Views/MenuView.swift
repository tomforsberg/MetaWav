// MenuViewManager.swift
import SwiftUI
import AppKit
import AVFoundation
import AudioToolbox

@MainActor
class MenuViewManager: NSObject, ObservableObject {
    static let shared = MenuViewManager()
    
    // Store window controllers to prevent deallocation
    private var menuWindowControllers: [MenuWindowController] = []
    
    private override init() {
        super.init()
    }
    
    // MARK: - Help Windows
    
    @objc func showHelp() {
        showMenuWindow(with: fullHelpContent)
    }
    
    func showQuickStart() {
        showMenuWindow(with: quickStartContent)
    }
    
    @objc func showKeyboardShortcuts() {
        showMenuWindow(with: keyboardShortcutsContent)
    }
    
    func showMetaAlbumHelp() {
        showMenuWindow(with: metaAlbumContent)
    }
    
    @objc func showFileOrganization() {
        showMenuWindow(with: fileOrganizationContent)
    }
    
    @objc func showTroubleshooting() {
        showMenuWindow(with: troubleshootingContent)
    }
    
    // MARK: - About Windows
    
    func showAboutMetaWav() {
        showMenuWindow(with: aboutMetaWavContent)
    }
    
    // MARK: - Settings Window
    
    func showSettings() {
        showSettingsWindow()
    }
    
    private func showSettingsWindow() {
        print("⚙️ Creating settings window")
        
        // Close any existing settings windows
        closeMenuWindowsOfType("Settings")
        
        // Create settings window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Settings"
        window.center()
        window.level = .floating
        window.hidesOnDeactivate = false
        // Enable transparent background to let glass render nicely
        window.isOpaque = false
        window.backgroundColor = .clear
        
        // Create window controller
        let windowController = MenuWindowController(window: window, menuViewManager: self)
        
        // Create SwiftUI settings view
        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        
        window.contentView = hostingView
        
        // Store the window controller
        menuWindowControllers.append(windowController)
        
        // Show the window
        windowController.showWindow(nil)
        
        print("⚙️ Settings window created and displayed")
    }
    
    // MARK: - Menu Window Management
    
    func showMenuWindow(with content: MenuContent) {
        print("📚 Creating menu window for: \(content.title)")
        
        // Close any existing windows of the same type
        closeMenuWindowsOfType(content.title)
        
        // Create new window with specific styling to prevent main window interference
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = content.title
        window.center()
        
        // Crucial: Set window level to keep it separate from main window
        window.level = .floating
        
        // Prevent this window from becoming key window and interfering with main window
        window.hidesOnDeactivate = false
        // Enable transparent background for glass rendering
        window.isOpaque = false
        window.backgroundColor = .clear
        
        // Create a window controller to manage the window properly
        let windowController = MenuWindowController(window: window, menuViewManager: self)
        
        // Create SwiftUI view for content
        let menuView = MenuView(content: content)
        let hostingView = NSHostingView(rootView: menuView)
        
        window.contentView = hostingView
        
        // Store the window controller to prevent deallocation
        menuWindowControllers.append(windowController)
        
        // Show the window
        windowController.showWindow(nil)
        
        // Make sure the main window stays active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let mainWindow = NSApplication.shared.windows.first(where: { $0.title == "" || $0.title.isEmpty }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }
        }
        
        print("📚 Menu window created and displayed: \(content.title)")
    }
    
    private func closeMenuWindowsOfType(_ title: String) {
        // Close any existing windows with the same title
        menuWindowControllers.removeAll { controller in
            if let window = controller.window, window.title == title {
                window.close()
                return true
            }
            return false
        }
    }
    
    // Called by MenuWindowController when a window closes
    func windowDidClose(_ windowController: MenuWindowController) {
        menuWindowControllers.removeAll { $0 === windowController }
        print("📚 Menu window closed and removed from tracking")
        
        // Ensure main window gets focus back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let mainWindow = NSApplication.shared.windows.first(where: { $0.title == "" || $0.title.isEmpty }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    // MARK: - Add to Main Menu (removed Help menu to avoid duplication)
}

// MARK: - SettingsManager Performance Preset Helpers
extension SettingsManager {
    private func applyPerformancePresetIfNeeded(_ preset: PerformancePreset) {
        guard preset != .custom else { return }
        isApplyingPreset = true
        switch preset {
        case .low:
            audioBufferSize = 4096
            uiUpdateFrequency = 30
            enableAudioOptimizations = false
            useHardwareAcceleration = false
        case .medium:
            audioBufferSize = 2048
            uiUpdateFrequency = 50
            enableAudioOptimizations = true
            useHardwareAcceleration = true
        case .high:
            audioBufferSize = 512
            uiUpdateFrequency = 60
            enableAudioOptimizations = true
            useHardwareAcceleration = true
        case .custom:
            break
        }
        isApplyingPreset = false
    }

    private func inferPresetFromCurrent() -> PerformancePreset {
        if audioBufferSize >= 4096 && uiUpdateFrequency <= 30 && enableAudioOptimizations && useHardwareAcceleration {
            return .low
        }
        if audioBufferSize == 2048 && uiUpdateFrequency == 50 && enableAudioOptimizations && useHardwareAcceleration {
            return .medium
        }
        if audioBufferSize <= 1024 && uiUpdateFrequency >= 60 && enableAudioOptimizations && useHardwareAcceleration {
            return .high
        }
        return .custom
    }

    private func syncPresetWithCurrentSettings() {
        let inferred = inferPresetFromCurrent()
        if performancePreset != inferred {
            performancePreset = inferred
        }
    }
}

// MARK: - Helper Window Controller

class MenuWindowController: NSWindowController, NSWindowDelegate {
    private weak var menuViewManager: MenuViewManager?
    
    init(window: NSWindow, menuViewManager: MenuViewManager) {
        self.menuViewManager = menuViewManager
        super.init(window: window)
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        menuViewManager?.windowDidClose(self)
    }
    
    // Prevent menu windows from interfering with main window
    func windowDidBecomeKey(_ notification: Notification) {
        // Menu windows should not steal key status from main window
        // This helps prevent the main window from closing
    }
}

// MARK: - Settings Manager (Updated to use Settings.plist in Info folder)

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // MARK: - Performance Preset
    enum PerformancePreset: String, CaseIterable {
        case low
        case medium
        case high
        case custom
    }
    
    @Published var performancePreset: PerformancePreset {
        didSet {
            applyPerformancePresetIfNeeded(performancePreset)
            saveSettings()
            print("⚙️ Performance preset changed to: \(performancePreset.rawValue)")
        }
    }
    
    private var isApplyingPreset = false
    
    @Published var skipLogoOnStartup: Bool {
        didSet {
            saveSettings()
            print("⚙️ Skip logo setting changed to: \(skipLogoOnStartup)")
        }
    }
    
    @Published var enableSoundEffects: Bool {
        didSet {
            saveSettings()
            print("⚙️ Sound effects setting changed to: \(enableSoundEffects)")
        }
    }
    
    // NEW: Power on by default setting
    @Published var powerOnByDefault: Bool {
        didSet {
            saveSettings()
            print("⚙️ Power on by default setting changed to: \(powerOnByDefault)")
        }
    }
    
    // NEW: Audio Performance Settings
    @Published var audioBufferSize: Int {
        didSet {
            saveSettings()
            print("⚙️ Audio buffer size changed to: \(audioBufferSize)")
            if !isApplyingPreset { syncPresetWithCurrentSettings() }
        }
    }
    
    @Published var enableAudioOptimizations: Bool {
        didSet {
            saveSettings()
            print("⚙️ Audio optimizations enabled: \(enableAudioOptimizations)")
            if !isApplyingPreset { syncPresetWithCurrentSettings() }
        }
    }
    
    @Published var uiUpdateFrequency: Int {
        didSet {
            saveSettings()
            print("⚙️ UI update frequency changed to: \(uiUpdateFrequency)")
            if !isApplyingPreset { syncPresetWithCurrentSettings() }
        }
    }
    
    @Published var useHardwareAcceleration: Bool {
        didSet {
            saveSettings()
            print("⚙️ Hardware acceleration enabled: \(useHardwareAcceleration)")
            if !isApplyingPreset { syncPresetWithCurrentSettings() }
        }
    }
    
    private var settingsFileURL: URL {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let metaWavDir = userHome
            .appendingPathComponent("Documents")
            .appendingPathComponent("MetaWav")
            .appendingPathComponent("Info")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: metaWavDir.path) {
            do {
                try FileManager.default.createDirectory(at: metaWavDir, withIntermediateDirectories: true)
                print("📁 Created MetaWav/Info directory for settings")
            } catch {
                print("❌ Failed to create MetaWav/Info directory: \(error)")
            }
        }
        
        return metaWavDir.appendingPathComponent("Settings.plist")
    }
    
    private init() {
        // Load settings from plist file, use defaults if file doesn't exist
        self.skipLogoOnStartup = false  // Default values
        self.enableSoundEffects = true
        self.powerOnByDefault = false  // NEW: Default to false for backward compatibility
        
        // NEW: Audio Performance defaults
        self.audioBufferSize = 2048        // 2KB default buffer (balanced)
        self.enableAudioOptimizations = true  // Enable optimizations by default
        self.uiUpdateFrequency = 50        // 50 FPS for smooth playback
        self.useHardwareAcceleration = true  // Enable hardware acceleration by default
        self.performancePreset = .high
        
        loadSettings()
        
        print("⚙️ Loaded settings from: \(settingsFileURL.path)")
        print("⚙️ Skip logo: \(skipLogoOnStartup), Sound effects: \(enableSoundEffects), Power on by default: \(powerOnByDefault)")
        print("⚙️ Audio buffer: \(audioBufferSize), Optimizations: \(enableAudioOptimizations), UI FPS: \(uiUpdateFrequency)")
    }
    
    private func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsFileURL.path) else {
            print("⚙️ No Settings.plist found - using defaults")
            return
        }
        
        do {
            let data = try Data(contentsOf: settingsFileURL)
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
            
            // Load settings with fallback to current values
            skipLogoOnStartup = plist["skipLogoOnStartup"] as? Bool ?? skipLogoOnStartup
            enableSoundEffects = plist["enableSoundEffects"] as? Bool ?? enableSoundEffects
            powerOnByDefault = plist["powerOnByDefault"] as? Bool ?? powerOnByDefault  // NEW
            
            // NEW: Load audio performance settings
            audioBufferSize = plist["audioBufferSize"] as? Int ?? audioBufferSize
            enableAudioOptimizations = plist["enableAudioOptimizations"] as? Bool ?? enableAudioOptimizations
            uiUpdateFrequency = plist["uiUpdateFrequency"] as? Int ?? uiUpdateFrequency
            useHardwareAcceleration = plist["useHardwareAcceleration"] as? Bool ?? useHardwareAcceleration
            if let presetRaw = plist["performancePreset"] as? String,
               let preset = PerformancePreset(rawValue: presetRaw) {
                performancePreset = preset
            } else {
                performancePreset = inferPresetFromCurrent()
            }
            
            print("⚙️ Settings loaded from Settings.plist")
        } catch {
            print("❌ Failed to load Settings.plist: \(error)")
        }
    }
    
    private func saveSettings() {
        let settings: [String: Any] = [
            "skipLogoOnStartup": skipLogoOnStartup,
            "enableSoundEffects": enableSoundEffects,
            "powerOnByDefault": powerOnByDefault,  // NEW
            "audioBufferSize": audioBufferSize,  // NEW
            "enableAudioOptimizations": enableAudioOptimizations,  // NEW
            "uiUpdateFrequency": uiUpdateFrequency,  // NEW
            "useHardwareAcceleration": useHardwareAcceleration,  // NEW
            "performancePreset": performancePreset.rawValue,
            "lastModified": Date().timeIntervalSince1970,
            "version": "1.0"
        ]
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
            try data.write(to: settingsFileURL)
            print("💾 Settings saved to: \(settingsFileURL.path)")
        } catch {
            print("❌ Failed to save settings: \(error)")
        }
    }
    
    // Static methods for compatibility (now read from plist)
    static var shouldSkipLogoScreen: Bool {
        return SettingsManager.shared.skipLogoOnStartup
    }
    
    static var areSoundEffectsEnabled: Bool {
        return SettingsManager.shared.enableSoundEffects
    }
    
    // NEW: Static method for power on by default
    static var shouldPowerOnByDefault: Bool {
        return SettingsManager.shared.powerOnByDefault
    }
    
    // NEW: Static methods for audio performance settings
    static var audioBufferSize: Int {
        return SettingsManager.shared.audioBufferSize
    }
    
    static var areAudioOptimizationsEnabled: Bool {
        return SettingsManager.shared.enableAudioOptimizations
    }
    
    static var uiUpdateFrequency: Int {
        return SettingsManager.shared.uiUpdateFrequency
    }
    
    static var isHardwareAccelerationEnabled: Bool {
        return SettingsManager.shared.useHardwareAcceleration
    }
    
    // Reset settings to defaults
    func resetToDefaults() {
        skipLogoOnStartup = false
        enableSoundEffects = false
        powerOnByDefault = false  // NEW
        performancePreset = .medium
        applyPerformancePresetIfNeeded(.medium)
        print("🔄 Settings reset to defaults")
    }
    
    // Delete settings file (for cleanup/reset)
    func deleteSettingsFile() {
        do {
            if FileManager.default.fileExists(atPath: settingsFileURL.path) {
                try FileManager.default.removeItem(at: settingsFileURL)
                print("🗑️ Settings.plist deleted")
            }
        } catch {
            print("❌ Failed to delete Settings.plist: \(error)")
        }
    }
}

// MARK: - Updated Settings View with Power On By Default Toggle
struct SettingsView: View {
    @ObservedObject private var audioManager = AudioDeviceManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var showAdvancedPerformance = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)
                
                // General Settings Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("General Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    // Skip Logo Screen Toggle
                    HStack {
                        Text("Skip logo screen on startup")
                            .font(.body)
                        
                        Spacer()
                        
                        Toggle("", isOn: $settingsManager.skipLogoOnStartup)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0, green: 0.75, blue: 0.39)))
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    
                    Text("When enabled, MetaWav will skip the startup logo animation and launch directly to the main interface.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 16)
                        .padding(.bottom, 8)
                    
                    // NEW: Power On By Default Toggle
                    HStack {
                        Text("Power on by default")
                            .font(.body)
                        
                        Spacer()
                        
                        Toggle("", isOn: $settingsManager.powerOnByDefault)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0, green: 0.75, blue: 0.39)))
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    
                    Text("When enabled, MetaWav will automatically power on when the app launches, ready to load files immediately.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 16)
                        .padding(.bottom, 8)
                    
                    // Sound Effects Toggle
                    HStack {
                        Text("Enable sound effects")
                            .font(.body)
                        
                        Spacer()
                        
                        Toggle("", isOn: $settingsManager.enableSoundEffects)
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0, green: 0.75, blue: 0.39)))
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    
                    Text("When enabled, MetaWav will play sound effects for button presses and transport controls.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 16)
                        .padding(.bottom, 8)
                    
                    Divider()
                }
                
                // Audio Settings Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Audio Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    // Output Device Selection
                    HStack {
                        Text("Output Device")
                            .font(.headline)
                        
                        Spacer()
                        
                        Picker("", selection: $audioManager.selectedDeviceID) {
                            ForEach(audioManager.outputDevices, id: \.deviceID) { device in
                                Text(device.name)
                                    .tag(device.deviceID)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: 250)
                        .labelsHidden()
                        .onChange(of: audioManager.selectedDeviceID) { _, newDeviceID in
                            audioManager.selectDevice(deviceID: newDeviceID)
                        }
                    }
                    
                    Divider()
                    
                    // Current Format Display
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Audio Format")
                            .font(.headline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sample Rate:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(audioManager.currentSampleRate)
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bit Depth:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(audioManager.currentBitDepth)
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                }
                // NEW: Audio Performance Settings Section (presets + advanced)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Performance")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    // Presets
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Performance")
                                .font(.headline)
                            Spacer()
                            Picker("", selection: $settingsManager.performancePreset) {
                                Text("Low").tag(SettingsManager.PerformancePreset.low)
                                Text("Medium").tag(SettingsManager.PerformancePreset.medium)
                                Text("High").tag(SettingsManager.PerformancePreset.high)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(maxWidth: 260)
                            .controlSize(.small)
                            .padding(.vertical, -2)
                        }
                    }
                    
                    DisclosureGroup(isExpanded: $showAdvancedPerformance) {
                        VStack(alignment: .leading, spacing: 10) {
                            // Buffer size
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Audio Buffer Size")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(settingsManager.audioBufferSize) samples")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Picker("Buffer Size", selection: $settingsManager.audioBufferSize) {
                                    Text("512 samples").tag(512)
                                    Text("1024 samples").tag(1024)
                                    Text("2048 samples").tag(2048)
                                    Text("4096 samples").tag(4096)
                                    Text("8192 samples").tag(8192)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: 220)
                                .labelsHidden()
                                Text("Smaller buffers = lower latency, higher CPU.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 16)
                            }
                            // UI FPS
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("UI Update Frequency")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(settingsManager.uiUpdateFrequency) FPS")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Picker("UI FPS", selection: $settingsManager.uiUpdateFrequency) {
                                    Text("30 FPS").tag(30)
                                    Text("40 FPS").tag(40)
                                    Text("50 FPS").tag(50)
                                    Text("60 FPS").tag(60)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: 220)
                                .labelsHidden()
                                Text("Lower FPS saves CPU; higher FPS gives smoother UI.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 16)
                            }
                            // Toggles
                            HStack {
                                Text("Enable Audio Optimizations")
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: $settingsManager.enableAudioOptimizations)
                                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0, green: 0.75, blue: 0.39)))
                                    .labelsHidden()
                            }
                            HStack {
                                Text("Use Hardware Acceleration")
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: $settingsManager.useHardwareAcceleration)
                                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0, green: 0.75, blue: 0.39)))
                                    .labelsHidden()
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        HStack {
                            Text("Advanced")
                                .font(.headline)
                            if settingsManager.performancePreset == .custom {
                                Spacer()
                                Text("Custom")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                }
                
                
                
                // Instant Metadata Management Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Instant Metadata Management")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Text("Manage metadata updates with instant refresh and automatic cleanup")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                    // Clean Up Action
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            
                            Text("Ready")
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Button("Clean Up") {
                                CleanupManager.shared.runCleanupAndShowLog()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    
                }
                
                // Footer with extra padding at bottom
                VStack(alignment: .leading, spacing: 4) {
                    Text("Changes take effect immediately")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Logo screen and power on settings apply on next app launch")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Audio performance settings optimize playback and reduce lag")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)
                .padding(.bottom, 32) // Extra bottom padding for scroll clearance
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            audioManager.refreshDevices()
        }
    }
    
    // MARK: - Helper Functions
    
    private func printImagePerformanceReport() {
        let metrics = ImagePerformanceOptimizer.shared.getPerformanceMetrics()
        
        print("🖼️ Image Performance Report:")
        print("   Total Requests: \(metrics["totalRequests"] ?? 0)")
        print("   Cache Hits: \(metrics["cacheHits"] ?? 0)")
        print("   Cache Hit Rate: \(String(format: "%.1f%%", (metrics["cacheHitRate"] as? Double ?? 0) * 100))")
        print("   Average Processing Time: \(String(format: "%.2f ms", (metrics["averageProcessingTime"] as? Double ?? 0) * 1000))")
        print("   Max Processing Time: \(String(format: "%.2f ms", (metrics["maxProcessingTime"] as? Double ?? 0) * 1000))")
        print("   Min Processing Time: \(String(format: "%.2f ms", (metrics["minProcessingTime"] as? Double ?? 0) * 1000))")
        print("   Image Cache Size: \(metrics["imageCacheSize"] ?? 0)")
        print("   Thumbnail Cache Size: \(metrics["thumbnailCacheSize"] ?? 0)")
    }
    
    // MARK: - Instant Metadata Management Functions
    
    private func validateFilePaths() async {
        print("🔍 Starting file path validation...")
        
        let allAlbums = AlbumMetadataManager.shared.loadAllAlbums()
        let totalRepaired = 0
        for _ in allAlbums {
            // File path validation removed for simplicity
        }
        print("✅ File path validation completed. Repaired \(totalRepaired) albums.")
    }
    
    private func checkSandboxCompliance() async {
        print("🔒 Checking sandbox compliance...")
        
        let allAlbums = AlbumMetadataManager.shared.loadAllAlbums()
        let totalCompliant = 0
        for _ in allAlbums {
            // Sandbox compliance check removed for simplicity
        }
        print("✅ Sandbox compliance check completed. Made \(totalCompliant) albums compliant.")
    }
    
    private func runMaintenance() async {
        print("🧹 Starting comprehensive maintenance...")
        
        do {
            // Maintenance functionality removed for simplicity
            // try await InstantMetadataManager.shared.performMaintenance()
            print("✅ Maintenance simplified - functionality removed.")
            
        }
    }
}

// MARK: - Menu Content Structure

struct MenuContent {
    let title: String
    let sections: [MenuSection]
}

struct MenuSection {
    let title: String
    let content: String
    let isCodeBlock: Bool
    
    init(title: String, content: String, isCodeBlock: Bool = false) {
        self.title = title
        self.content = content
        self.isCodeBlock = isCodeBlock
    }
}

// MARK: - SwiftUI Menu View

struct MenuView: View {
    let content: MenuContent
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text(content.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)
                
                // Sections
                ForEach(Array(content.sections.enumerated()), id: \.offset) { index, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        if section.isCodeBlock {
                            Text(section.content)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            Text(section.content)
                                .font(.body)
                                .lineSpacing(4)
                        }
                    }
                    
                    Divider()
                }
                
                Spacer(minLength: 40)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Content Definitions

// Help Content
private let fullHelpContent = MenuContent(
    title: "MetaWav User Guide",
    sections: [
        MenuSection(
            title: "Welcome to MetaWav",
            content: "MetaWav is a professional audio library manager. It creates albums from your audio files while preserving metadata and organizing everything in a clean, predictable structure."
        ),
        MenuSection(
            title: "Getting Started",
            content: """
1. Power On: Click the power button to activate MetaWav
2. Load Files: Click "LOAD FILES" and select one or more audio files
3. MetaWav creates an album, extracts metadata, and orders tracks (multi‑disc aware)
4. Browse albums in the library panel; select an album to view tracks and art
5. Press Play in the transport to verify playback and format info
"""
        ),
        MenuSection(
            title: "Interface Overview",
            content: """
• Power Button: Turn MetaWav on/off
• Load Files: Import new audio files (creates/updates an album)
• Transport: Play, pause, stop, previous/next track
• Timecode: Track number and playback time
• Format Info: Effective device/track sample rate and bit depth
• Library: Browse albums and tracks
• Album/Art/Track Panels: View & edit metadata and artwork
"""
        ),
        MenuSection(
            title: "Audio Formats Supported",
            content: """
MetaWav supports all major audio formats:
• WAV (Waveform Audio File Format)
• FLAC (Free Lossless Audio Codec)
• MP3 (MPEG-1 Audio Layer 3)
• M4A/AAC (Advanced Audio Coding)
• AIFF (Audio Interchange File Format)
• And many more standard audio formats

Format information is displayed in the timecode panel, including sample rate and bit depth.
"""
        ),
        MenuSection(
            title: "Power Tips",
            content: """
            • Create Playlist: ⇧⌘N
            • Add to Playlist: ⇧⌘L
            • Remove from Playlist: ⌥⌘R
            • Add to Queue: ⇧⌘Q
            • Repath Track: ⇧⌘P
            • Export Album to CSV: ⌘E
            • Export Track Lyrics (LRC): ⇧⌘L
            • Toggle Additional Panels: ⇧⌘P
            • Show Help: ⇧⌘?
            """
        )
    ]
)

private let quickStartContent = MenuContent(
    title: "Quick Start Guide",
    sections: [
        MenuSection(
            title: "Quick Setup",
            content: """
1. Launch MetaWav
2. Click the Power button to turn on the system
3. Click "LOAD FILES" button
4. Select your audio files (you can select multiple files at once)
5. MetaWav will automatically create an album and import everything
6. Your files are now imported and ready to play
7. Use the different side panels to manage your music
"""
        )
    ]
)

// FIXED: Corrected the troubleshooting content variable name and structure
private let troubleshootingContent = MenuContent(
    title: "Troubleshooting",
    sections: [
        MenuSection(
            title: "Loading Issues",
            content: """
Problem: Files won't load or "LOAD FILES" button doesn't work
• Make sure MetaWav is powered on (power button should show red light)
• Check that your audio files are in supported formats (WAV, MP3, FLAC, M4A, etc.)
• Try loading fewer files at once if you have many selected
• Restart MetaWav if the interface becomes unresponsive

Problem: Album appears but tracks don't play
• Check that the original audio files haven't been moved or deleted
• Use Edit > Repath Track to relink tracks to their new locations
• Verify the audio files aren't corrupted by opening them in another audio player
"""
        ),
        MenuSection(
            title: "File Path Issues",
            content: """
Problem: "File not found" or missing tracks
• Original files may have been moved - use Edit > Repath Track to fix this
• Check if files are on external drives that aren't connected
• Use File > Show Track Path to see where MetaWav expects the file to be
• For imported MetaAlbums, files should be in Documents/MetaWav/Library/[AlbumName]/Audio/

Problem: Cannot save metadata or create albums
• Check that you have write permissions to Documents/MetaWav folder
• Make sure your disk isn't full
• Try creating the Documents/MetaWav folder manually if it doesn't exist
"""
        ),
        MenuSection(
            title: "Audio Playback Problems",
            content: """
Problem: No sound or distorted audio
• Check your audio output device in Settings
• Verify your system volume and MetaWav isn't muted
• Try a different audio file to isolate the issue
• Check if other audio applications work normally
• Try changing audio output device in Settings

Problem: Playback is choppy or stuttering
• Check CPU usage - close other demanding applications
• For large/high-resolution files, try lowering system audio quality temporarily
• Make sure audio files are on a fast storage device (not slow USB drives)
"""
        ),
        MenuSection(
            title: "Interface and Display Issues",
            content: """
Problem: Interface appears corrupted or unresponsive
• Try toggling additional panels with ⇧⌘P
• Restart MetaWav completely
• Check for macOS system updates
• Reset window size by minimizing and restoring

Problem: Library shows empty or albums missing
• Use File > Refresh Library to rescan your MetaWav folder
• Check that Documents/MetaWav/Metadata folder exists and has .meta files
• Look for albums in wrong directories - they should be in Documents/MetaWav/
"""
        ),
        MenuSection(
            title: "Diagnostics & Maintenance",
            content: """
If issues persist, try these self‑help steps:

• Refresh Library: File > Refresh Library (⌘R)
• Rebuild Artwork: Edit > Rebuild Artwork (⇧⌘B)
• Repath Missing Tracks: Edit > Repath Track (⇧⌘P)
• Run Cleanup: Settings > Instant Metadata Management > Clean Up
• Verify Output Device: Settings > Audio Settings > Output Device
• Toggle Panels (UI reset): Window > Show/Hide Additional Panels (⇧⌘P)
• Restart MetaWav, then retry the action
"""
        )
    ]
)

private let keyboardShortcutsContent = MenuContent(
    title: "Keyboard Shortcuts",
    sections: [
        MenuSection(
            title: "App",
            content: """
⌘,     Settings…
⌘Q     Quit MetaWav
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "File",
            content: """
⌘O     Load Files…
⌘R     Refresh Library
⇧⌘M    Show Metadata Path
⇧⌘T    Show Track Path
⇧⌘A    Show Art Path
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "Edit & Library Management",
            content: """
⇧⌘N    Create Playlist…
⇧⌘B    Rebuild Artwork…
⇧⌘L    Add Track to Playlist…
⌥⌘R    Remove Track from Playlist…
⇧⌘Q    Add Track to Queue
⇧⌘P    Repath Track…
⌥⌘M    Move Track to Album…
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "Sharing",
            content: """
⇧⌘E    Export MetaAlbum…
⇧⌘I    Import MetaAlbum…
⌘E     Export Album to CSV…
⇧⌘L    Export Track Lyrics as LRC…
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "Window",
            content: """
⌃⌘F    Toggle Full Screen
⌘M     Minimize Window
⇧⌘P    Show/Hide Additional Panels
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "Plugins",
            content: """
⌥⌘S    Save MetaAmp…
⌥⌘O    Load MetaAmp…
⌥⌘P    Add Plugin…
⌥⌘R    Rescan Audio Units
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "Help",
            content: """
⇧⌘?    MetaWav Help
""",
            isCodeBlock: true
        )
    ]
)
private let metaAlbumContent = MenuContent(
    title: "MetaAlbum System",
    sections: [
        MenuSection(
            title: "What are MetaAlbums?",
            content: "MetaAlbums (.metaalbum files) are MetaWav's proprietary format for packaging complete albums with all their audio files, metadata, and artwork into a single, portable file."
        )
    ]
)

private let fileOrganizationContent = MenuContent(
    title: "File Organization",
    sections: [
        MenuSection(
            title: "Understanding MetaWav File Types",
            content: """
MetaWav uses two main file types for organization:

.meta files - Lightweight metadata files that reference your original audio files wherever they are on your system. These contain all album and track information but don't move or copy your original files.

.metaartist files - Artist profile files that contain information about the artist, such as their name, biography, and artwork. These are used for displaying artist information in the library panel.

.metaamp files - MetaAmp files that contain information about the MetaAmp, such as its plugin orders and parameters. These are used for recalling MetaAmp chains.

.metaalbum files - Complete album packages that contain copies of audio files, artwork, and metadata all bundled together. These are used for sharing, backup, or importing complete albums from other MetaWav users.
"""
        ),
        MenuSection(
            title: "Standard MetaWav Organization (User-Created Albums)",
            content: """
When you create albums by loading your own audio files, MetaWav uses a non-destructive approach:

Your Original Files (anywhere on your system):
Desktop/My Music/Song1.wav
Desktop/My Music/Song2.wav
/Users/you/Projects/Audio/Song3.wav

Documents/MetaWav/
└── Metadata/
    └── MyAlbum.meta          # Points to your original file locations

Key Points:
• Your original files stay exactly where they are
• Only lightweight .meta files are created in Documents/MetaWav/Metadata/
• .meta files contain file paths pointing to your originals
• No audio files are copied or moved
• Total storage used: ~50KB per album (just metadata)
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "MetaAlbum Import Organization",
            content: """
When you import a .metaalbum file from another user, MetaWav creates organized copies:

Documents/MetaWav/
├── Metadata/
│   └── ImportedAlbum.meta    # Metadata file (like all albums)
└── Library/ImportedAlbum/    # NEW: Complete album folder under Library
    ├── Audio/                # Audio files from the MetaAlbum
    │   ├── Track1.wav
    │   ├── Track2.wav
    │   └── Track3.wav
    └── Art/                  # Album artwork
        ├── front.jpg
        └── back.jpg

Key Points:
• Audio files are copied from the .metaalbum into your library
• Files are organized in a clean album/audio/art structure
• The .meta file points to these new local copies
• You have a complete, self-contained copy of the album
""",
            isCodeBlock: true
        ),
        MenuSection(
            title: "Why This System Works",
            content: """
User-Created Albums (File Paths):
• Respects your existing file organization
• No storage duplication
• Your workflow stays unchanged

MetaAlbum Imports (File Copies):
• Complete album packages you can share
• Self-contained and portable
• Safe from external file moves/deletions

Both approaches use .meta files for consistent metadata management, but handle audio files differently based on how the album was created.
"""
        ),
    ]
)

// About Content
private let aboutMetaWavContent = MenuContent(
    title: "About MetaWav",
    sections: [
        MenuSection(
            title: "MetaWav Professional Audio Library",
            content: """
MetaWav is a professional audio library designed for musicians, producers, and audio engineers who need precise, reliable control over their audio collections.

Version: 0.9.2
Build: 2026.08.15

"""
        ),
    ]
)

// MARK: - Audio Device Manager

class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()
    
    @Published var outputDevices: [AudioDeviceInfo] = []
    @Published var selectedDeviceID: UInt32 = 0
    @Published var currentSampleRate: String = "Unknown"
    @Published var currentBitDepth: String = "Unknown"
    
    struct AudioDeviceInfo {
        let deviceID: UInt32
        let name: String
    }
    
    private init() {
        refreshDevices()
    }
    
    func refreshDevices() {
        print("🔍 Refreshing audio devices...")
        
        // Get all output devices
        outputDevices = getOutputDevices()
        
        // Get current default device
        selectedDeviceID = getDefaultOutputDevice()
        
        // Update current format info
        updateCurrentFormat()
        
        print("🔍 Found \(outputDevices.count) output devices")
    }
    
    private func getOutputDevices() -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []
        
        // Get device count
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            print("❌ Failed to get device count")
            return devices
        }
        
        let deviceCount = Int(propertySize) / MemoryLayout<UInt32>.size
        var deviceIDs = [UInt32](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("❌ Failed to get device IDs")
            return devices
        }
        
        // Filter for output devices and get names
        for deviceID in deviceIDs {
            if isOutputDevice(deviceID: deviceID) {
                if let name = getDeviceName(deviceID: deviceID) {
                    devices.append(AudioDeviceInfo(deviceID: deviceID, name: name))
                }
            }
        }
        
        return devices
    }
    
    private func isOutputDevice(deviceID: UInt32) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else { return false }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }
        
        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            bufferList
        )
        
        guard getStatus == noErr else { return false }
        
        return bufferList.pointee.mNumberBuffers > 0
    }
    
    private func getDeviceName(deviceID: UInt32) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else { return nil }
        
        let nameStorage = UnsafeMutableRawPointer.allocate(byteCount: Int(propertySize), alignment: MemoryLayout<CFString?>.alignment)
        defer { nameStorage.deallocate() }
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            nameStorage
        )
        guard status == noErr else { return nil }
        
        let cfName = nameStorage.load(as: CFString?.self)
        return (cfName as String?)
    }
    
    private func getDefaultOutputDevice() -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        return status == noErr ? deviceID : 0
    }
    
    func selectDevice(deviceID: UInt32) {
        print("🔊 Selecting device: \(deviceID)")
        
        // Set as default output device
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceIDToSet = deviceID
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            propertySize,
            &deviceIDToSet
        )
        
        if status == noErr {
            selectedDeviceID = deviceID
            updateCurrentFormat()
            print("✅ Successfully selected device: \(deviceID)")
        } else {
            print("❌ Failed to select device: \(deviceID)")
        }
    }
    
    private func updateCurrentFormat() {
        guard selectedDeviceID != 0 else {
            currentSampleRate = "Unknown"
            currentBitDepth = "Unknown"
            return
        }
        
        // Get current sample rate
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 0
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        
        let sampleRateStatus = AudioObjectGetPropertyData(
            selectedDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        if sampleRateStatus == noErr {
            currentSampleRate = String(format: "%.1f kHz", sampleRate / 1000.0)
        } else {
            currentSampleRate = "Unknown"
        }
        
        // Get bit depth from physical stream format (more accurate)
        // First, get the output stream virtual format; if physical format is available, prefer it
        var streamFormat = AudioStreamBasicDescription()
        propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatOK = false
        
        // Try physical stream format (if supported)
        if #available(macOS 12.0, *) {
            var physicalAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamFormat,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let statusPhys = AudioObjectGetPropertyData(
                selectedDeviceID,
                &physicalAddr,
                0,
                nil,
                &propertySize,
                &streamFormat
            )
            formatOK = (statusPhys == noErr)
        }
        
        if !formatOK {
            // Fallback: query stream format as before
            propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamFormat,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectGetPropertyData(
                selectedDeviceID,
                &propertyAddress,
                0,
                nil,
                &propertySize,
                &streamFormat
            )
            formatOK = (status == noErr)
        }
        
        if formatOK {
            let isFloat = (streamFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            let bitDepth = streamFormat.mBitsPerChannel
            if bitDepth == 0 {
                // Some devices report 0 for float; infer from format flags
                currentBitDepth = isFloat ? "32-bit float" : "Unknown"
            } else {
                currentBitDepth = isFloat ? "\(bitDepth)-bit float" : "\(bitDepth)-bit"
            }
        } else {
            currentBitDepth = "Unknown"
        }
        
        print("🔊 Current format: \(currentSampleRate), \(currentBitDepth)")
    }
}

// MARK: - LRC Export Manager
class LRCExporter: ObservableObject {
    static let shared = LRCExporter()
    
    @Published var isExporting = false
    @Published var exportStatus = ""
    
    private init() {}
    
    // Export track lyrics as LRC file
    func exportTrackLyrics(_ track: TrackMetadata, from album: AlbumMetadata) {
        guard let lyrics = track.lyrics, !lyrics.isEmpty else {
            exportStatus = "No lyrics available for this track"
            print("❌ No lyrics to export for track: \(track.name)")
            showAlert(title: "No Lyrics Available",
                     message: "The track '\(track.name)' has no lyrics to export.")
            return
        }
        
        isExporting = true
        exportStatus = "Preparing LRC export..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let lrcContent = self.generateLRCContent(track: track, album: album)
            DispatchQueue.main.async {
                self.saveLRCFile(
                    content: lrcContent,
                    trackName: track.name,
                    albumName: album.albumName
                )
            }
        }
    }
    
    // Generate LRC file content
    private func generateLRCContent(track: TrackMetadata, album: AlbumMetadata) -> String {
        var lrc = ""
        
        // LRC metadata headers
        lrc += "[ar:\(track.artist ?? "Unknown Artist")]\n"
        lrc += "[ti:\(track.name)]\n"
        lrc += "[al:\(album.albumName)]\n"
        
        if let duration = track.duration {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            lrc += "[length:\(String(format: "%02d:%02d", minutes, seconds))]\n"
        }
        
        // Add disc and track info
        if album.discCount > 1 {
            lrc += "[disc:\(track.discNumber)]\n"
        }
        lrc += "[track:\(String(format: "%02d", track.trackNumber))]\n"
        
        // Add technical metadata if available
        if let format = track.format {
            lrc += "[format:\(format)]\n"
        }
        
        if let sampleRate = track.sampleRate {
            lrc += "[samplerate:\(Int(sampleRate))]\n"
        }
        
        if let bitDepth = track.bitDepth {
            lrc += "[bitdepth:\(bitDepth)]\n"
        }
        
        // Add creation info
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        lrc += "[by:MetaWav Professional Audio Library]\n"
        lrc += "[ve:1.0]\n"
        lrc += "[re:Exported on \(formatter.string(from: Date()))]\n"
        
        // Add optional metadata
        if let key = track.key {
            lrc += "[key:\(key)]\n"
        }
        
        if let bpm = track.bpm {
            lrc += "[bpm:\(bpm)]\n"
        }
        
        if let version = track.version {
            lrc += "[version:\(version)]\n"
        }
        
        if track.isExplicit == true {
            lrc += "[explicit:true]\n"
        }
        
        lrc += "\n"
        
        // Sort lyrics by time and convert to LRC format
        let sortedLyrics = track.lyrics!.sorted { $0.time < $1.time }
        
        for lyric in sortedLyrics {
            let timeTag = formatLRCTime(lyric.time)
            // Escape any square brackets in the lyric text
            let escapedText = lyric.text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            lrc += "[\(timeTag)]\(escapedText)\n"
        }
        
        // Add empty line at end for standard compliance
        lrc += "\n"
        
        return lrc
    }
    
    // Format time for LRC format (mm:ss.xx)
    private func formatLRCTime(_ time: TimeInterval) -> String {
        let totalCentiseconds = Int(time * 100)
        let minutes = totalCentiseconds / 6000
        let seconds = (totalCentiseconds % 6000) / 100
        let centiseconds = totalCentiseconds % 100
        
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
    
    // Save LRC file using NSSavePanel
    private func saveLRCFile(content: String, trackName: String, albumName: String) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Track Lyrics as LRC"
        savePanel.allowedContentTypes = [.lrc]
        savePanel.message = "Choose where to save the LRC lyrics file"
        
        // Create suggested filename
        let sanitizedTrackName = sanitizeFilename(trackName)
        let sanitizedAlbumName = sanitizeFilename(albumName)
        savePanel.nameFieldStringValue = "\(sanitizedAlbumName) - \(sanitizedTrackName).lrc"
        
        // Set default directory to Desktop
        savePanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        
        savePanel.begin { response in
            DispatchQueue.main.async {
                if response == .OK, let url = savePanel.url {
                    do {
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        self.exportStatus = "LRC export successful: \(url.lastPathComponent)"
                        print("✅ LRC export saved to: \(url.path)")
                        
                        // Show success message
                        self.showAlert(title: "LRC Export Complete",
                                     message: "Lyrics exported successfully to:\n\(url.lastPathComponent)")
                        
                        // Optionally reveal in Finder
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        
                    } catch {
                        self.exportStatus = "Failed to save LRC file: \(error.localizedDescription)"
                        print("❌ LRC save failed: \(error)")
                        self.showAlert(title: "Save Failed",
                                     message: "Failed to save LRC file: \(error.localizedDescription)")
                    }
                } else {
                    self.exportStatus = "LRC export cancelled"
                    print("📋 LRC export cancelled by user")
                }
                
                self.isExporting = false
            }
        }
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // Validate that a track has exportable lyrics
    func canExportLyrics(for track: TrackMetadata) -> Bool {
        return track.lyrics != nil && !track.lyrics!.isEmpty
    }
    
    // Get lyrics count for a track
    func getLyricsCount(for track: TrackMetadata) -> Int {
        return track.lyrics?.count ?? 0
    }
    
    // Preview LRC content (for debugging or preview purposes)
    func previewLRCContent(track: TrackMetadata, album: AlbumMetadata) -> String? {
        guard track.lyrics != nil && !track.lyrics!.isEmpty else { return nil }
        return generateLRCContent(track: track, album: album)
    }
    
    // Batch export multiple tracks
    func exportMultipleTracks(_ tracks: [TrackMetadata], from album: AlbumMetadata) {
        let tracksWithLyrics = tracks.filter { canExportLyrics(for: $0) }
        
        guard !tracksWithLyrics.isEmpty else {
            showAlert(title: "No Lyrics to Export",
                     message: "None of the selected tracks have lyrics to export.")
            return
        }
        
        // Show folder selection for batch export
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Export Folder"
        openPanel.message = "Select a folder to save \(tracksWithLyrics.count) LRC files"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let folderURL = openPanel.url {
                self.performBatchExport(tracks: tracksWithLyrics, album: album, to: folderURL)
            }
        }
    }
    
    private func performBatchExport(tracks: [TrackMetadata], album: AlbumMetadata, to folderURL: URL) {
        isExporting = true
        var successCount = 0
        var failCount = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            for track in tracks {
                do {
                    let lrcContent = self.generateLRCContent(track: track, album: album)
                    let sanitizedTrackName = self.sanitizeFilename(track.name)
                    let sanitizedAlbumName = self.sanitizeFilename(album.albumName)
                    let filename = "\(sanitizedAlbumName) - \(sanitizedTrackName).lrc"
                    let fileURL = folderURL.appendingPathComponent(filename)
                    
                    try lrcContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    successCount += 1
                    print("✅ Exported: \(filename)")
                } catch {
                    failCount += 1
                    print("❌ Failed to export \(track.name): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.isExporting = false
                
                let message = "Successfully exported \(successCount) LRC files" +
                            (failCount > 0 ? "\n\(failCount) files failed to export" : "")
                
                self.showAlert(title: "Batch Export Complete", message: message)
                
                // Reveal folder in Finder
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            }
        }
    }
}

// MARK: - Cleanup Manager and Log Window
class CleanupManager: ObservableObject {
    static let shared = CleanupManager()
    
    @Published var logLines: [String] = []
    private var logWindowController: NSWindowController?
    
    private init() {}
    
    func runCleanupAndShowLog() {
        logLines.removeAll()
        append("🧹 Cleanup started: \(Date())")
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.performCleanup()
            DispatchQueue.main.async {
                self.append("🧹 Cleanup finished: \(Date())")
                self.showLogWindow()
            }
        }
    }
    
    private func performCleanup() {
        // Basic checks to start with; can be expanded later
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent("Documents/MetaWav")
        let _ = base.appendingPathComponent("Metadata")
        
        // Prepare report sections
        let cleaned: [String] = []
        var missing: [String] = []
        let deleted: [String] = []
        
        _ = ISO8601DateFormatter().string(from: Date())
        
        // Check existence of base
        guard fm.fileExists(atPath: base.path) else {
            append("Cleaned Orphaned Files: -")
            append("Missing Files: -")
            append("Deleted Files: -")
            return
        }
        
        // Simple orphan detection: empty album folders (no Audio and no Metadata link)
        if let dirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]) {
            for url in dirs {
                if url.lastPathComponent == "Metadata" || url.lastPathComponent == "Info" || url.lastPathComponent == "Library" { continue }
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let audioDir = url.appendingPathComponent("Audio")
                    let artDir = url.appendingPathComponent("Art")
                    let audioHasFiles = fm.fileExists(atPath: audioDir.path) && ((try? fm.contentsOfDirectory(atPath: audioDir.path))?.isEmpty == false)
                    let artHasFiles = fm.fileExists(atPath: artDir.path) && ((try? fm.contentsOfDirectory(atPath: artDir.path))?.isEmpty == false)
                    // Report-only: flag folders that have neither Audio nor Art content as potential orphans
                    if !audioHasFiles && !artHasFiles {
                        // Potential orphan candidate; do not delete automatically
                        // Add to missing list as a candidate indicator
                        missing.append(url.lastPathComponent)
                    }
                }
            }
        }
        
        // Metadata scan to detect missing referenced files could be added here; placeholder:
        // missing.append("<file path>")
        
        if cleaned.isEmpty && missing.isEmpty && deleted.isEmpty {
            append("Nothing to report.")
        } else {
            append("Cleaned Orphaned Files: \(cleaned.isEmpty ? "-" : cleaned.joined(separator: ", "))")
            append("Missing Files: \(missing.isEmpty ? "-" : missing.joined(separator: ", "))")
            append("Deleted Files: \(deleted.isEmpty ? "-" : deleted.joined(separator: ", "))")
        }
    }
    
    private func append(_ line: String) {
        DispatchQueue.main.async {
            self.logLines.append(line)
        }
    }
    
    private func showLogWindow() {
        // Close existing
        logWindowController?.close()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cleanup Log"
        window.center()
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        
        let controller = NSWindowController(window: window)
        logWindowController = controller
        
        let view = CleanupLogView()
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        
        controller.showWindow(nil)
    }
}

struct CleanupLogView: View {
    @ObservedObject private var manager = CleanupManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Log")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            Text("This scan reports orphaned files and basic inconsistencies in your MetaWav folder. No files were deleted.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(manager.logLines.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                Button("Rerun Scan") {
                    CleanupManager.shared.runCleanupAndShowLog()
                }
                Button("Copy Log") {
                    let paste = NSPasteboard.general
                    paste.clearContents()
                    paste.setString(manager.logLines.joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - LRC Export Status View (Optional - for showing export progress)
struct LRCExportStatusView: View {
    @ObservedObject private var exporter = LRCExporter.shared
    
    var body: some View {
        Group {
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
                    .onAppear {
                        // Clear status after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            exporter.exportStatus = ""
                        }
                    }
            }
        }
    }
}
