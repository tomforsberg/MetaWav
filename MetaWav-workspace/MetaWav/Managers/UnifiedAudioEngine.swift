import AVFoundation
import CoreAudioKit
import AudioToolbox
import Foundation

final class UnifiedAudioEngine: ObservableObject {
    static let shared = UnifiedAudioEngine()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let varispeedNode = AVAudioUnitVarispeed()
    @Published var effectChain: [AVAudioUnit] = []
    @Published var currentEffectName: String?
    @Published var effectBypassed: Bool = false { didSet { /* legacy no-op */ } }
    @Published var currentEffectViewController: AUViewController?

    // No internal DSP state

    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    private var fileLengthFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100.0
    private var currentScheduledStartFrame: AVAudioFramePosition = 0
    private var lastKnownFramePosition: AVAudioFramePosition = 0

    @Published var isPlaying: Bool = false
    @Published var volume: Float = 1.0 {
        didSet { applyVolume() }
    }
    
    // VU meter tapped from the main mixer
    private var vuMeter: VuMeterDSP?
    var meter: VuMeterDSP? { vuMeter }
    
    // Stereo meter for L/R digital metering (Timecode AUDIO mode)
    private var stereoVuMeter: StereoVuMeterDSP?
    var stereoMeter: StereoVuMeterDSP? { stereoVuMeter }

    // Internal timer for gentle playback-rate ramps
    private var rateRampTimer: Timer?

    private init() {
        configureGraph()
        startEngineIfNeeded()
    }

