import Foundation

@MainActor
protocol WallpaperCatalogProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var sourceDescription: String { get }

    func fetchWallpapers() async throws -> [MarketplaceWallpaper]
}

@MainActor
final class VideoCatalogProvider: WallpaperCatalogProvider {
    let id = "video.catalog"
    let displayName = "动态壁纸"
    let sourceDescription = "IT-NuanxinPro Wallpaper Gallery"

    private let client: WallpaperCatalogClient

    init(client: WallpaperCatalogClient = .shared) {
        self.client = client
    }

    func fetchWallpapers() async throws -> [MarketplaceWallpaper] {
        try await client.fetchDesktopWallpapers()
    }
}

/// Provider for a user-controlled JSON manifest containing absolute image URLs.
@MainActor
final class StaticImageProvider: WallpaperCatalogProvider {
    let id: String
    let displayName: String
    let sourceDescription: String

    private let manifestURL: URL
    private let session: URLSession

    init(
        id: String = "image.manifest",
        displayName: String = "静态图片",
        manifestURL: URL,
        sourceDescription: String,
        session: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.manifestURL = manifestURL
        self.sourceDescription = sourceDescription
        self.session = session
    }

    func fetchWallpapers() async throws -> [MarketplaceWallpaper] {
        guard manifestURL.scheme == "https" else { throw MarketplaceError.untrustedURL }
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await session.data(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            data.count <= 10 * 1_024 * 1_024
        else {
            throw MarketplaceError.invalidResponse
        }
        let envelope = try JSONDecoder().decode(MarketplaceCatalogEnvelope.self, from: data)
        guard let wallpapers = envelope.wallpapers else {
            throw MarketplaceError.invalidCatalog
        }
        return wallpapers.filter {
            ["jpg", "jpeg", "png"].contains($0.format.lowercased())
        }
    }
}

@MainActor
final class BingWallpaperProvider: WallpaperCatalogProvider {
    let id = "image.bing"
    let displayName = "Bing 每日壁纸"
    let sourceDescription = "Microsoft Bing"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchWallpapers() async throws -> [MarketplaceWallpaper] {
        var components = URLComponents(string: "https://www.bing.com/HPImageArchive.aspx")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: "0"),
            URLQueryItem(name: "n", value: "8"),
            URLQueryItem(
                name: "mkt",
                value: Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
            ),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "AIWallpaperEngineMac/2.7 (macOS)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            data.count <= 2 * 1_024 * 1_024
        else {
            throw MarketplaceError.invalidResponse
        }

        let archive = try JSONDecoder().decode(BingArchive.self, from: data)
        return archive.images.map { image in
            let fullPath = "\(image.urlbase)_UHD.jpg"
            let previewPath = "\(image.urlbase)_1920x1080.jpg"
            return MarketplaceWallpaper(
                id: "bing-\(image.startdate)-\(image.hsh)",
                filename: "Bing-\(image.startdate).jpg",
                category: "Bing",
                path: Self.absoluteBingURLString(fullPath),
                thumbnailPath: Self.absoluteBingURLString(previewPath),
                previewPath: Self.absoluteBingURLString(previewPath),
                size: 0,
                format: "JPG",
                createdAt: image.startdate,
                displayTitle: image.title,
                description: image.copyright,
                tags: ["Bing", image.title],
                subcategory: "每日壁纸",
                usage: "desktop",
                topic: "每日壁纸",
                duration: nil,
                resolution: MarketplaceResolution(width: 3840, height: 2160, label: "UHD")
            )
        }
    }

    private static func absoluteBingURLString(_ path: String) -> String {
        URL(string: path, relativeTo: URL(string: "https://www.bing.com")!)!
            .absoluteURL.absoluteString
    }
}

/// Historical Bing catalog backed by the Apache-2.0 niumoo/bing-wallpaper
/// metadata archive. Images remain hosted by Microsoft Bing and are fetched
/// only when the user previews or downloads an item.
@MainActor
final class BingArchiveProvider: WallpaperCatalogProvider {
    let id = "image.bing.archive"
    let displayName = "Bing 历史壁纸"
    let sourceDescription = "niumoo/bing-wallpaper · Microsoft Bing 4K 历史归档"

