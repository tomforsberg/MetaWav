// QueueView.swift - Modern queue view with drag-and-drop support
import SwiftUI
import AVFoundation

struct QueueView: View {
    @ObservedObject private var queueManager = QueueManager.shared
    @Binding var isPoweredOn: Bool
    
    @State private var draggedItem: QueueItem?
    @State private var showShuffleControls = false
    @State private var showRepeatControls = false
    @StateObject private var dragState = DragState()
    
    var body: some View {
        ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Content area
                if queueManager.isQueueEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 0) {
                        // Fixed header area: NOW PLAYING + controls
                        nowPlayingSection
                            .padding(.horizontal, PanelTheme.horizontalPadding)
                            .padding(.top, PanelTheme.topPadding)
                            .padding(.bottom, PanelTheme.bottomPadding)
                        
                        // Scrollable area: QUEUE (x TRACKS) header and list
                        queueContentView
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        // Background dragging remains disabled; only the top drag strip in ContentView moves the window.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(maxHeight: .infinity)
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }
    
    private var controlButtonsView: some View {
        HStack(spacing: 12) {
            // Shuffle button
            Button(action: {
                queueManager.toggleShuffle()
            }) {
                Image(systemName: queueManager.isShuffled ? "shuffle.circle.fill" : "shuffle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(queueManager.isShuffled ? Color(red: 0, green: 0.75, blue: 0.39) : .white)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(6)
            .background(
                Color.clear.secondaryGlass(cornerRadius: 6)
            )
            
            // Repeat button
            Button(action: {
                queueManager.cycleRepeatMode()
            }) {
                Image(systemName: queueManager.repeatMode.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(queueManager.repeatMode != .none ? Color(red: 0, green: 0.75, blue: 0.39) : .white)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(6)
            .background(
                Color.clear.secondaryGlass(cornerRadius: 6)
            )
            

        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.4))
            
            Text("NO TRACKS IN QUEUE")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Color(white: 0.6))
            
            Text("Add albums or tracks to view or edit the queue")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Queue Content
    
    private var queueContentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // QUEUE SECTION (upcoming tracks)
                if !queueManager.upcomingItems.isEmpty {
                    upcomingTracksSection
                }
            }
            .padding(.horizontal, PanelTheme.horizontalPadding)
            .padding(.bottom, PanelTheme.bottomPadding)
        }
    }
    
    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with controls aligned right
            HStack {
                Text("NOW PLAYING")
                    .font(.system(size: PanelTheme.sectionHeaderFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
                Spacer()
                if !queueManager.isQueueEmpty {
                    controlButtonsView
                }
            }
            
            // Current track
            if let currentItem = queueManager.currentItem {
                QueueTrackRow(
                    item: currentItem,
                    isCurrentTrack: true,
                    isPlaying: queueManager.state == .playing,
                    queuePosition: 1,
                    canDrag: false,
                    onRemove: nil
                )
            }
        }
    }
    
    private var upcomingTracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("QUEUE (\(queueManager.upcomingItems.count) TRACKS)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
                
                Spacer()
            }
            
            // Track list with drag and drop
            VStack(spacing: 8) {
                ForEach(Array(queueManager.upcomingItems.enumerated()), id: \.element.id) { index, item in
                    if dragState.isDragging && dragState.dropTargetIndex == index {
                        dropGap()
                    }
                    QueueTrackRow(
                        item: item,
                        isCurrentTrack: false,
                        isPlaying: false,
                        queuePosition: index + 2, // Start from 2 since current is 1
                        canDrag: !queueManager.isShuffled,
                        onRemove: {
                            removeTrackFromQueue(item)
                        }
                    )
                    .compositingGroup()
                    .zIndex(draggedItem?.id == item.id ? 100 : 0)
                    .opacity(draggedItem?.id == item.id && dragState.isDragging ? 0.001 : 1)
                    .onDrag {
                        draggedItem = item
                        dragState.startDrag(itemId: item.id, item: item.displayName)
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: QueueDropDelegate(
                        destinationItem: item,
                        queueManager: queueManager,
                        draggedItem: $draggedItem,
                        dragState: dragState
                    ))
                }
                if dragState.isDragging && dragState.dropTargetIndex == queueManager.upcomingItems.count {
                    dropGap()
                }
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 8)
                    .onDrop(of: [.text], delegate: QueueEndDropDelegate(
                        queueManager: queueManager,
                        draggedItem: $draggedItem,
                        dragState: dragState
                    ))
            }
            .coordinateSpace(name: "QueueListSpace")
            .onDrop(of: [.text], isTargeted: nil) { providers in
                // Fallback: If a drop occurs on the container but not captured by row delegates,
                // finalize with current computed drop target.
                draggedItem = nil
                dragState.endDrag()
                return true
            }
            .overlay(alignment: .topLeading) {
                if dragState.isDragging, let loc = dragState.currentLocation, let label = dragState.draggedItem {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                        .position(x: loc.x, y: loc.y)
                        .allowsHitTesting(false)
                        .zIndex(999)
                }
            }
        }
    }
    
    private func dropIndicator() -> some View {
        HStack {
            Circle()
                .fill(PanelTheme.accent)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(PanelTheme.accent)
                .frame(height: 2)
            Circle()
                .fill(PanelTheme.accent)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.2), value: dragState.dropTargetIndex)
        .transition(.scale.combined(with: .opacity))
    }

    private func dropGap() -> some View {
        VStack(spacing: 6) {
            dropIndicator()
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 10)
                .cornerRadius(4)
        }
        .padding(.horizontal, 4)
        .zIndex(-1)
    }

    // MARK: - Helper Methods
    
    private func removeTrackFromQueue(_ item: QueueItem) {
        if let index = queueManager.queue.firstIndex(of: item) {
            queueManager.removeFromQueue(at: index)
        }
    }
}

