import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class WallpaperViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var displays: [DisplayObjc] = []
    @Published var folderPath = ""
    @Published var scaleMode = "fill"
    @Published var randomOnStartup = false
    @Published var pauseOnAppFocus = true
    @Published var volume = 50.0
    @Published var vinttageBar = true

    private var currentReloadID = UUID()
    private let reloadIDLock = NSLock()
    private let defaults = UserDefaults.standard

    let engine: AIWallpaperEngine

    init(engine: AIWallpaperEngine = .shared) {
        self.engine = engine
        loadSettings()
        engine.setupNotifications()
    }

    func invalidate() {
        engine.removeNotifications()
    }

    func loadSettings() {
        folderPath = engine.getFolderPath()
        scaleMode = defaults.string(forKey: UserDefaultsKeys.scaleMode) ?? "fill"
        randomOnStartup = defaults.bool(forKey: UserDefaultsKeys.randomOnStartup)
        pauseOnAppFocus = defaults.bool(forKey: UserDefaultsKeys.pauseOnAppFocus)
        volume = Double(defaults.float(forKey: UserDefaultsKeys.volumePercentage))
        vinttageBar = defaults.bool(forKey: UserDefaultsKeys.vignetteBar)
    }

    func reloadContent() {
        engine.checkFolderPath()
        ThumbnailCache.shared.clearCache()

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else {
            return
        }

        let videoFiles = files.filter {
            let fileExtension = ($0 as NSString).pathExtension.lowercased()
            return fileExtension == "mp4" || fileExtension == "mov"
        }

        let reloadID = UUID()
        reloadIDLock.lock()
        currentReloadID = reloadID
        reloadIDLock.unlock()

        let sourceFolder = folderPath
        let thumbnailFolder = engine.thumbnailCachePath()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let newVideos = videoFiles.map { filename in
                let fullPath = (sourceFolder as NSString).appendingPathComponent(filename)
                let baseName = (filename as NSString).deletingPathExtension
                let thumbnailPath = (thumbnailFolder as NSString)
                    .appendingPathComponent("\(baseName).png")
                return VideoItem(
                    filename: filename,
                    path: fullPath,
                    thumbnailPath: thumbnailPath
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.reloadIDLock.lock()
                let isValid = reloadID == self.currentReloadID
                self.reloadIDLock.unlock()
                guard isValid else { return }

                self.videos = newVideos
                self.loadQualityBadges(for: newVideos)

                if newVideos.contains(where: { $0.loadThumbnail() == nil }) {
                    self.engine.generateThumbnails(forFolder: sourceFolder) {
                        DispatchQueue.main.async {
                            ThumbnailCache.shared.clearCache()
                        }
                    }
                }
            }
        }
    }

    func loadDisplays() {
        displays = engine.getDisplays()
    }

    func startWallpaper(video: VideoItem, displays: [UInt32]) {
        do {
            try engine.startWallpaper(
                withPath: video.path,
                onDisplays: displays.map { NSNumber(value: $0) }
            )
        } catch {
            NSLog("Unable to start wallpaper: \(error.localizedDescription)")
        }
    }

    func clearCache() {
        engine.clearCache()
        ThumbnailCache.shared.clearCache()
        reloadContent()
    }

    func resetUserData() {
        engine.resetUserData()
        loadSettings()
        reloadContent()
    }

    func optimizeVideos() {
        engine.generateStaticWallpapers(forFolder: folderPath) {}
    }

    private func loadQualityBadges(for videos: [VideoItem]) {
        for video in videos {
            engine.videoQualityBadge(for: URL(fileURLWithPath: video.path)) { [weak self] badge in
                DispatchQueue.main.async {
                    guard let self,
                        let index = self.videos.firstIndex(where: { $0.id == video.id })
                    else { return }
                    self.videos[index].quality = badge
                }
            }
        }
    }
}
