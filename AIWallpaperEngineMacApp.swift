/*
 * This file is part of LiveWallpaper – LiveWallpaper App for macOS.
 * Copyright (C) 2025 Bios thusvill
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import AppKit
import ServiceManagement

let sharedEngine = WallpaperEngine.shared()

@MainActor
private final class WallpaperTouchBarWindow: NSWindow {
    private let providedTouchBar: () -> NSTouchBar?

    init(providedTouchBar: @escaping () -> NSTouchBar?) {
        self.providedTouchBar = providedTouchBar
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
    }

    override func makeTouchBar() -> NSTouchBar? {
        providedTouchBar()
    }
}

@main
struct AIWallpaperEngineMacApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
            Settings { EmptyView() }
    }
        
}


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    private var touchBarController: TouchBarController?
    
    let engine = sharedEngine
    @MainActor private lazy var coreEngine = AIWallpaperEngine.shared

    private var applicationDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "AIWallpaperEngineMac"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherApplicationInstances()
        _ = PerformanceSettingsStore.shared
        
        NSApp.setActivationPolicy(.accessory)

        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let icon = NSApp.applicationIconImage.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = false
            button.image = icon
            button.imagePosition = .imageOnly
            button.toolTip = "AIWallpaperEngineMac"
        }

        
        let menu = NSMenu()
        menu.addItem(statusMenuItem(title: L.showWindow, action: #selector(showWindow), keyEquivalent: "s"))
        menu.addItem(statusMenuItem(title: L.hideWindow, action: #selector(hideWindow), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(statusMenuItem(title: L.quit, action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        touchBarController = TouchBarController(
            showWindow: { [weak self] in self?.presentMainWindow() },
            hideWindow: { [weak self] in self?.hideMainWindow() }
        )

        // This window is a responder-chain Touch Bar provider. SwiftUI first
        // responders can then compose their contextual items into this bar.
        window = WallpaperTouchBarWindow { [weak self] in
            self?.touchBarController?.touchBar
        }
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 860, height: 560)
        
        window.center()
        window.contentView = NSHostingView(rootView: ContentView())
        window.title = applicationDisplayName
        window.isReleasedWhenClosed = false
        window.touchBar = touchBarController?.touchBar
        presentMainWindow()
        restoreSystemLockScreenImages()
        
        configureLoginItem()
        

        
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        coreEngine.terminateApplication()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        presentMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Show the config window
    @objc func showWindow() {
        presentMainWindow()
    }

    // Hide the window without quitting the app
    @objc func hideWindow() {
        hideMainWindow()
    }

    // Quit the app completely
    @MainActor @objc func quit() {
        
        coreEngine.terminateApplication()
        NSApp.terminate(nil)
    }

    private func presentMainWindow() {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func hideMainWindow() {
        window.orderOut(nil)
    }

    private func statusMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func configureLoginItem() {
        // Development builds must never create a second persistent login item.
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: UserDefaultsKeys.launchAtLogin) == nil {
            setLoginItem(enabled: true)
        } else {
            setLoginItem(enabled: defaults.bool(forKey: UserDefaultsKeys.launchAtLogin))
        }
    }

    private func terminateOtherApplicationInstances() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: identifier
        ) where application.processIdentifier != ownPID {
            application.terminate()
        }
    }

    private func restoreSystemLockScreenImages() {
        let displays = coreEngine.getDisplays()
        var restoredDisplays = Set<CGDirectDisplayID>()

        for display in displays {
            guard
                let path = display.videoPath,
                !path.isEmpty,
                FileManager.default.fileExists(atPath: path)
            else { continue }

            SystemWallpaperSynchronizer.shared.synchronize(
                sourceURL: URL(fileURLWithPath: path),
                displayIDs: [display.screen]
            )
            restoredDisplays.insert(display.screen)
        }

        guard
            restoredDisplays.isEmpty,
            let lastPath = UserDefaults.standard.string(forKey: "LastWallpaperPath"),
            FileManager.default.fileExists(atPath: lastPath)
        else { return }

        SystemWallpaperSynchronizer.shared.synchronize(
            sourceURL: URL(fileURLWithPath: lastPath),
            displayIDs: displays.map(\.screen)
        )
    }
}

func isLoginItemEnabled() -> Bool {
    let status = SMAppService.mainApp.status
    return status == .enabled || status == .requiresApproval
}

func setLoginItem(enabled: Bool) {
    let service = SMAppService.mainApp

    do {
        if enabled {
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }

        let registered = service.status == .enabled || service.status == .requiresApproval
        UserDefaults.standard.set(registered, forKey: UserDefaultsKeys.launchAtLogin)
        NSLog("Launch-at-login status: %ld", service.status.rawValue)
    } catch {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.launchAtLogin)
        NSLog("Unable to update launch-at-login registration: %@", error.localizedDescription)
    }
}
