import AppKit
import CoreGraphics
import Foundation

/// Native animated-image renderer for GIF wallpapers.
///
/// AppKit delegates GIF frame timing to Image I/O while the renderer owns the
/// same desktop-level lifecycle used by the Metal surface.
@MainActor
final class GIFRenderer: WallpaperRenderer {
    let identifier = "imageio.gif"
    let supportedFileExtensions: Set<String> = ["gif"]

    private var controllers: [CGDirectDisplayID: GIFWallpaperController] = [:]
    private var retiredControllers: [GIFWallpaperController] = []

    func render(_ request: RendererRequest) throws -> WallpaperSession {
        guard FileManager.default.fileExists(atPath: request.sourceURL.path) else {
            throw RendererError.unsupportedSource(request.sourceURL)
        }

        let availableScreens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let displayID = screen.gifDirectDisplayID else { return nil }
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
        var newControllers: [(CGDirectDisplayID, GIFWallpaperController)] = []

        do {
            for (displayID, screen) in targetScreens where controllers[displayID] == nil {
                let controller = try GIFWallpaperController(
                    sessionID: sessionID,
                    sourceURL: request.sourceURL,
                    screen: screen
                )
                newControllers.append((displayID, controller))
            }

            for (displayID, _) in targetScreens {
                try controllers[displayID]?.update(
                    sessionID: sessionID,
                    sourceURL: request.sourceURL
                )
            }
        } catch {
            newControllers.forEach { $0.1.deactivate() }
            throw error
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

    private func retire(_ controller: GIFWallpaperController) {
        controller.deactivate()
        retiredControllers.append(controller)
        let retiredSessionID = controller.sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.retiredControllers.removeAll { $0.sessionID == retiredSessionID }
        }
    }
}

private extension NSScreen {
    var gifDirectDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
private final class GIFWallpaperController: NSObject {
    private(set) var sessionID: UUID

    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private let imageView: NSImageView
    private let window: NSWindow
    private var performanceSettings = PerformanceSettingsStore.shared.snapshot
    private var isSleepingOrLocked = false
    private var policyTimer: Timer?

    init(sessionID: UUID, sourceURL: URL, screen: NSScreen) throws {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw RendererError.invalidAnimatedImage(sourceURL)
        }

        self.sessionID = sessionID
        self.screen = screen
        guard let displayID = screen.gifDirectDisplayID else {
            throw RendererError.rendererUnavailable("imageio.gif")
        }
        self.displayID = displayID
        imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        super.init()

        imageView.image = image
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.animates = true

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
        window.contentView = imageView

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(pauseAnimation),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(resumeAnimation),
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
            selector: #selector(pauseAnimation),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(resumeAnimation),
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

    func update(sessionID: UUID, sourceURL: URL) throws {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw RendererError.invalidAnimatedImage(sourceURL)
        }
        self.sessionID = sessionID
        imageView.animates = false
        policyTimer?.invalidate()
        policyTimer = nil
        imageView.image = image
        applyPerformancePolicy()
    }

    func deactivate() {
        imageView.animates = false
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        window.contentView = nil
        window.orderOut(nil)
    }

    @objc private func pauseAnimation() {
        isSleepingOrLocked = true
        imageView.animates = false
    }

    @objc private func resumeAnimation() {
        isSleepingOrLocked = false
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

    private func applyPerformancePolicy() {
        guard !isSleepingOrLocked else {
            imageView.animates = false
            return
        }
        if performanceSettings.pauseInLowPowerMode
            && (ProcessInfo.processInfo.isLowPowerModeEnabled
                || SystemPerformanceState.isBatteryLevelLow)
        {
            imageView.animates = false
            return
        }
        if performanceSettings.pauseForFullScreenApps
            && SystemPerformanceState.frontmostApplicationCovers(displayID: displayID)
        {
            imageView.animates = false
            return
        }
        imageView.animates = true
    }
}
