import AppKit
import CoreGraphics
import MetalKit
import QuartzCore

/// Native Metal wallpaper renderer for procedural, real-time scenes.
///
/// Each target display owns an independent MTKView at the desktop window level.
/// Rendering remains in-process so future package-defined shaders can reuse the
/// same lifecycle without changing Core or the SwiftUI application shell.
@MainActor
final class MetalRenderer: WallpaperRenderer {
    let identifier = "metal.shader"
    let supportedFileExtensions: Set<String> = []

    private var controllers: [CGDirectDisplayID: MetalWallpaperController] = [:]
    private var retiredControllers: [MetalWallpaperController] = []

    func canRender(_ sourceURL: URL) -> Bool {
        MetalShaderPreset(sourceURL: sourceURL) != nil
    }

    func render(_ request: RendererRequest) throws -> WallpaperSession {
        guard let preset = MetalShaderPreset(sourceURL: request.sourceURL) else {
            throw RendererError.unsupportedSource(request.sourceURL)
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalUnavailable
        }

        let availableScreens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let displayID = screen.directDisplayID else { return nil }
            return (displayID, screen)
        }
        let requestedIDs = Set(request.displayIDs)
        let targetScreens = request.displayIDs.isEmpty
            ? availableScreens
            : availableScreens.filter { requestedIDs.contains($0.0) }

        guard !targetScreens.isEmpty else {
            throw RendererError.rendererUnavailable(identifier)
        }

        let sessionID = UUID()
        var newControllers: [(CGDirectDisplayID, MetalWallpaperController)] = []

        do {
            for (displayID, screen) in targetScreens where controllers[displayID] == nil {
                let controller = try MetalWallpaperController(
                    sessionID: sessionID,
                    preset: preset,
                    screen: screen,
                    displayID: displayID,
                    device: device
                )
                newControllers.append((displayID, controller))
            }
        } catch {
            newControllers.forEach { $0.1.deactivate() }
            throw error
        }

        for (displayID, _) in targetScreens {
            controllers[displayID]?.update(sessionID: sessionID, preset: preset)
        }
        for (displayID, controller) in newControllers {
            controllers[displayID] = controller
            controller.start()
        }

        return WallpaperSession(
            id: sessionID,
            sourceURL: request.sourceURL,
            displayIDs: targetScreens.map(\.0),
            rendererIdentifier: identifier,
            state: .running
        )
    }

    func stop(_ session: WallpaperSession) {
        let matchingIDs = controllers.compactMap { displayID, controller in
            controller.sessionID == session.id ? displayID : nil
        }
        for displayID in matchingIDs {
            if let controller = controllers.removeValue(forKey: displayID) {
                retire(controller)
            }
        }
    }

    func stopAll() {
        let activeControllers = Array(controllers.values)
        controllers.removeAll()
        activeControllers.forEach(retire)
    }

    private func retire(_ controller: MetalWallpaperController) {
        controller.deactivate()
        retiredControllers.append(controller)
        let retiredSessionID = controller.sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.retiredControllers.removeAll { $0.sessionID == retiredSessionID }
        }
    }
}

private extension NSScreen {
    var directDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private struct ShaderUniforms {
    var time: Float
    var resolution: SIMD2<Float>
    var mouse: SIMD2<Float>
    var effect: UInt32
}

@MainActor
private final class MetalWallpaperController: NSObject, MTKViewDelegate {
    private(set) var sessionID: UUID

    private var preset: MetalShaderPreset
    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let metalView: MTKView
    private let window: NSWindow
    private let startedAt = CACurrentMediaTime()
    private var performanceSettings = PerformanceSettingsStore.shared.snapshot
    private var isScreenLocked = false
    private var lastPerformanceCheck: CFTimeInterval = 0
    private var policyTimer: Timer?

    init(
        sessionID: UUID,
        preset: MetalShaderPreset,
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        device: MTLDevice
    ) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.metalUnavailable
        }

