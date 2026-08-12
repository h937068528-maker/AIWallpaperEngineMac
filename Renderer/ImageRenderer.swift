import AppKit
import CoreGraphics
import Foundation

/// Low-overhead renderer for local JPEG and PNG desktop wallpapers.
@MainActor
final class ImageRenderer: WallpaperRenderer {
    let identifier = "image.static"
    let supportedFileExtensions: Set<String> = ["jpg", "jpeg", "png"]

    private var controllers: [CGDirectDisplayID: StaticImageWallpaperController] = [:]

    func canRender(_ sourceURL: URL) -> Bool {
        supportedFileExtensions.contains(sourceURL.pathExtension.lowercased())
            && !LivePhotoResourceResolver.isLivePhotoSource(sourceURL)
    }

    func render(_ request: RendererRequest) throws -> WallpaperSession {
        guard
            FileManager.default.fileExists(atPath: request.sourceURL.path),
            let image = NSImage(contentsOf: request.sourceURL)
        else {
            throw RendererError.unsupportedSource(request.sourceURL)
        }

        let availableScreens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let displayID = screen.staticImageDirectDisplayID else { return nil }
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
        for (displayID, screen) in targetScreens {
            if let controller = controllers[displayID] {
                controller.update(sessionID: sessionID, image: image)
            } else {
                let controller = StaticImageWallpaperController(
                    sessionID: sessionID,
                    image: image,
                    screen: screen
                )
                controllers[displayID] = controller
                controller.start()
            }
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
            controllers.removeValue(forKey: displayID)?.deactivate()
        }
    }

    func stopAll() {
        let activeControllers = Array(controllers.values)
        controllers.removeAll()
        activeControllers.forEach { $0.deactivate() }
    }
}

private extension NSScreen {
    var staticImageDirectDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
private final class StaticImageWallpaperController {
    private(set) var sessionID: UUID

    private let screen: NSScreen
    private let imageView: AspectFillImageView
    private let window: NSWindow

    init(sessionID: UUID, image: NSImage, screen: NSScreen) {
        self.sessionID = sessionID
        self.screen = screen
        imageView = AspectFillImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        imageView.image = image
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

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
    }

    func start() {
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }

    func update(sessionID: UUID, image: NSImage) {
        self.sessionID = sessionID
        imageView.image = image
        imageView.needsDisplay = true
    }

    func deactivate() {
        window.contentView = nil
        window.orderOut(nil)
    }
}

@MainActor
private final class AspectFillImageView: NSView {
    var image: NSImage?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, bounds.width > 0, bounds.height > 0 else { return }

        NSColor.black.setFill()
        bounds.fill()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let targetAspect = bounds.width / bounds.height
        let imageAspect = imageSize.width / imageSize.height
        var sourceRect = NSRect(origin: .zero, size: imageSize)

        if imageAspect > targetAspect {
            let croppedWidth = imageSize.height * targetAspect
            sourceRect.origin.x = (imageSize.width - croppedWidth) / 2
            sourceRect.size.width = croppedWidth
        } else {
            let croppedHeight = imageSize.width / targetAspect
            sourceRect.origin.y = (imageSize.height - croppedHeight) / 2
            sourceRect.size.height = croppedHeight
        }

        image.draw(
            in: bounds,
            from: sourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
