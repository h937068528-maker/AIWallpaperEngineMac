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
            self.rendererManager = manager
        }
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
        sessions.removeAll { existing in
            !Set(existing.displayIDs).isDisjoint(with: session.displayIDs)
        }
        sessions.append(session)
        return session
    }

    func stopAll() {
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
        sessions.removeAll()
        legacyEngine.terminateApplication()
    }
}
