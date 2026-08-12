import AppKit
import Combine
import Foundation

struct AIWallpaperGenerationRequest: Sendable {
    let prompt: String
    let style: AIWallpaperStyle
    let width: Int
    let height: Int
}

struct AIWallpaperGenerationResult: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let prompt: String
    let style: AIWallpaperStyle
    let localPath: String
    let createdAt: Date

    var localURL: URL {
        URL(fileURLWithPath: localPath)
    }
}

enum AIWallpaperStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case cinematic
    case illustration
    case minimal
    case abstract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cinematic: L.aiStyleCinematic
        case .illustration: L.aiStyleIllustration
        case .minimal: L.aiStyleMinimal
        case .abstract: L.aiStyleAbstract
        }
    }
}

@MainActor
protocol AIWallpaperProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var isDemo: Bool { get }

    func generate(
        _ request: AIWallpaperGenerationRequest,
        destinationFolder: URL
    ) async throws -> AIWallpaperGenerationResult
}

enum AIWallpaperGenerationError: Error {
    case emptyPrompt
    case invalidDestination
    case imageEncodingFailed
}

/// First-stage provider used to validate the complete product flow without an
/// API key. It creates an original procedural placeholder locally and never
/// sends the prompt or user data to a server.
@MainActor
final class DemoAIWallpaperProvider: AIWallpaperProvider {
    let id = "ai.demo.local"
    let displayName = "Local Demo"
    let isDemo = true

    func generate(
        _ request: AIWallpaperGenerationRequest,
        destinationFolder: URL
    ) async throws -> AIWallpaperGenerationResult {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw AIWallpaperGenerationError.emptyPrompt
        }
        guard destinationFolder.isFileURL else {
            throw AIWallpaperGenerationError.invalidDestination
        }