    private static let catalogURL = URL(
        string:
            "https://raw.githubusercontent.com/niumoo/bing-wallpaper/main/docs/images.json"
    )!
    private static let allowedImageHosts: Set<String> = [
        "bing.com",
        "www.bing.com",
        "cn.bing.com",
    ]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchWallpapers() async throws -> [MarketplaceWallpaper] {
        var request = URLRequest(url: Self.catalogURL)
        request.timeoutInterval = 30
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "AIWallpaperEngineMac/2.7 (macOS)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            data.count <= 5 * 1_024 * 1_024
        else {
            throw MarketplaceError.invalidResponse
        }

        let records = try JSONDecoder().decode([BingArchiveRecord].self, from: data)
        let preferredRegion = Locale.current.identifier.lowercased().hasPrefix("zh")
            ? "zh-cn" : "en-us"
        let localizedRecords = records.filter {
            $0.region.lowercased() == preferredRegion
        }
        let selectedRecords = localizedRecords.isEmpty ? records : localizedRecords

        var seenImageIDs = Set<String>()
        return selectedRecords
            .sorted { $0.date > $1.date }
            .compactMap { record -> MarketplaceWallpaper? in
                guard
                    let sourceURL = URL(string: record.url),
                    sourceURL.scheme?.lowercased() == "https",
                    let host = sourceURL.host?.lowercased(),
                    Self.allowedImageHosts.contains(host),
                    let imageID = Self.imageID(from: sourceURL),
                    seenImageIDs.insert(imageID).inserted
                else {
                    return nil
                }

                let month = String(record.date.prefix(7))
                let title = Self.title(from: record.description)
                return MarketplaceWallpaper(
                    id: "bing-archive-\(record.region)-\(record.date)-\(imageID)",
                    filename: "Bing-\(record.date)-\(imageID).jpg",
                    category: "Bing 历史壁纸",
                    path: Self.sizedURLString(sourceURL, width: 3840, height: 2160),
                    thumbnailPath: Self.sizedURLString(sourceURL, width: 640, height: 360),
                    previewPath: Self.sizedURLString(sourceURL, width: 1920, height: 1080),
                    size: 0,
                    format: "JPG",
                    createdAt: record.date,
                    displayTitle: title,
                    description: record.description,
                    tags: ["Bing", record.region, month],
                    subcategory: "历史归档",
                    usage: "desktop",
                    topic: month,
                    duration: nil,
                    resolution: MarketplaceResolution(width: 3840, height: 2160, label: "UHD")
                )
            }
    }

    private static func imageID(from url: URL) -> String? {
        guard
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value
        else {
            return nil
        }
        let base = value
            .replacingOccurrences(of: "_UHD.jpg", with: "")
            .replacingOccurrences(of: ".jpg", with: "")
        let safe = base.filter {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
        return safe.isEmpty ? nil : safe
    }

    private static func sizedURLString(_ url: URL, width: Int, height: Int) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "pid", value: "hp"),
            URLQueryItem(name: "w", value: String(width)),
            URLQueryItem(name: "h", value: String(height)),
            URLQueryItem(name: "rs", value: "1"),
            URLQueryItem(name: "c", value: "4"),
        ]
        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func title(from description: String) -> String {
        let marker = description.range(of: " (©")
            ?? description.range(of: "（©")
        let title = marker.map { String(description[..<$0.lowerBound]) } ?? description
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bing Wallpaper" : trimmed
    }
}

@MainActor
final class UserRepositoryProvider: WallpaperCatalogProvider {
    let id: String
    let displayName: String
    let sourceDescription: String

    private let owner: String
    private let repository: String
    private let branch: String
    private let session: URLSession
    private let allowedExtensions: Set<String>
    private let filenamePrefix: String?
    private let defaultCategory: String

    init(
        owner: String,
        repository: String,
        branch: String = "main",
        displayName: String? = nil,
        sourceDescription: String? = nil,
        allowedExtensions: Set<String> = [
            "jpg", "jpeg", "png", "mp4", "mov", "gif",
        ],
        filenamePrefix: String? = nil,
        defaultCategory: String = "GitHub",
        session: URLSession = .shared
    ) {
        self.owner = owner
        self.repository = repository
        self.branch = branch
        self.session = session
        self.allowedExtensions = allowedExtensions
        self.filenamePrefix = filenamePrefix
        self.defaultCategory = defaultCategory
        id = "github.\(owner).\(repository)"
        self.displayName = displayName ?? repository
        self.sourceDescription =
            sourceDescription ?? "GitHub: \(owner)/\(repository)"
    }

