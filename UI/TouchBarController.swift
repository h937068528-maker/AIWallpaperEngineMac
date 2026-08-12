import AppKit

/// Native Touch Bar controls for legacy MacBook Pro models.
/// No third-party animation assets or source code are used.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private enum ItemIdentifier {
        static let animatedMascot = NSTouchBarItem.Identifier("com.aiwallpaperengine.touchbar.animatedMascot")
        static let show = NSTouchBarItem.Identifier("com.aiwallpaperengine.touchbar.show")
        static let battery = NSTouchBarItem.Identifier("com.aiwallpaperengine.touchbar.battery")
        static let fps = NSTouchBarItem.Identifier("com.aiwallpaperengine.touchbar.fps")
        static let hide = NSTouchBarItem.Identifier("com.aiwallpaperengine.touchbar.hide")
    }

    let touchBar = NSTouchBar()
    private let showWindow: () -> Void
    private let hideWindow: () -> Void
    private weak var batteryButton: NSButton?

    init(showWindow: @escaping () -> Void, hideWindow: @escaping () -> Void) {
        self.showWindow = showWindow
        self.hideWindow = hideWindow
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            ItemIdentifier.animatedMascot,
        ]
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case ItemIdentifier.animatedMascot:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = RainbowCometCatView()
            item.customizationLabel = "彩虹彗星猫"
            return item
        case ItemIdentifier.show:
            return buttonItem(identifier, title: "AI Wallpaper", image: "sparkles", action: #selector(showApp))
        case ItemIdentifier.hide:
            return buttonItem(identifier, title: "隐藏", image: "eye.slash", action: #selector(hideApp))
        case ItemIdentifier.battery:
            let item = buttonItem(identifier, title: batteryTitle, image: "battery.75", action: #selector(toggleBatteryMode))
            batteryButton = item.view as? NSButton
            return item
        case ItemIdentifier.fps:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let control = NSSegmentedControl(labels: ["30", "60", "120"], trackingMode: .selectOne, target: self, action: #selector(changeFPS(_:)))
            control.segmentStyle = .rounded
            control.selectedSegment = [30, 60, 120].firstIndex(of: PerformanceSettingsStore.shared.targetFPS) ?? 1
            item.view = control
            item.customizationLabel = "壁纸帧率"
            return item
        default:
            return nil
        }
    }

    private var batteryTitle: String {
        PerformanceSettingsStore.shared.batteryModeEnabled ? "省电：开" : "省电：关"
    }

    private func buttonItem(
        _ identifier: NSTouchBarItem.Identifier,
        title: String,
        image: String,
        action: Selector
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: image, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        item.view = button
        item.customizationLabel = title
        return item
    }

    @objc private func showApp() { showWindow() }
    @objc private func hideApp() { hideWindow() }

    @objc private func toggleBatteryMode() {
        PerformanceSettingsStore.shared.batteryModeEnabled.toggle()
        batteryButton?.title = batteryTitle
    }

    @objc private func changeFPS(_ sender: NSSegmentedControl) {
        let options = [30, 60, 120]
        guard sender.selectedSegment >= 0, sender.selectedSegment < options.count else { return }
        PerformanceSettingsStore.shared.targetFPS = options[sender.selectedSegment]
    }
}

/// A small, original animated mascot made entirely from AppKit drawing primitives.
/// It intentionally contains no third-party sprites, audio, or copied animation frames.
@MainActor
private final class RainbowCometCatView: NSView {
    private var animationTimer: Timer?
    private var phase: CGFloat = 0
    private let palette: [NSColor] = [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemCyan, .systemPurple]

    override var intrinsicContentSize: NSSize { NSSize(width: 780, height: 30) }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 780, height: 30)))
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.09
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        animationTimer?.invalidate()
        animationTimer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()

        drawStars(in: bounds)
        let centerX = bounds.width * 0.68 + sin(phase) * 3
        let centerY = bounds.midY + sin(phase * 1.7) * 2
        drawRainbowTrail(from: centerX - 26, centerY: centerY)
        drawCat(center: NSPoint(x: centerX, y: centerY))
    }

    private func drawStars(in bounds: NSRect) {
        for index in 0..<18 {
            let seed = CGFloat(index)
            let x = (seed * 47 + phase * (9 + seed.truncatingRemainder(dividingBy: 4)))
                .truncatingRemainder(dividingBy: max(bounds.width, 1))
            let y = 4 + (seed * 13).truncatingRemainder(dividingBy: 22)
            let alpha = 0.2 + 0.55 * ((sin(phase * 1.5 + seed) + 1) / 2)
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.5, height: 1.5)).fill()
        }
    }

    private func drawRainbowTrail(from startX: CGFloat, centerY: CGFloat) {
        let tailLength: CGFloat = 150
        for (index, color) in palette.enumerated() {
            let yOffset = CGFloat(index - 2) * 2.7
            let path = NSBezierPath()
            path.move(to: NSPoint(x: max(4, startX - tailLength), y: centerY + yOffset))
            path.curve(
                to: NSPoint(x: startX, y: centerY + yOffset),
                controlPoint1: NSPoint(x: startX - tailLength * 0.55, y: centerY + yOffset + sin(phase + CGFloat(index)) * 5),
                controlPoint2: NSPoint(x: startX - 30, y: centerY + yOffset - sin(phase * 1.4 + CGFloat(index)) * 4)
            )
            color.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 2.6
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private func drawCat(center: NSPoint) {
        let bob = sin(phase * 1.7) * 1.3
        let body = NSBezierPath(roundedRect: NSRect(x: center.x - 19, y: center.y - 8 + bob, width: 35, height: 17), xRadius: 7, yRadius: 7)
        NSColor(calibratedRed: 0.34, green: 0.22, blue: 0.56, alpha: 1).setFill()
        body.fill()

        let head = NSBezierPath(ovalIn: NSRect(x: center.x + 9, y: center.y - 9 + bob, width: 17, height: 18))
        NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.98, alpha: 1).setFill()
        head.fill()
        drawEar(at: NSPoint(x: center.x + 12, y: center.y + 6 + bob))
        drawEar(at: NSPoint(x: center.x + 22, y: center.y + 6 + bob))

        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x + 15, y: center.y + 1 + bob, width: 2.4, height: 2.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: center.x + 21, y: center.y + 1 + bob, width: 2.4, height: 2.4)).fill()
        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x + 18, y: center.y - 3 + bob, width: 3, height: 2)).fill()

        NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.98, alpha: 1).setStroke()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: center.x - 16, y: center.y - 1 + bob))
        tail.curve(to: NSPoint(x: center.x - 25, y: center.y + 7 + bob), controlPoint1: NSPoint(x: center.x - 25, y: center.y - 8 + bob), controlPoint2: NSPoint(x: center.x - 31, y: center.y + 5 + bob))
        tail.lineWidth = 3
        tail.lineCapStyle = .round
        tail.stroke()
    }

    private func drawEar(at point: NSPoint) {
        let ear = NSBezierPath()
        ear.move(to: point)
        ear.line(to: NSPoint(x: point.x + 4, y: point.y + 7))
        ear.line(to: NSPoint(x: point.x + 7, y: point.y))
        ear.close()
        NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.98, alpha: 1).setFill()
        ear.fill()
    }
}
