import AppKit
import Combine
import CoreGraphics
import Foundation
import WebKit

/// Native macOS HTML/WebGL wallpaper renderer.
///
/// This deliberately uses WKWebView rather than the Windows WorkerW / Qt
/// implementation used by the reference project. Each display owns its own
/// isolated web process and remains click-through until Option is held.
@MainActor
final class WebRenderer: NSObject, WallpaperRenderer {
    let identifier = "web.webkit"
    let supportedFileExtensions: Set<String> = ["html", "htm"]

    private var controllers: [CGDirectDisplayID: WebWallpaperController] = [:]

    func canRender(_ sourceURL: URL) -> Bool {
        sourceURL.isFileURL
            ? supportedFileExtensions.contains(sourceURL.pathExtension.lowercased())
            : ["http", "https"].contains(sourceURL.scheme?.lowercased() ?? "")
    }

    func render(_ request: RendererRequest) throws -> WallpaperSession {
        guard canRender(request.sourceURL) else {
            throw RendererError.unsupportedSource(request.sourceURL)
        }
        if request.sourceURL.isFileURL,
           !FileManager.default.fileExists(atPath: request.sourceURL.path) {
            throw RendererError.unsupportedSource(request.sourceURL)
        }

        let available = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let id = screen.webDirectDisplayID else { return nil }
            return (id, screen)
        }
        let requested = Set(request.displayIDs)
        let targets = request.displayIDs.isEmpty
            ? available : available.filter { requested.contains($0.0) }
        guard !targets.isEmpty else { throw RendererError.rendererUnavailable(identifier) }

        let sessionID = UUID()
        for (displayID, screen) in targets {
            controllers[displayID]?.deactivate()
            let controller = WebWallpaperController(
                sessionID: sessionID,
                sourceURL: request.sourceURL,
                screen: screen
            )
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
        let ids = controllers.compactMap { id, controller in
            controller.sessionID == session.id ? id : nil
        }
        ids.forEach { controllers.removeValue(forKey: $0)?.deactivate() }
    }

    func stopAll() {
        let active = Array(controllers.values)
        controllers.removeAll()
        active.forEach { $0.deactivate() }
    }
}

private extension NSScreen {
    var webDirectDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
private final class WebWallpaperController: NSObject, WKNavigationDelegate {
    let sessionID: UUID
    private let sourceURL: URL
    private let screen: NSScreen
    private let webView: WKWebView
    private let window: NSWindow
    private var hasForwardedPointer = false
    private let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1
    )

