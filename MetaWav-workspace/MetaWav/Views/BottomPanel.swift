// BottomPanel.swift - Updated with resizable panels
import SwiftUI
import AVFoundation
import Foundation

struct BottomPanel: View {
    // All the existing bindings (keep these for compatibility)
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentFileIndex: Int?
    @Binding var activeView: BottomPanelViewType
    @Binding var isPoweredOn: Bool
    @Binding var currentTime: TimeInterval
    @Binding var isBottomPanelVisible: Bool
    @Binding var isEditing: Bool
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var audioPlayer: AVAudioPlayer?
    @Binding var selectedTrack: TrackMetadata?
    
    private let fixedWidth: CGFloat = 1024
    
    // MARK: - Resizable State
    @State private var libraryPanelWidth: CGFloat = 683 // Initial 2/3 width
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    
    // Constraints for resizing
    private let minLibraryWidth: CGFloat = 300  // Minimum library panel width
    private let minDynamicWidth: CGFloat = 250  // Minimum dynamic panel width
    private let dividerWidth: CGFloat = 8       // Width of the draggable divider
    
    // Calculate dynamic panel width based on library width
    private var dynamicPanelWidth: CGFloat {
        fixedWidth - libraryPanelWidth - dividerWidth
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Library Panel Container (resizable width)
            LibraryPanel(
                currentAlbum: $currentAlbum,
                audioFiles: $audioFiles,
                currentFileIndex: $currentFileIndex,
                currentTime: $currentTime,
                selectedTrack: $selectedTrack,
                isPoweredOn: $isPoweredOn,
                audioPlayer: $audioPlayer,
                onNavigateToArtist: { artistName in
                    // Navigation is handled internally by LibraryPanel
                    print("🎭 Artist navigation triggered: \(artistName)")
                }
            )
            .frame(width: libraryPanelWidth)
            .clipped() // Ensure content doesn't overflow during resize

            // Visual divider between panels (reserved width already accounted for)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: dividerWidth)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            
            // Additional Window Container (dynamic width)
            AdditionalWindowView(
                activeView: $activeView,
                currentFileIndex: $currentFileIndex,
                audioFiles: $audioFiles,
                currentTime: $currentTime,
                isEditing: $isEditing,
                currentAlbum: $currentAlbum,
                selectedTrack: $selectedTrack,
                isPoweredOn: $isPoweredOn
            )
            .frame(width: dynamicPanelWidth)
            .background(Color.clear)
            .clipped() // Ensure content doesn't overflow during resize
        }
        .frame(width: fixedWidth)
        .scaleEffect(isHovering ? 1.005 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.2), value: isHovering)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.2), value: activeView)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: currentFileIndex) { _, newIndex in
            if newIndex == nil {
                isEditing = false
                selectedTrack = nil
            }
        }
        .onChange(of: isPoweredOn) { _, powered in
            if !powered {
                selectedTrack = nil
            }
        }
    }
    
    // MARK: - Resize Logic
    
    private func updateLibraryWidth(_ dragAmount: CGFloat) {
        let newWidth = libraryPanelWidth + dragAmount
        
        // Calculate the maximum library width (ensuring minimum dynamic panel width)
        let maxLibraryWidth = fixedWidth - minDynamicWidth - dividerWidth
        
        // Apply constraints
        let constrainedWidth = max(minLibraryWidth, min(maxLibraryWidth, newWidth))
        
        libraryPanelWidth = constrainedWidth
        
        print("📏 Library panel width: \(Int(libraryPanelWidth))px, Dynamic panel width: \(Int(dynamicPanelWidth))px")
    }
}

struct AdditionalWindowView: View {
    @Binding var activeView: BottomPanelViewType
    @Binding var currentFileIndex: Int?
    @Binding var audioFiles: [AVAudioFile]
    @Binding var currentTime: TimeInterval
    @Binding var isEditing: Bool
    @Binding var currentAlbum: AlbumMetadata?
    @Binding var selectedTrack: TrackMetadata?
    @Binding var isPoweredOn: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Dynamic panel mode header – shared across all skins
            HStack(spacing: 8) {
                headerButton(label: "AMP", view: .amp)
                headerButton(label: "LYRICS", view: .lyrics)
                headerButton(label: "QUEUE", view: .queue)
                headerButton(label: "META", view: .metadata)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            
        ZStack {
            if !isPoweredOn {
                VStack {
                    Spacer()
                    Text("POWER OFF")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                    Spacer()
                }
                .background(Color.clear)
                .frame(maxHeight: .infinity)
                .padding(.top, 8)
            } else {
                switch activeView {
                case .lyrics:
                    LyricsView(
                        currentFileIndex: $currentFileIndex,
                        audioFiles: $audioFiles,
                        currentTime: $currentTime,
                        isEditing: $isEditing,
                        currentAlbum: $currentAlbum,
                        selectedTrack: $selectedTrack
                    )
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    
                case .metadata:
                    AlbumMetadataView(
                        currentFileIndex: $currentFileIndex,
                        audioFiles: $audioFiles,
                        currentAlbum: $currentAlbum,
                        selectedTrack: $selectedTrack
                    )
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    
                case .amp:
                    AudioUnitRackView()
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                        
                case .queue:
                    QueueView(isPoweredOn: $isPoweredOn)
                    .padding(.top, 8)
                    .background(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(maxHeight: .infinity)
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }
}

private extension AdditionalWindowView {
    func headerButton(label: String, view: BottomPanelViewType) -> some View {
        let isActive = activeView == view
        return Button(action: {
            activeView = view
        }) {
            Text(label)
                .font(Font.custom("Rubik Mono One", size: 8))
                .tracking(0.5)
                .foregroundColor(isActive ? Color(red: 0, green: 0.75, blue: 0.39) : Color.white.opacity(0.7))
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isPoweredOn)
        .opacity(isPoweredOn ? 1.0 : 0.4)
    }
}

// MARK: - Cursor Extension for SwiftUI

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Glass Card Modifier

private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
    }
}

