import AppKit
import CoreGraphics
import IOKit.ps
import MetalKit
import QuartzCore

private let maximumParticleCount = 250_000

private struct ParticleGPU {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var target: SIMD2<Float>
    var life: Float
    var seed: Float
}

private struct ParticleSimulationUniforms {
    var mousePosition: SIMD2<Float>
    var previousMousePosition: SIMD2<Float>
    var shockwaveCenter: SIMD2<Float>
    var simulationBounds: SIMD2<Float>
    var deltaTime: Float
    var time: Float
    var interactionRadius: Float
    var forceStrength: Float
    var returnSpeed: Float
    var swirlStrength: Float
    var shockwaveAge: Float
    var shockwaveStrength: Float
    var pressure: Float
    var audioLevel: Float
    var audioBass: Float
    var mouseActive: UInt32
    var particleCount: UInt32
    var padding: UInt32 = 0
}

private struct ParticleRenderUniforms {
    var viewportSize: SIMD2<Float>
    var simulationBounds: SIMD2<Float>
    var particleSize: Float
    var trailLength: Float
    var time: Float
    var audioLevel: Float
}

/// GPU particle wallpaper with an independent compute and render pipeline.
@MainActor
final class ParticleRenderer: WallpaperRenderer {
    let identifier = "metal.particles"
    let supportedFileExtensions: Set<String> = []

    private let settingsStore: ParticleSettingsStore
    private var controllers: [CGDirectDisplayID: ParticleWallpaperController] = [:]
    private var retiredControllers: [ParticleWallpaperController] = []

    init(settingsStore: ParticleSettingsStore = .shared) {
        self.settingsStore = settingsStore
    }

    func canRender(_ sourceURL: URL) -> Bool {
        sourceURL.scheme == "particle" && sourceURL.host == "ai-logo"
    }

    func render(_ request: RendererRequest) throws -> WallpaperSession {
        guard canRender(request.sourceURL) else {
            throw RendererError.unsupportedSource(request.sourceURL)
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalUnavailable
        }

        let availableScreens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let displayID = screen.particleDisplayID else { return nil }
            return (displayID, screen)
        }
        let requested = Set(request.displayIDs)
        let targets = request.displayIDs.isEmpty
            ? availableScreens
            : availableScreens.filter { requested.contains($0.0) }
        guard !targets.isEmpty else {
            throw RendererError.rendererUnavailable(identifier)
        }

        let sessionID = UUID()
        var created: [(CGDirectDisplayID, ParticleWallpaperController)] = []
        do {
            for (displayID, screen) in targets where controllers[displayID] == nil {
                created.append((displayID, try ParticleWallpaperController(
                    sessionID: sessionID,
                    screen: screen,
                    displayID: displayID,
                    device: device,
                    settings: settingsStore.snapshot
                )))
            }
        } catch {
            created.forEach { $0.1.deactivate() }
            throw error
        }

        for (displayID, _) in targets {
            controllers[displayID]?.update(sessionID: sessionID, settings: settingsStore.snapshot)
        }
        for (displayID, controller) in created {
            controllers[displayID] = controller
            controller.start()
        }

        return WallpaperSession(
            id: sessionID,
            sourceURL: request.sourceURL,
            displayIDs: targets.map(\.0),
            rendererIdentifier: identifier,
            state: .running
        )
    }

    func stop(_ session: WallpaperSession) {
        let ids = controllers.compactMap { displayID, controller in
            controller.sessionID == session.id ? displayID : nil
        }
        for displayID in ids {
            if let controller = controllers.removeValue(forKey: displayID) {
                retire(controller)
            }
        }
    }

    func stopAll() {
        let active = Array(controllers.values)
        controllers.removeAll()
        active.forEach(retire)
    }

    private func retire(_ controller: ParticleWallpaperController) {
        controller.deactivate()
        retiredControllers.append(controller)
        let id = controller.sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.retiredControllers.removeAll { $0.sessionID == id }
        }
    }
}

