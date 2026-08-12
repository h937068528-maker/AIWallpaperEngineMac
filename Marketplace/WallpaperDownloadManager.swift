import Combine
import Foundation

@MainActor
final class WallpaperDownloadManager: ObservableObject {
    static let shared = WallpaperDownloadManager()

    @Published private(set) var activeWallpaperID: String?
    @Published private(set) var progress: Double = 0

    private let maximumDownloadSize: Int64 = 1_500 * 1_024 * 1_024
    private var trustedHosts: Set<String> = [
        "raw.githubusercontent.com",
        "www.bing.com",
        "bing.com",
        "cn.bing.com",
    ]

    private init() {}

    func allowDownloadHost(_ host: String) {
        trustedHosts.insert(host.lowercased())
    }

    func localURL(for wallpaper: MarketplaceWallpaper, folderPath: String) -> URL {
        if let sourceURL = wallpaper.downloadURL, sourceURL.isFileURL {
            return sourceURL
        }
        return URL(fileURLWithPath: folderPath, isDirectory: true)
            .appendingPathComponent(wallpaper.filename, isDirectory: false)
    }

    func isDownloaded(_ wallpaper: MarketplaceWallpaper, folderPath: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: wallpaper, folderPath: folderPath).path)
    }

    func download(_ wallpaper: MarketplaceWallpaper, folderPath: String) async throws -> URL {
        if let localSourceURL = wallpaper.downloadURL, localSourceURL.isFileURL {
            guard FileManager.default.fileExists(atPath: localSourceURL.path) else {
                throw MarketplaceError.invalidResponse
            }
            return localSourceURL
        }
        guard
            let remoteURL = wallpaper.downloadURL,
            remoteURL.scheme == "https",
            let host = remoteURL.host?.lowercased(),
            trustedHosts.contains(host)
        else {
            throw MarketplaceError.untrustedURL
        }
        let fileExtension = wallpaper.format.lowercased()
        guard ["mp4", "mov", "gif", "jpg", "jpeg", "png"].contains(fileExtension) else {
            throw MarketplaceError.unsupportedMedia
        }
        guard wallpaper.size <= maximumDownloadSize else {
            throw MarketplaceError.fileTooLarge
        }

        let destinationFolder = URL(fileURLWithPath: folderPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true
        )
        let destinationURL = localURL(for: wallpaper, folderPath: folderPath)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        activeWallpaperID = wallpaper.id
        progress = 0
        defer {
            activeWallpaperID = nil
            progress = 0
        }

        let operation = MarketplaceDownloadOperation(
            remoteURL: remoteURL,
            fileExtension: fileExtension,
            maximumSize: maximumDownloadSize
        ) { [weak self] value in
            Task { @MainActor in self?.progress = value }
        }
        let temporaryURL = try await operation.start()
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? 0) <= maximumDownloadSize else {
            throw MarketplaceError.fileTooLarge
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }
}

private final class MarketplaceDownloadOperation: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let remoteURL: URL
    private let fileExtension: String
    private let maximumSize: Int64
    private let progressHandler: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadedURL: URL?
    private lazy var session = URLSession(
        configuration: .ephemeral,
        delegate: self,
        delegateQueue: nil
    )

    init(
        remoteURL: URL,
        fileExtension: String,
        maximumSize: Int64,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) {
        self.remoteURL = remoteURL
        self.fileExtension = fileExtension
        self.maximumSize = maximumSize
        self.progressHandler = progressHandler
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: remoteURL).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > maximumSize {
            downloadTask.cancel()
            return
        }
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(
            min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let response = downloadTask.response as? HTTPURLResponse
            guard
                let response,
                (200..<300).contains(response.statusCode),
                response.expectedContentLength <= maximumSize
            else {
                throw MarketplaceError.invalidResponse
            }
            let mimeType = response.mimeType?.lowercased() ?? ""
            guard
                mimeType.isEmpty
                    || mimeType.hasPrefix("video/")
                    || mimeType.hasPrefix("image/")
                    || mimeType == "application/octet-stream"
            else {
                throw MarketplaceError.unsupportedMedia
            }
            let stableURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try FileManager.default.moveItem(at: location, to: stableURL)
            downloadedURL = stableURL
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            continuation = nil
            self.session.finishTasksAndInvalidate()
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else if let downloadedURL {
            continuation.resume(returning: downloadedURL)
        } else {
            continuation.resume(throwing: MarketplaceError.invalidResponse)
        }
    }
}
