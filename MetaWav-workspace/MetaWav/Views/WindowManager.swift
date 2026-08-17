import SwiftUI
import AppKit
import SwiftUI

// Helper NSViewRepresentable to access NSWindow from SwiftUI hierarchy
struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            } else {
                // Try again shortly in case the view hasn't been attached yet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let window = view.window {
                        onResolve(window)
                    }
                }
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            onResolve(window)
        }
    }
}

// A transparent NSView subclass that allows dragging the window when dragging this strip.
private final class DragStripNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct TitlebarDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragStripNSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op; drag behavior is provided by DragStripNSView override
    }
}

struct ExtraItems: View {
    @Binding var mainPanelMode: MainPanelMode
    
    /// Model number text varies by main panel skin.
    private var modelNumberText: String {
        return mainPanelMode == .cd ? "CD-12064" : ""
    }
    
    var body: some View {
        // Model number text – only when non-empty
        if !modelNumberText.isEmpty {
            Text(modelNumberText)
                .font(Font.custom("Rubik Mono One", size: 10))
                .tracking(0.50)
                .lineSpacing(20)
                .foregroundColor(.white)
                .frame(width: 60, alignment: .leading)
                .offset(x: -9.69, y: -98.57)
        }
        
        // Credits image - replacing "BUILT BY FORS AUDIO" text
        Image("MWFA")
            .resizable()
            .scaledToFit()
            .frame(height: 100)
            .opacity(0.75)
            .offset(x: -232.13, y: 45.63)
        
        // Professional Audio Library image - replacing "METAWAV PROFESSIONAL AUDIO LIBRARY" text
        Image("PAL")
            .resizable()
            .scaledToFit()
            .frame(height: 200) // Slightly smaller than MWFA
            .offset(x: 320, y: 110) // moved up by 10px for better balance
            .zIndex(1500) // Ensure PAL floats above streaming overlay
    }
}

// Updated Lights struct for WindowManager.swift
struct Lights: View {
    @Binding var isPoweredOn: Bool
    @Binding var timecodePanelMode: TimecodePanelMode
    @Binding var mainPanelMode: MainPanelMode
    
    var body: some View {
        if mainPanelMode == .cd {
            // Power indicator light (red rectangle) - embedded into the front panel
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isPoweredOn ? Color(red: 0.78, green: 0, blue: 0) : Color(red: 0.3, green: 0, blue: 0))
                .frame(width: 32.86, height: 9.70)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.8),
                                    Color.white.opacity(0.25)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )
                .offset(x: -447.09, y: -75.68)
            
            // CD deck-only button lights. Streaming skin uses symbol color instead.
            if mainPanelMode == .cd {
                // Metadata button light indicator
                Circle()
                    .fill(timecodePanelMode == .advanced && isPoweredOn ?
                          Color(red: 0.78, green: 0, blue: 0) :
                          Color(red: 0.3, green: 0, blue: 0))
                    .frame(width: 9.70, height: 9.70)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7),
                                        Color.white.opacity(0.4)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.7
                            )
                    )
                    .offset(x: 465.68, y: -43.36)
                
                // Amp button light indicator
                Circle()
                    .fill(timecodePanelMode == .audio && isPoweredOn ?
                          Color(red: 0.78, green: 0, blue: 0) :
                          Color(red: 0.3, green: 0, blue: 0))
                    .frame(width: 9.70, height: 9.70)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7),
                                        Color.white.opacity(0.4)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.7
                            )
                    )
                    .offset(x: 377.34, y: 24.51)
                
                // Queue button light indicator
                Circle()
                    .fill(timecodePanelMode == .device && isPoweredOn ?
                          Color(red: 0.78, green: 0, blue: 0) :
                          Color(red: 0.3, green: 0, blue: 0))
                    .frame(width: 9.70, height: 9.70)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7),
                                        Color.white.opacity(0.4)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.7
                            )
                    )
                    .offset(x: 465.68, y: 24.51)
                
                // Lyric button light indicator
                Circle()
                    .fill(timecodePanelMode == .standard && isPoweredOn ?
                          Color(red: 0.78, green: 0, blue: 0) :
                          Color(red: 0.3, green: 0, blue: 0))
                    .frame(width: 9.70, height: 9.70)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7),
                                        Color.white.opacity(0.4)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.7
                            )
                    )
                    .offset(x: 377.34, y: -43.90)
            }
        }
    }
}

