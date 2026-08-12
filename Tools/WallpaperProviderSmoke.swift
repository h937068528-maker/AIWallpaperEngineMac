import Foundation

@main
@MainActor
struct WallpaperProviderSmoke {
    static func main() async throws {
        let videoItems = try await VideoCatalogProvider().fetchWallpapers()
        guard !videoItems.isEmpty else { throw MarketplaceError.invalidCatalog }
        print("VideoCatalogProvider: \(videoItems.count)")

        let bingItems = try await BingWallpaperProvider().fetchWallpapers()
        guard
            !bingItems.isEmpty,
            bingItems.allSatisfy({ ["jpg", "jpeg", "png"].contains($0.format.lowercased()) })
        else {
            throw MarketplaceError.invalidCatalog
        }
        print("BingWallpaperProvider: \(bingItems.count)")

        let repositoryItems = try await UserRepositoryProvider(
            owner: "mylinuxforwork",
            repository: "wallpaper"
        ).fetchWallpapers()
        guard !repositoryItems.isEmpty else { throw MarketplaceError.invalidCatalog }
        print("UserRepositoryProvider: \(repositoryItems.count)")

        let localItems = try await LocalFolderProvider(
            folderURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).fetchWallpapers()
        print("LocalFolderProvider: \(localItems.count)")
    }
}