// MARK: - Drop Delegate

struct QueueDropDelegate: DropDelegate {
    let destinationItem: QueueItem
    let queueManager: QueueManager
    @Binding var draggedItem: QueueItem?
    let dragState: DragState
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem != destinationItem else { return }
        
        // Use object identity to find positions in the full queue
        if let fromIndex = queueManager.queue.firstIndex(where: { $0.id == draggedItem.id }),
           let toIndex = queueManager.queue.firstIndex(where: { $0.id == destinationItem.id }) {
            // Update visual indicator to show drop above this row within upcoming section
            // Map absolute queue index to upcoming section index (which starts after currentIndex)
            let currentIdx = queueManager.currentIndex ?? -1
            let upcomingIndex = max(0, toIndex - (currentIdx + 1))
            dragState.updateDropTarget(index: upcomingIndex)
            queueManager.moveQueueItem(from: fromIndex, to: toIndex)
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        dragState.endDrag()
        return true
    }
}

struct QueueEndDropDelegate: DropDelegate {
    let queueManager: QueueManager
    @Binding var draggedItem: QueueItem?
    let dragState: DragState
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        if let fromIndex = queueManager.queue.firstIndex(where: { $0.id == draggedItem.id }) {
            let lastIndex = max(0, queueManager.queue.count - 1)
            dragState.updateDropTarget(index: queueManager.upcomingItems.count)
            if fromIndex != lastIndex {
                queueManager.moveQueueItem(from: fromIndex, to: lastIndex)
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        dragState.endDrag()
        return true
    }
}

// MARK: - Queue Track Row

struct QueueTrackRow: View {
    let item: QueueItem
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let queuePosition: Int
    let canDrag: Bool
    let onRemove: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle or status icon
            Group {
                if canDrag {
                    Image(systemName: "line.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                } else if isCurrentTrack {
                    // Lock icon for current track
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(white: 0.4))
                } else {
                    // Shuffle icon when shuffled
                    Image(systemName: "shuffle")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(white: 0.4))
                }
            }
            .frame(width: 16)
            
            // Position/play indicator
            Group {
                if isCurrentTrack {
                    Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PanelTheme.accent)
                } else {
                    Text("\(queuePosition)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .frame(width: 20, alignment: .center)
            
            // Track number from metadata
            Group {
                if let trackMetadata = item.track {
                    Text(String(format: "%02d", trackMetadata.trackNumber))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isCurrentTrack ? PanelTheme.accent : Color(white: 0.6))
                } else {
                    Text("--")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }
            }
            .frame(width: 24, alignment: .trailing)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                // Track name
                Text(item.displayName)
                    .font(.system(size: 13, weight: isCurrentTrack ? .medium : .regular))
                    .foregroundColor(isCurrentTrack ? .white : Color(white: 0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Artist (if available)
                if !item.artistName.isEmpty {
                    Text(item.artistName)
                        .font(.system(size: 11))
                        .foregroundColor(isCurrentTrack ? Color(red: 0, green: 0.75, blue: 0.39) : Color(white: 0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            
            Spacer()
            
            // Duration
            Text(item.formattedDuration)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
            
            // Remove button (only for upcoming tracks)
            if !isCurrentTrack, let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.4))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(0.7)
            }
        }
        .padding(12)
        .background(
            Group {
                if isCurrentTrack {
                    Color.clear.selectedGlass(cornerRadius: 6)
                } else {
                    Color.clear.secondaryGlass(cornerRadius: 6)
                }
            }
        )
        .onHover { _ in /* disable hover tint during DnD in queue; handled at parent if needed */ }
        .zIndex(0.5) // keep rows below any dragged SwiftUI rows that apply zIndex=2
    }
}

// MARK: - Preview

struct QueueView_Previews: PreviewProvider {
    static var previews: some View {
        QueueView(isPoweredOn: .constant(true))
            .frame(width: 400, height: 600)
    }
}