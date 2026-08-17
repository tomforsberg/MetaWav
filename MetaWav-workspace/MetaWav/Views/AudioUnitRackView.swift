// AudioUnitRackView.swift - Coming Soon placeholder
import SwiftUI
import AVFoundation
import CoreAudioKit
import AppKit

struct AudioUnitRackView: View {
    @ObservedObject private var engine = UnifiedAudioEngine.shared
    @State private var showingBrowser = false
    @State private var showingAUView = false
    @State private var selectedUIIndex: Int? = nil
    @StateObject private var dragState = DragState()
    @State private var draggedIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header + trailing action (match MetadataView section header style)
            HStack {
                Text("AUDIO UNITS")
                    .font(.system(size: PanelTheme.sectionHeaderFontSize, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
                Spacer()
                Button(action: { MenuBarManager.shared.showAddPluginWindow() }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(PanelTheme.accent)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 4)

            // Rack list (multiple plugins)
            VStack(spacing: 8) {
                if engine.effectChain.isEmpty {
                    HStack {
                        Text("No plugins in rack")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                        Spacer()
                    }
                    .padding(10)
                    .selectedGlass(cornerRadius: 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(engine.effectChain.enumerated()), id: \.offset) { index, unit in
                            if dragState.isDragging && dragState.dropTargetIndex == index {
                                dropGap()
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(Color(white: 0.6))
                                    .help("Reorder")
                                    .onDrag {
                                        draggedIndex = index
                                        let name = unit.auAudioUnit.audioUnitName ?? "Audio Unit"
                                        dragState.startDrag(itemId: UUID(), item: name)
                                        return NSItemProvider(object: "\(index)" as NSString)
                                    }
                                Text(unit.auAudioUnit.audioUnitName ?? "Unknown")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {
                                    if let eff = unit as? AVAudioUnitEffect {
                                        engine.setEffectBypassed(!eff.bypass, at: index)
                                    }
                                }) {
                                    let isBypassed = (unit as? AVAudioUnitEffect)?.bypass ?? false
                                    Image(systemName: isBypassed ? "power" : "power")
                                        .symbolVariant(isBypassed ? .none : .fill)
                                        .foregroundColor(isBypassed ? Color(white: 0.6) : Color(red: 0, green: 0.75, blue: 0.39))
                                        .help(isBypassed ? "Bypassed" : "Active")
                                }
                                .buttonStyle(.plain)
                                Button(action: { AUWindowManager.shared.openEditor(forIndex: index, fromChain: engine.effectChain, title: unit.auAudioUnit.audioUnitName ?? "Audio Unit") }) {
                                    Image(systemName: "macwindow")
                                        .foregroundColor(Color(white: 0.8))
                                        .help("Open Plugin UI")
                                }
                                .buttonStyle(.plain)
                                Button(action: { engine.unloadEffect(at: index) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(Color(white: 0.6))
                                        .help("Remove Plugin")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .selectedGlass(cornerRadius: 6)
                            .opacity(draggedIndex == index && dragState.isDragging ? 0.001 : 1)
                            .onDrop(of: [.text], delegate: RackDropDelegate(destinationIndex: index, engine: engine, draggedIndex: $draggedIndex, dragState: dragState))
                        }
                        if dragState.isDragging && dragState.dropTargetIndex == engine.effectChain.count {
                            dropGap()
                        }
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 8)
                            .onDrop(of: [.text], delegate: RackEndDropDelegate(engine: engine, draggedIndex: $draggedIndex, dragState: dragState))
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        draggedIndex = nil
                        dragState.endDrag()
                        return true
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, PanelTheme.horizontalPadding)
        .padding(.bottom, PanelTheme.bottomPadding)
        .padding(.top, PanelTheme.topPadding)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        // Match MetadataView: no extra container glass here
    }

    private func dropIndicator() -> some View {
        HStack {
            Circle()
                .fill(Color(red: 0, green: 0.75, blue: 0.39))
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color(red: 0, green: 0.75, blue: 0.39))
                .frame(height: 2)
            Circle()
                .fill(Color(red: 0, green: 0.75, blue: 0.39))
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
    }
}

// MARK: - Rack Drop Delegates

private struct RackDropDelegate: DropDelegate {
    let destinationIndex: Int
    let engine: UnifiedAudioEngine
    @Binding var draggedIndex: Int?
    let dragState: DragState

    func dropEntered(info: DropInfo) {
        guard let from = draggedIndex, from != destinationIndex else { return }
        dragState.updateDropTarget(index: destinationIndex)
        engine.moveEffect(from: from, to: destinationIndex)
        draggedIndex = destinationIndex
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedIndex = nil
        dragState.endDrag()
        return true
    }
}

private struct RackEndDropDelegate: DropDelegate {
    let engine: UnifiedAudioEngine
    @Binding var draggedIndex: Int?
    let dragState: DragState

    func dropEntered(info: DropInfo) {
        guard let from = draggedIndex else { return }
        let lastIndex = max(0, engine.effectChain.count - 1)
        dragState.updateDropTarget(index: engine.effectChain.count)
        if from != lastIndex {
            engine.moveEffect(from: from, to: lastIndex)
            draggedIndex = lastIndex
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedIndex = nil
        dragState.endDrag()
        return true
    }
}

private struct HoverGlass: View {
    let cornerRadius: CGFloat
    @State private var isHovered = false
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.clear)
            .background(
                Group {
                    if isHovered {
                        Color.clear.secondaryGlass(cornerRadius: cornerRadius)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius).fill(Color.clear)
                    }
                }
                .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 4 : 0)
            .offset(x: isHovered ? 4 : 0)
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .onHover { hovering in isHovered = hovering }
    }
}

private struct AUBrowserView: View {
    @Binding var isPresented: Bool
    @State private var components: [AVAudioUnitComponent] = []
    @State private var searchText: String = ""
    @State private var sortByManufacturer: Bool = false
    @State private var brandTabs: [String] = ["All"]
    @State private var selectedBrand: String = "All"

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Brand tabs (Apple, UAD, Waves, Other...)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(brandTabs, id: \.self) { brand in
                            Button(action: { selectedBrand = brand }) {
                                Text(brand)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedBrand == brand ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .secondaryGlass(cornerRadius: 10)
                HStack(spacing: 8) {
                    TextField("Search AUs", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 320)
                    Picker("Sort", selection: $sortByManufacturer) {
                        Text("Name").tag(false)
                        Text("Developer").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding(.horizontal, 12)
                .glass3(cornerRadius: 10)

                List(filteredSortedAndBranded, id: \.name) { comp in
                Button(action: {
                    UnifiedAudioEngine.shared.loadEffect(component: comp) { _ in
                        isPresented = false
                    }
                }) {
                    VStack(alignment: .leading) {
                        Text(comp.name)
                        Text(comp.manufacturerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                }
            }
            .navigationTitle("Audio Units")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { isPresented = false } } }
            .onAppear {
                components = UnifiedAudioEngine.shared.availableEffects()
                brandTabs = buildBrandTabs(from: components)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 720, minHeight: 520)
        .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var filteredAndSorted: [AVAudioUnitComponent] {
        var list = components
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) || $0.manufacturerName.lowercased().contains(q) }
        }
        if sortByManufacturer {
            return list.sorted { lhs, rhs in
                if lhs.manufacturerName == rhs.manufacturerName { return lhs.name < rhs.name }
                return lhs.manufacturerName < rhs.manufacturerName
            }
        } else {
            return list.sorted { lhs, rhs in lhs.name < rhs.name }
        }
    }

    private var filteredSortedAndBranded: [AVAudioUnitComponent] {
        let base = filteredAndSorted
        if selectedBrand == "All" { return base }
        if selectedBrand == "Other" {
            let known = Set(["Apple", "UAD", "Universal Audio", "Waves"])
            return base.filter { !known.contains($0.manufacturerName) }
        }
        if selectedBrand == "UAD" {
            return base.filter { $0.manufacturerName == "UAD" || $0.manufacturerName == "Universal Audio" }
        }
        return base.filter { $0.manufacturerName == selectedBrand }
    }

    private func buildBrandTabs(from list: [AVAudioUnitComponent]) -> [String] {
        var set = Set(list.map { $0.manufacturerName })
        // Normalize UAD naming
        if set.contains("Universal Audio") { set.insert("UAD") }
        // Known primary brands first
        var tabs: [String] = ["All"]
        if set.contains("Apple") { tabs.append("Apple") }
        if set.contains("UAD") || set.contains("Universal Audio") { tabs.append("UAD") }
        if set.contains("Waves") { tabs.append("Waves") }
        // Others collapsed under Other
        tabs.append("Other")
        return tabs
    }
}

private struct AUContainerView: NSViewControllerRepresentable {
    @Binding var isPresented: Bool
    let index: Int
    let headerHeight: CGFloat

    func makeNSViewController(context: Context) -> NSViewController {
        let host = AUHostingViewController()
        host.loadAU(at: index, headerHeight: headerHeight)
        return host
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
    }
}

private struct AUEditorSheetView: View {
    @Binding var isPresented: Bool
    var title: String
    let index: Int
    @State private var headerHeight: CGFloat = 0
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Close") { isPresented = false }
            }
            .padding(12)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { headerHeight = proxy.size.height }
                        .onChange(of: proxy.size) { _, newSize in headerHeight = newSize.height }
                }
            )
            Divider()
            AUContainerView(isPresented: $isPresented, index: index, headerHeight: headerHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Make sheet non-blocking by allowing interactions with other windows
            NSApp.keyWindow?.level = .floating
        }
    }
}

