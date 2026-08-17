import AppKit
import CoreAudioKit
import AVFoundation
import AudioToolbox
import AudioUnit
import Foundation

@objc protocol AUCocoaUIBaseShim: NSObjectProtocol {
    @objc func uiView(forAudioUnit inAudioUnit: AudioUnit, withSize inPreferredSize: NSSize) -> [NSView]
}

final class AUWindowManager: NSObject {
    static let shared = AUWindowManager()

    private var controllers: [NSWindowController] = []
    private var unitWindows: [ObjectIdentifier: NSWindowController] = [:]
    private var unitViewControllers: [ObjectIdentifier: NSViewController] = [:]
    private var windowObserverTokens: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    private func registerToken(_ token: NSObjectProtocol, for window: NSWindow) {
        let key = ObjectIdentifier(window)
        var tokens = windowObserverTokens[key] ?? []
        tokens.append(token)
        windowObserverTokens[key] = tokens
    }

    private func removeWindowObserverTokens(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let tokens = windowObserverTokens[key] {
            for t in tokens { NotificationCenter.default.removeObserver(t) }
            windowObserverTokens.removeValue(forKey: key)
        }
    }

    func openEditor(forIndex index: Int, fromChain effectChain: [AVAudioUnit], title: String? = nil) {
        guard let avu = effectChain[safe: index] else { return }
        let key = ObjectIdentifier(avu)
        if let existing = unitWindows[key], let window = existing.window {
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                existing.showWindow(nil)
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // If we have a cached AU view controller, present it immediately
        if let cachedVC = unitViewControllers[key] {
            let au = avu.auAudioUnit
            let size = self.preferredSizeFromAUConfig(au)
            self.presentWindow(for: cachedVC, avu: avu, au: au, title: title ?? (au.audioUnitName ?? "Audio Unit"), sizeOverride: size)
            return
        }
        let au = avu.auAudioUnit
        DispatchQueue.main.async {
            let size = self.preferredSizeFromAUConfig(au)
            print("[AUWindow] Negotiated AUv3 size: \(size)")
            do { try au.allocateRenderResources() } catch { print("[AUWindow] allocateRenderResources error: \(error)") }
            au.requestViewController { [weak self] vc in
                guard let self = self else { return }
                if let vc = vc {
                    DispatchQueue.main.async {
                        print("[AUWindow] Received AU view controller: \(type(of: vc))")
                        self.unitViewControllers[key] = vc
                        self.presentWindow(for: vc, avu: avu, au: au, title: title ?? (au.audioUnitName ?? "Audio Unit"), sizeOverride: size)
                    }
                } else {
                    if self.presentCocoaWindowIfAvailable(for: avu, title: title) { return }
                    let paramsVC = NSHostingController(rootView: GenericAUParametersView(auUnit: au))
                    self.presentWindow(forGeneric: paramsVC, avu: avu, title: title ?? (au.audioUnitName ?? "Audio Unit"))
                }
            }
        }
    }

    private func presentWindow(for auVC: NSViewController, avu: AVAudioUnit, au: AUAudioUnit?, title: String, sizeOverride: NSSize? = nil) {
        // Determine plugin view and its natural size
        let pluginView = auVC.view
        var size = sizeOverride ?? .zero
        if size == .zero { size = naturalSize(for: auVC) }
        if size == .zero { size = NSSize(width: 900, height: 650) }

        // Detect whether the plugin view supports resizing
        let supportsResizing = viewSupportsResizing(pluginView, au: au)
        print("[AUWindow] viewSupportsResizing=\(supportsResizing), initialSize=\(size)")

        // Host controller & container setup
        let hostVC = NSViewController()
        hostVC.view = NSView()
        hostVC.view.wantsLayer = true

        let window = NSWindow(contentViewController: hostVC)
        window.title = title
        window.isReleasedWhenClosed = false

        if supportsResizing {
            // Resizable plugin: let it fill and keep window resizable
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.contentMinSize = NSSize(width: max(480, size.width), height: max(320, size.height))
            window.setContentSize(NSSize(width: max(480, size.width), height: max(320, size.height)))
            embed(child: auVC, into: hostVC)

            // Track plugin-driven size changes (Apple AUs adjust preferred size)
            pluginView.postsFrameChangedNotifications = true
            let token1 = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: pluginView, queue: .main) { [weak window] _ in
                guard let window = window else { return }
                let sNow = self.naturalSize(for: auVC)
                let adjusted = NSSize(width: max(sNow.width, 480), height: max(sNow.height, 320))
                window.setContentSize(adjusted)
            }
            registerToken(token1, for: window)
        } else {
            // Fixed-size plugin: center the view and lock window size
            window.styleMask = [.titled, .closable, .miniaturizable] // no .resizable
            window.setContentSize(size)
            window.contentMinSize = size
            window.contentMaxSize = size

            // Use a centering container that never stretches the plugin view
            let container = FixedSizeCenteringContainerView(fixedContentSize: size)
            hostVC.view = container
            hostVC.addChild(auVC)
            container.attach(contentView: pluginView)

            // If size somehow changes (rare), keep window locked to the new natural size
            pluginView.postsFrameChangedNotifications = true
            let token2 = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: pluginView, queue: .main) { [weak window] _ in
                guard let window = window else { return }
                let sNow = self.naturalSize(for: auVC)
                if sNow != .zero {
                    window.setContentSize(sNow)
                    window.contentMinSize = sNow
                    window.contentMaxSize = sNow
                }
            }
            registerToken(token2, for: window)
        }