private extension NSScreen {
    var particleDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
private final class ParticleWallpaperController: NSObject, MTKViewDelegate {
    private(set) var sessionID: UUID

    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let metalView: MTKView
    private let window: NSWindow
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    private let particleBuffers: [MTLBuffer]
    private let simulationUniformBuffers: [MTLBuffer]
    private let renderUniformBuffers: [MTLBuffer]
    private var inputRouter: GestureInputRouter!
    private var currentBufferIndex = 0
    private var frameIndex = 0
    private var lastFrameTime = CACurrentMediaTime()
    private let startedAt = CACurrentMediaTime()
    private var settings: ParticleSettingsSnapshot
    private var performanceSettings = PerformanceSettingsStore.shared.snapshot
    private var previousMouse = SIMD2<Float>(repeating: 0)
    private var lastShockwaveSerial: UInt64 = 0
    private var shockwaveCenter = SIMD2<Float>(repeating: 0)
    private var shockwaveStartedAt: CFTimeInterval = -100
    private var isScreenLocked = false
    private var lastPerformanceCheck: CFTimeInterval = 0
    private var policyTimer: Timer?

    init(
        sessionID: UUID,
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        device: MTLDevice,
        settings: ParticleSettingsSnapshot
    ) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.metalUnavailable
        }

        let library: MTLLibrary
        do {
            guard let url = Bundle.main.url(forResource: "ParticleShaders", withExtension: "metal") else {
                throw RendererError.shaderCompilationFailed("ParticleShaders.metal is missing.")
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            if let rendererError = error as? RendererError { throw rendererError }
            throw RendererError.shaderCompilationFailed(error.localizedDescription)
        }

        guard
            let computeFunction = library.makeFunction(name: "updateParticles"),
            let vertexFunction = library.makeFunction(name: "particleVertex"),
            let fragmentFunction = library.makeFunction(name: "particleFragment")
        else {
            throw RendererError.shaderCompilationFailed("Particle shader functions are missing.")
        }

        do {
            computePipeline = try device.makeComputePipelineState(function: computeFunction)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Particle Batch Render Pipeline"
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererError.shaderCompilationFailed(error.localizedDescription)
        }

        let particleLength = MemoryLayout<ParticleGPU>.stride * maximumParticleCount
        guard
            let particle0 = device.makeBuffer(length: particleLength, options: .storageModeShared),
            let particle1 = device.makeBuffer(length: particleLength, options: .storageModeShared),
            let particle2 = device.makeBuffer(length: particleLength, options: .storageModeShared)
        else {
            throw RendererError.metalUnavailable
        }
        particle0.label = "Particle State A"
        particle1.label = "Particle State B"
        particle2.label = "Particle State C"
        particleBuffers = [particle0, particle1, particle2]

        func makeUniformPool(length: Int, label: String) throws -> [MTLBuffer] {
            try (0..<3).map { index in
                guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                    throw RendererError.metalUnavailable
                }
                buffer.label = "\(label) \(index)"
                return buffer
            }
        }
        simulationUniformBuffers = try makeUniformPool(
            length: MemoryLayout<ParticleSimulationUniforms>.stride,
            label: "Particle Simulation Uniforms"
        )
        renderUniformBuffers = try makeUniformPool(
            length: MemoryLayout<ParticleRenderUniforms>.stride,
            label: "Particle Render Uniforms"
        )

        self.sessionID = sessionID
        self.screen = screen
        self.displayID = displayID
        self.device = device
        self.commandQueue = commandQueue
        self.settings = settings