    init(sessionID: UUID, sourceURL: URL, screen: NSScreen) {
        self.sessionID = sessionID
        self.sourceURL = sourceURL
        self.screen = screen

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = true
        let contentController = WKUserContentController()
        contentController.addUserScript(
            WKUserScript(
                source: WebWallpaperBridge.bootstrapScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController = contentController
        webView = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: configuration)
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init()

        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        window.level = desktopLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.animationBehavior = .none
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.sharingType = .readOnly
        window.contentView = webView
    }

    func start() {
        window.setFrame(screen.frame, display: true)
        loadSource()
        window.orderFrontRegardless()

        // A global NSEvent monitor intentionally does not receive events while
        // its owning app is active. Return focus to Finder after applying the
        // wallpaper so click-through desktop use and pointer forwarding work
        // at the same time. The app is still available from the menu bar.
        DispatchQueue.main.async {
            NSApp.hide(nil)
        }

        // A CGEvent tap is required for reliable cross-app mouse tracking at
        // the desktop layer. It is listen-only: it never consumes or alters
        // Finder/Desktop input.
        WebInputMonitor.shared.add(self)
        WebPointerPoller.shared.add(self)
    }

    func deactivate() {
        WebInputMonitor.shared.remove(self)
        WebPointerPoller.shared.remove(self)
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        window.contentView = nil
        window.orderOut(nil)
    }

    private func loadSource() {
        if sourceURL.isFileURL {
            let accessURL = sourceURL.deletingLastPathComponent()
            webView.loadFileURL(sourceURL, allowingReadAccessTo: accessURL)
        } else {
            webView.load(URLRequest(url: sourceURL))
        }
    }

    fileprivate func forward(_ event: NSEvent) {
        let optionHeld = event.modifierFlags.contains(.option)
        if event.type == .flagsChanged {
            window.ignoresMouseEvents = !optionHeld
            window.level = optionHeld
                ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                : desktopLevel
            if optionHeld { window.orderFrontRegardless() }
            return
        }

        // In direct mode WKWebView receives native events itself. Mirroring
        // only occurs while click-through is active, avoiding duplicate input.
        guard !optionHeld else { return }
        let point = event.locationInWindow
        let x = point.x - screen.frame.minX
        let y = screen.frame.maxY - point.y
        guard x >= 0, y >= 0, x <= screen.frame.width, y <= screen.frame.height else { return }

        let type: String
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged: type = "mousemove"
        case .leftMouseDown, .rightMouseDown: type = "mousedown"
        case .leftMouseUp, .rightMouseUp: type = "mouseup"
        case .scrollWheel: type = "wheel"
        default: return
        }
        let button = event.type == .rightMouseDown || event.type == .rightMouseUp ? 2 : 0
        let deltaY = event.type == .scrollWheel ? event.scrollingDeltaY : 0
        let pointerType: String
        switch type {
        case "mousemove": pointerType = "pointermove"
        case "mousedown": pointerType = "pointerdown"
        case "mouseup": pointerType = "pointerup"
        default: pointerType = ""
        }
        let script = """
        (() => {
          const target = document.elementFromPoint(\(x), \(y)) || document.body || window;
          const base = { clientX: \(x), clientY: \(y), screenX: \(point.x), screenY: \(point.y), button: \(button), buttons: \(NSEvent.pressedMouseButtons), bubbles: true, cancelable: true };
          \(type == "wheel" ? "target.dispatchEvent(new WheelEvent('wheel', { ...base, deltaY: \(deltaY) }));" : "target.dispatchEvent(new PointerEvent('\(pointerType)', { ...base, pointerId: 1, pointerType: 'mouse', isPrimary: true })); target.dispatchEvent(new MouseEvent('\(type)', base));")
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                NSLog("Web wallpaper interaction injection failed: %@", error.localizedDescription)
                WebInputMonitor.shared.recordInjection(error: error.localizedDescription)
            } else if self?.hasForwardedPointer == false {
                self?.hasForwardedPointer = true
                NSLog("Web wallpaper interaction forwarding is active for %@", self?.sourceURL.absoluteString ?? "unknown")
                WebInputMonitor.shared.recordInjection(error: nil)
            }
        }
    }

    /// Permission-free base input for pages authored for AIWallpaperBridge.
    /// It reads the public cursor position and does not consume desktop input.
    fileprivate func forwardBridgeCursor(globalPoint: NSPoint, buttons: Int) {
        let x = globalPoint.x - screen.frame.minX
        let y = screen.frame.maxY - globalPoint.y
        guard x >= 0, y >= 0, x <= screen.frame.width, y <= screen.frame.height else { return }
        let script = "window.AIWallpaperBridge?.receiveInput({ x: \(x), y: \(y), width: \(screen.frame.width), height: \(screen.frame.height), buttons: \(buttons), timestamp: \(Date().timeIntervalSince1970 * 1000) });"
        webView.evaluateJavaScript(script)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let permitted = url.isFileURL || ["http", "https", "about", "data"].contains(url.scheme?.lowercased() ?? "")
        decisionHandler(permitted ? .allow : .cancel)
    }
}

/// Contract injected into every web wallpaper at document start. Web authors
/// listen for `aiwallpaperinput` or call `AIWallpaperBridge.onInput(handler)`.
enum WebWallpaperBridge {
    static let bootstrapScript = """
    (() => {
      if (window.AIWallpaperBridge) return;
      const handlers = new Set();
      const bridge = {
        input: Object.freeze({ x: 0, y: 0, width: 0, height: 0, buttons: 0, timestamp: 0 }),
        onInput(handler) { handlers.add(handler); return () => handlers.delete(handler); },
        receiveInput(next) {
          bridge.input = Object.freeze({ ...bridge.input, ...next });
          window.dispatchEvent(new CustomEvent('aiwallpaperinput', { detail: bridge.input }));
          handlers.forEach(handler => { try { handler(bridge.input); } catch (_) {} });
        }
      };
      Object.defineProperty(window, 'AIWallpaperBridge', { value: bridge, configurable: false });
    })();
    """
}

@MainActor
private final class WebPointerPoller {
    static let shared = WebPointerPoller()

    private let controllers = NSHashTable<WebWallpaperController>.weakObjects()
    private var timer: Timer?

    func add(_ controller: WebWallpaperController) {
        controllers.add(controller)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.deliverCursor()
            }
        }
        timer?.tolerance = 1.0 / 120.0
    }

    func remove(_ controller: WebWallpaperController) {
        controllers.remove(controller)
        guard controllers.allObjects.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    private func deliverCursor() {
        let point = NSEvent.mouseLocation
        let buttons = NSEvent.pressedMouseButtons
        controllers.allObjects.forEach {
            $0.forwardBridgeCursor(globalPoint: point, buttons: buttons)
        }
    }
}

@MainActor
final class WebInputMonitor: ObservableObject {
    static let shared = WebInputMonitor()

    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var eventTapActive = false
    @Published private(set) var forwardedEventCount = 0
    @Published private(set) var lastEventDescription = "尚未收到桌面鼠标事件"
    @Published private(set) var lastInjectionError: String?

    private let controllers = NSHashTable<WebWallpaperController>.weakObjects()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    fileprivate func add(_ controller: WebWallpaperController) {
        controllers.add(controller)
        startIfNeeded()
    }

    fileprivate func remove(_ controller: WebWallpaperController) {
        controllers.remove(controller)
        if controllers.allObjects.isEmpty { stop() }
    }

    func requestPermissionAndRetry() {
        permissionGranted = AXIsProcessTrusted()
        if !permissionGranted {
            AXIsProcessTrustedWithOptions(
                ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            )
            lastEventDescription = "等待系统授予辅助功能权限"
            return
        }
        startIfNeeded()
    }

    func recordInjection(error: String?) {
        lastInjectionError = error
    }

    private func startIfNeeded() {
        guard eventTap == nil else {
            eventTapActive = true
            return
        }
        permissionGranted = AXIsProcessTrusted()
        guard permissionGranted else {
            AXIsProcessTrustedWithOptions(
                ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            )
            eventTapActive = false
            NSLog("Web wallpaper interaction needs Accessibility permission.")
            return
        }

        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown,
            .rightMouseUp, .leftMouseDragged, .rightMouseDragged,
            .scrollWheel, .flagsChanged,
        ]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
                DispatchQueue.main.async {
                    WebInputMonitor.shared.deliver(nsEvent)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        guard let eventTap else {
            eventTapActive = false
            NSLog("Unable to create web wallpaper event tap.")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        eventTapActive = true
        lastEventDescription = "事件 Tap 已启动，等待桌面鼠标输入"
    }

    private func deliver(_ event: NSEvent) {
        forwardedEventCount += 1
        lastEventDescription = String(
            format: "%@  (%.0f, %.0f)",
            String(describing: event.type),
            event.locationInWindow.x,
            event.locationInWindow.y
        )
        controllers.allObjects.forEach { $0.forward(event) }
    }

    private func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        eventTapActive = false
    }
}