        window.center()

        let wc = NSWindowController(window: window)
        controllers.append(wc)
        unitWindows[ObjectIdentifier(avu)] = wc
        wc.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Final re-measure pass in case the plugin lays out asynchronously
        func reMeasureAndApply() {
            let sNow = self.naturalSize(for: auVC)
            if supportsResizing {
                let adjusted = NSSize(width: max(sNow.width, 480), height: max(sNow.height, 320))
                window.setContentSize(adjusted)
            } else if sNow != .zero {
                window.setContentSize(sNow)
                window.contentMinSize = sNow
                window.contentMaxSize = sNow
            }
        }
        DispatchQueue.main.async { reMeasureAndApply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { reMeasureAndApply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { reMeasureAndApply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.00) { reMeasureAndApply() }
    }

    private func presentWindow(forGeneric controller: NSHostingController<GenericAUParametersView>, avu: AVAudioUnit, title: String) {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 480))
        window.center()
        let wc = NSWindowController(window: window)
        controllers.append(wc)
        unitWindows[ObjectIdentifier(avu)] = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    private func presentCocoaWindowIfAvailable(for avu: AVAudioUnit, title: String?) -> Bool {
        var dataSize: UInt32 = 0
        let audioUnitRef = avu.audioUnit
        var writable: DarwinBoolean = false
        let statusInfo = AudioUnitGetPropertyInfo(audioUnitRef, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &dataSize, &writable)
        guard statusInfo == noErr, dataSize >= UInt32(MemoryLayout<AudioUnitCocoaViewInfo>.size) else { return false }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioUnitCocoaViewInfo>.alignment)
        defer { raw.deallocate() }
        var mutableSize = dataSize
        let status = AudioUnitGetProperty(audioUnitRef, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, raw, &mutableSize)
        guard status == noErr else { return false }
        let infoPtr = raw.bindMemory(to: AudioUnitCocoaViewInfo.self, capacity: Int(mutableSize) / MemoryLayout<AudioUnitCocoaViewInfo>.size)
        let info = infoPtr.pointee

        let bundleURL = info.mCocoaAUViewBundleLocation.takeUnretainedValue() as URL
        let className = info.mCocoaAUViewClass.takeUnretainedValue() as String