        let library: MTLLibrary
        do {
            guard
                let shaderURL = Bundle.main.url(
                    forResource: "WallpaperShaders",
                    withExtension: "metal"
                )
            else {
                throw RendererError.shaderCompilationFailed("Shader resource is missing.")
            }
            let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
            let options = MTLCompileOptions()
            options.fastMathEnabled = true
            library = try device.makeLibrary(source: shaderSource, options: options)
        } catch {
            if let rendererError = error as? RendererError {
                throw rendererError
            }
            throw RendererError.shaderCompilationFailed(error.localizedDescription)
        }

        guard
            let vertexFunction = library.makeFunction(name: "wallpaperVertex"),
            let fragmentFunction = library.makeFunction(name: "wallpaperFragment")
        else {
            throw RendererError.shaderCompilationFailed("Required shader functions are missing.")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Procedural Wallpaper Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw RendererError.shaderCompilationFailed(error.localizedDescription)
        }

        self.sessionID = sessionID
        self.preset = preset
        self.screen = screen
        self.displayID = displayID
        self.commandQueue = commandQueue

        metalView = MTKView(frame: screen.frame, device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColorMake(0.01, 0.015, 0.035, 1)
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.preferredFramesPerSecond = 60
        metalView.autoResizeDrawable = false
        // Render at logical display resolution. This keeps 5K/6K Retina output
        // efficient while AppKit performs a single hardware-accelerated upscale.
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

        metalView.delegate = self
        // Stay above the system's static wallpaper surface while remaining
        // below Finder's desktop-icon window.
        window.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1
        )
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.animationBehavior = .none
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.sharingType = .readOnly
        window.contentView = metalView

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(pauseRendering),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(resumeRendering),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(performanceEnvironmentChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(performanceSettingsChanged),
            name: .performanceSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(performanceEnvironmentChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(screenLocked),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    func start() {
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
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

    func update(sessionID: UUID, preset: MetalShaderPreset) {
        self.sessionID = sessionID
        self.preset = preset
        applyPerformancePolicy()
    }

    func deactivate() {
        metalView.isPaused = true
        metalView.delegate = nil
        policyTimer?.invalidate()
        policyTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        window.contentView = nil
        window.orderOut(nil)
    }

    @objc private func pauseRendering() {
        metalView.isPaused = true
    }

    @objc private func resumeRendering() {
        isScreenLocked = false
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

    @objc private func screenLocked() {
        isScreenLocked = true
        metalView.isPaused = true
    }

    @objc private func screenUnlocked() {
        isScreenLocked = false
        applyPerformancePolicy()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if now - lastPerformanceCheck >= 1 {
            lastPerformanceCheck = now
            applyPerformancePolicy()
        }
        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        let mouseLocation = NSEvent.mouseLocation
        let localX = Float((mouseLocation.x - screen.frame.minX) / max(screen.frame.width, 1))
        let localY = Float((mouseLocation.y - screen.frame.minY) / max(screen.frame.height, 1))

        var uniforms = ShaderUniforms(
            time: Float(now - startedAt),
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            mouse: SIMD2(min(max(localX, 0), 1), min(max(localY, 0), 1)),
            effect: effectIndex
        )

        encoder.label = "Procedural Wallpaper Encoder \(displayID)"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<ShaderUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func applyPerformancePolicy() {
        guard
            !isScreenLocked,
            CGDisplayIsActive(displayID) != 0,
            CGDisplayIsAsleep(displayID) == 0
        else {
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

        var fps = performanceSettings.targetFPS
        if performanceSettings.batteryModeEnabled && SystemPerformanceState.isOnBatteryPower {
            fps = min(fps, 30)
        }
        metalView.preferredFramesPerSecond = max(fps, 15)
        metalView.isPaused = false
    }

    private var effectIndex: UInt32 {
        switch preset {
        case .particles: 0
        case .water: 1
        case .interactive: 2
        }
    }
}