        metalView = MTKView(frame: screen.frame, device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColorMake(0.002, 0.008, 0.018, 1)
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.preferredFramesPerSecond = settings.targetFPS
        metalView.autoResizeDrawable = false
        metalView.drawableSize = screen.frame.size
        metalView.layer?.magnificationFilter = .linear

        window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        super.init()

        initializeParticles()
        metalView.delegate = self
        window.level = passiveWindowLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.animationBehavior = .none
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        window.sharingType = .readOnly
        window.contentView = metalView

        inputRouter = GestureInputRouter(screenFrame: screen.frame) { [weak window] in
            window?.windowNumber ?? -1
        }
        inputRouter.fullInteractionDidChange = { [weak self] enabled in
            guard let self else { return }
            self.window.ignoresMouseEvents = !enabled
            self.window.level = enabled ? self.interactiveWindowLevel : self.passiveWindowLevel
            if enabled {
                self.window.makeFirstResponder(self.metalView)
                self.window.orderFrontRegardless()
            }
        }

        installLifecycleObservers()
        NSLog(
            "ParticleRenderer display %u: %@, unifiedMemory=%@, maxParticles=%d",
            displayID,
            device.name,
            device.hasUnifiedMemory ? "YES" : "NO",
            maximumParticleCount
        )
    }

