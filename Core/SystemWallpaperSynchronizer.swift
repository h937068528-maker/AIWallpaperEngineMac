import AppKit
import AVFoundation
import CoreGraphics
import Foundation

/// Keeps macOS' own desktop image aligned with the active engine session.
///
/// Custom desktop windows cannot be displayed by the secure lock screen.
/// The system therefore receives a still frame representing the active
/// wallpaper and uses it while the dynamic surface is unavailable.
@MainActor
final class SystemWallpaperSynchronizer {
    static let shared = SystemWallpaperSynchronizer()

    private let fileManager = FileManager.default
    private var generationTokens: [CGDirectDisplayID: UUID] = [:]
    private var currentImages: [CGDirectDisplayID: URL] = [:]
    private var screenLockObserver: NSObjectProtocol?

    private init() {
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SystemWallpaperSynchronizer.shared.reapplyCurrentImages()
            }
        }
    }

    func synchronize(sourceURL: URL, displayIDs: [CGDirectDisplayID]) {
        let targets = targetScreens(displayIDs: displayIDs)
        guard !targets.isEmpty else { return }

        let token = UUID()
        targets.forEach { generationTokens[$0.displayID] = token }

        if let stillURL = stillImageURL(for: sourceURL) {
            apply(stillURL, to: targets, token: token)
            return
        }

        if ["mp4", "mov"].contains(sourceURL.pathExtension.lowercased()) {
            generateVideoFrame(sourceURL: sourceURL, targets: targets, token: token)
            return
        }

        if sourceURL.pathExtension.lowercased() == "gif" {
            generateImageFrame(sourceURL: sourceURL, targets: targets, token: token)
            return
        }

        if sourceURL.scheme == "shader" || sourceURL.scheme == "particle"
            || ["http", "https"].contains(sourceURL.scheme?.lowercased() ?? "")
            || ["html", "htm"].contains(sourceURL.pathExtension.lowercased())
        {
            generateProceduralPlaceholder(
                title: sourceURL.host ?? sourceURL.lastPathComponent,
                targets: targets,
                token: token
            )
        }
    }

    func reapplyCurrentImages() {
        var reappliedDisplayIDs: [CGDirectDisplayID] = []
        for target in targetScreens(displayIDs: Array(currentImages.keys)) {
            guard let imageURL = currentImages[target.displayID] else { continue }
            if applySystemDesktopImage(imageURL, target: target) {
                reappliedDisplayIDs.append(target.displayID)
            }
        }
        if !reappliedDisplayIDs.isEmpty {
            scheduleLockScreenIdleSynchronization(displayIDs: reappliedDisplayIDs)
        }
    }

    private func stillImageURL(for sourceURL: URL) -> URL? {
        if
            ["jpg", "jpeg", "png", "heic", "heif"].contains(
                sourceURL.pathExtension.lowercased()
            ),
            fileManager.fileExists(atPath: sourceURL.path)
        {
            return sourceURL
        }
        return LivePhotoResourceResolver.resolveStillImageURL(for: sourceURL)
    }

    private func generateVideoFrame(
        sourceURL: URL,
        targets: [ScreenTarget],
        token: UUID
    ) {
        Task {
            do {
                let asset = AVURLAsset(url: sourceURL)
                let duration = try await asset.load(.duration)
                let seconds = max(CMTimeGetSeconds(duration), 0)
                let requestedTime = CMTime(
                    seconds: seconds.isFinite ? seconds / 2 : 0,
                    preferredTimescale: 600
                )
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = maximumPixelSize(for: targets)

                let image: CGImage
                if #available(macOS 15.0, *) {
                    image = try await generator.image(at: requestedTime).image
                } else {
                    image = try generator.copyCGImage(
                        at: requestedTime,
                        actualTime: nil
                    )
                }
                let cacheURL = try writePNG(
                    image,
                    sourceKey: sourceURL.standardizedFileURL.path
                )
                apply(cacheURL, to: targets, token: token)
            } catch {
                NSLog(
                    "Unable to synchronize lock-screen frame for %@: %@",
                    sourceURL.lastPathComponent,
                    error.localizedDescription
                )
            }
        }
    }

    private func generateImageFrame(
        sourceURL: URL,
        targets: [ScreenTarget],
        token: UUID
    ) {
        guard
            let image = NSImage(contentsOf: sourceURL),
            let representation = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
            let data = representation.representation(using: .png, properties: [:])
        else { return }

        do {
            let cacheURL = try cacheURL(sourceKey: sourceURL.standardizedFileURL.path)
            try data.write(to: cacheURL, options: .atomic)
            apply(cacheURL, to: targets, token: token)
        } catch {
            NSLog("Unable to save GIF lock-screen frame: %@", error.localizedDescription)
        }
    }

    private func generateProceduralPlaceholder(
        title: String,
        targets: [ScreenTarget],
        token: UUID
    ) {
        let size = NSSize(width: 1920, height: 1080)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.01, green: 0.03, blue: 0.08, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.25, blue: 0.40, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.05, blue: 0.24, alpha: 1),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -25)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 86, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.45, green: 0.95, blue: 1, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        "AI Wallpaper · \(title)".draw(
            in: NSRect(x: 100, y: 470, width: 1720, height: 140),
            withAttributes: attributes
        )
        image.unlockFocus()

        guard
            let representation = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
            let data = representation.representation(using: .png, properties: [:])
        else { return }

        do {
            let cacheURL = try cacheURL(sourceKey: "procedural-\(title)")
            try data.write(to: cacheURL, options: .atomic)
            apply(cacheURL, to: targets, token: token)
        } catch {
            NSLog("Unable to save procedural lock-screen image: %@", error.localizedDescription)
        }
    }

    private func apply(_ imageURL: URL, to targets: [ScreenTarget], token: UUID) {
        var synchronizedDisplayIDs: [CGDirectDisplayID] = []
        for target in targets where generationTokens[target.displayID] == token {
            guard fileManager.fileExists(atPath: imageURL.path) else { continue }
            if applySystemDesktopImage(imageURL, target: target) {
                currentImages[target.displayID] = imageURL
                synchronizedDisplayIDs.append(target.displayID)
            }
        }
        if !synchronizedDisplayIDs.isEmpty {
            scheduleLockScreenIdleSynchronization(displayIDs: synchronizedDisplayIDs)
        }
    }

    @discardableResult
    private func applySystemDesktopImage(_ imageURL: URL, target: ScreenTarget) -> Bool {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
            .fillColor: NSColor.black,
        ]
        do {
            try NSWorkspace.shared.setDesktopImageURL(
                imageURL,
                for: target.screen,
                options: options
            )
            return true
        } catch {
            NSLog(
                "Unable to set system wallpaper for display %u: %@",
                target.displayID,
                error.localizedDescription
            )
            return false
        }
    }

    private func targetScreens(displayIDs: [CGDirectDisplayID]) -> [ScreenTarget] {
        let requested = Set(displayIDs)
        return NSScreen.screens.compactMap { screen in
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else { return nil }
            let displayID = number.uint32Value
            guard requested.isEmpty || requested.contains(displayID) else { return nil }
            return ScreenTarget(displayID: displayID, screen: screen)
        }
    }

    /// On current macOS releases the secure lock flow first shows Desktop and
    /// then hands rendering to the independently configured Idle wallpaper.
    /// NSWorkspace only updates Desktop, so preserve the system store and align
    /// the matching Idle records with the image choice that macOS just wrote.
    ///
    /// There is no public API for changing the user's selected screen saver.
    /// Keep this compatibility code narrowly scoped, atomic, and backed up.
    private func scheduleLockScreenIdleSynchronization(
        displayIDs: [CGDirectDisplayID]
    ) {
        synchronizeLockScreenIdleConfiguration(displayIDs: displayIDs)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            synchronizeLockScreenIdleConfiguration(displayIDs: displayIDs)
        }
    }

    private func synchronizeLockScreenIdleConfiguration(
        displayIDs: [CGDirectDisplayID]
    ) {
        let displayUUIDs = Set(displayIDs.compactMap(displayUUIDString))
        guard !displayUUIDs.isEmpty else { return }

        let storeURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper")
            .appendingPathComponent("Store/Index.plist")
        guard let originalData = try? Data(contentsOf: storeURL) else { return }

        do {
            try saveWallpaperStoreBackupIfNeeded(originalData)
            guard
                var root = try PropertyListSerialization.propertyList(
                    from: originalData,
                    options: 0,
                    format: nil
                ) as? [String: Any]
            else { return }

            let changed = alignIdleRecords(
                in: &root,
                displayUUIDs: displayUUIDs
            )
            guard changed else { return }

            let updatedData = try PropertyListSerialization.data(
                fromPropertyList: root,
                format: .binary,
                options: 0
            )
            try updatedData.write(
                to: storeURL,
                options: Data.WritingOptions.atomic
            )
        } catch {
            NSLog(
                "Unable to align lock-screen Idle wallpaper: %@",
                error.localizedDescription
            )
        }
    }

    private func alignIdleRecords(
        in root: inout [String: Any],
        displayUUIDs: Set<String>
    ) -> Bool {
        var changed = false
        var globalIdleContent: Any?

        if var displays = root["Displays"] as? [String: Any] {
            for displayUUID in displayUUIDs {
                guard var display = displays[displayUUID] as? [String: Any] else {
                    continue
                }
                if globalIdleContent == nil,
                   let desktop = display["Desktop"] as? [String: Any]
                {
                    globalIdleContent = desktop["Content"]
                }
                if alignIdleWithDesktop(in: &display) {
                    displays[displayUUID] = display
                    changed = true
                }
            }
            root["Displays"] = displays
        }

        // macOS 26 currently consults this global Idle record during the
        // secure-lock transition even when each display is marked individual.
        if let globalIdleContent,
           var allDisplays = root["AllSpacesAndDisplays"] as? [String: Any]
        {
            var idle = allDisplays["Idle"] as? [String: Any] ?? [:]
            idle["Content"] = globalIdleContent
            idle["LastSet"] = Date()
            allDisplays["Idle"] = idle
            root["AllSpacesAndDisplays"] = allDisplays
            changed = true
        }

        if var spaces = root["Spaces"] as? [String: Any] {
            for (spaceID, rawSpace) in spaces {
                guard var space = rawSpace as? [String: Any] else { continue }
                var spaceChanged = false

                if var defaultRecord = space["Default"] as? [String: Any],
                   alignIdleWithDesktop(in: &defaultRecord)
                {
                    space["Default"] = defaultRecord
                    spaceChanged = true
                }

                if var displays = space["Displays"] as? [String: Any] {
                    for displayUUID in displayUUIDs {
                        guard
                            var display = displays[displayUUID] as? [String: Any]
                        else { continue }
                        if alignIdleWithDesktop(in: &display) {
                            displays[displayUUID] = display
                            spaceChanged = true
                        }
                    }
                    space["Displays"] = displays
                }

                if spaceChanged {
                    spaces[spaceID] = space
                    changed = true
                }
            }
            root["Spaces"] = spaces
        }

        return changed
    }

    private func alignIdleWithDesktop(in record: inout [String: Any]) -> Bool {
        guard
            let desktop = record["Desktop"] as? [String: Any],
            let desktopContent = desktop["Content"]
        else { return false }

        var idle = record["Idle"] as? [String: Any] ?? [:]
        idle["Content"] = desktopContent
        idle["LastSet"] = Date()
        record["Idle"] = idle
        return true
    }

    private func displayUUIDString(
        displayID: CGDirectDisplayID
    ) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func saveWallpaperStoreBackupIfNeeded(_ data: Data) throws {
        let backupURL = try cacheDirectory()
            .appendingPathComponent("SystemWallpaperStore-Original.plist")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try data.write(to: backupURL, options: .atomic)
    }

    private func maximumPixelSize(for targets: [ScreenTarget]) -> CGSize {
        targets.reduce(CGSize(width: 1920, height: 1080)) { result, target in
            CGSize(
                width: max(result.width, target.screen.frame.width * target.screen.backingScaleFactor),
                height: max(result.height, target.screen.frame.height * target.screen.backingScaleFactor)
            )
        }
    }

    private func writePNG(_ image: CGImage, sourceKey: String) throws -> URL {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let destination = try cacheURL(sourceKey: sourceKey)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func cacheURL(sourceKey: String) throws -> URL {
        let baseURL = try cacheDirectory()
            .appendingPathComponent("SystemWallpapers", isDirectory: true)
        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        let digest = sourceKey.utf8.reduce(UInt64(1_469_598_103_934_665_603)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return baseURL.appendingPathComponent(String(digest, radix: 16))
            .appendingPathExtension("png")
    }

    private func cacheDirectory() throws -> URL {
        let baseURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("AIWallpaperEngineMac", isDirectory: true)
        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        return baseURL
    }
}

private struct ScreenTarget {
    let displayID: CGDirectDisplayID
    let screen: NSScreen
}
