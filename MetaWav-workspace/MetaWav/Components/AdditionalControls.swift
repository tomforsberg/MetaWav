import SwiftUI
import MediaPlayer

struct AdditionalControls: View {
    @Binding var activeView: BottomPanelViewType
    @Binding var isBottomPanelVisible: Bool
    @Binding var mainPanelMode: MainPanelMode
    @Binding var isPoweredOn: Bool
    @Binding var timecodePanelMode: TimecodePanelMode
    
    private class SoundPlayer {
        private var sounds: [String: NSSound] = [:]
        private let settingsManager = SettingsManager.shared
        
        func play(named name: String) {
            guard settingsManager.enableSoundEffects else {
                print("🔇 Sound effects disabled - skipping \(name)")
                return
            }
            
            sounds[name]?.stop()
            
            if sounds[name] == nil {
                guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                    print("Sound file not found: \(name).wav")
                    return
                }
                sounds[name] = NSSound(contentsOf: url, byReference: false)
                sounds[name]?.volume = 1.0
            }
            
            sounds[name]?.currentTime = 0
            sounds[name]?.play()
            print("🔊 Playing transport sound: \(name)")
        }
    }
    
    private let soundPlayer = SoundPlayer()
    
    var body: some View {
        ZStack {
            // Show/Hide button (unchanged behavior)
            Button(action: {
                print("🔄 Show/Hide button tapped - current state: \(isBottomPanelVisible)")
                isBottomPanelVisible.toggle()
                print("🔄 New state: \(isBottomPanelVisible)")
                
                WindowManager.shared.togglePanels(visible: isBottomPanelVisible)
            }) {
                Color.clear
            }
            .realistic3DButton(width: 147.60, height: 10)
            .offset(x: 0, y: 140)
            
            // Labels above buttons. CD skin keeps placeholder labels.
            // Streaming skin drops these labels entirely.
            Group {
                if mainPanelMode == .cd {
                    // Placeholder CD panel labels for future use
                    Text("AUDIO")
                        .font(Font.custom("Rubik Mono One", size: 8))
                        .tracking(0.50)
                        .opacity(0.90)
                        .lineSpacing(20)
                        .foregroundColor(.white)
                        .offset(x: 345.39, y: 24.51) // Left edge of button, Y aligned with AMP light
                        .allowsHitTesting(false)
                        .frame(width: 70, alignment: .leading)
                    
                    Text("STANDARD")
                        .font(Font.custom("Rubik Mono One", size: 8))
                        .tracking(0.50)
                        .opacity(0.90)
                        .lineSpacing(20)
                        .foregroundColor(.white)
                        .offset(x: 345.39, y: -43.90) // Left edge of button, Y aligned with LYRICS light
                        .allowsHitTesting(false)
                        .frame(width: 70, alignment: .leading)
                    
                    Text("DEVICE")
                        .font(Font.custom("Rubik Mono One", size: 8))
                        .tracking(0.50)
                        .opacity(0.90)
                        .lineSpacing(20)
                        .foregroundColor(.white)
                        .offset(x: 434.73, y: 24.51) // Left edge of button, same Y as AMP
                        .allowsHitTesting(false)
                        .frame(width: 70, alignment: .leading)
                    
                    Text("ADVANCED")
                        .font(Font.custom("Rubik Mono One", size: 8))
                        .tracking(0.50)
                        .opacity(0.90)
                        .lineSpacing(20)
                        .foregroundColor(.white)
                        .offset(x: 434.73, y: -43.90) // Left edge of button, Y aligned with METADATA light
                        .allowsHitTesting(false)
                        .frame(width: 70, alignment: .leading)
                }
            }
            
            if mainPanelMode == .cd {
                // CD skin: physical 3D buttons only, with no current functionality.
                // AMP Button
                Button(action: {
                    soundPlayer.play(named: "AudioSound_1")
                    guard isPoweredOn else { return }
                    timecodePanelMode = .audio
                }) {
                    Color.clear
                }
                .realistic3DButton(width: 73.80, height: 35.01)
                .offset(x: 345.29, y: 50.63)
                .disabled(!isPoweredOn)
                
                // LYRICS Button
                Button(action: {
                    soundPlayer.play(named: "StandardSound_1")
                    guard isPoweredOn else { return }
                    timecodePanelMode = .standard
                }) {
                    Color.clear
                }
                .realistic3DButton(width: 73.80, height: 35.01)
                .offset(x: 345.29, y: -17.24)
                .disabled(!isPoweredOn)
                
                // QUEUE Button
                Button(action: {
                    soundPlayer.play(named: "DeviceSound_1")
                    guard isPoweredOn else { return }
                    timecodePanelMode = .device
                }) {
                    Color.clear
                }
                .realistic3DButton(width: 73.80, height: 35.01)
                .offset(x: 433.63, y: 50.63)
                .disabled(!isPoweredOn)
                
                // METADATA Button
                Button(action: {
                    soundPlayer.play(named: "AdvancedSound_1")
                    guard isPoweredOn else { return }
                    timecodePanelMode = .advanced
                }) {
                    Color.clear
                }
                .realistic3DButton(width: 73.80, height: 35.01)
                .offset(x: 433.63, y: -17.24)
                .disabled(!isPoweredOn)
            }
            
        }
    }
}