// WindowManager.swift - Updated for FULLY RESIZABLE window

class WindowManager {
    static let shared = WindowManager()
    
    // Track whether additional panels are visible to adjust min-height dynamically
    private var areAdditionalPanelsVisible: Bool = true
    private var lastExpandedContentHeight: CGFloat? = nil
    private var lastExpandedContentWidth: CGFloat? = nil

    // MARK: - Fully Resizable Window Calculations
    struct WindowCalculations {
        static let minHeight: CGFloat = 400
        static let maxHeight: CGFloat = 1200
        
        // CHANGED: Made width fully flexible
        static let minWidth: CGFloat = 800   // Minimum width to keep UI usable
        static let maxWidth: CGFloat = 3000  // Reasonable maximum for ultra-wide displays
        
        // REMOVED: Fixed width constraint
        static func requiredWidth(forHeight height: CGFloat, withPanels: Bool) -> CGFloat {
            // Return minimum width - window can grow beyond this
            return minWidth
        }
        
        // Default startup sizes - more reasonable for modern displays
        static let defaultHeight: CGFloat = 586
        static let defaultWidth: CGFloat = 1200  // Slightly wider default
        
    }
    
    private init() {}
    
    // Apply hidden/transparent title bar and full-size content view to a given window
    func applyHiddenTitleBar(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        // Do not force background dragging here; configure explicitly elsewhere
    }

    // We no longer toggle background movability dynamically; only the explicit strip should move the window.

    // MARK: - Fully Resizable Window Setup
    func configureWindow(for providedWindow: NSWindow? = nil) {
        DispatchQueue.main.async {
            guard let window = providedWindow ?? NSApplication.shared.windows.first else {
                print("❌ No window found")
                return
            }
            
            // Use AppKit properties to remove the default title bar appearance
            self.applyHiddenTitleBar(to: window)

            // Set initial size
            let initialSize = NSSize(
                width: WindowCalculations.defaultWidth,
                height: WindowCalculations.defaultHeight
            )
            window.setContentSize(initialSize)
            
            // Apply dynamic constraints based on current panel visibility
            self.applyCurrentConstraints()
            
            // Make fully resizable (both width and height)
            window.styleMask.insert(.resizable)
            
            // Set delegate for proper resizing behavior
            window.delegate = FullyResizableDelegate.shared
            
            // Default: prevent moving window by dragging background to avoid conflicts with content drags
            window.isMovableByWindowBackground = false

            window.center()
            print("✅ Window configured as fully resizable: \(WindowCalculations.minWidth)-\(WindowCalculations.maxWidth)px wide")
        }
    }
    
    // Compute the minimum window height for a given width based on panel visibility
    func computeMinHeight(forWidth width: CGFloat) -> CGFloat {
        if areAdditionalPanelsVisible {
            return WindowCalculations.minHeight
        }
        // CD-only mode: match ContentView where CD uses 100% of width
        let cdPanelAspectRatio: CGFloat = 1024.0 / 286.39 // width / height
        let cdHeight = width / cdPanelAspectRatio
        // Keep a small sensible floor to avoid ultra-small windows
        return max(ceil(cdHeight), 200)
    }

    // Re-apply current min/max constraints to the active window
    func applyCurrentConstraints() {
        guard let window = NSApplication.shared.windows.first else { return }
        let currentWidth = window.frame.size.width
        let minHeight = computeMinHeight(forWidth: currentWidth)
        window.minSize = NSSize(
            width: WindowCalculations.minWidth,
            height: minHeight
        )
        window.maxSize = NSSize(
            width: WindowCalculations.maxWidth,
            height: WindowCalculations.maxHeight
        )
    }

