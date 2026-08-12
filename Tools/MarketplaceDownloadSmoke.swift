import Foundation

@main
@MainActor
struct MarketplaceDownloadSmoke {
    static func main() async throws {
        let wallpaper = MarketplaceWallpaper(
            id: "marketplace-download-smoke",
            filename: "AIWallpaperEngineMac-marketplace-smoke.mp4",
            category: "desktop",
            path: "/wallpaper/video/desktop/IP形象/%E6%B0%B4%E8%B1%9A%E5%99%9C%E5%99%9C_%E8%81%9A%E5%85%89%E5%B8%85%E8%88%9E.mp4",
            thumbnailPath: "",
            previewPath: nil,
            size: 1_498_877,
            format: "MP4",
            createdAt: "",
            displayTitle: "Marketplace Download Smoke Test",
            description: nil,
            tags: nil,
            subcategory: nil,
            usage: "desktop",
            topic: nil,
            duration: nil,
            resolution: nil
        )
        let destinationFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIWallpaperEngineMac-MarketplaceSmoke", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadedURL = try await WallpaperDownloadManager.shared.download(
            wallpaper,
            folderPath: destinationFolder.path
        )
        let values = try downloadedURL.resourceValues(forKeys: [.fileSizeKey])
        guard values.fileSize == Int(wallpaper.size) else {
            throw MarketplaceError.invalidResponse
        }
        print("Marketplace download smoke test passed: \(downloadedURL.path)")
        print("Downloaded bytes: \(values.fileSize ?? 0)")

        let bingWallpaper = try await BingWallpaperProvider().fetchWallpapers().first
        guard let bingWallpaper else { throw MarketplaceError.invalidCatalog }
        let bingURL = try await WallpaperDownloadManager.shared.download(
            bingWallpaper,
            folderPath: destinationFolder.path
        )
        let bingSize = try bingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bingSize > 0 else { throw MarketplaceError.invalidResponse }
        print("Bing image download passed: \(bingURL.path)")
        print("Downloaded bytes: \(bingSize)")
    }
}