    private var passiveWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
    }

    private var interactiveWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func start() {
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        inputRouter.start()
        policyTimer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(performanceTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        policyTimer?.tolerance = 1
        applyPerformancePolicy()
    }

    func update(sessionID: UUID, settings: ParticleSettingsSnapshot) {
        self.sessionID = sessionID
        self.settings = settings
        applyPerformancePolicy()
    }

    func deactivate() {
        metalView.isPaused = true
        metalView.delegate = nil
        inputRouter.stop()
        policyTimer?.invalidate()
        policyTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        window.contentView = nil
        window.orderOut(nil)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        inputRouter.refreshModifierState()
        let now = CACurrentMediaTime()
        if now - lastPerformanceCheck >= 1 {
            lastPerformanceCheck = now
            applyPerformancePolicy()
        }
        guard !isScreenLocked, CGDisplayIsActive(displayID) != 0, CGDisplayIsAsleep(displayID) == 0 else {
            return
        }
        guard inFlightSemaphore.wait(timeout: .now()) == .success else { return }
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            inFlightSemaphore.signal()
            return
        }

        let deltaTime = Float(min(max(now - lastFrameTime, 1.0 / 240.0), 1.0 / 15.0))
        lastFrameTime = now
        let input = inputRouter.consumeSnapshot()
        let aspect = Float(max(screen.frame.width / max(screen.frame.height, 1), 1))
        let mouse = simulationPoint(from: input.globalMouseLocation, aspect: aspect)
        if input.shockwaveSerial != lastShockwaveSerial {
            lastShockwaveSerial = input.shockwaveSerial
            shockwaveCenter = simulationPoint(from: input.shockwaveLocation, aspect: aspect)
            shockwaveStartedAt = now
        }

        let sourceIndex = currentBufferIndex
        let destinationIndex = (currentBufferIndex + 1) % particleBuffers.count
        let uniformIndex = frameIndex % 3
        frameIndex &+= 1
        let activeCount = min(settings.particleCount, maximumParticleCount)
        let pressureScale = input.mouseIsDown ? max(input.pressure, 0.35) : 1
        let signedForce: Float
        if input.mouseIsDown {
            signedForce = input.isRepelling ? -abs(settings.forceStrength) : abs(settings.forceStrength)
        } else {
            signedForce = settings.forceStrength
        }
        let dragStrength = min(length(input.dragDelta) * 0.012, 4)
        let swirl = dragStrength + input.rotation * 2.4 + input.scrollDelta
        let adjustedRadius = settings.interactionRadius * max(0.4, 1 + input.magnification * 2)
        let music = MusicEffectEngine.shared.currentFrame()

        var simulationUniforms = ParticleSimulationUniforms(
            mousePosition: mouse,
            previousMousePosition: previousMouse,
            shockwaveCenter: shockwaveCenter,
            simulationBounds: SIMD2(aspect, 1),
            deltaTime: deltaTime,
            time: Float(now - startedAt),
            interactionRadius: adjustedRadius,
            forceStrength: signedForce,
            returnSpeed: settings.returnSpeed * (1 + music.bass * 0.65),
            swirlStrength: swirl,
            shockwaveAge: Float(now - shockwaveStartedAt),
            shockwaveStrength: 3.8,
            pressure: pressureScale,
            audioLevel: music.level,
            audioBass: music.bass,
            mouseActive: input.mouseIsInsideDisplay ? 1 : 0,
            particleCount: UInt32(activeCount)
        )
        previousMouse = mouse
        copy(&simulationUniforms, to: simulationUniformBuffers[uniformIndex])

        var renderUniforms = ParticleRenderUniforms(
            viewportSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            simulationBounds: SIMD2(aspect, 1),
            particleSize: settings.particleSize * (1 + music.level * 0.7),
            trailLength: settings.trailLength,
            time: Float(now - startedAt),
            audioLevel: music.level
        )
        copy(&renderUniforms, to: renderUniformBuffers[uniformIndex])

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            inFlightSemaphore.signal()
            return
        }
        computeEncoder.label = "Particle Compute Pass \(displayID)"
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setBuffer(particleBuffers[sourceIndex], offset: 0, index: 0)
        computeEncoder.setBuffer(particleBuffers[destinationIndex], offset: 0, index: 1)
        computeEncoder.setBuffer(simulationUniformBuffers[uniformIndex], offset: 0, index: 2)
        let width = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
        computeEncoder.dispatchThreads(
            MTLSize(width: activeCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        computeEncoder.endEncoding()

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            inFlightSemaphore.signal()
            return
        }
        renderEncoder.label = "Particle Batch Render Pass \(displayID)"
        renderEncoder.setRenderPipelineState(renderPipeline)
        renderEncoder.setVertexBuffer(particleBuffers[destinationIndex], offset: 0, index: 0)
        renderEncoder.setVertexBuffer(renderUniformBuffers[uniformIndex], offset: 0, index: 1)
        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: activeCount
        )
        renderEncoder.endEncoding()

        currentBufferIndex = destinationIndex
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }
        commandBuffer.commit()
    }

    private func initializeParticles() {
        let aspect = Float(max(screen.frame.width / max(screen.frame.height, 1), 1))
        let particles = (0..<maximumParticleCount).map { index -> ParticleGPU in
            let seed = hash(UInt32(index) &* 747_796_405 &+ 2_891_336_453)
            let target = logoTarget(index: index, count: maximumParticleCount, aspect: aspect, seed: seed)
            let angle = seed * .pi * 2
            let radius = 0.03 + hash(UInt32(index) &+ 91) * 0.42
            return ParticleGPU(
                position: target + SIMD2(cos(angle), sin(angle)) * radius,
                velocity: .zero,
                target: target,
                life: 2 + hash(UInt32(index) &+ 17) * 8,
                seed: seed
            )
        }
        particles.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            for buffer in particleBuffers {
                memcpy(buffer.contents(), baseAddress, bytes.count)
            }
        }
    }

    /// Generates the app-mark target: rounded frame, sun, and layered landscape waves.
    private func logoTarget(index: Int, count: Int, aspect: Float, seed: Float) -> SIMD2<Float> {
        let fraction = Float(index) / Float(max(count - 1, 1))
        let jitter = (hash(UInt32(index) &+ 313) - 0.5) * 0.012
        if fraction < 0.08 {
            let t = fraction / 0.08
            let angle = t * .pi * 2
            return SIMD2(cos(angle) * 0.78, sin(angle) * 0.78) + SIMD2(repeating: jitter)
        }
        if fraction < 0.17 {
            let t = (fraction - 0.08) / 0.09
            let angle = t * .pi * 2
            return SIMD2(0.34 * aspect + cos(angle) * 0.13, 0.33 + sin(angle) * 0.13)
                + SIMD2(repeating: jitter)
        }
        let wave = (fraction - 0.17) / 0.83
        let band = index % 3
        let x = (hash(UInt32(index) &+ 601) * 1.55 - 0.775) * min(aspect, 1.8)
        let phase = Float(band) * 0.85
        let base = -0.12 - Float(band) * 0.17
        let y = base + sin(x * (2.1 + Float(band) * 0.35) + phase) * (0.20 - Float(band) * 0.025)
        let fill = (hash(UInt32(index) &+ 997) - 0.5) * (0.12 + wave * 0.06)
        return SIMD2(x, y + fill + seed * 0.008)
    }

    private func hash(_ value: UInt32) -> Float {
        var x = value
        x = ((x >> 16) ^ x) &* 0x45D9F3B
        x = ((x >> 16) ^ x) &* 0x45D9F3B
        x = (x >> 16) ^ x
        return Float(x & 0x00FF_FFFF) / Float(0x0100_0000)
    }

    private func simulationPoint(from globalPoint: CGPoint, aspect: Float) -> SIMD2<Float> {
        let normalizedX = Float((globalPoint.x - screen.frame.minX) / max(screen.frame.width, 1))
        let normalizedY = Float((globalPoint.y - screen.frame.minY) / max(screen.frame.height, 1))
        return SIMD2((normalizedX * 2 - 1) * aspect, normalizedY * 2 - 1)
    }

    private func copy<T>(_ value: inout T, to buffer: MTLBuffer) {
        withUnsafeBytes(of: &value) { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memcpy(buffer.contents(), baseAddress, bytes.count)
        }
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsChanged), name: .particleSettingsDidChange, object: nil)
        center.addObserver(self, selector: #selector(performanceSettingsChanged), name: .performanceSettingsDidChange, object: nil)
        center.addObserver(self, selector: #selector(performanceEnvironmentChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        center.addObserver(self, selector: #selector(performanceEnvironmentChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(performanceEnvironmentChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(pauseForSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resumeAfterSleep), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(performanceEnvironmentChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func settingsChanged() {
        settings = ParticleSettingsStore.shared.snapshot
        applyPerformancePolicy()
    }

    @objc private func performanceSettingsChanged() {
        performanceSettings = PerformanceSettingsStore.shared.snapshot
        applyPerformancePolicy()
    }

    @objc private func performanceEnvironmentChanged() {
        applyPerformancePolicy()
    }

    @objc private func performanceTimerFired(_ timer: Timer) {
        applyPerformancePolicy()
    }

    @objc private func pauseForSleep() {
        metalView.isPaused = true
    }

    @objc private func resumeAfterSleep() {
        isScreenLocked = false
        lastFrameTime = CACurrentMediaTime()
        applyPerformancePolicy()
    }

    @objc private func screenLocked() {
        isScreenLocked = true
        metalView.isPaused = true
    }

    @objc private func screenUnlocked() {
        isScreenLocked = false
        lastFrameTime = CACurrentMediaTime()
        applyPerformancePolicy()
    }

    private func applyPerformancePolicy() {
        guard !isScreenLocked, CGDisplayIsActive(displayID) != 0, CGDisplayIsAsleep(displayID) == 0 else {
            metalView.isPaused = true
            return
        }

        if performanceSettings.pauseInLowPowerMode
            && (ProcessInfo.processInfo.isLowPowerModeEnabled
                || SystemPerformanceState.isBatteryLevelLow)
        {
            metalView.isPaused = true
            return
        }
        if performanceSettings.pauseForFullScreenApps
            && SystemPerformanceState.frontmostApplicationCovers(displayID: displayID)
        {
            metalView.isPaused = true
            return
        }

        var fps = min(settings.targetFPS, performanceSettings.targetFPS)
        if performanceSettings.batteryModeEnabled && SystemPerformanceState.isOnBatteryPower {
            fps = min(fps, 30)
        }
        switch ProcessInfo.processInfo.thermalState {
        case .serious:
            fps = min(fps, 30)
        case .critical:
            fps = min(fps, 15)
        default:
            break
        }
        metalView.preferredFramesPerSecond = max(fps, 5)
        metalView.isPaused = false
    }
}