// MARK: - AU Hosting VC with native-size support and DPI awareness
private final class AUHostingViewController: NSViewController {
    private var auVC: AUViewController?
    private var resizeObserver: Any?
    private var headerHeight: CGFloat = 0

    func loadAU(at index: Int, headerHeight: CGFloat) {
        self.headerHeight = headerHeight
        // Set default size immediately to avoid tiny initial sheet
        preferredContentSize = NSSize(width: 820, height: 560)
        view.frame.size = preferredContentSize
        view.needsLayout = true

        UnifiedAudioEngine.shared.requestEffectViewController(at: index) { [weak self] vc in
            guard let self = self, let vc = vc else { return }
            self.auVC = vc
            self.embed(viewController: vc)
            DispatchQueue.main.async { self.sizeToAUView(vc) }
            self.observeAUResizing(vc)
        }

        // Generic fallback if no custom editor arrives shortly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self, self.auVC == nil else { return }
            let chain = UnifiedAudioEngine.shared.effectChain
            if index >= 0 && index < chain.count {
                let avu = chain[index]
                let paramsView = NSHostingView(rootView: GenericAUParametersView(auUnit: avu.auAudioUnit))
                paramsView.translatesAutoresizingMaskIntoConstraints = false
                self.view.addSubview(paramsView)
                NSLayoutConstraint.activate([
                    paramsView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                    paramsView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                    paramsView.topAnchor.constraint(equalTo: self.view.topAnchor),
                    paramsView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
                ])
                let count = avu.auAudioUnit.parameterTree?.allParameters.count ?? 10
                let total = NSSize(width: 640, height: min(max(CGFloat(count) * 36 + headerHeight + 40, 360), 900))
                self.preferredContentSize = total
                self.view.window?.setContentSize(total)
            }
        }
    }

    private func embed(viewController child: NSViewController) {
        child.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(child)
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func sizeToAUView(_ vc: AUViewController) {
        // Preferred sizing: AUAudioUnitViewConfiguration not universally exposed; use Cocoa view size
        let auView = vc.view
        auView.layoutSubtreeIfNeeded()
        var size = auView.fittingSize
        if size == .zero { size = auView.bounds.size }
        guard size != .zero else { return }
        // Add header height and minor chrome padding
        let totalHeight = size.height + headerHeight + 1
        let totalSize = NSSize(width: size.width, height: totalHeight)
        preferredContentSize = totalSize
        if let window = view.window {
            window.setContentSize(totalSize)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.view.window?.setContentSize(totalSize)
            }
        }
    }

    private func observeAUResizing(_ vc: AUViewController) {
        vc.view.postsFrameChangedNotifications = true
        resizeObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: vc.view, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.sizeToAUView(vc)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let vc = auVC {
            sizeToAUView(vc)
        }
    }

    deinit {
        if let token = resizeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

// moved to AUWindowManager.swift

private struct AUParamSlider: View {
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
