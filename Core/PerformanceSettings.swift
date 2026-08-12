import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit.ps

struct PerformanceSettingsSnapshot: Sendable {
    var batteryModeEnabled: Bool
    var pauseInLowPowerMode: Bool
    var pauseForFullScreenApps: Bool
    var targetFPS: Int
}

extension Notification.Name {
    static let performanceSettingsDidChange = Notification.Name(
        "com.aiwallpaperengine.mac.performanceSettingsDidChange"
    )
}

@MainActor
final class PerformanceSettingsStore: ObservableObject {
    static let shared = PerformanceSettingsStore()
    static let darwinNotification = "com.aiwallpaperengine.mac.performanceSettingsChanged"

    @Published var batteryModeEnabled: Bool { didSet { persist() } }
    @Published var pauseInLowPowerMode: Bool { didSet { persist() } }
    @Published var pauseForFullScreenApps: Bool { didSet { persist() } }
    @Published var targetFPS: Int { didSet { persist() } }

    enum Key {
        static let batteryModeEnabled = "performance.batteryModeEnabled"
        static let pauseInLowPowerMode = "performance.pauseInLowPowerMode"
        static let pauseForFullScreenApps = "performance.pauseForFullScreenApps"
        static let targetFPS = "performance.targetFPS"
    }

    private let defaults: UserDefaults
    private var isLoading = true

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.batteryModeEnabled: true,
            Key.pauseInLowPowerMode: true,
            Key.pauseForFullScreenApps: true,
            Key.targetFPS: 60,
        ])
        batteryModeEnabled = defaults.bool(forKey: Key.batteryModeEnabled)
        pauseInLowPowerMode = defaults.bool(forKey: Key.pauseInLowPowerMode)
        pauseForFullScreenApps = defaults.bool(forKey: Key.pauseForFullScreenApps)
        targetFPS = defaults.integer(forKey: Key.targetFPS)
        isLoading = false
    }

    var snapshot: PerformanceSettingsSnapshot {
        PerformanceSettingsSnapshot(
            batteryModeEnabled: batteryModeEnabled,
            pauseInLowPowerMode: pauseInLowPowerMode,
            pauseForFullScreenApps: pauseForFullScreenApps,
            targetFPS: min(max(targetFPS, 15), 120)
        )
    }

    private func persist() {
        guard !isLoading else { return }
        defaults.set(batteryModeEnabled, forKey: Key.batteryModeEnabled)
        defaults.set(pauseInLowPowerMode, forKey: Key.pauseInLowPowerMode)
        defaults.set(pauseForFullScreenApps, forKey: Key.pauseForFullScreenApps)
        defaults.set(min(max(targetFPS, 15), 120), forKey: Key.targetFPS)
        defaults.synchronize()
        NotificationCenter.default.post(name: .performanceSettingsDidChange, object: nil)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.darwinNotification as CFString),
            nil,
            nil,
            true
        )
    }
}

enum SystemPerformanceState {
    static var isOnBatteryPower: Bool {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                let type = description[kIOPSTypeKey] as? String,
                let state = description[kIOPSPowerSourceStateKey] as? String
            else { continue }
            if type == kIOPSInternalBatteryType && state == kIOPSBatteryPowerValue {
                return true
            }
        }
        return false
    }

    static var isBatteryLevelLow: Bool {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Double,
                let maximum = description[kIOPSMaxCapacityKey] as? Double,
                maximum > 0
            else { continue }
            if current / maximum <= 0.20 {
                return true
            }
        }
        return false
    }

    static func frontmostApplicationCovers(displayID: CGDirectDisplayID) -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else { return false }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        guard application.bundleIdentifier != "com.apple.finder" else { return false }
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return false }

        let displayBounds = CGDisplayBounds(displayID)
        let displayArea = displayBounds.width * displayBounds.height
        guard displayArea > 0 else { return false }

        return windows.contains { info in
            guard
                (info[kCGWindowOwnerPID as String] as? pid_t) == application.processIdentifier,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: dictionary)
            else { return false }
            let intersection = bounds.intersection(displayBounds)
            let coverage = intersection.width * intersection.height / displayArea
            return coverage >= 0.94
        }
    }
}
