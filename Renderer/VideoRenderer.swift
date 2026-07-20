import AVFoundation
import Foundation

/// Compatibility renderer around the existing AVFoundation daemon pipeline.
/// Actual playback remains in `wallpaperdaemon/daemon.mm` in this phase.
@MainActor
final class VideoRenderer: WallpaperRenderer {
    let identifier = "video.avfoundation"
    let supportedFileExtensions: Set<String> = ["mp4", "mov"]

    private let legacyEngine: WallpaperEngine

    init(legacyEngine: WallpaperEngine) {
        self.legacyEngine = legacyEngine
    }

    func render(_ request: RendererRequest) throws -> WallpaperSession {
        guard FileManager.default.fileExists(atPath: request.sourceURL.path) else {
            throw RendererError.unsupportedSource(request.sourceURL)
        }

        legacyEngine.startWallpaper(
            withPath: request.sourceURL.path,
            onDisplays: request.displayIDs.map { NSNumber(value: $0) }
        )

        return WallpaperSession(
            sourceURL: request.sourceURL,
            displayIDs: request.displayIDs,
            rendererIdentifier: identifier,
            state: .running
        )
    }

    func stop(_ session: WallpaperSession) {
        // The legacy backend only supports global daemon termination.
        // Per-session stop will become precise when the XPC runtime replaces it.
        legacyEngine.killAllDaemons()
    }

    func stopAll() {
        legacyEngine.killAllDaemons()
    }
}
