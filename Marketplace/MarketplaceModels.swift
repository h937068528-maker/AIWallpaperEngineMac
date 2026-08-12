import Foundation

struct MarketplaceResolution: Codable, Hashable, Sendable {
    let width: Int
    let height: Int
    let label: String
}

struct MarketplaceWallpaper: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let category: String
    let path: String
    let thumbnailPath: String
    let previewPath: String?
    let size: Int64
    let format: String
    let createdAt: String
    let displayTitle: String?
    let description: String?
    let tags: [String]?
    let subcategory: String?
    let usage: String
    let topic: String?
    let duration: Double?
    let resolution: MarketplaceResolution?

    // The gallery CDN currently challenges native clients with Cloudflare.
    // Its public asset repository exposes the same paths without requiring web cookies.
    static let resourceBaseURL = URL(
        string: "https://raw.githubusercontent.com/IT-NuanxinPro/nuanXinProPic/main/"
    )!

    var title: String {
        let value = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty
            ? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            : value
    }

    var thumbnailURL: URL? { remoteURL(for: thumbnailPath) }
    var previewURL: URL? { remoteURL(for: previewPath ?? path) }
    var downloadURL: URL? { remoteURL(for: path) }

    var categoryTitle: String {
        topic ?? subcategory ?? category
    }

    var detailText: String {
        var values: [String] = []
        if let resolution {
            values.append("\(resolution.width) × \(resolution.height)")
        }
        if let duration {
            values.append(String(format: "%.0f s", duration))
        }
        values.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        return values.joined(separator: " · ")
    }

    private func remoteURL(for resourcePath: String) -> URL? {
        guard !resourcePath.isEmpty else { return nil }
        if let absolute = URL(string: resourcePath), absolute.scheme != nil {
            return absolute
        }
        let relativePath = String(resourcePath.drop(while: { $0 == "/" }))
        let encoded = relativePath.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed.union(
                CharacterSet(charactersIn: "%")
            )
        ) ?? relativePath
        return URL(string: encoded, relativeTo: Self.resourceBaseURL)?.absoluteURL
    }
}

struct MarketplaceCatalogEnvelope: Codable, Sendable {
    let generatedAt: String?
    let series: String?
    let category: String?
    let total: Int?
    let blob: String?
    let payload: String?
    let wallpapers: [MarketplaceWallpaper]?
}

enum MarketplaceError: LocalizedError {
    case invalidCatalog
    case unsupportedEncoding
    case untrustedURL
    case invalidResponse
    case fileTooLarge
    case unsupportedMedia

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: "The online wallpaper catalog is invalid."
        case .unsupportedEncoding: "The online wallpaper catalog uses an unsupported encoding."
        case .untrustedURL: "The wallpaper download address is not trusted."
        case .invalidResponse: "The wallpaper server returned an invalid response."
        case .fileTooLarge: "The wallpaper exceeds the maximum supported download size."
        case .unsupportedMedia: "The downloaded file is not a supported video wallpaper."
        }
    }
}
