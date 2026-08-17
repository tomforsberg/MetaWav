import SwiftUI
import AVFoundation
import AppKit

struct PowerButton: View {
    @Binding var isPoweredOn: Bool
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentFileIndex: Int?
    @Binding var currentTime: TimeInterval
    @Binding var audioPlayer: AVAudioPlayer?
    @Binding var selectedTrack: TrackMetadata?
    @Binding var mainPanelMode: MainPanelMode
    
    private let audioProcessor = AudioProcessor.shared
    private var powerOnSound: NSSound?
    private var powerOffSound: NSSound?
    
    @StateObject private var settingsManager = SettingsManager.shared
    
    init(isPoweredOn: Binding<Bool>,
         audioFiles: Binding<[AVAudioFile]>,
         currentFileIndex: Binding<Int?>,
         currentTime: Binding<TimeInterval>,
         audioPlayer: Binding<AVAudioPlayer?>,
         selectedTrack: Binding<TrackMetadata?>,
         mainPanelMode: Binding<MainPanelMode>) {
        
        self._isPoweredOn = isPoweredOn
        self._audioFiles = audioFiles
        self._currentFileIndex = currentFileIndex
        self._currentTime = currentTime
        self._audioPlayer = audioPlayer
        self._selectedTrack = selectedTrack
        self._mainPanelMode = mainPanelMode
        
        // Updated sound file names
        self.powerOnSound = loadSound(named: "PowerOnSound_1")
        self.powerOffSound = loadSound(named: "PowerOffSound_1")
    }

    var body: some View {
        ZStack {
            if mainPanelMode == .cd {
                // CD skin: original label + physical 3D button
                Text("POWER")
                    .font(Font.custom("Rubik Mono One", size: 10))
                    .tracking(0.50)
                    .opacity(0.90)
                    .lineSpacing(20)
                    .foregroundColor(.white)
                    .offset(x: -447.09, y: -54.02) // Above button
                    .allowsHitTesting(false)
                
                Button(action: togglePower) {
                    Color.clear
                }
                .realistic3DSquareButton(size: 41.48)
                .offset(x: -447.26, y: -20.46)
            }
        }
    }
    
    private func loadSound(named filename: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "wav") else {
            print("Error: Sound file \(filename).wav not found")
            return nil
        }
        
        let sound = NSSound(contentsOf: url, byReference: false)
        sound?.volume = 1.0
        return sound
    }
    
    private func playSound(_ sound: NSSound?) {
        guard settingsManager.enableSoundEffects else {
            print("🔇 Sound effects disabled - skipping sound")
            return
        }
        
        sound?.stop()
        sound?.currentTime = 0
        sound?.play()
        print("🔊 Playing \(sound == powerOnSound ? "power on" : "power off") sound effect")
    }
    
    private func togglePower() {
        // Play the appropriate sound effect
        if isPoweredOn {
            playSound(powerOffSound)
        } else {
            playSound(powerOnSound)
        }
        
        // Slight delay to let the sound play before state change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isPoweredOn.toggle()
            if self.isPoweredOn {
                self.powerOn()
            } else {
                self.powerOff()
            }
        }
    }
    
    private func powerOn() {
        print("🔋 Powering ON audio system")
        // Additional power-on initialization if needed
    }
    
    private func powerOff() {
        print("🔌 Powering OFF audio system - FULL CLEANUP")
        
        // Stop playback and clear audio engine state
        audioProcessor.fullCleanup()
        audioPlayer?.stop()
        audioPlayer = nil
        currentFileIndex = nil
        currentTime = 0
        audioFiles.removeAll()
        selectedTrack = nil
        
        // Ensure the queue/UI are reset so nothing resumes on power-on
        QueueManager.shared.clearQueue()
        NowPlayingManager.shared.clearNowPlayingInfo()

        MenuBarManager.shared.updateSelectedTrack(nil)
        MenuBarManager.shared.updateCurrentTrack(nil)
    }
}
