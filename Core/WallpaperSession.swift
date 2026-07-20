import CoreGraphics
import Foundation

/// A renderer-independent description of one wallpaper playback request.
struct WallpaperSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let displayIDs: [CGDirectDisplayID]
    let rendererIdentifier: String
    let createdAt: Date
    var state: WallpaperState

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        displayIDs: [CGDirectDisplayID],
        rendererIdentifier: String,
        createdAt: Date = Date(),
        state: WallpaperState = .preparing
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayIDs = displayIDs
        self.rendererIdentifier = rendererIdentifier
        self.createdAt = createdAt
        self.state = state
    }
}