    func fetchWallpapers() async throws -> [MarketplaceWallpaper] {
        let allowedComponent = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard
            let safeOwner = owner.addingPercentEncoding(withAllowedCharacters: allowedComponent),
            let safeRepository = repository.addingPercentEncoding(withAllowedCharacters: allowedComponent),
            let safeBranch = branch.addingPercentEncoding(withAllowedCharacters: allowedComponent),
            let url = URL(
                string: "https://api.github.com/repos/\(safeOwner)/\(safeRepository)/git/trees/\(safeBranch)?recursive=1"
            )
        else {
            throw MarketplaceError.untrustedURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            data.count <= 10 * 1_024 * 1_024
        else {
            throw MarketplaceError.invalidResponse
        }

        let tree = try JSONDecoder().decode(GitHubTree.self, from: data)
        return tree.tree.compactMap { entry in
            guard
                entry.type == "blob",
                let fileExtension = entry.path.split(separator: ".").last?.lowercased(),
                allowedExtensions.contains(String(fileExtension))
            else { return nil }
            let encodedPath = entry.path.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? entry.path
            let rawURL = "https://raw.githubusercontent.com/\(safeOwner)/\(safeRepository)/\(safeBranch)/\(encodedPath)"
            let originalFilename = URL(fileURLWithPath: entry.path).lastPathComponent
            let filename = filenamePrefix.map { "\($0)\(originalFilename)" }
                ?? originalFilename
            let directory = URL(fileURLWithPath: entry.path)
                .deletingLastPathComponent().lastPathComponent
            return MarketplaceWallpaper(
                id: "github-\(entry.sha)",
                filename: filename,
                category: directory.isEmpty ? defaultCategory : directory,
                path: rawURL,
                thumbnailPath: ["jpg", "jpeg", "png"].contains(String(fileExtension)) ? rawURL : "",
                previewPath: ["jpg", "jpeg", "png"].contains(String(fileExtension)) ? rawURL : nil,
                size: Int64(entry.size ?? 0),
                format: String(fileExtension).uppercased(),
                createdAt: "",
                displayTitle: URL(fileURLWithPath: originalFilename)
                    .deletingPathExtension().lastPathComponent,
                description: sourceDescription,
                tags: [owner, repository, defaultCategory],
                subcategory: nil,
                usage: "desktop",
                topic: directory.isEmpty ? defaultCategory : directory,
                duration: nil,
                resolution: nil
            )
        }
    }
}

@MainActor
final class LocalFolderProvider: WallpaperCatalogProvider {
    let id = "local.folder"
    let displayName = "本地文件夹"
    let sourceDescription = "Local Mac"

    var folderURL: URL

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    func fetchWallpapers() async throws -> [MarketplaceWallpaper] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            let fileExtension = url.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "gif", "mp4", "mov"].contains(fileExtension) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return MarketplaceWallpaper(
                id: "local-\(url.standardizedFileURL.path)",
                filename: url.lastPathComponent,
                category: "本地",
                path: url.absoluteString,
                thumbnailPath: ["jpg", "jpeg", "png", "gif"].contains(fileExtension)
                    ? url.absoluteString : "",
                previewPath: ["jpg", "jpeg", "png", "gif"].contains(fileExtension)
                    ? url.absoluteString : nil,
                size: Int64(values?.fileSize ?? 0),
                format: fileExtension.uppercased(),
                createdAt: ISO8601DateFormatter().string(
                    from: values?.contentModificationDate ?? .distantPast
                ),
                displayTitle: nil,
                description: nil,
                tags: nil,
                subcategory: nil,
                usage: "desktop",
                topic: nil,
                duration: nil,
                resolution: nil
            )
        }
        .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }
}

private struct BingArchive: Decodable {
    let images: [BingImage]
}

private struct BingImage: Decodable {
    let startdate: String
    let urlbase: String
    let title: String
    let copyright: String
    let hsh: String
}

private struct BingArchiveRecord: Decodable {
    let date: String
    let region: String
    let url: String
    let description: String

    private enum CodingKeys: String, CodingKey {
        case date
        case region
        case url
        case description = "desc"
    }
}

private struct GitHubTree: Decodable {
    let tree: [GitHubTreeEntry]
}

private struct GitHubTreeEntry: Decodable {
    let path: String
    let type: String
    let sha: String
    let size: Int?
}

@MainActor
final class WallpaperProviderRegistry {
    private(set) var providers: [any WallpaperCatalogProvider]

    init(folderURL: URL, defaults: UserDefaults = .standard) {
        var configuredProviders: [any WallpaperCatalogProvider] = [
            VideoCatalogProvider(),
            BingWallpaperProvider(),
            BingArchiveProvider(),
            UserRepositoryProvider(
                owner: "mylinuxforwork",
                repository: "wallpaper",
                displayName: "ML4W 授权静态壁纸",
                sourceDescription:
                    "mylinuxforwork/wallpaper · 已获商业使用与第三方素材授权",
                allowedExtensions: ["jpg", "jpeg", "png"],
                filenamePrefix: "ML4W-",
                defaultCategory: "ML4W 静态壁纸"
            ),
            LocalFolderProvider(folderURL: folderURL),
        ]

        if
            let manifest = defaults.string(forKey: "marketplace.staticManifestURL"),
            let manifestURL = URL(string: manifest)
        {
            configuredProviders.append(
                StaticImageProvider(
                    manifestURL: manifestURL,
                    sourceDescription: manifestURL.host ?? "Custom image catalog"
                )
            )
        }

        if
            let owner = defaults.string(forKey: "marketplace.githubOwner"),
            let repository = defaults.string(forKey: "marketplace.githubRepository")
        {
            configuredProviders.append(
                UserRepositoryProvider(
                    owner: owner,
                    repository: repository,
                    branch: defaults.string(forKey: "marketplace.githubBranch") ?? "main"
                )
            )
        }
        providers = configuredProviders
    }
}