        try await Task.sleep(for: .milliseconds(850))
        try FileManager.default.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true
        )

        let id = UUID()
        let filename = "AI-Demo-\(Self.timestamp())-\(id.uuidString.prefix(8)).png"
        let destinationURL = destinationFolder.appendingPathComponent(filename)
        guard
            let representation = Self.makeProceduralImage(for: request),
            let png = representation.representation(using: .png, properties: [:])
        else {
            throw AIWallpaperGenerationError.imageEncodingFailed
        }
        try png.write(to: destinationURL, options: .atomic)

        return AIWallpaperGenerationResult(
            id: id,
            prompt: prompt,
            style: request.style,
            localPath: destinationURL.path,
            createdAt: Date()
        )
    }

    private static func makeProceduralImage(
        for request: AIWallpaperGenerationRequest
    ) -> NSBitmapImageRep? {
        let size = NSSize(width: request.width, height: request.height)
        guard
            let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: request.width,
                pixelsHigh: request.height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: representation)
        else {
            return nil
        }
        representation.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer {
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }

        let seed = request.prompt.utf8.reduce(UInt64(5381)) {
            (($0 << 5) &+ $0) &+ UInt64($1)
        }
        let hue = CGFloat(seed % 360) / 360
        let colors = palette(style: request.style, hue: hue)
        NSGradient(colors: colors)?.draw(
            in: NSRect(origin: .zero, size: size),
            angle: -32
        )

        var generator = seed
        for index in 0..<18 {
            generator = generator &* 6_364_136_223_846_793_005 &+ 1
            let x = CGFloat(generator % UInt64(request.width))
            generator = generator &* 6_364_136_223_846_793_005 &+ 1
            let y = CGFloat(generator % UInt64(request.height))
            let diameter = CGFloat(90 + generator % 420)
            colors[index % colors.count].withAlphaComponent(0.11).setFill()
            NSBezierPath(
                ovalIn: NSRect(
                    x: x - diameter / 2,
                    y: y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            ).fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let mark = "AI"
        mark.draw(
            in: NSRect(
                x: 0,
                y: size.height * 0.35,
                width: size.width,
                height: size.height * 0.3
            ),
            withAttributes: [
                .font: NSFont.systemFont(
                    ofSize: min(size.width, size.height) * 0.23,
                    weight: .black
                ),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88),
                .paragraphStyle: paragraph,
            ]
        )

        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt.draw(
            in: NSRect(
                x: size.width * 0.15,
                y: size.height * 0.18,
                width: size.width * 0.7,
                height: size.height * 0.12
            ),
            withAttributes: [
                .font: NSFont.systemFont(
                    ofSize: min(size.width, size.height) * 0.032,
                    weight: .medium
                ),
                .foregroundColor: NSColor.white.withAlphaComponent(0.72),
                .paragraphStyle: paragraph,
            ]
        )
        return representation
    }

    private static func palette(
        style: AIWallpaperStyle,
        hue: CGFloat
    ) -> [NSColor] {
        let accent = NSColor(calibratedHue: hue, saturation: 0.72, brightness: 0.9, alpha: 1)
        switch style {
        case .cinematic:
            return [.black, accent.blended(withFraction: 0.35, of: .black) ?? accent, .darkGray]
        case .illustration:
            return [accent, .systemPink, .systemPurple]
        case .minimal:
            return [.windowBackgroundColor, accent, .white]
        case .abstract:
            return [.black, .systemBlue, accent, .systemPurple]
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

@MainActor
final class AIWallpaperHistoryStore: ObservableObject {
    @Published private(set) var items: [AIWallpaperGenerationResult] = []

    private let defaults: UserDefaults
    private let storageKey = "ai.wallpaper.generationHistory.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ result: AIWallpaperGenerationResult) {
        items.removeAll { $0.id == result.id }
        items.insert(result, at: 0)
        items = Array(items.prefix(30))
        save()
    }

    func removeMissingFiles() {
        items.removeAll {
            !FileManager.default.fileExists(atPath: $0.localPath)
        }
        save()
    }

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(
                [AIWallpaperGenerationResult].self,
                from: data
            )
        else {
            return
        }
        items = decoded.filter {
            FileManager.default.fileExists(atPath: $0.localPath)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

@MainActor
final class AIWallpaperGenerationViewModel: ObservableObject {
    @Published var prompt = ""
    @Published var style: AIWallpaperStyle = .cinematic
    @Published var selectedProviderID: String {
        didSet {
            defaults.set(selectedProviderID, forKey: providerPreferenceKey)
        }
    }
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestResult: AIWallpaperGenerationResult?

    let providers: [any AIWallpaperProvider]
    let history: AIWallpaperHistoryStore
    private let defaults: UserDefaults
    private let providerPreferenceKey = "ai.wallpaper.selectedProvider.v1"

    init(
        providers: [any AIWallpaperProvider]? = nil,
        history: AIWallpaperHistoryStore = AIWallpaperHistoryStore(),
        defaults: UserDefaults = .standard
    ) {
        let resolvedProviders = providers ?? [
            DemoAIWallpaperProvider(),
            OpenAIWallpaperProvider(),
            VolcengineWallpaperProvider(),
        ]
        self.providers = resolvedProviders
        self.history = history
        self.defaults = defaults
        let storedProviderID = defaults.string(forKey: providerPreferenceKey)
        selectedProviderID = resolvedProviders.contains {
            $0.id == storedProviderID
        } ? storedProviderID! : resolvedProviders.first?.id ?? ""
    }

    var selectedProvider: (any AIWallpaperProvider)? {
        providers.first { $0.id == selectedProviderID }
    }

    func generate(folderPath: String) async -> AIWallpaperGenerationResult? {
        guard !isGenerating else { return nil }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            guard let selectedProvider else {
                throw AIWallpaperGenerationError.imageEncodingFailed
            }
            let result = try await selectedProvider.generate(
                AIWallpaperGenerationRequest(
                    prompt: prompt,
                    style: style,
                    width: 1792,
                    height: 1024
                ),
                destinationFolder: URL(
                    fileURLWithPath: folderPath,
                    isDirectory: true
                )
            )
            latestResult = result
            history.add(result)
            return result
        } catch is CancellationError {
            return nil
        } catch let error as AIWallpaperGenerationError {
            switch error {
            case .emptyPrompt:
                errorMessage = L.aiEmptyPrompt
            case .invalidDestination:
                errorMessage = L.aiInvalidFolder
            case .imageEncodingFailed:
                errorMessage = L.aiGenerationFailed
            }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
