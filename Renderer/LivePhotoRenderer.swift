import Foundation

/// Resolves the still and paired video resources that make up an Apple Live Photo.
enum LivePhotoResourceResolver {
    static let stillExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg"]
    static let packageExtensions: Set<String> = ["livp", "livephoto"]
    static let videoExtensions: Set<String> = ["mov", "mp4"]

    static func isLivePhotoSource(_ sourceURL: URL) -> Bool {
        resolveVideoURL(for: sourceURL) != nil
    }

    static func resolveVideoURL(for sourceURL: URL) -> URL? {
        if isDirectory(sourceURL), packageExtensions.contains(sourceURL.pathExtension.lowercased()) {
            return packageResources(in: sourceURL).first {
                videoExtensions.contains($0.pathExtension.lowercased())
            }
        }

        guard stillExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            return nil
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let directory = sourceURL.deletingLastPathComponent()
        guard let siblings = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return siblings.first { candidate in
            videoExtensions.contains(candidate.pathExtension.lowercased())
                && candidate.deletingPathExtension().lastPathComponent
                    .caseInsensitiveCompare(baseName) == .orderedSame
        }
    }

    static func resolveStillImageURL(for sourceURL: URL) -> URL? {
        if stillExtensions.contains(sourceURL.pathExtension.lowercased()) {
            return sourceURL
        }
        guard isDirectory(sourceURL) else { return nil }
        return packageResources(in: sourceURL).first {
            stillExtensions.contains($0.pathExtension.lowercased())
        }
    }

    private static func packageResources(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { !isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

/// Live Photos reuse the proven AVFoundation daemon after resolving their paired video.
@MainActor
final class LivePhotoRenderer: WallpaperRenderer {
    let identifier = "photo.live"
    let supportedFileExtensions =
        LivePhotoResourceResolver.stillExtensions.union(LivePhotoResourceResolver.packageExtensions)

    private let legacyEngine: WallpaperEngine

    init(legacyEngine: WallpaperEngine) {
        self.legacyEngine = legacyEngine
    }

    func canRender(_ sourceURL: URL) -> Bool {
        LivePhotoResourceResolver.isLivePhotoSource(sourceURL)
    }

    func render(_ request: RendererRequest) throws -> WallpaperSession {
        guard let videoURL = LivePhotoResourceResolver.resolveVideoURL(for: request.sourceURL) else {
            throw RendererError.missingLivePhotoVideo(request.sourceURL)
        }

        legacyEngine.startWallpaper(
            withPath: videoURL.path,
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
        legacyEngine.killAllDaemons()
    }

    func stopAll() {
        legacyEngine.killAllDaemons()
    }
}
