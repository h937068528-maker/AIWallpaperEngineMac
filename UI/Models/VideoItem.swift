import AppKit
import Combine
import Foundation

enum WallpaperMediaKind: String, Sendable {
    case video
    case image
    case gif
    case livePhoto
}

struct VideoItem: Identifiable {
    let id = UUID()
    let filename: String
    let path: String
    let thumbnailPath: String
    let kind: WallpaperMediaKind
    let thumbnailSourcePath: String?
    var quality: String?

    var formatLabel: String {
        switch kind {
        case .video:
            return (filename as NSString).pathExtension.uppercased()
        case .image:
            return (filename as NSString).pathExtension.uppercased()
        case .gif:
            return "GIF"
        case .livePhoto:
            return "LIVE PHOTO"
        }
    }

    var qualitySourceURL: URL? {
        switch kind {
        case .video:
            return URL(fileURLWithPath: path)
        case .image:
            return nil
        case .livePhoto:
            return LivePhotoResourceResolver.resolveVideoURL(
                for: URL(fileURLWithPath: path)
            )
        case .gif:
            return nil
        }
    }

    func loadThumbnail() -> NSImage? {
        if let thumbnailSourcePath,
            let image = NSImage(contentsOfFile: thumbnailSourcePath)
        {
            return image
        }
        return ThumbnailCache.shared.image(for: thumbnailPath)
    }
}

@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    @Published var lastUpdate = Date()

    private init() {
        cache.countLimit = 100

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailSaved(_:)),
            name: NSNotification.Name("ThumbnailSaved"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailsGenerated(_:)),
            name: NSNotification.Name("ThumbnailsGenerated"),
            object: nil
        )
    }

    @objc private func thumbnailSaved(_ notification: Notification) {
        if let path = notification.userInfo?["path"] as? String {
            cache.removeObject(forKey: path as NSString)
        }
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    @objc private func thumbnailsGenerated(_ notification: Notification) {
        cache.removeAllObjects()
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    func image(for path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: path),
            let image = NSImage(contentsOfFile: path)
        else {
            return nil
        }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    func clearCache() {
        cache.removeAllObjects()
        lastUpdate = Date()
    }
}