        var view: NSView?
        let createViewBlock = {
            if let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL as CFURL) {
                CFBundleLoadExecutable(bundle)
                if let cls = NSClassFromString(className) as? (NSObject & AUCocoaUIBaseShim).Type {
                    let factory = cls.init()
                    let views = factory.uiView(forAudioUnit: audioUnitRef, withSize: NSSize(width: 1, height: 1))
                    view = views.first
                }
            }
        }
        if Thread.isMainThread { createViewBlock() } else { DispatchQueue.main.sync { createViewBlock() } }
        guard let pluginView = view else { return false }

        let hostVC = NSViewController()
        hostVC.view = NSView()
        hostVC.view.wantsLayer = true
        // Determine resizing support for AUv2 Cocoa view
        hostVC.view.layoutSubtreeIfNeeded()
        var s = naturalSize(for: pluginView)
        if s == .zero { s = NSSize(width: 900, height: 650) }
        let supportsResizing = viewSupportsResizing(pluginView, au: nil)
        print("[AUWindow] (Cocoa) viewSupportsResizing=\(supportsResizing), initialSize=\(s)")

        let window = NSWindow(contentViewController: hostVC)
        window.title = title ?? (avu.auAudioUnit.audioUnitName ?? "Audio Unit")
        window.isReleasedWhenClosed = false

        if supportsResizing {
            // Fill container and allow resize
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.contentMinSize = NSSize(width: max(480, s.width), height: max(320, s.height))
            window.setContentSize(NSSize(width: max(480, s.width), height: max(320, s.height)))
            pluginView.translatesAutoresizingMaskIntoConstraints = false
            hostVC.view.addSubview(pluginView)
            NSLayoutConstraint.activate([
                pluginView.leadingAnchor.constraint(equalTo: hostVC.view.leadingAnchor),
                pluginView.trailingAnchor.constraint(equalTo: hostVC.view.trailingAnchor),
                pluginView.topAnchor.constraint(equalTo: hostVC.view.topAnchor),
                pluginView.bottomAnchor.constraint(equalTo: hostVC.view.bottomAnchor)
            ])

            pluginView.postsFrameChangedNotifications = true
            let token3 = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: pluginView, queue: .main) { [weak window] _ in
                guard let window = window else { return }
                let sizeNow = self.naturalSize(for: pluginView)
                let adjusted = NSSize(width: max(sizeNow.width, 480), height: max(sizeNow.height, 320))
                window.setContentSize(adjusted)
            }
            registerToken(token3, for: window)
        } else {
            // Center and lock size; never stretch AUv2 fixed UIs
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(s)
            window.contentMinSize = s
            window.contentMaxSize = s
            let container = FixedSizeCenteringContainerView(fixedContentSize: s)
            hostVC.view = container
            container.attach(contentView: pluginView)

            pluginView.postsFrameChangedNotifications = true
            let token4 = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: pluginView, queue: .main) { [weak window] _ in
                guard let window = window else { return }
                let sizeNow = self.naturalSize(for: pluginView)
                if sizeNow != .zero {
                    window.setContentSize(sizeNow)
                    window.contentMinSize = sizeNow
                    window.contentMaxSize = sizeNow
                }
            }
            registerToken(token4, for: window)

        // Remove tokens on window close
        let closeToken = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak window] _ in
            guard let self = self, let w = window else { return }
            self.removeWindowObserverTokens(for: w)
        }
        registerToken(closeToken, for: window)
        }

        window.center()

        let wc = NSWindowController(window: window)
        controllers.append(wc)
        unitWindows[ObjectIdentifier(avu)] = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        func reMeasureAndApply() {
            hostVC.view.layoutSubtreeIfNeeded()
            let sizeNow = self.naturalSize(for: pluginView)
            if supportsResizing {
                let adjusted = NSSize(width: max(sizeNow.width, 480), height: max(sizeNow.height, 320))
                window.setContentSize(adjusted)
            } else if sizeNow != .zero {
                window.setContentSize(sizeNow)
                window.contentMinSize = sizeNow
                window.contentMaxSize = sizeNow
            }
        }
        DispatchQueue.main.async { reMeasureAndApply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { reMeasureAndApply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { reMeasureAndApply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.00) { reMeasureAndApply() }

        return true
    }

    private func embed(child: NSViewController, into parent: NSViewController) {
        parent.addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
        ])
    }

    private func preferredSize(for vc: NSViewController) -> NSSize {
        vc.view.layoutSubtreeIfNeeded()
        let preferred = vc.preferredContentSize
        if preferred != .zero { return preferred }
        var size = vc.view.fittingSize
        if size == .zero { size = vc.view.bounds.size }
        if size == .zero { size = NSSize(width: 820, height: 560) }
        return size
    }

    private func preferredSizeFromAUConfig(_ au: AUAudioUnit?) -> NSSize {
        guard let au = au else { return .zero }
        let sizes: [NSSize] = [
            NSSize(width: 900, height: 650),
            NSSize(width: 820, height: 560),
            NSSize(width: 1024, height: 768),
            NSSize(width: 700, height: 500)
        ]
        for hostHasController in [true, false] {
            let candidates = sizes.map { AUAudioUnitViewConfiguration(width: $0.width, height: $0.height, hostHasController: hostHasController) }
            let supported = au.supportedViewConfigurations(candidates)
            print("[AUWindow] supported configs (hostHasController=\(hostHasController)): \(supported)")
            for idx in supported {
                let cfg = candidates[idx]
                au.select(cfg)
                print("[AUWindow] select(\(Int(cfg.width))x\(Int(cfg.height)), hostHasController=\(hostHasController))")
                return NSSize(width: cfg.width, height: cfg.height)
            }
        }
        return .zero
    }

    private func naturalSize(for vc: NSViewController) -> NSSize {
        vc.view.layoutSubtreeIfNeeded()
        var s = vc.preferredContentSize
        if s == .zero {
            let intrinsic = vc.view.intrinsicContentSize
            if intrinsic.width > 0 && intrinsic.height > 0 { s = intrinsic }
        }
        if s == .zero { s = vc.view.fittingSize }
        if s == .zero { s = vc.view.bounds.size }
        return s
    }

    private func naturalSize(for view: NSView) -> NSSize {
        view.layoutSubtreeIfNeeded()
        var s = view.intrinsicContentSize
        if s.width <= 0 || s.height <= 0 { s = view.fittingSize }
        if s == .zero { s = view.bounds.size }
        return s
    }

    private func viewSupportsResizing(_ view: NSView, au: AUAudioUnit?) -> Bool {
        // AUv3 hint: if the AU reports supported view configurations, treat as resizable
        if let au = au {
            let candidates = [
                NSSize(width: 700, height: 500),
                NSSize(width: 820, height: 560),
                NSSize(width: 900, height: 650),
                NSSize(width: 1024, height: 768)
            ].map { AUAudioUnitViewConfiguration(width: $0.width, height: $0.height, hostHasController: true) }
            let supported = au.supportedViewConfigurations(candidates)
            if !supported.isEmpty { return true }
        }
        // Cocoa AUv2 hint: width/height sizable indicates resize capability
        let mask = view.autoresizingMask
        if mask.contains(.width) || mask.contains(.height) { return true }
        // As an optional heuristic, see if the view has any constraints tying edges
        if !view.constraints.filter({ constraint in
            guard let first = constraint.firstItem as? NSView else { return false }
            if first == view { return true }
            return false
        }).isEmpty { return true }
        // Default: assume fixed-size
        return false
    }
}

