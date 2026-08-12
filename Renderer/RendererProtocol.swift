import CoreGraphics
import Foundation

struct RendererRequest: Sendable {
    let sourceURL: URL
    let displayIDs: [CGDirectDisplayID]
}

enum MetalShaderPreset: String, CaseIterable, Identifiable, Sendable {
    case particles
    case water
    case interactive

    var id: String { rawValue }

    var sourceURL: URL {
        URL(string: "shader://\(rawValue)")!
    }

    init?(sourceURL: URL) {
        guard sourceURL.scheme == "shader" else { return nil }
        self.init(rawValue: sourceURL.host ?? sourceURL.lastPathComponent)
    }
}

enum RendererError: LocalizedError {
    case unsupportedSource(URL)
    case rendererUnavailable(String)
    case metalUnavailable
    case shaderCompilationFailed(String)
    case invalidAnimatedImage(URL)
    case missingLivePhotoVideo(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource(let url):
            return "No renderer supports \(url.lastPathComponent)."
        case .rendererUnavailable(let identifier):
            return "Renderer \(identifier) is unavailable."
        case .metalUnavailable:
            return "Metal is unavailable on this Mac."
        case .shaderCompilationFailed(let message):
            return "Metal shader compilation failed: \(message)"
        case .invalidAnimatedImage(let url):
            return "Unable to decode animated image \(url.lastPathComponent)."
        case .missingLivePhotoVideo(let url):
            return "Live Photo \(url.lastPathComponent) is missing its paired MOV file."
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
