import Foundation

struct WallpaperCatalogDecoder: Sendable {
    private static let versionPrefix = "v1."
    private static let decodeMap: [Character: Character] = {
        let original = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        let mapped = Array("QWERTYUIOPASDFGHJKLZXCVBNM".uppercased()
            + "qwertyuiopasdfghjklzxcvbnm"
            + "5678901234-_.")
        return Dictionary(uniqueKeysWithValues: zip(mapped, original))
    }()

    func decode(_ envelope: MarketplaceCatalogEnvelope) throws -> [MarketplaceWallpaper] {
        if let wallpapers = envelope.wallpapers {
            return wallpapers
        }
        guard let encoded = envelope.blob ?? envelope.payload else {
            throw MarketplaceError.invalidCatalog
        }
        guard encoded.hasPrefix(Self.versionPrefix) else {
            throw MarketplaceError.unsupportedEncoding
        }

        let transformed = encoded.dropFirst(Self.versionPrefix.count)
            .reversed()
            .map { Self.decodeMap[$0] ?? $0 }
        guard
            let data = Data(base64Encoded: String(transformed)),
            !data.isEmpty
        else {
            throw MarketplaceError.invalidCatalog
        }
        return try JSONDecoder().decode([MarketplaceWallpaper].self, from: data)
    }
}

@MainActor
final class WallpaperCatalogClient {
    static let shared = WallpaperCatalogClient()

    private let catalogURL = URL(
        string: "https://raw.githubusercontent.com/IT-NuanxinPro/nuanXinProPic/main/data/video/desktop.json"
    )!
    private let decoder = WallpaperCatalogDecoder()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDesktopWallpapers() async throws -> [MarketplaceWallpaper] {
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            data.count <= 10 * 1_024 * 1_024
        else {
            throw MarketplaceError.invalidResponse
        }
        let envelope = try JSONDecoder().decode(MarketplaceCatalogEnvelope.self, from: data)
        return try decoder.decode(envelope)
            .filter { $0.usage == "desktop" && ["mp4", "mov"].contains($0.format.lowercased()) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