// Centering container that keeps a fixed-size plugin view crisp (no stretching)
final class FixedSizeCenteringContainerView: NSView {
    private var contentViewRef: NSView?
    private var fixedSize: NSSize

    init(fixedContentSize: NSSize) {
        self.fixedSize = fixedContentSize
        super.init(frame: NSRect(origin: .zero, size: fixedContentSize))
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        self.fixedSize = .zero
        super.init(coder: coder)
        self.wantsLayer = true
    }

    func attach(contentView: NSView) {
        self.contentViewRef = contentView
        contentView.translatesAutoresizingMaskIntoConstraints = true
        contentView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(contentView)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        guard let content = contentViewRef else { return }
        let bounds = self.bounds
        let w = fixedSize.width
        let h = fixedSize.height
        let x = max(0, (bounds.width - w) * 0.5)
        let y = max(0, (bounds.height - h) * 0.5)
        content.frame = NSRect(x: x, y: y, width: w, height: h)
    }
}

import SwiftUI

struct GenericAUParametersView: View {
    let auUnit: AUAudioUnit
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let params = auUnit.parameterTree?.allParameters, !params.isEmpty {
                    ForEach(params, id: \.address) { LocalParamSlider(param: $0) }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                } else {
                    Text("This Audio Unit does not provide a custom editor or parameters.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.top, 8)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

private struct LocalParamSlider: View {
    let param: AUParameter
    @State private var value: AUValue = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(param.displayName)
                Spacer()
                Text(String(format: "%.2f", value))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Slider(value: Binding(get: {
                if value == 0 { value = param.value }
                return Double(value)
            }, set: { newVal in
                value = AUValue(newVal)
                param.value = value
            }), in: Double(param.minValue)...Double(param.maxValue))
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

