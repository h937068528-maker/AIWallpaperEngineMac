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
    @Published private(set) var activeShaderPreset: MetalShaderPreset?
    @Published private(set) var isParticleDemoActive = false
    @Published private(set) var rendererErrorMessage: String?

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

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        guard let sourceURLs = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            videos = []
            return
        }

        let thumbnailFolder = engine.thumbnailCachePath()
        let livePhotoSources = sourceURLs.filter {
            LivePhotoResourceResolver.isLivePhotoSource($0)
        }
        let pairedVideoPaths = Set(
            livePhotoSources.compactMap {
                LivePhotoResourceResolver.resolveVideoURL(for: $0)?.standardizedFileURL.path
            }
        )

        let newMedia = sourceURLs.compactMap { sourceURL -> VideoItem? in
            let fileExtension = sourceURL.pathExtension.lowercased()
            let kind: WallpaperMediaKind
            let thumbnailSourcePath: String?

            if livePhotoSources.contains(sourceURL) {
                kind = .livePhoto
                thumbnailSourcePath = LivePhotoResourceResolver
                    .resolveStillImageURL(for: sourceURL)?.path
            } else if ["jpg", "jpeg", "png"].contains(fileExtension) {
                kind = .image
                thumbnailSourcePath = sourceURL.path
            } else if fileExtension == "gif" {
                kind = .gif
                thumbnailSourcePath = sourceURL.path
            } else if ["mp4", "mov"].contains(fileExtension),
                !pairedVideoPaths.contains(sourceURL.standardizedFileURL.path)
            {
                kind = .video
                thumbnailSourcePath = nil
            } else {
                return nil
            }

            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let thumbnailPath = (thumbnailFolder as NSString)
                .appendingPathComponent("\(baseName).png")
            return VideoItem(
                filename: sourceURL.lastPathComponent,
                path: sourceURL.path,
                thumbnailPath: thumbnailPath,
                kind: kind,
                thumbnailSourcePath: thumbnailSourcePath
            )
        }
        .sorted {
            $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        }

        videos = newMedia
        loadQualityBadges(for: newMedia)

        if newMedia.contains(where: { $0.kind == .video && $0.loadThumbnail() == nil }) {
            engine.generateThumbnails(forFolder: folderPath) {
                DispatchQueue.main.async {
                    ThumbnailCache.shared.clearCache()
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
            activeShaderPreset = nil
            isParticleDemoActive = false
            rendererErrorMessage = nil
        } catch {
            rendererErrorMessage = error.localizedDescription
            NSLog("Unable to start wallpaper: \(error.localizedDescription)")
        }
    }

    func startMetalEffect(_ preset: MetalShaderPreset, displays: [UInt32]) {
        do {
            try engine.startMetalWallpaper(
                preset: preset,
                onDisplays: displays.map { NSNumber(value: $0) }
            )
            activeShaderPreset = preset
            isParticleDemoActive = false
            rendererErrorMessage = nil
        } catch {
            rendererErrorMessage = error.localizedDescription
            NSLog("Unable to start Metal wallpaper: \(error.localizedDescription)")
        }
    }

    func startParticleDemo(displays: [UInt32]) {
        do {
            try engine.startParticleWallpaper(
                onDisplays: displays.map { NSNumber(value: $0) }
            )
            activeShaderPreset = nil
            isParticleDemoActive = true
            rendererErrorMessage = nil
        } catch {
            rendererErrorMessage = error.localizedDescription
            NSLog("Unable to start particle wallpaper: \(error.localizedDescription)")
        }
    }

    func startWebWallpaper(sourceURL: URL, displays: [UInt32]) {
        do {
            try engine.startWebWallpaper(
                with: sourceURL,
                onDisplays: displays.map { NSNumber(value: $0) }
            )
            activeShaderPreset = nil
            isParticleDemoActive = false
            rendererErrorMessage = nil
        } catch {
            rendererErrorMessage = error.localizedDescription
            NSLog("Unable to start web wallpaper: \(error.localizedDescription)")
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
            guard let qualitySourceURL = video.qualitySourceURL else { continue }
            engine.videoQualityBadge(for: qualitySourceURL) { [weak self] badge in
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
