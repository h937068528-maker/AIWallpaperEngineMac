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

        // A video daemon and an in-process Metal surface must never compete for
        // the desktop layer. Sessions within the same renderer remain supported.
        renderers.values
            .filter { $0.identifier != renderer.identifier }
            .forEach { $0.stopAll() }

        return try renderer.render(request)
    }

    func stop(_ session: WallpaperSession) {
        renderers[session.rendererIdentifier]?.stop(session)
    }

    func stopAll() {
        renderers.values.forEach { $0.stopAll() }
    }
}