    // MARK: - Panel Toggle
    func togglePanels(visible: Bool) {
        areAdditionalPanelsVisible = visible
        applyCurrentConstraints()
        guard let window = NSApplication.shared.windows.first else {
            print("❌ No window to resize on panel toggle")
            return
        }

        // Work with content rect to compute precise heights
        let currentFrame = window.frame
        let styleMask = window.styleMask
        let currentContentRect = NSWindow.contentRect(forFrameRect: currentFrame, styleMask: styleMask)
        let currentContentWidth = currentContentRect.width
        // CD is laid out at 70% of the window width in main layout
        let cdLayoutWidth = currentContentWidth * 0.7

        // If we are about to hide panels, remember current content size as the expanded size to restore later
        if !visible {
            lastExpandedContentHeight = currentContentRect.height
            lastExpandedContentWidth = currentContentRect.width
        }

        // Compute target content width first
        let targetContentWidth: CGFloat = {
            if visible {
                let desiredW = lastExpandedContentWidth ?? WindowCalculations.defaultWidth
                let clampedW = min(max(desiredW, WindowCalculations.minWidth), WindowCalculations.maxWidth)
                return clampedW
            } else {
                // Collapse horizontally by bringing in the right side to the left-column width (70%)
                let collapsed = max(200, cdLayoutWidth)
                return collapsed
            }
        }()

        // Compute target content height based on mode
        let targetContentHeight: CGFloat = {
            if visible {
                // Restore last expanded height if available, otherwise use default
                let desiredH = lastExpandedContentHeight ?? WindowCalculations.defaultHeight
                let clampedH = min(max(desiredH, WindowCalculations.minHeight), WindowCalculations.maxHeight)
                return clampedH
            } else {
                // CD-only height derived from the target CD width so aspect is correct
                let cdAspect: CGFloat = 1024.0 / 286.39
                let cdHeight = targetContentWidth / cdAspect
                // Also respect our dynamic minimum for robustness
                let dynamicMin = computeMinHeight(forWidth: targetContentWidth)
                return max(cdHeight, dynamicMin)
            }
        }()

        // Before resizing, relax min width when hiding so the window can shrink horizontally
        let currentMin = window.minSize
        if !visible {
            let newMinWidth = min(WindowCalculations.minWidth, targetContentWidth)
            window.minSize = NSSize(width: newMinWidth, height: currentMin.height)
        } else {
            window.minSize = NSSize(width: WindowCalculations.minWidth, height: currentMin.height)
        }

        // First, set content size directly to target size
        window.setContentSize(NSSize(width: targetContentWidth, height: targetContentHeight))
        window.contentView?.layoutSubtreeIfNeeded()

        // Then build new frame keeping the TOP and LEFT edges anchored (collapse from bottom/right)
        var newContentRect = currentContentRect
        newContentRect.size.height = targetContentHeight
        newContentRect.size.width = targetContentWidth
        let newFrameRect = NSWindow.frameRect(forContentRect: newContentRect, styleMask: styleMask)
        let newOriginY = currentFrame.maxY - newFrameRect.height
        let adjustedFrame = NSRect(x: currentFrame.origin.x, y: newOriginY, width: newFrameRect.width, height: newFrameRect.height)

        // Animate resize for a smoother feel
        window.setFrame(adjustedFrame, display: true, animate: true)
        print("🔄 Panel visibility changed -> visible: \(visible). Window resized to height: \(Int(targetContentHeight))")
    }
    
    // MARK: - Current State
    func getCurrentWindowState() -> (size: NSSize, hasPanels: Bool) {
        guard let window = NSApplication.shared.windows.first else {
            return (NSSize(width: WindowCalculations.defaultWidth, height: WindowCalculations.defaultHeight), true)
        }
        
        return (window.frame.size, true)
    }
}

// MARK: - Fully Resizable Window Delegate
class FullyResizableDelegate: NSObject, NSWindowDelegate {
    static let shared = FullyResizableDelegate()
    
    private override init() {
        super.init()
    }
    
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Allow both width and height changes within constraints
        let constrainedWidth = max(
            WindowManager.WindowCalculations.minWidth,
            min(WindowManager.WindowCalculations.maxWidth, frameSize.width)
        )

        // Dynamic min height depends on current width and panel visibility
        let dynamicMinHeight = WindowManager.shared.computeMinHeight(forWidth: constrainedWidth)
        let constrainedHeight = max(
            dynamicMinHeight,
            min(WindowManager.WindowCalculations.maxHeight, frameSize.height)
        )
        
        let newSize = NSSize(width: constrainedWidth, height: constrainedHeight)
        
        print("📐 Fully resizable: \(Int(newSize.width)) x \(Int(newSize.height))")
        
        return newSize
    }
    
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Re-apply title bar settings to ensure they remain after any system adjustments
        WindowManager.shared.applyHiddenTitleBar(to: window)
        let newSize = window.frame.size
        print("📐 Window resized to: \(Int(newSize.width)) x \(Int(newSize.height))")
    }
}
