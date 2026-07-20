import CoreGraphics
import Foundation

struct RendererRequest: Sendable {
    let sourceURL: URL
    let displayIDs: [CGDirectDisplayID]
}

enum RendererError: LocalizedError {
    case unsupportedSource(URL)
    case rendererUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource(let url):
            return "No renderer supports \(url.lastPathComponent)."
        case .rendererUnavailable(let identifier):
            return "Renderer \(identifier) is unavailable."
        }
    }
}

/// Extension point for VideoRenderer, future MetalRenderer and AIRenderer.
@MainActor
protocol WallpaperRenderer: AnyObject {
    var identifier: String { get }
    var supportedFileExtensions: Set<String> { get }

    func canRender(_ sourceURL: URL) -> Bool
    func render(_ request: RendererRequest) throws -> WallpaperSession
    func stop(_ session: WallpaperSession)
    func stopAll()
}

extension WallpaperRenderer {
    func canRender(_ sourceURL: URL) -> Bool {
        supportedFileExtensions.contains(sourceURL.pathExtension.lowercased())
    }
}
