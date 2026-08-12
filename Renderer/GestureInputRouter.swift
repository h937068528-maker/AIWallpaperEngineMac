import AppKit
import CoreGraphics

struct ParticleInteractionSnapshot: Sendable {
    var globalMouseLocation: CGPoint
    var mouseIsInsideDisplay: Bool
    var mouseIsDown: Bool
    var isRepelling: Bool
    var dragDelta: SIMD2<Float>
    var scrollDelta: Float
    var magnification: Float
    var rotation: Float
    var pressure: Float
    var shockwaveSerial: UInt64
    var shockwaveLocation: CGPoint
}

/// Routes advanced gestures only while Option is held. Basic pointer following
/// always uses the system-wide cursor position and therefore needs no event tap.
@MainActor
final class GestureInputRouter {
    var fullInteractionDidChange: ((Bool) -> Void)?

    private let screenFrame: CGRect
    private let windowNumber: () -> Int
    private var localMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var optionIsDown = false
    private var mouseIsDown = false
    private var isRepelling = false
    private var dragDelta = SIMD2<Float>(repeating: 0)
    private var scrollDelta: Float = 0
    private var magnification: Float = 0
    private var rotation: Float = 0
    private var pressure: Float = 0
    private var shockwaveSerial: UInt64 = 0
    private var shockwaveLocation = CGPoint.zero
    private var mouseDownLocation = CGPoint.zero

    init(screenFrame: CGRect, windowNumber: @escaping () -> Int) {
        self.screenFrame = screenFrame
        self.windowNumber = windowNumber
    }

    func start() {
        guard localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .leftMouseDragged, .rightMouseDragged, .mouseMoved, .scrollWheel,
            .magnify, .rotate, .pressure,
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            self?.updateOptionState(event.modifierFlags.contains(.option))
        }
        refreshModifierState()
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
        localMonitor = nil
        globalFlagsMonitor = nil
        updateOptionState(false)
    }

    func refreshModifierState() {
        updateOptionState(NSEvent.modifierFlags.contains(.option))
    }

    func consumeSnapshot() -> ParticleInteractionSnapshot {
        let location = NSEvent.mouseLocation
        let snapshot = ParticleInteractionSnapshot(
            globalMouseLocation: location,
            mouseIsInsideDisplay: screenFrame.contains(location),
            mouseIsDown: mouseIsDown,
            isRepelling: isRepelling,
            dragDelta: dragDelta,
            scrollDelta: scrollDelta,
            magnification: magnification,
            rotation: rotation,
            pressure: pressure,
            shockwaveSerial: shockwaveSerial,
            shockwaveLocation: shockwaveLocation
        )
        dragDelta *= 0.45
        scrollDelta *= 0.55
        magnification *= 0.55
        rotation *= 0.55
        return snapshot
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            updateOptionState(event.modifierFlags.contains(.option))
            return
        }
        guard optionIsDown, event.windowNumber == windowNumber() else { return }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            mouseIsDown = true
            isRepelling = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
            mouseDownLocation = NSEvent.mouseLocation
            pressure = max(Float(event.pressure), 0.35)
        case .leftMouseUp, .rightMouseUp:
            let location = NSEvent.mouseLocation
            if hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y) < 12 {
                shockwaveSerial &+= 1
                shockwaveLocation = location
            }
            mouseIsDown = false
            pressure = 0
        case .leftMouseDragged, .rightMouseDragged:
            dragDelta += SIMD2(Float(event.deltaX), Float(-event.deltaY))
            pressure = max(Float(event.pressure), pressure)
        case .scrollWheel:
            scrollDelta += Float(event.scrollingDeltaY) * 0.012
        case .magnify:
            magnification += Float(event.magnification)
        case .rotate:
            rotation += Float(event.rotation) * .pi / 180
        case .pressure:
            pressure = Float(event.pressure)
        default:
            break
        }
    }

    private func updateOptionState(_ enabled: Bool) {
        guard enabled != optionIsDown else { return }
        optionIsDown = enabled
        if !enabled {
            mouseIsDown = false
            pressure = 0
        }
        fullInteractionDidChange?(enabled)
    }
}
