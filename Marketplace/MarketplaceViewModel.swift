import Combine
import Foundation

@MainActor
final class MarketplaceViewModel: ObservableObject {
    @Published private(set) var wallpapers: [MarketplaceWallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedCategory = "all"
    @Published var selectedProviderID: String

    let downloadManager: WallpaperDownloadManager
    @Published private(set) var providers: [any WallpaperCatalogProvider]
    private let defaults: UserDefaults

    init(
        providers: [any WallpaperCatalogProvider]? = nil,
        downloadManager: WallpaperDownloadManager = .shared,
        defaults: UserDefaults = .standard
    ) {
        let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
        let resolvedProviders = providers
            ?? WallpaperProviderRegistry(folderURL: defaultFolder, defaults: defaults).providers
        self.providers = resolvedProviders
        selectedProviderID = resolvedProviders.first?.id ?? ""
        self.downloadManager = downloadManager
        self.defaults = defaults
    }

    var selectedProvider: (any WallpaperCatalogProvider)? {
        providers.first { $0.id == selectedProviderID }
    }

    var sourceDescription: String {
        selectedProvider?.sourceDescription ?? ""
    }

    var categories: [String] {
        ["all"] + Set(wallpapers.map(\.categoryTitle)).sorted()
    }

    var filteredWallpapers: [MarketplaceWallpaper] {
        wallpapers.filter { wallpaper in
            let categoryMatches =
                selectedCategory == "all" || wallpaper.categoryTitle == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard categoryMatches, !query.isEmpty else { return categoryMatches }
            let searchable = [
                wallpaper.title,
                wallpaper.filename,
                wallpaper.categoryTitle,
                wallpaper.tags?.joined(separator: " ") ?? "",
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    func load(folderPath: String? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            if
                let folderPath,
                let localProvider = selectedProvider as? LocalFolderProvider
            {
                localProvider.folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
            }
            guard let selectedProvider else {
                throw MarketplaceError.invalidCatalog
            }
            wallpapers = try await selectedProvider.fetchWallpapers()
            if selectedProvider is StaticImageProvider {
                wallpapers.compactMap(\.downloadURL).compactMap(\.host).forEach {
                    downloadManager.allowDownloadHost($0)
                }
            }
            selectedCategory = "all"
        } catch {
            wallpapers = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func download(_ wallpaper: MarketplaceWallpaper, folderPath: String) async -> URL? {
        errorMessage = nil
        do {
            return try await downloadManager.download(wallpaper, folderPath: folderPath)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func addGitHubProvider(owner: String, repository: String, branch: String) throws {
        let cleanOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRepository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOwner.isEmpty, !cleanRepository.isEmpty, !cleanBranch.isEmpty else {
            throw MarketplaceError.invalidCatalog
        }
        let provider = UserRepositoryProvider(
            owner: cleanOwner,
            repository: cleanRepository,
            branch: cleanBranch
        )
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        defaults.set(cleanOwner, forKey: "marketplace.githubOwner")
        defaults.set(cleanRepository, forKey: "marketplace.githubRepository")
        defaults.set(cleanBranch, forKey: "marketplace.githubBranch")
        selectedProviderID = provider.id
    }

    func addStaticManifestProvider(name: String, urlString: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https"
        else {
            throw MarketplaceError.untrustedURL
        }
        let provider = StaticImageProvider(
            displayName: cleanName.isEmpty ? "静态图片" : cleanName,
            manifestURL: url,
            sourceDescription: url.host ?? "Custom image catalog"
        )
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        defaults.set(url.absoluteString, forKey: "marketplace.staticManifestURL")
        selectedProviderID = provider.id
    }
}
