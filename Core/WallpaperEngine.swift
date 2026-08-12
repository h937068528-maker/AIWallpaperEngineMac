import AppKit
import Combine
import CoreGraphics
import Foundation

/// Public facade for the new engine architecture.
///
/// The Objective-C++ `WallpaperEngine` remains the compatibility backend during
/// migration. New callers depend on this facade and renderer abstractions instead.
@MainActor
final class AIWallpaperEngine: ObservableObject {
    static let shared = AIWallpaperEngine()

    @Published private(set) var sessions: [WallpaperSession] = []

    let legacyEngine: WallpaperEngine
    let rendererManager: RendererManager
    private var hasTerminated = false
    private var desiredSessions: [DesiredWallpaperSession] = []
    private var screenChangeCancellable: AnyCancellable?
    private var displayRecoveryTask: Task<Void, Never>?

    init(
        legacyEngine: WallpaperEngine = sharedEngine ?? WallpaperEngine.shared(),
        rendererManager: RendererManager? = nil
    ) {
        self.legacyEngine = legacyEngine

        if let rendererManager {
            self.rendererManager = rendererManager
        } else {
            let manager = RendererManager()
            manager.register(VideoRenderer(legacyEngine: legacyEngine))
            manager.register(LivePhotoRenderer(legacyEngine: legacyEngine))
            manager.register(ImageRenderer())
            manager.register(GIFRenderer())
            manager.register(WebRenderer())
            manager.register(ParticleRenderer())
            manager.register(MetalRenderer())
            self.rendererManager = manager
        }

        screenChangeCancellable = NotificationCenter.default
            .publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleDisplayRecovery()
            }
    }

    @discardableResult
    func startMetalWallpaper(
        preset: MetalShaderPreset,
        onDisplays displayIDs: [NSNumber]
    ) throws -> WallpaperSession {
        let request = RendererRequest(
            sourceURL: preset.sourceURL,
            displayIDs: displayIDs.map(\.uint32Value)
        )
        let session = try rendererManager.start(request)
        SystemWallpaperSynchronizer.shared.synchronize(
            sourceURL: request.sourceURL,
            displayIDs: session.displayIDs
        )
        recordDesiredSession(
            session,
            requestedDisplayIDs: displayIDs.map(\.uint32Value)
        )
        return session
    }

    @discardableResult
    func startParticleWallpaper(onDisplays displayIDs: [NSNumber]) throws -> WallpaperSession {
        let request = RendererRequest(
            sourceURL: URL(string: "particle://ai-logo")!,
            displayIDs: displayIDs.map(\.uint32Value)
        )
        let session = try rendererManager.start(request)
        SystemWallpaperSynchronizer.shared.synchronize(
            sourceURL: request.sourceURL,
            displayIDs: session.displayIDs
        )
        recordDesiredSession(
            session,
            requestedDisplayIDs: displayIDs.map(\.uint32Value)
        )
        return session
    }

    @discardableResult
    func startWallpaper(withPath path: String, onDisplays displayIDs: [NSNumber]) throws
        -> WallpaperSession
    {
        let request = RendererRequest(
            sourceURL: URL(fileURLWithPath: path),
            displayIDs: displayIDs.map(\.uint32Value)
        )
        let session = try rendererManager.start(request)
        SystemWallpaperSynchronizer.shared.synchronize(
            sourceURL: request.sourceURL,
            displayIDs: session.displayIDs
        )
        recordDesiredSession(
            session,
            requestedDisplayIDs: displayIDs.map(\.uint32Value)
        )
        return session
    }

    @discardableResult
    func startWebWallpaper(with sourceURL: URL, onDisplays displayIDs: [NSNumber]) throws
        -> WallpaperSession
    {
        let request = RendererRequest(
            sourceURL: sourceURL,
            displayIDs: displayIDs.map(\.uint32Value)
        )
        let session = try rendererManager.start(request)
        SystemWallpaperSynchronizer.shared.synchronize(
            sourceURL: request.sourceURL,
            displayIDs: session.displayIDs
        )
        recordDesiredSession(
            session,
            requestedDisplayIDs: displayIDs.map(\.uint32Value)
        )
        return session
    }

    func stopAll() {
        displayRecoveryTask?.cancel()
        displayRecoveryTask = nil
        desiredSessions.removeAll()
        rendererManager.stopAll()
        sessions = sessions.map { session in
            var stopped = session
            stopped.state = .stopped
            return stopped
        }
    }

    // MARK: - Legacy compatibility facade

    func setupNotifications() {
        legacyEngine.setupNotifications()
    }

    func removeNotifications() {
        legacyEngine.removeNotifications()
    }

    func isFirstLaunch() -> Bool {
        legacyEngine.isFirstLaunch()
    }

    func selectFolder(_ path: String) {
        legacyEngine.selectFolder(path)
    }

    func checkFolderPath() {
        legacyEngine.checkFolderPath()
    }

    func getFolderPath() -> String {
        legacyEngine.getFolderPath()
    }

    func thumbnailCachePath() -> String {
        legacyEngine.thumbnailCachePath()
    }

    func getDisplays() -> [DisplayObjc] {
        legacyEngine.getDisplays() as? [DisplayObjc] ?? []
    }

    func generateThumbnails() {
        legacyEngine.generateThumbnails()
    }

    func generateThumbnails(
        forFolder folderPath: String,
        completion: @escaping @Sendable () -> Void
    ) {
        legacyEngine.generateThumbnails(forFolder: folderPath, withCompletion: completion)
    }

    func videoQualityBadge(for url: URL, completion: @escaping @Sendable (String?) -> Void) {
        legacyEngine.videoQualityBadge(for: url, completion: completion)
    }

    func clearCache() {
        legacyEngine.clearCache()
    }

    func resetUserData() {
        legacyEngine.resetUserData()
    }

    func generateStaticWallpapers(
        forFolder folderPath: String,
        completion: @escaping @Sendable () -> Void
    ) {
        legacyEngine.generateStaticWallpapers(forFolder: folderPath, withCompletion: completion)
    }

    func updateVolume(_ value: Double) {
        legacyEngine.updateVolume(value)
    }

    func updateScaleMode(_ mode: Int) {
        legacyEngine.updateScaleMode(mode)
    }

    var rotationType: RotationType {
        get { legacyEngine.rotationType }
        set { legacyEngine.rotationType = newValue }
    }

    var rotationDelay: Int32 {
        get { legacyEngine.rotationDelay }
        set { legacyEngine.rotationDelay = newValue }
    }

    var isRotationRunning: Bool {
        get { legacyEngine.isrotationrunning }
        set { legacyEngine.isrotationrunning = newValue }
    }

    func startWallpaperRotation() {
        legacyEngine.startWallpaperRotation()
    }

    func stopWallpaperRotation() {
        legacyEngine.stopWallpaperRotation()
    }

    func terminateApplication() {
        guard !hasTerminated else { return }
        hasTerminated = true
        displayRecoveryTask?.cancel()
        displayRecoveryTask = nil
        screenChangeCancellable?.cancel()
        screenChangeCancellable = nil
        desiredSessions.removeAll()
        sessions.removeAll()
        legacyEngine.terminateApplication()
    }

    // MARK: - Display hot-plug recovery

    private func recordDesiredSession(
        _ session: WallpaperSession,
        requestedDisplayIDs: [CGDirectDisplayID]
    ) {
        let followsAllDisplays = requestedDisplayIDs.isEmpty
        let targetIDs = followsAllDisplays
            ? session.displayIDs : requestedDisplayIDs
        let targetUUIDs = Set(targetIDs.compactMap(Self.displayUUID))

        if desiredSessions.contains(where: {
            $0.rendererIdentifier != session.rendererIdentifier
        }) {
            desiredSessions.removeAll()
            sessions.removeAll()
        }

        if followsAllDisplays {
            desiredSessions.removeAll()
            sessions.removeAll()
        } else {
            let connectedUUIDs = Set(
                Self.connectedDisplays().compactMap {
                    Self.displayUUID($0.id)
                }
            )
            desiredSessions = desiredSessions.compactMap { desired in
                var updated = desired
                if updated.followsAllDisplays {
                    updated.followsAllDisplays = false
                    updated.targetDisplayUUIDs = connectedUUIDs
                        .subtracting(targetUUIDs)
                } else {
                    updated.targetDisplayUUIDs.subtract(targetUUIDs)
                }
                return updated.targetDisplayUUIDs.isEmpty ? nil : updated
            }
            sessions.removeAll { existing in
                !Set(existing.displayIDs).isDisjoint(with: targetIDs)
            }
        }

        desiredSessions.append(
            DesiredWallpaperSession(
                sourceURL: session.sourceURL,
                rendererIdentifier: session.rendererIdentifier,
                targetDisplayUUIDs: targetUUIDs,
                followsAllDisplays: followsAllDisplays,
                createdAt: session.createdAt
            )
        )
        UserDefaults.standard.set(
            session.rendererIdentifier,
            forKey: "wallpaper.activeRendererIdentifier"
        )
        sessions.append(session)
    }

    private func scheduleDisplayRecovery() {
        guard !hasTerminated, !desiredSessions.isEmpty else { return }
        displayRecoveryTask?.cancel()
        displayRecoveryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(700))
                try Task.checkCancellation()
                self?.recoverAfterDisplayChange()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func recoverAfterDisplayChange() {
        let connected = Self.connectedDisplays()
        let displayIDByUUID = Dictionary(
            uniqueKeysWithValues: connected.compactMap { display in
                Self.displayUUID(display.id).map { ($0, display.id) }
            }
        )

        rendererManager.stopAll()
        var restoredSessions: [WallpaperSession] = []

        for desired in desiredSessions {
            let targetIDs: [CGDirectDisplayID]
            if desired.followsAllDisplays {
                targetIDs = connected.map(\.id)
            } else {
                targetIDs = desired.targetDisplayUUIDs.compactMap {
                    displayIDByUUID[$0]
                }
            }

            guard !targetIDs.isEmpty else {
                restoredSessions.append(
                    WallpaperSession(
                        sourceURL: desired.sourceURL,
                        displayIDs: [],
                        rendererIdentifier: desired.rendererIdentifier,
                        createdAt: desired.createdAt,
                        state: .paused
                    )
                )
                continue
            }

            do {
                let session = try rendererManager.start(
                    RendererRequest(
                        sourceURL: desired.sourceURL,
                        displayIDs: targetIDs
                    )
                )
                restoredSessions.append(session)
                SystemWallpaperSynchronizer.shared.synchronize(
                    sourceURL: desired.sourceURL,
                    displayIDs: targetIDs
                )
            } catch {
                restoredSessions.append(
                    WallpaperSession(
                        sourceURL: desired.sourceURL,
                        displayIDs: targetIDs,
                        rendererIdentifier: desired.rendererIdentifier,
                        createdAt: desired.createdAt,
                        state: .failed(message: error.localizedDescription)
                    )
                )
            }
        }

        sessions = restoredSessions
    }

    private static func connectedDisplays() -> [
        (id: CGDirectDisplayID, screen: NSScreen)
    ] {
        NSScreen.screens.compactMap { screen in
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else { return nil }
            return (number.uint32Value, screen)
        }
    }

    private static func displayUUID(
        _ displayID: CGDirectDisplayID
    ) -> String? {
        guard
            let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID)
        else { return nil }
        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }
}

private struct DesiredWallpaperSession {
    let sourceURL: URL
    let rendererIdentifier: String
    var targetDisplayUUIDs: Set<String>
    var followsAllDisplays: Bool
    let createdAt: Date
}
