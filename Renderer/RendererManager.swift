import Foundation

/// Selects renderers without exposing their implementation to Core or UI.
@MainActor
final class RendererManager {
    private var renderers: [String: any WallpaperRenderer] = [:]

    func register(_ renderer: any WallpaperRenderer) {
        renderers[renderer.identifier] = renderer
    }

    func renderer(identifier: String) -> (any WallpaperRenderer)? {
        renderers[identifier]
    }

    func start(_ request: RendererRequest) throws -> WallpaperSession {
        guard let renderer = renderers.values.first(where: { $0.canRender(request.sourceURL) }) else {
            throw RendererError.unsupportedSource(request.sourceURL)
        }
        return try renderer.render(request)
    }

    func stop(_ session: WallpaperSession) {
        renderers[session.rendererIdentifier]?.stop(session)
    }

    func stopAll() {
        renderers.values.forEach { $0.stopAll() }
    }
}
