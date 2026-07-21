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

@main
struct LiveWallpaperApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
            Settings { EmptyView() }
    }
        
}


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    
    let engine = sharedEngine
    @MainActor private lazy var coreEngine = AIWallpaperEngine.shared

    private var applicationDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "LiveWallpaper"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        
        NSApp.setActivationPolicy(.accessory)

        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: "Live Wallpaper")
        }

        
        let menu = NSMenu()
        menu.addItem(statusMenuItem(title: L.showWindow, action: #selector(showWindow), keyEquivalent: "s"))
        menu.addItem(statusMenuItem(title: L.hideWindow, action: #selector(hideWindow), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(statusMenuItem(title: L.quit, action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // Create main window with ContentView
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView,.borderless],
            backing: .buffered,
            defer: false
        )
        //hide titlebar
        //window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unified
        
        window.center()
        window.contentView = NSHostingView(rootView: ContentView())
        window.title = applicationDisplayName
        window.isReleasedWhenClosed = false
        presentMainWindow()
        
        setLoginItem(enabled: true)
        

        
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
        NSApp.activate()
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
}

func isLoginItemEnabled() -> Bool {
    let status = SMAppService.mainApp.status
    return status == .enabled || status == .requiresApproval
}

func setLoginItem(enabled: Bool) {
    let service = SMAppService.mainApp

    do {
        if enabled {
            if service.status == .notRegistered {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }

        let registered = service.status == .enabled || service.status == .requiresApproval
        UserDefaults.standard.set(registered, forKey: UserDefaultsKeys.launchAtLogin)
    } catch {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.launchAtLogin)
        NSLog("Unable to update launch-at-login registration: %@", error.localizedDescription)
    }
}
