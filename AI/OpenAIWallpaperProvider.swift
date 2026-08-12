import AppKit
import Combine
import Foundation
import Security

enum OpenAIKeychainError: LocalizedError {
    case invalidKey
    case unexpectedData
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            "The API key does not look valid."
        case .unexpectedData:
            "The saved API key could not be read."
        case let .status(code):
            SecCopyErrorMessageString(code, nil) as String?
                ?? "Keychain error \(code)."
        }
    }
}

/// Stores the user's API key in the login Keychain. The raw key is never
/// published to SwiftUI, UserDefaults, logs, generation history, or analytics.
@MainActor
final class OpenAIAPIKeyStore: ObservableObject {
    static let shared = OpenAIAPIKeyStore()

    @Published private(set) var hasKey = false
    @Published private(set) var maskedKey = ""

    private let service = "com.aiwallpaperengine.mac.openai"
    private let account = "image-generation-api-key"

    init() {
        refreshStatus()
    }

    func save(_ rawKey: String) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20, !key.contains(where: \.isWhitespace) else {
            throw OpenAIKeychainError.invalidKey
        }
        guard let data = key.data(using: .utf8) else {
            throw OpenAIKeychainError.unexpectedData
        }

        let lookup = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insertion = lookup
            attributes.forEach { insertion[$0.key] = $0.value }
            let status = SecItemAdd(insertion as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw OpenAIKeychainError.status(status)
            }
        } else if updateStatus != errSecSuccess {
            throw OpenAIKeychainError.status(updateStatus)
        }
        refreshStatus()
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIKeychainError.status(status)
        }
        refreshStatus()
    }

    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw OpenAIKeychainError.status(status)
        }
        guard
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            throw OpenAIKeychainError.unexpectedData
        }
        return key
    }

    func refreshStatus() {
        do {
            guard let key = try read(), !key.isEmpty else {
                hasKey = false
                maskedKey = ""
                return
            }
            hasKey = true
            maskedKey = Self.mask(key)
        } catch {
            hasKey = false
            maskedKey = ""
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func mask(_ key: String) -> String {
        guard key.count > 8 else { return "••••••••" }
        return "\(key.prefix(3))••••••••\(key.suffix(4))"
    }
}

enum OpenAIWallpaperError: LocalizedError {
    case missingKey
    case invalidResponse
    case api(status: Int, message: String)
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Configure an OpenAI API key first."
        case .invalidResponse:
            "OpenAI returned an invalid response."
        case let .api(status, message):
            "OpenAI \(status): \(message)"
        case .invalidImage:
            "OpenAI did not return a valid image."
        }
    }
}

@MainActor
final class OpenAIWallpaperProvider: AIWallpaperProvider {
    let id = "ai.openai.image"
    let displayName = "OpenAI · GPT Image 2"
    let isDemo = false

    private let keyStore: OpenAIAPIKeyStore
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/images/generations")!
    private let modelEndpoint = URL(string: "https://api.openai.com/v1/models/gpt-image-2")!

    init(
        keyStore: OpenAIAPIKeyStore = .shared,
        session: URLSession = .shared
    ) {
        self.keyStore = keyStore
        self.session = session
    }

    func validateAPIKey(_ key: String) async throws {
        var request = URLRequest(url: modelEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.validateHTTPResponse(data: data, response: response)
    }

    func generate(
        _ request: AIWallpaperGenerationRequest,
        destinationFolder: URL
    ) async throws -> AIWallpaperGenerationResult {
        guard let apiKey = try keyStore.read() else {
            throw OpenAIWallpaperError.missingKey
        }
        try Task.checkCancellation()

        let apiSize = Self.supportedSize(width: request.width, height: request.height)
        let payload = OpenAIImageGenerationPayload(
            model: "gpt-image-2",
            prompt: Self.wallpaperPrompt(request),
            size: apiSize,
            quality: "medium",
            outputFormat: "png"
        )
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 240
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        try Self.validateHTTPResponse(data: data, response: response)
        guard
            data.count <= 100 * 1_024 * 1_024,
            let envelope = try? JSONDecoder().decode(
                OpenAIImageGenerationEnvelope.self,
                from: data
            ),
            let encodedImage = envelope.data.first?.base64JSON,
            let imageData = Data(base64Encoded: encodedImage),
            imageData.count <= 80 * 1_024 * 1_024,
            let representation = NSBitmapImageRep(data: imageData),
            representation.pixelsWide > 0,
            representation.pixelsHigh > 0
        else {
            throw OpenAIWallpaperError.invalidImage
        }

        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true
        )
        let id = UUID()
        let filename = "AI-OpenAI-\(Self.timestamp())-\(id.uuidString.prefix(8)).png"
        let destinationURL = destinationFolder.appendingPathComponent(filename)
        try imageData.write(to: destinationURL, options: .atomic)

        return AIWallpaperGenerationResult(
            id: id,
            prompt: request.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            style: request.style,
            localPath: destinationURL.path,
            createdAt: Date()
        )
    }

    private static func validateHTTPResponse(
        data: Data,
        response: URLResponse
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw OpenAIWallpaperError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(
                OpenAIErrorEnvelope.self,
                from: data
            )
            let message = envelope?.error.message ?? HTTPURLResponse.localizedString(
                    forStatusCode: response.statusCode
                )
            throw OpenAIWallpaperError.api(
                status: response.statusCode,
                message: message
            )
        }
    }

    private static func supportedSize(width: Int, height: Int) -> String {
        if width == height { return "1024x1024" }
        return width > height ? "1536x1024" : "1024x1536"
    }

    private static func wallpaperPrompt(
        _ request: AIWallpaperGenerationRequest
    ) -> String {
        """
        Create a polished macOS desktop wallpaper based on this description:
        \(request.prompt)

        Visual style: \(request.style.rawValue).
        Keep the composition suitable for desktop icons, with calm negative
        space and no text, logos, watermarks, UI elements, or borders.
        """
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

private struct OpenAIImageGenerationPayload: Encodable {
    let model: String
    let prompt: String
    let size: String
    let quality: String
    let outputFormat: String

    private enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case size
        case quality
        case outputFormat = "output_format"
    }
}

private struct OpenAIImageGenerationEnvelope: Decodable {
    let data: [OpenAIImageGenerationData]
}

private struct OpenAIImageGenerationData: Decodable {
    let base64JSON: String?

    private enum CodingKeys: String, CodingKey {
        case base64JSON = "b64_json"
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIErrorBody
}

private struct OpenAIErrorBody: Decodable {
    let message: String
}
