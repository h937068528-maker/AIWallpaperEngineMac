import Foundation

/// Lifecycle state shared by every wallpaper renderer.
enum WallpaperState: Equatable, Sendable {
    case idle
    case preparing
    case running
    case paused
    case stopped
    case failed(message: String)
}