    private func configureGraph() {
        engine.attach(playerNode)
        engine.attach(varispeedNode)
        reconnectGraph()
        applyVolume()
        
         // Install tap on main mixer for metering once the engine is configured
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        // Force a known format for metering so DSP can always read `floatChannelData`.
        let tapFormat = AVAudioFormat(
            standardFormatWithSampleRate: format.sampleRate,
            channels: format.channelCount
        ) ?? format
        vuMeter = VuMeterDSP(sampleRate: format.sampleRate)
        // Digital meter wants faster response than analog VU: shorter RMS window + quicker attack.
        stereoVuMeter = StereoVuMeterDSP(
            sampleRate: format.sampleRate,
            rmsWindowMs: 80.0,
            attackMs: 5.0,
            releaseMs: 140.0,
            peakHoldMs: 600.0
        )
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 512,
            format: tapFormat
        ) { [weak self] buffer, _ in
            self?.vuMeter?.process(buffer: buffer)
            self?.stereoVuMeter?.process(buffer: buffer)
        }
    }

    private func startEngineIfNeeded() {
        if engine.isRunning { return }
        do { try engine.start() } catch { print("AVAudioEngine failed to start: \(error)") }
    }

    private func reconnectGraph() {
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(varispeedNode)
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let format = audioFormat ?? mixerFormat

        // Attach effect chain
        for unit in effectChain {
            if unit.engine == nil { engine.attach(unit) }
        }

        // Build chain: player -> varispeed -> [effects...] -> mainMixer
        engine.connect(playerNode, to: varispeedNode, format: format)
        var tail: AVAudioNode = varispeedNode
        for unit in effectChain {
            engine.connect(tail, to: unit, format: format)
            tail = unit
        }
        engine.connect(tail, to: engine.mainMixerNode, format: format)
    }

    /// Adjust playback rate for transport. 1.0 = normal.
    func setTransportRate(_ rate: Float) {
        // Clamp to a reasonable range to avoid extreme artifacts.
        let clamped = max(0.25, min(rate, 8.0))
        varispeedNode.rate = clamped
    }

    /// Smoothly ramp the transport rate to a target value over a short duration.
    func rampTransportRate(to target: Float, duration: TimeInterval = 0.18) {
        rateRampTimer?.invalidate()
        let start = varispeedNode.rate
        let clampedTarget = max(0.25, min(target, 8.0))
        guard duration > 0, start != clampedTarget else {
            setTransportRate(clampedTarget)
            return
        }
        let steps = max(4, Int(duration * 60)) // ~60 fps
        var currentStep = 0
        let delta = clampedTarget - start
        let stepDuration = duration / Double(steps)

        rateRampTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            currentStep += 1
            let t = min(Double(currentStep) / Double(steps), 1.0)
            // Simple ease-out curve so the last part of the ramp is softer
            let eased = Float(1.0 - pow(1.0 - t, 2.0))
            let rate = start + delta * eased
            self.setTransportRate(rate)
            if currentStep >= steps {
                timer.invalidate()
                self.rateRampTimer = nil
            }
        }
    }

    func setVolume(_ value: Float) {
        volume = value
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = volume
    }

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(Double(fileLengthFrames) / sampleRate)
    }

    var currentTime: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        let framePos = currentFramePosition()
        return TimeInterval(Double(framePos) / sampleRate)
    }

    func load(url: URL) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        load(file: file)
    }

    /// Prepare the engine with an already-open AVAudioFile (no disk I/O).
    func load(file: AVAudioFile) {
        stop()
        audioFile = file
        audioFormat = file.processingFormat
        fileLengthFrames = file.length
        sampleRate = file.processingFormat.sampleRate
        currentScheduledStartFrame = 0
        lastKnownFramePosition = 0
    }

    func play() {
        guard let file = audioFile else { return }
        if !engine.isRunning { startEngineIfNeeded() }
        if !playerNode.isPlaying {
            scheduleFromCurrentPosition(file: file)
            playerNode.play()
            isPlaying = true
        }
    }

    func pause() {
        guard playerNode.isPlaying else { return }
        // Capture exact frame position before pausing so we can resume accurately
        lastKnownFramePosition = currentFramePosition()
        playerNode.pause()
        isPlaying = false
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        currentScheduledStartFrame = 0
        lastKnownFramePosition = 0
    }

    func seek(to seconds: TimeInterval) {
        guard let file = audioFile else { return }
        let clamped = max(0, min(seconds, duration))
        let startFrame = AVAudioFramePosition(clamped * sampleRate)
        scheduleSegment(file: file, startingAt: startFrame)
        lastKnownFramePosition = startFrame
        if !playerNode.isPlaying {
            playerNode.play()
            isPlaying = true
        }
    }

    private func scheduleFromCurrentPosition(file: AVAudioFile) {
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           playerNode.isPlaying {
            // Convert the player's elapsed frames (in node/render sample rate)
            // to the file's frame domain to avoid drift when rates differ
            let nodeSampleRate = playerTime.sampleRate
            let nodeElapsedFrames = Double(playerTime.sampleTime)
            let fileElapsedFrames = nodeSampleRate > 0 ? nodeElapsedFrames * (sampleRate / nodeSampleRate) : nodeElapsedFrames
            let currentFrame = AVAudioFramePosition(fileElapsedFrames.rounded())
            scheduleSegment(file: file, startingAt: currentFrame)
            lastKnownFramePosition = currentFrame
        } else {
            // Not currently playing; resume from the last known frame position
            let resumeFrame = min(max(0, lastKnownFramePosition), file.length)
            scheduleSegment(file: file, startingAt: resumeFrame)
        }
    }

    private func scheduleSegment(file: AVAudioFile, startingAt startFrame: AVAudioFramePosition) {
        let framesRemaining = max(0, file.length - startFrame)
        playerNode.stop()
        currentScheduledStartFrame = startFrame
        lastKnownFramePosition = startFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(framesRemaining),
            at: nil,
            completionHandler: nil
        )
    }

    // MARK: - Amp Chain Save/Load (.metaamp)
    struct AmpChainFile: Codable {
        let version: Int
        let createdAt: Date
        let items: [AmpUnitState]
    }

    struct AmpUnitState: Codable {
        let componentType: UInt32
        let componentSubType: UInt32
        let componentManufacturer: UInt32
        let name: String?
        let bypassed: Bool
        let fullStatePlistBase64: String?
    }

    private func documentsAmpDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("MetaWav/Amp", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            print("[AmpChain] Failed to create directory: \(error)")
            return nil
        }
    }

    private func ensureMetaAmpExtension(_ name: String) -> String {
        if name.lowercased().hasSuffix(".metaamp") { return name }
        return name + ".metaamp"
    }

    func saveAmpChain(named fileName: String) throws {
        guard let dir = documentsAmpDirectory() else { throw NSError(domain: "MetaWav", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents/MetaWav/amp"]) }
        let url = dir.appendingPathComponent(ensureMetaAmpExtension(fileName))
        try saveAmpChain(to: url)
    }

    func saveAmpChain(to url: URL) throws {
        let items: [AmpUnitState] = effectChain.compactMap { unit in
            let au = unit.auAudioUnit
            let desc = au.componentDescription
            let bypass = (unit as? AVAudioUnitEffect)?.bypass ?? false

            var stateDict: Any?
            if let docState = au.fullStateForDocument {
                stateDict = docState as NSDictionary
            } else if let full = au.fullState {
                stateDict = full as NSDictionary
            }

            var encoded: String?
            if let dict = stateDict {
                if PropertyListSerialization.propertyList(dict, isValidFor: .xml) {
                    if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
                        encoded = data.base64EncodedString()
                    }
                } else if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
                    encoded = data.base64EncodedString()
                }
            }

            return AmpUnitState(
                componentType: desc.componentType,
                componentSubType: desc.componentSubType,
                componentManufacturer: desc.componentManufacturer,
                name: au.audioUnitName,
                bypassed: bypass,
                fullStatePlistBase64: encoded
            )
        }

        let file = AmpChainFile(version: 1, createdAt: Date(), items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
        print("[AmpChain] Saved \(items.count) units to: \(url.path)")
    }

    func loadAmpChain(named fileName: String, completion: ((Bool) -> Void)? = nil) {
        guard let dir = documentsAmpDirectory() else { completion?(false); return }
        let url = dir.appendingPathComponent(ensureMetaAmpExtension(fileName))
        loadAmpChain(from: url, completion: completion)
    }

    func loadAmpChain(from url: URL, completion: ((Bool) -> Void)? = nil) {
        guard let data = try? Data(contentsOf: url) else { print("[AmpChain] Failed to read file at \(url.path)"); completion?(false); return }
        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(AmpChainFile.self, from: data) else { print("[AmpChain] Failed to decode .metaamp JSON"); completion?(false); return }

        // Prepare playback state
        let wasPlaying = playerNode.isPlaying
        let desiredFrame = currentFramePosition()
        playerNode.pause()

        // Remove existing effects
        for unit in effectChain {
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
        }
        effectChain.removeAll()

        // Instantiate sequentially to preserve order
        instantiateChain(items: file.items) { [weak self] success in
            guard let self = self else { completion?(false); return }
            self.reconnectGraph()
            if let file = self.audioFile {
                self.scheduleSegment(file: file, startingAt: min(desiredFrame, file.length))
                if wasPlaying {
                    self.playerNode.play()
                    self.isPlaying = true
                }
            }
            completion?(success)
        }
    }

    private func instantiateChain(items: [AmpUnitState], completion: @escaping (Bool) -> Void) {
        if items.isEmpty { completion(true); return }

        var index = 0
        func instantiateNext() {
            if index >= items.count { completion(true); return }
            let item = items[index]
            let desc = AudioComponentDescription(
                componentType: item.componentType,
                componentSubType: item.componentSubType,
                componentManufacturer: item.componentManufacturer,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { [weak self] unit, error in
                guard let self = self else { completion(false); return }
                if let error = error { print("[AmpChain] Instantiate error: \(error)"); completion(false); return }
                guard let unit = unit else { print("[AmpChain] Instantiate returned nil unit"); completion(false); return }

                // Restore state if present
                if let b64 = item.fullStatePlistBase64, let data = Data(base64Encoded: b64) {
                    if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                        unit.auAudioUnit.fullState = plist
                    } else if let plistDict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary {
                        unit.auAudioUnit.fullState = plistDict as? [String: Any]
                    }
                }

                if let effect = unit as? AVAudioUnitEffect {
                    effect.bypass = item.bypassed
                }

                self.effectChain.append(unit)
                index += 1
                instantiateNext()
            }
        }
        instantiateNext()
    }

    // MARK: - Amp (Dynamics) Effect Management (optional helper)
    func setAmpEnabled(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        if enabled {
            insertAppleDynamicsProcessor(completion: completion)
        } else {
            // remove all dynamics processors from chain
            effectChain.removeAll { $0.auAudioUnit.audioUnitName == "Dynamics Processor" }
            reconnectGraph()
            completion?(true)
        }
    }

    private func insertAppleDynamicsProcessor(completion: ((Bool) -> Void)? = nil) {
        if effectChain.contains(where: { $0.auAudioUnit.audioUnitName == "Dynamics Processor" }) {
            completion?(true)
            return
        }
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
        AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { [weak self] unit, error in
            guard let self = self else { completion?(false); return }
            if let error = error { print("AU instantiate error: \(error)"); completion?(false); return }
            guard let unit = unit else { completion?(false); return }
            DispatchQueue.main.async {
                self.effectChain.append(unit)
                self.cacheDynamicsParamTree(unit: unit)
                self.currentEffectName = unit.auAudioUnit.audioUnitName
                self.reconnectGraph()
                completion?(true)
            }
        }
    }

    private func removeEffect() {
        // Legacy remove: clear entire chain
        for unit in effectChain {
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
        }
        effectChain.removeAll()
        reconnectGraph()
        currentEffectName = nil
    }

    // MARK: - Dynamics Processor Parameters
    private enum DynParam: String {
        case threshold = "threshold"
        case headroom = "headroom"
        case attack = "attackTime"
        case release = "releaseTime"
        case masterGain = "masterGain"
    }

    private var dynParams: [DynParam: AUParameter] = [:]

    private func cacheDynamicsParamTree(unit: AVAudioUnit) {
        guard let tree = unit.auAudioUnit.parameterTree else { return }
        var found: [DynParam: AUParameter] = [:]
        for param in tree.allParameters {
            if let key = DynParam(rawValue: param.identifier) {
                found[key] = param
            }
        }
        dynParams = found
    }

    func setDynamicsThreshold(_ value: Float) { dynParams[.threshold]?.value = value }
    func setDynamicsHeadroom(_ value: Float) { dynParams[.headroom]?.value = value }
    func setDynamicsAttack(_ value: Float) { dynParams[.attack]?.value = value }
    func setDynamicsRelease(_ value: Float) { dynParams[.release]?.value = value }
    func setDynamicsMasterGain(_ value: Float) { dynParams[.masterGain]?.value = value }

    // No internal DSP bridge

    // MARK: - General AU Hosting
    func availableEffects() -> [AVAudioUnitComponent] {
        let manager = AVAudioUnitComponentManager.shared()
        let all = manager.components(matching: NSPredicate(value: true))
        return all.filter { $0.audioComponentDescription.componentType == kAudioUnitType_Effect }
    }

    func loadEffect(component: AVAudioUnitComponent, completion: ((Bool) -> Void)? = nil) {
        let desc = component.audioComponentDescription
        // Capture current playback state and position for seamless resume
        let wasPlaying = self.playerNode.isPlaying

        AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { [weak self] unit, error in
            guard let self = self else { completion?(false); return }
            if let error = error { print("AU instantiate error: \(error)"); completion?(false); return }
            guard let unit = unit else { completion?(false); return }
            DispatchQueue.main.async {
                // Pause and capture precise frame
                let desiredFrame = self.currentFramePosition()
                self.playerNode.pause()
                self.effectChain.append(unit)
                self.currentEffectName = unit.auAudioUnit.audioUnitName
                self.effectBypassed = false
                self.cacheDynamicsParamTree(unit: unit)
                self.reconnectGraph()
                if let file = self.audioFile {
                    self.scheduleSegment(file: file, startingAt: min(desiredFrame, file.length))
                }
                // Persist last used AU component
                UserDefaults.standard.set(component.audioComponentDescription.componentSubType, forKey: "MW_LastAU_Subtype")
                UserDefaults.standard.set(component.manufacturerName, forKey: "MW_LastAU_Manufacturer")
                UserDefaults.standard.set(component.name, forKey: "MW_LastAU_Name")
                // Seamless resume: seek and play if needed
                if wasPlaying {
                    self.playerNode.play()
                    self.isPlaying = true
                }
                completion?(true)
            }
        }
    }

    func loadLastUsedEffect(completion: ((Bool) -> Void)? = nil) {
        let manager = AVAudioUnitComponentManager.shared()
        let all = manager.components(matching: NSPredicate(value: true))
        let lastName = UserDefaults.standard.string(forKey: "MW_LastAU_Name")
        let lastManu = UserDefaults.standard.string(forKey: "MW_LastAU_Manufacturer")
        if let name = lastName, let manu = lastManu, let comp = all.first(where: { $0.name == name && $0.manufacturerName == manu }) {
            loadEffect(component: comp, completion: completion)
        } else {
            completion?(false)
        }
    }

    func unloadEffect() {
        // Seamless resume: capture state then remove
        let wasPlaying = playerNode.isPlaying
        let desiredFrame = currentFramePosition()
        playerNode.pause()
        removeEffect()
        if let file = audioFile {
            scheduleSegment(file: file, startingAt: min(desiredFrame, file.length))
            if wasPlaying {
                playerNode.play()
                isPlaying = true
            }
        }
    }

    // Per-index unload for rack rows
    func unloadEffect(at index: Int) {
        guard index >= 0 && index < effectChain.count else { return }
        let wasPlaying = playerNode.isPlaying
        let desiredFrame = currentFramePosition()
        playerNode.pause()
        let unit = effectChain.remove(at: index)
        engine.disconnectNodeOutput(unit)
        engine.detach(unit)
        reconnectGraph()
        if let file = audioFile {
            scheduleSegment(file: file, startingAt: min(desiredFrame, file.length))
            if wasPlaying {
                playerNode.play()
                isPlaying = true
            }
        }
    }

    // Reorder an effect within the chain
    func moveEffect(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < effectChain.count,
              toIndex >= 0, toIndex < effectChain.count else { return }

        let wasPlaying = playerNode.isPlaying
        let desiredFrame = currentFramePosition()
        playerNode.pause()

        let unit = effectChain.remove(at: fromIndex)
        effectChain.insert(unit, at: toIndex)

        reconnectGraph()

        if let file = audioFile {
            scheduleSegment(file: file, startingAt: min(desiredFrame, file.length))
            if wasPlaying {
                playerNode.play()
                isPlaying = true
            }
        }
    }

    func setEffectBypassed(_ bypassed: Bool) {
        effectBypassed = bypassed
    }

    // Per-index bypass for rack rows
    func setEffectBypassed(_ bypassed: Bool, at index: Int) {
        guard index >= 0 && index < effectChain.count, let eff = effectChain[index] as? AVAudioUnitEffect else { return }
        eff.bypass = bypassed
        // Notify observers so SwiftUI updates instantly
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func applyEffectBypass() { /* legacy no-op */ }

    // MARK: - Native AU UI
    func requestEffectViewController(at index: Int, completion: @escaping (AUViewController?) -> Void) {
        guard index >= 0 && index < effectChain.count else { completion(nil); return }
        let au = effectChain[index].auAudioUnit
        au.requestViewController { vc in
            DispatchQueue.main.async {
                completion(vc as? AUViewController)
            }
        }
    }

    // Generic AU parameters
    func currentParameterTree() -> AUParameterTree? {
        effectChain.last?.auAudioUnit.parameterTree
    }

    // No internal DSP render helper

    // No internal buffer size integration

    // No ring buffer or format helpers
}

// MARK: - Position helpers
private extension UnifiedAudioEngine {
    func currentFramePosition() -> AVAudioFramePosition {
        guard playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            // When not playing, return the last captured frame position
            return lastKnownFramePosition
        }
        // playerTime.sampleTime is in the player's render sample rate; normalize to file domain
        let nodeSampleRate = playerTime.sampleRate
        let nodeElapsedFrames = Double(playerTime.sampleTime)
        let fileElapsedFrames = nodeSampleRate > 0 ? nodeElapsedFrames * (sampleRate / nodeSampleRate) : nodeElapsedFrames
        return currentScheduledStartFrame + AVAudioFramePosition(fileElapsedFrames.rounded())
    }
}


